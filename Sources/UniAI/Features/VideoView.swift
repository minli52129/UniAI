import SwiftUI
import AVKit

struct VideoSubmitRequest: Encodable {
    var model: String
    var prompt: String
    var mode: String?
    var size: String?
    var duration: Int?
    var withAudio: Bool?
    var quality: String?

    enum CodingKeys: String, CodingKey {
        case model, prompt, mode, size, duration, quality
        case withAudio = "with_audio"
    }
}

@MainActor
final class VideoViewModel: ObservableObject {
    @Published var prompt = ""
    @Published var size = ""
    @Published var duration = ""
    @Published var quality = ""
    @Published var withAudio = false

    @Published var isGenerating = false
    @Published var statusText = ""
    @Published var player: AVPlayer?
    @Published var videoData: Data?
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?
    private var startedAt: Date?

    private static let successStates: Set<String> = ["success", "succeeded", "completed", "complete", "finished", "done"]
    private static let failureStates: Set<String> = ["fail", "failed", "failure", "error", "cancelled", "canceled"]

    func generate(settings: AppSettings, client: APIClient) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }
        cancel()

        errorMessage = nil
        player = nil
        videoData = nil
        statusText = "提交生成任务…"
        isGenerating = true

        var request = VideoSubmitRequest(model: settings.videoModel, prompt: text)
        let trimmedMode = settings.videoMode.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedMode.isEmpty { request.mode = trimmedMode }
        let trimmedSize = size.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSize.isEmpty { request.size = trimmedSize }
        if let seconds = Int(duration.trimmingCharacters(in: .whitespacesAndNewlines)) { request.duration = seconds }
        if withAudio { request.withAudio = true }
        let trimmedQuality = quality.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuality.isEmpty { request.quality = trimmedQuality }

        let submitPath = settings.videoSubmitPath
        let pollTemplate = settings.videoPollPath

        task = Task { [weak self] in
            await self?.run(request: request, submitPath: submitPath, pollTemplate: pollTemplate, client: client)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isGenerating = false
        statusText = ""
    }

    func exportVideo() {
        guard let data = videoData else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "UniAI-video.mp4"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func run(request: VideoSubmitRequest, submitPath: String, pollTemplate: String, client: APIClient) async {
        do {
            let body = try JSONEncoder().encode(request)
            let submitData = try await client.postData(submitPath, json: body)
            let submitJSON = (try? JSONSerialization.jsonObject(with: submitData)) as? [String: Any] ?? [:]
            guard let taskID = Self.findString(in: submitJSON, keys: ["id", "task_id", "taskId", "job_id"]) else {
                let raw = String(data: submitData.prefix(400), encoding: .utf8) ?? "未知响应"
                throw APIError(message: "提交成功但未返回任务 ID：\(raw)")
            }

            let pollPath = pollTemplate.replacingOccurrences(of: "{id}", with: taskID)
            startedAt = Date()
            var videoBytes: Data?

            while true {
                try Task.checkCancellation()
                let elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? 0
                if elapsed > 15 * 60 {
                    throw APIError(message: "等待超时（15 分钟）。任务 ID：\(taskID)，可稍后自行到平台查询。")
                }
                statusText = String(format: "生成中… 已等待 %.0f 秒（任务 ID：%@）", elapsed, taskID)
                try await Task.sleep(nanoseconds: 3_000_000_000)

                let pollData = try await client.getData(pollPath)
                let pollJSON = (try? JSONSerialization.jsonObject(with: pollData)) as? [String: Any] ?? [:]
                let state = (Self.findString(in: pollJSON, keys: ["task_status", "status", "state"]) ?? "").lowercased()

                if Self.successStates.contains(state) {
                    if let urlString = Self.findVideoURL(in: pollJSON), let url = URL(string: urlString) {
                        statusText = "生成完成，正在下载视频…"
                        videoBytes = try await Self.download(url: url)
                    } else {
                        // 兼容"下载内容"型接口（如 OpenAI Sora：/videos/{id}/content）
                        let contentPath = submitPath.hasSuffix("/")
                            ? submitPath + "\(taskID)/content"
                            : submitPath + "/\(taskID)/content"
                        videoBytes = try await client.getData(contentPath)
                    }
                    break
                }
                if Self.failureStates.contains(state) {
                    let raw = String(data: pollData.prefix(400), encoding: .utf8) ?? state
                    throw APIError(message: "视频生成失败：\(raw)")
                }
            }

            guard let videoBytes, !videoBytes.isEmpty else {
                throw APIError(message: "任务已完成，但未获取到视频内容")
            }
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("UniAI-video-\(UUID().uuidString).mp4")
            try videoBytes.write(to: fileURL, options: .atomic)

            let newPlayer = AVPlayer(url: fileURL)
            self.videoData = videoBytes
            self.player = newPlayer
            newPlayer.play()
            statusText = "完成"
            isGenerating = false
            task = nil
        } catch is CancellationError {
            isGenerating = false
        } catch let error as URLError where error.code == .cancelled {
            isGenerating = false
        } catch {
            errorMessage = error.localizedDescription
            statusText = ""
            isGenerating = false
        }
    }

    private static func findString(in node: Any, keys: [String]) -> String? {
        if let dict = node as? [String: Any] {
            for key in keys {
                if let value = dict[key] as? String, !value.isEmpty {
                    return value
                }
            }
            for value in dict.values {
                if let found = findString(in: value, keys: keys) { return found }
            }
        } else if let array = node as? [Any] {
            for value in array {
                if let found = findString(in: value, keys: keys) { return found }
            }
        }
        return nil
    }

    private static func findVideoURL(in node: Any) -> String? {
        let keys = ["url", "video_url", "videoUrl", "download_url", "downloadUrl"]
        if let dict = node as? [String: Any] {
            for key in keys {
                if let value = dict[key] as? String, value.hasPrefix("http") {
                    return value
                }
            }
            for value in dict.values {
                if let found = findVideoURL(in: value) { return found }
            }
        } else if let array = node as? [Any] {
            for value in array {
                if let found = findVideoURL(in: value) { return found }
            }
        }
        return nil
    }

    static func download(url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        return try APIClient.validate(data: data, response: response)
    }
}

struct VideoView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @StateObject private var viewModel = VideoViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("提示词")
                    .font(.headline)
                Text("模型：\(settingsStore.settings.videoModel)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                if viewModel.isGenerating {
                    Button("取消") { viewModel.cancel() }
                }
            }

            TextEditor(text: $viewModel.prompt)
                .frame(height: 84)

            DisclosureGroup {
                LabeledContent("尺寸") {
                    TextField("如 1920x1080，留空不发送", text: $viewModel.size)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("时长（秒）") {
                    TextField("如 5，留空不发送", text: $viewModel.duration)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("画质") {
                    TextField("quality / speed（智谱），留空不发送", text: $viewModel.quality)
                        .textFieldStyle(.roundedBorder)
                }
                Toggle("附带音频（with_audio）", isOn: $viewModel.withAudio)
            } label: {
                Text("高级参数")
            }
            .font(.callout)

            HStack(spacing: 10) {
                Button("生成视频") {
                    viewModel.generate(
                        settings: settingsStore.settings,
                        client: settingsStore.client(for: settingsStore.settings.videoEndpoint)
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isGenerating || viewModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if viewModel.isGenerating {
                    ProgressView()
                        .controlSize(.small)
                    Text(viewModel.statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("导出…") { viewModel.exportVideo() }
                    .disabled(viewModel.videoData == nil)
            }

            if let player = viewModel.player {
                VideoPlayer(player: player)
                    .frame(minHeight: 330)
                    .cornerRadius(10)
            }

            Spacer()
        }
        .padding()
        .errorAlert($viewModel.errorMessage)
        .navigationTitle("视频生成")
    }
}
