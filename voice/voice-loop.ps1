# AI Jarvis 语音问答循环
#   你对着笔记本说话 -> 本地 whisper 听写成文字 -> 云端 DeepSeek 回答 -> 神经语音念出来
param(
  [string]$Mic = '麦克风阵列 (Realtek(R) Audio)',
  [int]$ChunkSeconds = 5,
  [double]$PeakDb = -45,
  [string]$Server = 'http://127.0.0.1:31847',
  [string]$TestWav = '',
  [string]$Engine = 'fast',
  [int]$Threads = 12,
  [string]$CodexConfig = "$env:USERPROFILE\.codex\config.toml"
)
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
try { Add-Type -AssemblyName System.Windows.Extensions -ErrorAction SilentlyContinue } catch {}

$root = $PSScriptRoot
$ff = Join-Path $root 'bin\ffmpeg.exe'
$cli = Join-Path $root 'bin\whisper\whisper-cli.exe'
$model = Join-Path $root 'model\ggml-small.bin'
$speak = Join-Path $root 'speak.ps1'
$edgeScript = Join-Path $root 'speak-edge.mjs'
$ttsConfig = Join-Path $root 'tts.json'
$mp3 = Join-Path $root 'reply.mp3'
$speakWav = Join-Path $root 'reply.wav'
$wav = Join-Path $root 'chunk.wav'
$replyFile = Join-Path $root 'reply.txt'
$log = Join-Path $root 'voice-loop.log'
$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

# ---------- 念稿设置（想换声音只改 tts.json 就行）----------
$TtsEngine = 'edge'                    # edge = 微软在线神经语音；system = Windows 自带语音
$EdgeVoice = 'zh-CN-YunyangNeural'     # 云扬（男声，沉稳）
$EdgeRate = '-10%'                     # 语速，负数更慢
$EdgePitch = '-6%'                     # 音调，负数更低沉
if (Test-Path -LiteralPath $ttsConfig) {
  try {
    $cfg = Get-Content -LiteralPath $ttsConfig -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($cfg.engine) { $TtsEngine = $cfg.engine }
    if ($cfg.voice) { $EdgeVoice = $cfg.voice }
    if ($cfg.rate) { $EdgeRate = $cfg.rate }
    if ($cfg.pitch) { $EdgePitch = $cfg.pitch }
  } catch { }
}

function Log([string]$message) {
  $line = (Get-Date -Format 'MM-dd HH:mm:ss') + '  ' + $message
  Write-Host $line
  Add-Content -LiteralPath $log -Value $line -Encoding UTF8
}

function Get-DeepSeekToken() {
  if (-not (Test-Path -LiteralPath $CodexConfig)) { return $null }
  foreach ($line in Get-Content -LiteralPath $CodexConfig) {
    if ($line -match '^\s*experimental_bearer_token\s*=\s*"(.*)"') { return $Matches[1] }
  }
  return $null
}

function Ask-DeepSeek([string]$question) {
  $token = Get-DeepSeekToken
  if (-not $token) { return $null }
  $payload = @{
    model = 'deepseek-flash'
    messages = @(
      @{ role = 'system'; content = '你是桌面助手"贾维斯"，用中文口语回答。回答必须简短：一两句话，尽量 40 字以内，像跟人当面说话一样，不要列表、不要markdown、不要客套开场。' },
      @{ role = 'user'; content = $question }
    )
    max_tokens = 900
  } | ConvertTo-Json -Depth 6 -Compress
  try {
    # 同样不能用 Invoke-RestMethod（会把 UTF-8 当 Latin-1 解码成乱码）
    $req = [System.Net.HttpWebRequest]::Create('https://api.deepseek.com/chat/completions')
    $req.Method = 'POST'
    $req.ContentType = 'application/json; charset=utf-8'
    [void]$req.Headers.Add('Authorization', "Bearer $token")
    $req.Timeout = 60000
    $req.ReadWriteTimeout = 60000
    $bytes = [Text.Encoding]::UTF8.GetBytes($payload)
    $req.ContentLength = $bytes.Length
    $stream = $req.GetRequestStream()
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Close()
    $resp = $req.GetResponse()
    $reader = New-Object IO.StreamReader($resp.GetResponseStream(), [Text.Encoding]::UTF8)
    $json = $reader.ReadToEnd()
    $reader.Close()
    $resp.Close()
    $text = ($json | ConvertFrom-Json).choices[0].message.content
    if ($text) { return $text.Trim() }
  } catch {
    Log ('云端回答失败：' + $_.Exception.Message)
  }
  return $null
}

# 用微软在线神经语音念稿：合成 mp3 -> 转 wav -> 播放。成功返回 $true
function Speak-Edge([string]$text) {
  if (-not (Test-Path -LiteralPath $edgeScript)) { return $false }
  $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
  if (-not $nodeCmd) { Log '没有找到 node，跳过在线语音。'; return $false }
  $start = Get-Date
  $out = & $nodeCmd.Source $edgeScript '--text-file' $replyFile '--out' $mp3 '--voice' $EdgeVoice '--rate' $EdgeRate '--pitch' $EdgePitch 2>&1
  if (-not (Test-Path -LiteralPath $mp3)) { Log ('在线语音失败：' + (($out | Out-String).Trim())); return $false }
  if ((Get-Item -LiteralPath $mp3).LastWriteTime -lt $start.AddSeconds(-2)) { Log '在线语音没有产出新音频。'; return $false }
  & $ff -hide_banner -loglevel error -y -i $mp3 $speakWav 2>$null
  if (-not (Test-Path -LiteralPath $speakWav)) { Log '音频转码失败。'; return $false }
  try {
    $player = New-Object System.Media.SoundPlayer($speakWav)
    $player.PlaySync()
    return $true
  } catch {
    Log ('播放失败：' + $_.Exception.Message)
  }
  return $false
}

foreach ($file in @($ff, $cli, $model)) {
  if (-not (Test-Path -LiteralPath $file)) { Log ("缺少文件：" + $file); exit 1 }
}

Log ('语音问答已启动（念稿引擎：' + $TtsEngine + ' / ' + $EdgeVoice + '）：对着笔记本正常说话即可')
if ($TestWav) { Log ('测试模式：只用音频文件 ' + $TestWav + ' 跑一轮') }
$lastText = ''

while ($true) {
  if ($TestWav) {
    if (-not (Test-Path -LiteralPath $TestWav)) { Log '测试音频不存在'; exit 1 }
    $wav = $TestWav
  } else {
    & $ff -hide_banner -loglevel error -f dshow -i ('audio=' + $Mic) -t $ChunkSeconds -ac 1 -ar 16000 -af 'volume=2.5' -y $wav 2>$null
  }
  if (-not (Test-Path -LiteralPath $wav)) { Start-Sleep -Seconds 2; continue }

  if (-not $TestWav) {
    $stats = & $ff -hide_banner -i $wav -af astats -f null - 2>&1
    $peakLine = $stats | Select-String -Pattern 'Peak level dB' | Select-Object -First 1
    $peak = -99.0
    if ($peakLine) {
      $raw = ($peakLine.Line -split ':')[-1].Trim()
      [void][double]::TryParse($raw, [ref]$peak)
    }
    if ($peak -lt $PeakDb) { continue }
  }

  $text = ((& $cli -m $model -f $wav -l zh -nt -np -t $Threads --prompt '以下是普通话的句子，请使用简体中文。' 2>$null) -join ' ').Trim()
  $text = ($text -replace '\s+', '')
  if ($text.Length -lt 2) { continue }
  if ($text -eq $lastText) { continue }
  $lastText = $text
  Log ('听到：' + $text)

  $body = @{ message = $text } | ConvertTo-Json -Compress
  $reply = $null
  $askStart = Get-Date
  if ($Engine -ne 'local') {
    $reply = Ask-DeepSeek $text
  }
  if ($reply) {
    Log ('（云端 ' + [math]::Round(((Get-Date) - $askStart).TotalSeconds,1) + ' 秒）')
  } else {
    Log '云端不可用，改用本机模型（较慢，约 1 分钟）…'
  }
  if (-not $reply) {
    try {
    # 说明：这里不用 Invoke-RestMethod，因为 Windows PowerShell 5.1 会把 UTF-8 响应按
    # Latin-1 解码，导致中文变乱码；下面显式指定 UTF-8 解码。
    $request = [System.Net.HttpWebRequest]::Create($Server + '/api/v1/assistant/chat')
    $request.Method = 'POST'
    $request.ContentType = 'application/json; charset=utf-8'
    $request.Timeout = 900000
    $request.ReadWriteTimeout = 900000
    $payload = [Text.Encoding]::UTF8.GetBytes($body)
    $request.ContentLength = $payload.Length
    $stream = $request.GetRequestStream()
    $stream.Write($payload, 0, $payload.Length)
    $stream.Close()
    $response = $request.GetResponse()
    $reader = New-Object IO.StreamReader($response.GetResponseStream(), [Text.Encoding]::UTF8)
    $json = $reader.ReadToEnd()
    $reader.Close()
    $response.Close()
    $reply = ($json | ConvertFrom-Json).reply
  } catch {
    Log ('提问失败：' + $_.Exception.Message)
  }
  }

  if ($reply) {
    Log ('它回答：' + $reply)
    # 只念前 120 字，避免回答太长导致"念半天"
    $spoken = $reply
    if ($spoken.Length -gt 120) { $spoken = $spoken.Substring(0, 120) }
    [IO.File]::WriteAllText($replyFile, $spoken, (New-Object Text.UTF8Encoding($false)))
    $spokenOk = $false
    if ($TtsEngine -eq 'edge') { $spokenOk = Speak-Edge $spoken }
    if (-not $spokenOk) {
      Log '在线语音不可用，改用系统自带语音。'
      & $psExe -NoProfile -ExecutionPolicy Bypass -File $speak -TextFile $replyFile
    }
  }
  if ($TestWav) { Log '测试模式：一轮结束'; exit 0 }
}
