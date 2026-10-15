# 来源与授权（Credits & Licenses）

本仓库是二次开发项目，代码与素材来自多个上游。下面逐项列明来源和授权——这既是 GPL-3.0 的要求，
也是对这些作者起码的尊重。

## 1. 基础项目

**[LYiHub/pub-local-jarvis](https://github.com/LYiHub/pub-local-jarvis) — MIT License**

本仓库绝大部分代码来自它：FastAPI 编排层、场景策略、课程与本地记忆、Electron 桌面端、
C++ 原生采集与推理调度、llama.cpp-omni 接入等。

MIT 许可证原文保留在 [LICENSES/MIT-AI-Jarvis-upstream.txt](LICENSES/MIT-AI-Jarvis-upstream.txt)。

## 2. 桌宠视觉层与角色素材（决定本仓库协议的部分）

**[Big-Guan/jarvis-codex](https://github.com/Big-Guan/jarvis-codex) — GNU GPL-3.0**

以下内容移植自该项目：

- `desktop/src/ui/` 下 `pet.html` / `pet.css` / `pet.js` 中的头盔组装动效——
  结构类名 `character-aura`、`character-rig`、`assembly-orbits`、`armor-shard`、
  `helmet-scan`、`assembly-flash`、`particle-field`，关键帧 `character-float`、
  `aura-breathe`、`helmet-scan`、`materialize`、`armor-shard-assemble`、
  `assembly-orbits-in`、`assembly-core-flash`
- `desktop/assets/pet/jarvis-character-v2.png`（角色素材，与上游同名同源）

由于包含了上述 GPL-3.0 内容，**本仓库整体以 GPL-3.0 发布**，全文见 [LICENSE](LICENSE)。
GPL-3.0 要求衍生作品同样开源，这正是本仓库采用该协议的原因。

## 3. 本版自己写的部分

以下文件是本次二次开发新增的，同样以 GPL-3.0 释出：

| 文件 | 作用 |
| --- | --- |
| `desktop/src/ui/particle-map.js` | 离线预生成的粒子坐标表（992 个采样点），绕开 Electron `file://` 下 canvas 读图片像素被判跨域的问题 |
| `desktop/src/ui/pet.js` 等 | 粒子飞行、装甲拼合、扫描线、能量环、呼吸起伏的驱动逻辑 |
| `desktop/src/main.js` | 气泡文字转语音（`speakBubble`）与紧凑窗口尺寸 |
| `native/src/windows/wasapi_mix_capture.cpp` | 系统声音与全部麦克风混音采集（替换原 `wasapi_capture.cpp`） |
| `voice/` | 完整的语音问答链路 |
| `desktop/重新打包界面.ps1` | 只重打界面包，不需要 Python / CUDA / VS |

## 4. 随仓库分发的第三方二进制

**whisper.cpp — MIT License** · <https://github.com/ggml-org/whisper.cpp>

`voice/bin/whisper/` 下是编译好的 Windows 二进制（`whisper-cli.exe`、`whisper.dll`、
`ggml.dll`、`ggml-base.dll`、`ggml-cpu.dll`），对应上游版本 **v1.9.5**。

## 5. 不随仓库分发、需要自行获取的依赖

| 依赖 | 用途 | 获取方式 |
| --- | --- | --- |
| FFmpeg | 麦克风采集、音量检测、音频转码 | `voice/安装依赖.ps1` 自动下载（gyan.dev 官方构建） |
| `ggml-small.bin` | whisper 中文听写模型，约 466 MB | `voice/安装依赖.ps1` 从 hf-mirror 自动下载 |
| MiniCPM-o 4.5 GGUF | 原版本地多模态模型，约 6.32 GB | 原版首次启动时自动下载 |
| `msedge-tts` | 调用微软 Edge 在线语音合成 | `voice/安装依赖.ps1` 用 npm 安装 |

这些文件体积过大或另有授权条款，因此不放进仓库。FFmpeg 为 LGPL/GPL 双授权，本仓库只是
以命令行方式调用它，不修改也不链接。模型权重遵循各发布者的许可。

## 6. 致谢

感谢 **LYiHub** 做出这个项目并开源；感谢 **Big-Guan** 做出视频里那套视觉并开源；
也感谢 **tc-mb/llama.cpp-omni**、**OpenBMB/MiniCPM-V**、**ggml-org/whisper.cpp** 这些上游。
