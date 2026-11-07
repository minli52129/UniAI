import SwiftUI
import AVFoundation
import AppKit
import UniformTypeIdentifiers

enum SpeechMode: String, CaseIterable, Identifiable {
    case synthesis
    case recognition

    var id: String { rawValue }
}

@MainActor
final class SpeechViewModel: ObservableObject {
    @Published var mode: SpeechMode = .synthesis

    // 语音合成
    @Published var synthesisText = ""
    @Published var isSynthesizing = false
    @Published var audioData: Data?
    @Published var isPlaying = false

    // 语音识别
    @Published var isRecording = false
    @Published var recordingSeconds = 0
    @Published var isTranscribing = false
    @Published var transcribedText = ""

    @Published var errorMessage: String?

    private var player: AVPlayer?
    private var playbackObserver: NSObjectProtocol?
    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    private var recordingURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("UniAI-recording.m4a")
    }

    deinit {
        timer?.invalidate()
        if let observer = playbackObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - 语音合成

    func synthesize(settings: AppSettings, client: APIClient) async {
        let text = synthesisText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSynthesizing else { return }
        isSynthesizing = true
        errorMessage = nil
        defer { isSynthesizing = false }
        do {
            struct TTSRequest: Encodable {
                var model: String
                var input: String
                var voice: String
            }
            let body = try JSONEncoder().encode(TTSRequest(model: settings.ttsModel, input: text, voice: settings.ttsVoice))
            let data = try await client.postData("/audio/speech", json: body)
            guard !data.isEmpty else {
                throw APIError(message: "接口未返回音频数据（请确认服务支持 /audio/speech）")
            }
            audioData = data
            play()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func play() {
        guard let data = audioData else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("UniAI-tts.mp3")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        stopPlayback()
        let newPlayer = AVPlayer(url: url)
        player = newPlayer
        playbackObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: newPlayer.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
            }
        }
        isPlaying = true
        newPlayer.play()
    }

    func stopPlayback() {
        player?.pause()
        player = nil
        isPlaying = false
    }

    func exportAudio() {
        guard let data = audioData else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "mp3") ?? .data]
        panel.nameFieldStringValue = "UniAI-tts.mp3"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 语音识别

    func startRecording() {
        guard !isRecording, !isTranscribing else { return }
        errorMessage = nil
        let url = recordingURL
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        do {
            let newRecorder = try AVAudioRecorder(url: url, settings: settings)
            guard newRecorder.record() else {
                throw APIError(message: "无法开始录音：请检查麦克风权限（系统设置 → 隐私与安全性 → 麦克风）。")
            }
            recorder = newRecorder
            recordingSeconds = 0
            isRecording = true
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.recordingSeconds += 1
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopAndTranscribe(settings: AppSettings, client: APIClient) async {
        guard isRecording else { return }
        recorder?.stop()
        recorder = nil
        timer?.invalidate()
        timer = nil
        isRecording = false
        await transcribe(fileURL: recordingURL, settings: settings, client: client)
    }

    func pickFileAndTranscribe(settings: AppSettings, client: APIClient) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await transcribe(fileURL: url, settings: settings, client: client)
        }
    }

    func copyTranscription() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcribedText, forType: .string)
    }

    private func transcribe(fileURL: URL, settings: AppSettings, client: APIClient) async {
        guard !isTranscribing else { return }
        isTranscribing = true
        errorMessage = nil
        defer { isTranscribing = false }
        do {
            let data = try Data(contentsOf: fileURL)
            guard !data.isEmpty else {
                throw APIError(message: "音频内容为空")
            }
            var form = MultipartBody()
            form.addField("model", settings.sttModel)
            form.addFile("file", filename: fileURL.lastPathComponent, mimeType: "audio/mp4", content: data)
            let response = try await client.postMultipart("/audio/transcriptions", form: form)
            struct TranscriptionResponse: Decodable {
                var text: String
            }
            transcribedText = try JSONDecoder().decode(TranscriptionResponse.self, from: response).text
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SpeechView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @StateObject private var viewModel = SpeechViewModel()

    var body: some View {
        VStack(spacing: 0) {
            Picker("模式", selection: $viewModel.mode) {
                Text("语音合成").tag(SpeechMode.synthesis)
                Text("语音识别").tag(SpeechMode.recognition)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
            .padding(.top, 12)

            switch viewModel.mode {
            case .synthesis: synthesisPane
            case .recognition: recognitionPane
            }
        }
        .errorAlert($viewModel.errorMessage)
        .navigationTitle("语音")
    }

    private var synthesisPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("模型：\(settingsStore.settings.ttsModel)｜音色：\(settingsStore.settings.ttsVoice)（可在设置中修改）")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextEditor(text: $viewModel.synthesisText)
                .frame(height: 170)
            HStack {
                Text("\(viewModel.synthesisText.count) 字")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if viewModel.isPlaying {
                    Button("停止播放") { viewModel.stopPlayback() }
                } else {
                    Button("播放") { viewModel.play() }
                        .disabled(viewModel.audioData == nil)
                }
                Button("导出…") { viewModel.exportAudio() }
                    .disabled(viewModel.audioData == nil)
                Button("生成语音") {
                    Task {
                        await viewModel.synthesize(
                            settings: settingsStore.settings,
                            client: settingsStore.client(for: settingsStore.settings.speechEndpoint)
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isSynthesizing || viewModel.synthesisText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if viewModel.isSynthesizing {
                ProgressView("正在合成…")
            }
            Spacer()
        }
        .padding()
    }

    private var recognitionPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("模型：\(settingsStore.settings.sttModel)（可在设置中修改）")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                if viewModel.isRecording {
                    Label("录音中 \(viewModel.recordingSeconds)s", systemImage: "record.circle")
                        .foregroundStyle(.red)
                    Button("停止并识别") {
                        Task {
                            await viewModel.stopAndTranscribe(
                                settings: settingsStore.settings,
                                client: settingsStore.client(for: settingsStore.settings.speechEndpoint)
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("开始录音") { viewModel.startRecording() }
                        .disabled(viewModel.isTranscribing)
                    Button("选择音频文件…") {
                        viewModel.pickFileAndTranscribe(
                            settings: settingsStore.settings,
                            client: settingsStore.client(for: settingsStore.settings.speechEndpoint)
                        )
                    }
                    .disabled(viewModel.isTranscribing)
                }
                if viewModel.isTranscribing {
                    ProgressView()
                        .controlSize(.small)
                    Text("识别中…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("复制结果") { viewModel.copyTranscription() }
                    .disabled(viewModel.transcribedText.isEmpty)
            }
            TextEditor(text: $viewModel.transcribedText)
                .frame(minHeight: 180)
            Spacer()
        }
        .padding()
    }
}
