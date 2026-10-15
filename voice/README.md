# 语音问答模块

这条链路让贾维斯能**听见你说话并用语音回答**。它是独立的：不修改安装目录里的任何文件，
关掉命令行窗口就完全停止，也不会开机自启。

## 它怎么工作

```text
麦克风（ffmpeg 采集，每段 5 秒，带 2.5 倍增益）
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

## 安装

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\安装依赖.ps1
```

脚本会做三件事，已经有的会自动跳过：

1. 下载 **ffmpeg**（约 90 MB）放进 `bin\ffmpeg.exe`——单文件 169 MB，不适合放进仓库；
2. 下载 **whisper 听写模型**（约 466 MB）放进 `model\ggml-small.bin`；
3. 用 npm 安装 **msedge-tts**（在线神经语音用；没有 Node.js 也能用，会自动退回系统语音）。

`bin\whisper\` 里的 whisper.cpp v1.9.5 二进制已经随仓库提供，不需要额外下载。

## 启动

双击 **启动语音问答.bat**，然后对着电脑正常说一句话，说完停住。

> 它**不认唤醒词**，直接说内容即可。说"你好"，它就会回你。

日志写在 `voice-loop.log`，中文不会乱码。

## 配置

### tts.json —— 换声音

```json
{
  "engine": "edge",
  "voice": "zh-CN-YunyangNeural",
  "rate": "-10%",
  "pitch": "-6%"
}
```

| 字段 | 说明 |
| --- | --- |
| `engine` | `edge` = 微软在线神经语音；`system` = Windows 自带离线语音 |
| `voice` | 音色 ID，见下表 |
| `rate` | 语速，负数更慢，范围约 `-50%` ~ `+100%` |
| `pitch` | 音调，负数更低沉，范围约 `-50%` ~ `+50%` |

常用中文音色：

| 音色 ID | 听感 |
| --- | --- |
| `zh-CN-YunyangNeural` | 云扬，沉稳男声（默认） |
| `zh-CN-YunxiNeural` | 云希，年轻男声，偏自然口语 |
| `zh-CN-YunjianNeural` | 云健，浑厚有力 |
| `zh-CN-XiaoxiaoNeural` | 晓晓，女声 |
| `zh-CN-XiaoyiNeural` | 晓伊，年轻女声 |

### voice-loop.ps1 —— 调反应速度和麦克风

参数都在文件开头的 `param()` 里：

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `-Mic` | `麦克风阵列 (Realtek(R) Audio)` | 麦克风设备名。用 `bin\ffmpeg.exe -list_devices true -f dshow -i dummy` 查看自己电脑上的名字 |
| `-ChunkSeconds` | 5 | 每段录音长度。调小反应更快，但说话偏慢会被截断 |
| `-PeakDb` | -45 | 音量门槛，低于它当作环境噪音跳过。误触发多就调高到 `-35` |
| `-Threads` | 12 | 听写占用的 CPU 线程数 |
| `-Engine` | `fast` | `fast` 走云端回答；`local` 强制用本机模型（很慢） |

## 关于"云端回答"

链路里"云端大模型回答"这一步读的是 `%USERPROFILE%\.codex\config.toml` 里的接口配置。
**如果你没有这份配置，它会自动退回本机模型**——功能仍然完整，只是每句话要多等约一分钟。

## 常见问题

**它不回我。**
看 `voice-loop.log`。有"听到：xxx"说明麦克风正常，问题在回答环节；连"听到"都没有，
说明麦克风设备名不对（用上面的命令查真名），或者环境噪音没到音量门槛。

**同一句话被反复回答。**
把 `-PeakDb` 调高到 `-35` 左右。

**在线语音没声音了。**
看日志里有没有"在线语音不可用，改用系统自带语音"。有的话通常是网络断了——这是设计好的兜底，
不影响继续对话。
