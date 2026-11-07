import SwiftUI

struct ChatCompletionRequest: Encodable {
    struct Message: Encodable {
        var role: String
        var content: String
    }

    var model: String
    var messages: [Message]
    var stream = true
}

struct ChatStreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            var content: String?
        }

        var delta: Delta?
    }

    var choices: [Choice]?

    static func contentDelta(from data: Data) -> String? {
        guard let chunk = try? JSONDecoder().decode(ChatStreamChunk.self, from: data) else { return nil }
        return chunk.choices?.first?.delta?.content
    }
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var input = ""
    @Published var isStreaming = false

    private var task: Task<Void, Never>?

    func send(store: ChatStore, settings: AppSettings, client: APIClient) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        input = ""

        let sessionID = store.ensureCurrentSession()
        store.append(sessionID: sessionID, ChatMessage(role: .user, content: text))
        store.append(sessionID: sessionID, ChatMessage(role: .assistant, content: ""))
        isStreaming = true

        task = Task { [weak self] in
            await self?.streamReply(sessionID: sessionID, store: store, settings: settings, client: client)
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isStreaming = false
    }

    private func streamReply(sessionID: UUID, store: ChatStore, settings: AppSettings, client: APIClient) async {
        do {
            var history: [ChatCompletionRequest.Message] = []
            let system = settings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !system.isEmpty {
                history.append(ChatCompletionRequest.Message(role: "system", content: system))
            }
            if let index = store.sessions.firstIndex(where: { $0.id == sessionID }) {
                for message in store.sessions[index].messages.suffix(60) {
                    guard message.role != .system else { continue }
                    if message.role == .assistant && message.content.isEmpty { continue }
                    history.append(ChatCompletionRequest.Message(role: message.role.rawValue, content: message.content))
                }
            }

            let body = try JSONEncoder().encode(ChatCompletionRequest(model: settings.chatModel, messages: history))
            let stream = client.streamSSE("/chat/completions", json: body)
            for try await chunk in stream {
                if let errorText = APIClient.streamErrorText(from: chunk) {
                    throw APIError(message: errorText)
                }
                if let delta = ChatStreamChunk.contentDelta(from: chunk), !delta.isEmpty {
                    store.appendDelta(sessionID: sessionID, text: delta)
                }
            }
        } catch is CancellationError {
            // 用户主动停止
        } catch let error as URLError where error.code == .cancelled {
            // 用户主动停止
        } catch {
            store.appendErrorToLastMessage(sessionID: sessionID, text: error.localizedDescription)
        }
        store.finishStreaming(sessionID: sessionID)
        isStreaming = false
        task = nil
    }
}

struct ChatView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @StateObject private var store = ChatStore.shared
    @StateObject private var viewModel = ChatViewModel()

    private var currentMessages: [ChatMessage] {
        store.currentSession?.messages ?? []
    }

    var body: some View {
        HStack(spacing: 0) {
            sessionList
            Divider()
            chatArea
        }
        .navigationTitle("文字对话")
        .onAppear {
            store.ensureCurrentSession()
        }
    }

    private var sessionList: some View {
        VStack(spacing: 0) {
            Button {
                store.createSession()
            } label: {
                Label("新对话", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            List(selection: $store.currentSessionID) {
                ForEach(store.sessions) { session in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.title)
                            .lineLimit(1)
                        Text("\(session.messages.count) 条消息")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .tag(session.id)
                    .contextMenu {
                        Button("删除对话", role: .destructive) {
                            viewModel.stop()
                            store.deleteSession(session.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .frame(width: 210)
    }

    private var chatArea: some View {
        VStack(spacing: 0) {
            messageList
            Divider()
            inputBar
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if currentMessages.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                            .font(.system(size: 42))
                            .foregroundStyle(.quaternary)
                        Text("在下方输入消息，与「\(settingsStore.settings.chatModel)」对话")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 140)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(currentMessages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.vertical, 14)
                }
            }
            .onChange(of: currentMessages.last?.content ?? "") { _ in
                scrollToBottom(proxy)
            }
            .onChange(of: currentMessages.count) { _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = currentMessages.last else { return }
        proxy.scrollTo(last.id, anchor: .bottom)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextEditor(text: $viewModel.input)
                .font(.body)
                .frame(height: 64)
                .padding(.top, 4)
            if viewModel.isStreaming {
                Button {
                    viewModel.stop()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("停止生成")
            } else {
                Button {
                    viewModel.send(
                        store: store,
                        settings: settingsStore.settings,
                        client: settingsStore.client(for: settingsStore.settings.chatEndpoint)
                    )
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.return, modifiers: .command)
                .help("发送（⌘↩）")
                .disabled(viewModel.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(10)
    }
}
