import Foundation
import Combine

/// 各功能的接入点覆盖；留空则回退到全局 Base URL / API Key。
struct EndpointOverride: Codable, Equatable {
    var baseURL = ""
    var apiKey = ""

    enum CodingKeys: String, CodingKey { case baseURL, apiKey }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
    }
}

struct AppSettings: Codable, Equatable {
    // 全局
    var baseURL = "https://open.bigmodel.cn/api/paas/v4"
    var apiKey = ""

    // 文字对话
    var chatModel = "glm-4-flash"
    var systemPrompt = ""
    var chatEndpoint = EndpointOverride()

    // 图片生成
    var imageModel = "cogview-3-flash"
    var imageEndpoint = EndpointOverride()

    // 语音
    var ttsModel = "cogtts"
    var ttsVoice = "tongtong"
    var sttModel = "glm-asr"
    var speechEndpoint = EndpointOverride()

    // 视频
    var videoModel = "cogvideox-3"
    var videoSubmitPath = "/videos/generations"
    var videoPollPath = "/videos/generations/{id}"
    var videoMode = ""
    var videoEndpoint = EndpointOverride()

    enum CodingKeys: String, CodingKey {
        case baseURL, apiKey
        case chatModel, systemPrompt, chatEndpoint
        case imageModel, imageEndpoint
        case ttsModel, ttsVoice, sttModel, speechEndpoint
        case videoModel, videoSubmitPath, videoPollPath, videoMode, videoEndpoint
    }

    init() {}

    /// 宽松解码：缺字段时回退到默认值，保证老配置升级不崩。
    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(String.self, forKey: .baseURL) { baseURL = value }
        if let value = try container.decodeIfPresent(String.self, forKey: .apiKey) { apiKey = value }
        if let value = try container.decodeIfPresent(String.self, forKey: .chatModel) { chatModel = value }
        if let value = try container.decodeIfPresent(String.self, forKey: .systemPrompt) { systemPrompt = value }
        if let value = try container.decodeIfPresent(EndpointOverride.self, forKey: .chatEndpoint) { chatEndpoint = value }
        if let value = try container.decodeIfPresent(String.self, forKey: .imageModel) { imageModel = value }
        if let value = try container.decodeIfPresent(EndpointOverride.self, forKey: .imageEndpoint) { imageEndpoint = value }
        if let value = try container.decodeIfPresent(String.self, forKey: .ttsModel) { ttsModel = value }
        if let value = try container.decodeIfPresent(String.self, forKey: .ttsVoice) { ttsVoice = value }
        if let value = try container.decodeIfPresent(String.self, forKey: .sttModel) { sttModel = value }
        if let value = try container.decodeIfPresent(EndpointOverride.self, forKey: .speechEndpoint) { speechEndpoint = value }
        if let value = try container.decodeIfPresent(String.self, forKey: .videoModel) { videoModel = value }
        if let value = try container.decodeIfPresent(String.self, forKey: .videoSubmitPath) { videoSubmitPath = value }
        if let value = try container.decodeIfPresent(String.self, forKey: .videoPollPath) { videoPollPath = value }
        if let value = try container.decodeIfPresent(String.self, forKey: .videoMode) { videoMode = value }
        if let value = try container.decodeIfPresent(EndpointOverride.self, forKey: .videoEndpoint) { videoEndpoint = value }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var settings: AppSettings { didSet { persist() } }

    private static let storageKey = "UniAI.settings.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    /// 按功能构造客户端：覆盖值优先，其次全局配置。
    func client(for endpoint: EndpointOverride) -> APIClient {
        let base = endpoint.baseURL.isEmpty ? settings.baseURL : endpoint.baseURL
        let key = endpoint.apiKey.isEmpty ? settings.apiKey : endpoint.apiKey
        return APIClient(config: APIConfig(baseURL: base, apiKey: key))
    }
}
