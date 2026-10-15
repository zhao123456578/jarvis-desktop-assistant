# ============================================================
#  AI Jarvis 语音问答 · 依赖安装
#
#  用法（在 voice 目录下执行）：
#    powershell -NoProfile -ExecutionPolicy Bypass -File .\安装依赖.ps1
#
#  可选参数：
#    -SkipFfmpeg   不下载 ffmpeg
#    -SkipModel    不下载听写模型
#    -SkipNpm      不安装 npm 依赖
#
#  说明：ffmpeg 单文件约 169 MB，听写模型约 466 MB，两者都不随仓库分发。
# ============================================================
param(
  [switch]$SkipFfmpeg,
  [switch]$SkipModel,
  [switch]$SkipNpm
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$root = $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
Set-Location -LiteralPath $root

$binDir   = Join-Path $root 'bin'
$modelDir = Join-Path $root 'model'
$ffmpeg   = Join-Path $binDir 'ffmpeg.exe'
$model    = Join-Path $modelDir 'ggml-small.bin'

function Say($t, $c) {
  if (-not $c) { $c = 'Gray' }
  Write-Host $t -ForegroundColor $c
}

function Get-RemoteFile([string]$url, [string]$dest) {
  Say ("    地址：" + $url) 'DarkGray'
  $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
  if ($curl) {
    & $curl.Source -L --fail --retry 3 --retry-delay 3 -o $dest $url
    if ($LASTEXITCODE -ne 0) { throw ("下载失败，curl 返回 " + $LASTEXITCODE + "。检查网络后重试。") }
  } else {
    $old = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
    $ProgressPreference = $old
  }
  if (-not (Test-Path -LiteralPath $dest)) { throw "下载结束但没有找到文件" }
}

Say ""
Say "  == AI Jarvis 语音问答 · 依赖安装 ==" 'Cyan'
Say ("  目录：" + $root) 'DarkGray'
Say ""

# ---------- 1. FFmpeg ----------
if (-not $SkipFfmpeg) {
  Say "[1/3] FFmpeg（麦克风采集与音频转码）" 'Cyan'
  if (Test-Path -LiteralPath $ffmpeg) {
    Say "    已经装好了，跳过。" 'Green'
  } else {
    New-Item -ItemType Directory -Force -Path $binDir | Out-Null
    $zip = Join-Path $env:TEMP 'ffmpeg-release-essentials.zip'
    Say "    下载中（约 90 MB），可能要几分钟…"
    Get-RemoteFile 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip' $zip
    $unpack = Join-Path $env:TEMP ('ffmpeg-unpack-' + ([guid]::NewGuid().ToString('N').Substring(0, 8)))
    Say "    解压中…"
    Expand-Archive -LiteralPath $zip -DestinationPath $unpack -Force
    $found = Get-ChildItem -LiteralPath $unpack -Recurse -Filter 'ffmpeg.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $found) { throw "解压后没找到 ffmpeg.exe，请手动下载 ffmpeg 放到 bin\ffmpeg.exe" }
    Copy-Item -LiteralPath $found.FullName -Destination $ffmpeg -Force
    Say ("    [完成] " + $ffmpeg) 'Green'
    Say ("    临时文件在这里，确认能用之后可以自己删掉：" + $zip) 'DarkGray'
  }
}

# ---------- 2. 听写模型 ----------
if (-not $SkipModel) {
  Say ""
  Say "[2/3] 听写模型 ggml-small.bin（约 466 MB）" 'Cyan'
  if (Test-Path -LiteralPath $model) {
    Say "    已经下过了，跳过。" 'Green'
  } else {
    New-Item -ItemType Directory -Force -Path $modelDir | Out-Null
    Say "    下载中，这一段比较久，别关窗口…"
    Get-RemoteFile 'https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/ggml-small.bin' $model
    $mb = [math]::Round((Get-Item -LiteralPath $model).Length / 1MB, 1)
    Say ("    [完成] " + $mb + " MB") 'Green'
  }
}

# ---------- 3. 在线语音依赖 ----------
if (-not $SkipNpm) {
  Say ""
  Say "[3/3] 在线神经语音依赖 msedge-tts" 'Cyan'
  $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
  if (-not $npm) { $npm = Get-Command npm -ErrorAction SilentlyContinue }
  if ($npm) {
    & $npm.Source install --no-audit --no-fund
    if ($LASTEXITCODE -eq 0) {
      Say "    [完成]" 'Green'
    } else {
      Say "    npm 安装失败，联网后可以重新执行一次本脚本。" 'Yellow'
    }
  } else {
    Say "    没有找到 Node.js。" 'Yellow'
    Say "    不影响基本使用：没有它会自动退回 Windows 自带语音。" 'Yellow'
    Say "    想用在线神经语音，先装 Node.js LTS：https://nodejs.org/zh-cn" 'Yellow'
  }
}

# ---------- 收尾检查 ----------
Say ""
Say "  == 检查结果 ==" 'Cyan'
$checks = @(
  @{ name = 'FFmpeg        '; path = $ffmpeg },
  @{ name = '听写模型      '; path = $model },
  @{ name = 'whisper 可执行'; path = (Join-Path $root 'bin\whisper\whisper-cli.exe') }
)
foreach ($c in $checks) {
  if (Test-Path -LiteralPath $c.path) { Say ("    [有] " + $c.name) 'Green' }
  else { Say ("    [缺] " + $c.name + "  ->  " + $c.path) 'Yellow' }
}
Say ""
Say "  都齐了之后，双击「启动语音问答.bat」就能用了。" 'White'
Say ""
