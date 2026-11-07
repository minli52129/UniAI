import SwiftUI

enum Feature: String, CaseIterable, Identifiable {
    case chat, image, speech, video, settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chat: return "文字对话"
        case .image: return "图片生成"
        case .speech: return "语音合成 / 识别"
        case .video: return "视频生成"
        case .settings: return "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .chat: return "bubble.left.and.text.bubble.right"
        case .image: return "photo.on.rectangle.angled"
        case .speech: return "waveform"
        case .video: return "video"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    @State private var selection: Feature = .chat

    var body: some View {
        NavigationSplitView {
            List {
                Section("能力") {
                    ForEach(Feature.allCases) { feature in
                        Label(feature.label, systemImage: feature.systemImage)
                            .tag(feature)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 240)
        } detail: {
            switch selection {
            case .chat: ChatView()
            case .image: ImageView()
            case .speech: SpeechView()
            case .video: VideoView()
            case .settings: SettingsView()
            }
        }
    }
}
