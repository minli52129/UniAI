import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    private var settings: Binding<AppSettings> {
        $settingsStore.settings
    }

    var body: some View {
        Form {
            Section("服务端（OpenAI 兼容）") {
                LabeledContent("Base URL") {
                    TextField("https://open.bigmodel.cn/api/paas/v4", text: settings.baseURL)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("API Key") {
                    SecureField("sk-…", text: settings.apiKey)
                        .textFieldStyle(.roundedBorder)
                }
                Text("四个功能共用上面的地址和密钥，也可以在下方为单个功能覆盖（例如对话用 OpenAI、视频用智谱）。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("文字对话") {
                LabeledContent("模型") {
                    TextField("glm-4-flash / gpt-4o-mini / …", text: settings.chatModel)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("系统提示词") {
                    TextField("可选：为模型设定人设或规则", text: settings.systemPrompt)
                        .textFieldStyle(.roundedBorder)
                }
                endpointEditor("对话服务覆盖", settings.chatEndpoint)
            }

            Section("图片生成") {
                LabeledContent("模型") {
                    TextField("cogview-3-flash / dall-e-3 / …", text: settings.imageModel)
                        .textFieldStyle(.roundedBorder)
                }
                endpointEditor("图片服务覆盖", settings.imageEndpoint)
            }

            Section("语音") {
                LabeledContent("合成模型") {
                    TextField("cogtts / tts-1 / …", text: settings.ttsModel)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("合成音色") {
                    TextField("tongtong / alloy / …", text: settings.ttsVoice)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("识别模型") {
                    TextField("glm-asr / whisper-1 / …", text: settings.sttModel)
                        .textFieldStyle(.roundedBorder)
                }
                endpointEditor("语音服务覆盖", settings.speechEndpoint)
            }

            Section("视频生成（提交任务 + 轮询）") {
                LabeledContent("模型") {
                    TextField("cogvideox-3 / sora-2 / …", text: settings.videoModel)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("提交路径") {
                    TextField("/videos/generations", text: settings.videoSubmitPath)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("轮询路径") {
                    TextField("/videos/generations/{id}", text: settings.videoPollPath)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("mode 参数") {
                    TextField("如 Agnes 填 text；留空不发送", text: settings.videoMode)
                        .textFieldStyle(.roundedBorder)
                }
                Text("OpenAI Sora 配置示例：提交 /videos、轮询 /videos/{id}；应用在任务成功后会自动尝试从「提交路径 + /{id}/content」下载成片。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                endpointEditor("视频服务覆盖", settings.videoEndpoint)
            }

            Section("说明") {
                Text("配置保存在本机 UserDefaults（明文），历史对话保存在 ~/Library/Application Support/UniAI/。请勿在公用电脑上保存敏感密钥。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("恢复默认设置", role: .destructive) {
                    settingsStore.settings = AppSettings()
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
        .navigationTitle("设置")
    }

    private func endpointEditor(_ title: String, _ endpoint: Binding<EndpointOverride>) -> some View {
        DisclosureGroup {
            LabeledContent("Base URL") {
                TextField("留空使用全局配置", text: endpoint.baseURL)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("API Key") {
                SecureField("留空使用全局配置", text: endpoint.apiKey)
                    .textFieldStyle(.roundedBorder)
            }
        } label: {
            Text(title)
        }
    }
}
