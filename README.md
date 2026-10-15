<div align="center">
  <img src="desktop/assets/pet/jarvis-character-v2.png" width="200" alt="AI Jarvis desktop assistant">
  <h1>AI Jarvis — Desktop Assistant</h1>
  <p><strong>A Windows desktop assistant that hears what you say and answers out loud.</strong></p>
  <p>能听懂你说话、用神经语音回答的桌面助手（Windows）</p>
  <p>Windows · helmet assembly animation · microphone full-duplex · cloud-fast Q&amp;A · swappable voice</p>
</div>

<p align="center">
  <a href="#english"><strong>English</strong></a> ·
  <a href="#这是什么">这是什么</a> ·
  <a href="#本版做了什么">本版做了什么</a> ·
  <a href="#快速开始">快速开始</a> ·
  <a href="#语音问答模块">语音问答模块</a> ·
  <a href="#常见问题">常见问题</a> ·
  <a href="#许可证与来源">许可证与来源</a>
</p>

---

## 这是什么

这是 [LYiHub/pub-local-jarvis](https://github.com/LYiHub/pub-local-jarvis) 的**二次开发版**。
原版是一个"能看屏幕、能听系统声音"的桌宠助手：用本地多模态模型持续理解你的桌面画面和电脑正在播放的声音，
在合适的时候弹气泡提醒你，还能记网课笔记。它的定位是**陪伴**。

但原版有两个在实际使用中会立刻撞上的墙：

- **你对着麦克风说话，它听不见。** 原版只采集系统播放的声音（WASAPI 回路），不采集麦克风。
- **回答要等大约一分钟。** 全部靠本地大模型推理，且原版明确表示不提供语音播报。

本版把这条路补完了：**你说话 → 本地听写成文字 → 云端大模型回答（1~2 秒）→ 用神经语音念给你听**，
并把桌宠形象换成了那种"碎片组装成头盔"的动效。

## 本版做了什么

| 方面 | 原版 | 本版 |
| --- | --- | --- |
| 桌宠形象 | 静态 GIF 小宠物 | 高清头盔素材 + 完整组装动效：992 颗粒子从窗口边缘飞入、19 块装甲碎片拼合、扫描线、能量环、呼吸起伏 |
| 听见你说话 | 只采集**系统播放的声音**，对麦克风说话听不到 | 原生采集层重写：**系统声音 + 全部可用麦克风自动混音**，可用环境变量单独开关 |
| 回答速度 | 本地模型推理，一句话约 60 秒 | 云端大模型，实测拿到回答 **1~2 秒** |
| 语音播报 | 无 | **微软 Edge 在线神经语音**（默认云扬），语速/音调可调，断网自动退回系统语音 |
| 语音问答 | 无 | 独立模块 `voice/`，双击即用，不依赖界面 |

改的过程中有两个坑值得记一笔，因为任何人接着改这个项目都会撞上：

1. **Electron 用 `file://` 加载页面时，canvas 读图片像素会被判跨域**，"从图片采样生成粒子"这条路必然失败。
   本版改成**离线预生成粒子坐标表**（`desktop/src/ui/particle-map.js`），彻底绕开。
2. **Windows PowerShell 5.1 的 `Invoke-RestMethod` 会把 UTF-8 响应按 Latin-1 解码**，中文全部变乱码。
   本版所有 HTTP 调用改成 `HttpWebRequest` + 显式 UTF-8 解码。

## 快速开始

### 路线一：只想要"说一句就回答"（最省事）

不需要装 Python、CUDA，也不需要重新构建任何东西。

1. 先装好原版 AI Jarvis（安装包 + 首次模型下载，步骤见 [README-upstream.md](README-upstream.md)）；
2. 把本仓库下载到本地；
3. 在 PowerShell 里进入 `voice` 目录，执行：

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\安装依赖.ps1
   ```

   它会自动下载 ffmpeg 和听写模型（合计约 570 MB），第一次要等几分钟；
4. 双击 `voice\启动语音问答.bat`，然后对着电脑正常说一句话，说完停住。

### 路线二：连界面的头盔动效一起要

界面部分只需要 **Node.js**，不需要 Python / CUDA / Visual Studio。

1. 完成路线一的第 1 步；
2. 在 PowerShell 里进入 `desktop` 目录，执行：

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\重新打包界面.ps1
   ```

3. 脚本会生成新的 `app.asar` 并打印替换步骤（**替换前先备份原文件**）。

### 路线三：从源码完整构建

需要 Python 3.12+、Git、CMake 3.24+、Visual Studio C++ Build Tools、Node.js LTS；
构建安装包还需要 CUDA Toolkit 13.1 或更新版本。

```powershell
cd desktop
npm run deps:install
cd ..
.\start-real.cmd
```

完整的依赖说明、CUDA 故障排查、从零构建安装包等，见 [README-upstream.md](README-upstream.md)
（上游原版文档，本版未改动其内容）。

## 语音问答模块

`voice/` 是一条独立链路：随时可以停，不依赖界面，也不修改安装目录里的任何文件。

```text
麦克风（ffmpeg 采集，5 秒一段，带 2.5 倍增益）
        |
        v
本地 whisper.cpp 听写（12 线程，约 3 秒）
        |
        v
云端大模型回答（约 1~2 秒）
        |
        v
微软 Edge 在线神经语音念出来（约 1 秒）
```

从你说完到听见回答，大约 **5~7 秒**。

### 换音色

改 `voice/tts.json` 即可，不用动代码：

```json
{
  "engine": "edge",
  "voice": "zh-CN-YunyangNeural",
  "rate": "-10%",
  "pitch": "-6%"
}
```

`rate` 是语速（负数更慢），`pitch` 是音调（负数更低沉）。常用中文音色：

| 音色 ID | 听感 |
| --- | --- |
| `zh-CN-YunyangNeural` | 云扬，沉稳男声（默认） |
| `zh-CN-YunxiNeural` | 云希，年轻男声，偏自然口语 |
| `zh-CN-YunjianNeural` | 云健，浑厚有力 |
| `zh-CN-XiaoxiaoNeural` | 晓晓，女声 |

把 `engine` 改成 `system`，就退回 Windows 自带的离线语音（完全不需要联网）。

### 速度调节

`voice/voice-loop.ps1` 顶部的参数：

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `-ChunkSeconds` | 5 | 每段录音长度。调小反应更快，但说话慢会被截断 |
| `-Threads` | 12 | 听写占用的 CPU 线程数 |
| `-PeakDb` | -45 | 音量门槛，低于它当作环境噪音跳过 |
| `-Mic` | 麦克风阵列 | 麦克风设备名，用 `ffmpeg -list_devices true -f dshow -i dummy` 查看 |

## 常见问题

**它不回我。**
先看 `voice\voice-loop.log`。如果有"听到：xxx"，说明麦克风正常，问题在回答环节；
如果连"听到"都没有，那是麦克风设备名不对，或者环境噪音没达到音量门槛。

**说"你好贾维斯"没反应。**
本版**不认唤醒词**，直接说内容就行——说"你好"它就会回你。

**它一直在重复回答同一句话。**
日志里如果同一句被听写多次，把 `-PeakDb` 调高一些（比如 `-35`）。

**怎么临时关掉？**
关掉那个命令行窗口，或在任务管理器里结束对应的 PowerShell 进程。它不会开机自启。

**为什么需要比较高权限？**
原版要采集屏幕和声音，本身就需要较高权限。本版没有新增权限需求。

## 许可证与来源

**本仓库以 [GPL-3.0](LICENSE) 发布。**

这里需要解释一句：原版项目是 MIT 协议，但本版移植的桌宠视觉动效和角色素材来自
[Big-Guan/jarvis-codex](https://github.com/Big-Guan/jarvis-codex)，那个项目是 **GPL-3.0**。
GPL-3.0 的传染性要求——**使用了它的代码，整个作品必须以 GPL-3.0 发布**。
所以本仓库不能是 MIT。

这不影响任何人使用、修改甚至商用，只要求一件事：**你改完之后也要开源**。

各部分的来源与授权细节见 [CREDITS.md](CREDITS.md)。

## 贡献

欢迎提 Issue 和 PR。几个比较有价值的方向：

- **一键安装包**：把语音模块和界面动效打包成安装程序（现在要手工几步）
- **唤醒词**：现在是一直在听，不需要喊唤醒词，但也意味着它一直在录音
- **更快的本地听写**：whisper small 模型约占 3 秒，换 GPU 加速或更小模型还能再压
- **macOS 适配**：本版的原生采集层用的是 Windows 专有 API

---

## English

**AI Jarvis — Desktop Assistant** is a Windows desktop assistant forked from
[LYiHub/pub-local-jarvis](https://github.com/LYiHub/pub-local-jarvis).

The original watches your screen and the audio your PC plays. This fork adds what was missing:

- **It actually hears you.** The native capture layer was rewritten to mix system audio with *all*
  available microphones — upstream only captured system playback, so talking to your mic did nothing.
- **It answers out loud, quickly.** A new `voice/` module chains microphone → local whisper.cpp
  transcription (~3 s) → cloud LLM answer (~1–2 s) → Microsoft Edge neural speech (~1 s).
  Roughly 5–7 seconds from the moment you stop talking.
- **Jarvis-style animation.** The desktop pet is a helmet that assembles itself: 992 particles
  flying in from the window edges, 19 armor shards, scan lines, energy rings, a breathing glow.
  Ported from [Big-Guan/jarvis-codex](https://github.com/Big-Guan/jarvis-codex).

### Quick start (voice only)

No Python, CUDA or Visual Studio needed — just the official AI Jarvis install and Node.js.

```powershell
git clone https://github.com/zhao123456578/jarvis-desktop-assistant
cd jarvis-desktop-assistant/voice
powershell -NoProfile -ExecutionPolicy Bypass -File .\安装依赖.ps1   # downloads ffmpeg + whisper model
```

Then launch `启动语音问答.bat` and simply talk. There is **no wake word** — say "hello" and it answers.

> Most in-repo documentation is written in Chinese, the project's main audience. Some script
> filenames are Chinese too: `安装依赖.ps1` = install dependencies, `启动语音问答.bat` = start the
> voice loop, `重新打包界面.ps1` = repack the UI bundle (Node.js only, no build toolchain).
> Issues and pull requests in English are welcome.

**Licensed GPL-3.0**, because the ported visual layer is GPL-3.0. See [CREDITS.md](CREDITS.md).
