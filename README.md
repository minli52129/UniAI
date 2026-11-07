# UniAI — macOS 原生 AI 工作台

一个纯 SwiftPM 构建、**不需要 Xcode 工程**的 macOS 原生应用（SwiftUI），统一接入自定义大模型服务：

- 💬 **文字对话**：OpenAI 兼容 `/chat/completions`，流式输出，多会话本地保存
- 🖼 **图片生成**：OpenAI 兼容 `/images/generations`，同时兼容返回 URL 或 `b64_json` 的服务
- 🎙 **语音**：文字转语音（`/audio/speech`，自动播放 / 导出）+ 语音转文字（`/audio/transcriptions`，支持录音或选音频文件）
- 🎬 **视频生成**：通用「提交任务 + 轮询」模式，默认适配智谱 CogVideoX，也兼容 OpenAI Sora
- ⚙️ **自定义接入**：全局 Base URL / API Key，且每个功能可单独覆盖服务端与密钥（例如对话用 OpenAI、视频用智谱）

编译完全在 GitHub Actions 上完成，本机无需安装 Xcode。

## 快速开始（本机不需要 Xcode）

1. 在 GitHub 创建仓库，把本目录推上去：

   ```bash
   cd UniAI
   git init && git add . && git commit -m "init"
   git remote add origin git@github.com:<你的用户名>/<仓库名>.git
   git push -u origin main
   ```

2. 打开仓库 **Actions** 页，等待 `Build macOS App` 变绿；
3. 在该次运行页面底部 **Artifacts** 下载 `UniAI-macOS.zip`；
4. 解压得到 `UniAI.app`，首次打开如提示无法验证开发者（ad-hoc 签名的正常现象），执行：

   ```bash
   xattr -cr UniAI.app
   open UniAI.app
   ```

   或右键 → 打开。
5. 打开 App → 「设置」，填入服务端地址和 API Key 即可使用。

## 发布版本

打 tag 自动创建 GitHub Release 并附上 zip：

```bash
git tag v1.0.0 && git push origin v1.0.0
```

> 注意：私有仓库使用 GitHub 托管 macOS 构建机消耗的额度较大（约 10 倍计费倍率），公开仓库免费。

## 默认配置与常见服务商

App 默认按**智谱开放平台**（OpenAI 兼容）配置，一个 Key 即可用全部四个功能：

| 功能 | 端点（相对 Base URL） | 默认模型 |
| ---- | ---- | ---- |
| 对话 | POST `/chat/completions` | glm-4-flash |
| 图片 | POST `/images/generations` | cogview-3-flash |
| 语音合成 | POST `/audio/speech` | cogtts（音色 tongtong） |
| 语音识别 | POST `/audio/transcriptions` | glm-asr |
| 视频 | POST `/videos/generations`，轮询 GET `/videos/generations/{id}` | cogvideox-3 |

默认 Base URL：`https://open.bigmodel.cn/api/paas/v4`。模型名请以各平台文档为准，App 内可随时修改。

### Agnes AI（已实测）

免费全模态网关 [apihub.agnes-ai.com](https://apihub.agnes-ai.com)，OpenAI 兼容：

| 设置项 | 值 |
| ---- | ---- |
| Base URL | `https://apihub.agnes-ai.com/v1` |
| 对话模型 | agnes-3.0-flash（或 agnes-2.5-flash / agnes-2.5-pro-alpha） |
| 图片模型 | agnes-image-2.5-flash |
| 视频 | agnes-video-2.5-flash，提交 `/videos`、轮询 `/videos/{id}`，**mode 参数填 `text`** |
| 语音 | Agnes 暂未开放音频端点，可在「语音服务覆盖」里指向任意支持 `/audio/speech`、`/audio/transcriptions` 的服务 |

视频任务提交后若返回 `video_queue_full`，是免费队列繁忙，稍后再试即可。

### 换成 OpenAI

| 设置项 | 值 |
| ---- | ---- |
| Base URL | `https://api.openai.com/v1` |
| 对话模型 | gpt-4o-mini |
| 图片模型 | dall-e-3 |
| 合成模型 / 音色 | tts-1 / alloy |
| 识别模型 | whisper-1 |
| 视频 | sora-2，提交 `/videos`、轮询 `/videos/{id}`（应用会自动从 `/videos/{id}/content` 下载成片） |

### 本地模型（Ollama / LM Studio）

- Ollama：Base URL `http://localhost:11434/v1`，API Key 随意填，对话模型如 `qwen2.5`
- LM Studio：Base URL `http://localhost:1234/v1`

本地推理服务一般只提供对话端点；图片 / 语音 / 视频可在对应功能的「服务覆盖」里分别指向别的服务商。

## 项目结构

```
UniAI/
├── Package.swift                  # SwiftPM 清单（零第三方依赖）
├── Scripts/
│   ├── package_app.sh             # 组装 .app（含 ad-hoc 签名）
│   └── generate_icon.swift        # 生成应用图标（CI 中调用）
├── .github/workflows/build.yml    # Actions：构建 + 打包 + 发布
└── Sources/UniAI/
    ├── Info.plist
    ├── App.swift                  # @main
    ├── Core/
    │   ├── APIClient.swift        # HTTP / SSE 流式 / multipart
    │   ├── ChatStore.swift        # 会话持久化
    │   ├── Errors.swift
    │   └── SettingsStore.swift    # 配置持久化
    └── Features/
        ├── ContentView.swift      # 侧边栏导航
        ├── ChatView.swift         # 文字对话
        ├── ImageView.swift        # 图片生成
        ├── SpeechView.swift       # 语音合成 / 识别
        ├── VideoView.swift        # 视频生成
        ├── SettingsView.swift     # 设置
        └── Components.swift       # 消息气泡 / 通用错误弹窗
```

## 本地开发（可选）

不装完整 Xcode 也可以：`xcode-select --install` 装好命令行工具后：

```bash
swift run                                    # 调试运行
swift build -c release --arch arm64          # 本机架构
swift build -c release --arch x86_64         # Intel 架构（打包脚本会自动用 lipo 合并两者）
./Scripts/package_app.sh                     # 打包出 build/UniAI.app
```

（本机连命令行工具都不想装的话，全部交给 GitHub Actions 即可。）

## 技术说明

- 纯 Swift Package Manager：`Info.plist` 通过链接参数内嵌进可执行文件，`Scripts/package_app.sh` 负责组装 `.app`（两个架构的产物自动 lipo 合并）；
- CI 在 `macos-15` 上产出 arm64 + x86_64 通用二进制，ad-hoc 签名（无需开发者账号）；
- 未做 Apple 公证（notarization）。分发给别人时对方需 `xattr -cr` 或右键打开；如你有开发者账号，可在工作流中自行加入 Developer ID 签名与公证步骤；
- API Key 保存在本机 UserDefaults（明文），历史对话保存在 `~/Library/Application Support/UniAI/chats.json`；
- Info.plist 允许任意网络（ATS），以便接入 `http://localhost` 的本地模型；
- 修改应用名：改 `Package.swift` 的 target 名、`Info.plist` 的 `CFBundleName/CFBundleExecutable`、`Scripts/package_app.sh` 的 `APP_NAME`。

## 常见问题

- **提示"已损坏，无法打开"**：执行 `xattr -cr UniAI.app`（ad-hoc 签名应用的正常现象）。
- **对话报 404 / model not found**：检查 Base URL 是否带 `/v1`、`/v4` 等版本段，以及模型名是否正确。
- **对话没有流式输出**：对话使用 SSE（`stream: true`），请确认服务支持流式。
- **录音没反应**：到「系统设置 → 隐私与安全性 → 麦克风」给 UniAI 授权；直接 `swift run` 的裸二进制 macOS 可能无法授权，请使用打包后的 `.app`。
- **视频一直轮询**：视频接口各服务商差异较大，可在「设置 → 视频生成」自定义提交 / 轮询路径；应用默认 3 秒轮询、15 分钟超时。
