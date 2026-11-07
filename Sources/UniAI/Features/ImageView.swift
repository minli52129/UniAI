import SwiftUI
import AppKit

struct GeneratedImage: Identifiable, Equatable {
    let id = UUID()
    let prompt: String
    let createdAt = Date()
    let data: Data

    static func == (lhs: GeneratedImage, rhs: GeneratedImage) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
final class ImageViewModel: ObservableObject {
    @Published var prompt = ""
    @Published var size = "1024x1024"
    @Published var isGenerating = false
    @Published var history: [GeneratedImage] = []
    @Published var selectedID: UUID?
    @Published var errorMessage: String?

    var selected: GeneratedImage? {
        history.first { $0.id == selectedID }
    }

    func generate(settings: AppSettings, client: APIClient) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }
        isGenerating = true
        errorMessage = nil

        var payload: [String: Any] = [
            "model": settings.imageModel,
            "prompt": text
        ]
        let trimmedSize = size.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSize.isEmpty {
            payload["size"] = trimmedSize
        }

        Task { [weak self] in
            defer { self?.isGenerating = false }
            do {
                let body = try JSONSerialization.data(withJSONObject: payload)
                let response = try await client.postData("/images/generations", json: body)
                let imageData = try await Self.resolveImageData(from: response)
                guard let self else { return }
                let item = GeneratedImage(prompt: text, data: imageData)
                history.insert(item, at: 0)
                selectedID = item.id
            } catch {
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    /// 同时兼容返回 url 或 b64_json 的服务。
    private static func resolveImageData(from response: Data) async throws -> Data {
        struct Payload: Decodable {
            struct Item: Decodable {
                let url: String?
                let b64Json: String?

                enum CodingKeys: String, CodingKey {
                    case url
                    case b64Json = "b64_json"
                }
            }
            let data: [Item]
        }
        let payload = try JSONDecoder().decode(Payload.self, from: response)
        guard let item = payload.data.first else {
            throw APIError(message: "接口未返回图片数据")
        }
        // 有些服务（如 Agnes）返回空的 b64_json 字符串，需跳过
        if let base64 = item.b64Json, !base64.isEmpty, let data = Data(base64Encoded: base64) {
            return data
        }
        guard let urlString = item.url, let url = URL(string: urlString) else {
            throw APIError(message: "接口返回的图片地址无效")
        }
        let (data, urlResponse) = try await URLSession.shared.data(from: url)
        return try APIClient.validate(data: data, response: urlResponse)
    }

    func export(_ item: GeneratedImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "UniAI-image-\(Int(item.createdAt.timeIntervalSince1970)).png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Self.pngData(from: item.data).write(to: url, options: .atomic)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    static func pngData(from raw: Data) throws -> Data {
        if raw.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return raw
        }
        if let rep = NSBitmapImageRep(data: raw),
           let png = rep.representation(using: .png, properties: [:]) {
            return png
        }
        return raw
    }

    func copyToPasteboard(_ item: GeneratedImage) {
        guard let image = NSImage(data: item.data) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    func delete(_ item: GeneratedImage) {
        if selectedID == item.id { selectedID = nil }
        history.removeAll { $0.id == item.id }
    }
}

struct ImageView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @StateObject private var viewModel = ImageViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("描述你想要的画面，例如：一只在星空中冲浪的柴犬", text: $viewModel.prompt)
                    .textFieldStyle(.roundedBorder)
                TextField("尺寸", text: $viewModel.size)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .help("留空则使用服务端默认尺寸")
                Button("生成") {
                    viewModel.generate(
                        settings: settingsStore.settings,
                        client: settingsStore.client(for: settingsStore.settings.imageEndpoint)
                    )
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(viewModel.isGenerating || viewModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Text("模型：\(settingsStore.settings.imageModel)（可在设置中修改）")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if viewModel.isGenerating {
                ProgressView("正在生成…")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 60)
            } else if let selected = viewModel.selected {
                preview(selected)
            }

            if !viewModel.history.isEmpty {
                Text("历史记录")
                    .font(.headline)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                        ForEach(viewModel.history) { item in
                            thumbnail(item)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
        .errorAlert($viewModel.errorMessage)
        .navigationTitle("图片生成")
    }

    private func preview(_ item: GeneratedImage) -> some View {
        VStack(spacing: 8) {
            if let image = NSImage(data: item.data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 360)
                    .cornerRadius(10)
            }
            HStack {
                Text(item.prompt)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("复制") { viewModel.copyToPasteboard(item) }
                Button("导出…") { viewModel.export(item) }
            }
        }
    }

    private func thumbnail(_ item: GeneratedImage) -> some View {
        Group {
            if let image = NSImage(data: item.data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.gray.opacity(0.2)
            }
        }
        .frame(width: 110, height: 110)
        .clipped()
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(item.id == viewModel.selectedID ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .onTapGesture { viewModel.selectedID = item.id }
        .contextMenu {
            Button("删除") { viewModel.delete(item) }
        }
    }
}
