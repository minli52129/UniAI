import Foundation

struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable {
        case system, user, assistant
    }

    var id = UUID()
    var role: Role
    var content: String
    var createdAt = Date()
}

struct ChatSession: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = "新对话"
    var createdAt = Date()
    var messages: [ChatMessage] = []
}

@MainActor
final class ChatStore: ObservableObject {
    static let shared = ChatStore()

    @Published private(set) var sessions: [ChatSession] = [] { didSet { scheduleSave() } }
    @Published var currentSessionID: UUID?

    private var saveTask: DispatchWorkItem?

    static var storageURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("UniAI", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("chats.json")
    }

    private init() {
        load()
        if sessions.isEmpty {
            createSession()
        }
    }

    var currentSession: ChatSession? {
        sessions.first { $0.id == currentSessionID }
    }

    @discardableResult
    func createSession() -> UUID {
        let session = ChatSession()
        sessions.insert(session, at: 0)
        currentSessionID = session.id
        return session.id
    }

    @discardableResult
    func ensureCurrentSession() -> UUID {
        if let id = currentSessionID, sessions.contains(where: { $0.id == id }) {
            return id
        }
        return createSession()
    }

    func deleteSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        if currentSessionID == id {
            currentSessionID = sessions.first?.id
            if currentSessionID == nil {
                createSession()
            }
        }
    }

    func append(sessionID: UUID, _ message: ChatMessage) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].messages.append(message)
        if message.role == .user && sessions[index].title == "新对话" {
            sessions[index].title = String(message.content.prefix(18))
        }
    }

    func appendDelta(sessionID: UUID, text: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }),
              let last = sessions[index].messages.indices.last,
              sessions[index].messages[last].role == .assistant else { return }
        sessions[index].messages[last].content += text
    }

    /// 流结束后兜底：assistant 消息仍为空时填入占位文案。
    func finishStreaming(sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }),
              let last = sessions[index].messages.indices.last,
              sessions[index].messages[last].role == .assistant,
              sessions[index].messages[last].content.isEmpty else { return }
        sessions[index].messages[last].content = "（模型未返回内容）"
    }

    func appendErrorToLastMessage(sessionID: UUID, text: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }),
              let last = sessions[index].messages.indices.last else { return }
        let current = sessions[index].messages[last].content
        sessions[index].messages[last].content = current.isEmpty ? "❌ \(text)" : current + "\n\n❌ \(text)"
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.storageURL),
              let decoded = try? JSONDecoder().decode([ChatSession].self, from: data) else { return }
        sessions = decoded.sorted { $0.createdAt > $1.createdAt }
        currentSessionID = sessions.first?.id
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        try? data.write(to: Self.storageURL, options: .atomic)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.save() }
        saveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: task)
    }
}
