# ============================================================
#  只重新打包界面（生成 app.asar）
#
#  用处：装好官方 AI Jarvis 安装包之后，只想把界面换成带头盔动效的版本。
#        这个过程只需要 Node.js —— 不需要 Python、CUDA、Visual Studio。
#
#  用法（在 desktop 目录下执行）：
#    powershell -NoProfile -ExecutionPolicy Bypass -File .\重新打包界面.ps1
#
#  参数：
#    -OutFile <路径>   指定生成位置，默认生成到仓库根目录的 app.asar
# ============================================================
param([string]$OutFile = '')

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$root = $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
if (-not $OutFile) { $OutFile = Join-Path (Split-Path $root -Parent) 'app.asar' }

function Say($t, $c) {
  if (-not $c) { $c = 'Gray' }
  Write-Host $t -ForegroundColor $c
}

Say ""
Say "  == 重新打包界面 ==" 'Cyan'
Say ("  源码：" + $root) 'DarkGray'
Say ""

# ---------- 1. 检查 Node.js ----------
$node = Get-Command node.exe -ErrorAction SilentlyContinue
if (-not $node) { $node = Get-Command node -ErrorAction SilentlyContinue }
if (-not $node) {
  Say "  [x] 没找到 Node.js。装一个 LTS 版本再回来：https://nodejs.org/zh-cn" 'Red'
  exit 1
}
$npx = Get-Command npx.cmd -ErrorAction SilentlyContinue
if (-not $npx) { $npx = Get-Command npx -ErrorAction SilentlyContinue }
if (-not $npx) {
  Say "  [x] 没找到 npx（Node.js 自带的工具）。建议重新安装 Node.js LTS。" 'Red'
  exit 1
}
Say ("  [OK] Node.js：" + (& $node.Source --version)) 'Green'

# ---------- 2. 生产依赖 ----------
$nm = Join-Path $root 'node_modules'
if (-not (Test-Path -LiteralPath $nm)) {
  Say "  缺少 node_modules，先安装生产依赖（很小，只有 lucide 和 ws）…" 'Cyan'
  $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
  if (-not $npm) { $npm = Get-Command npm -ErrorAction SilentlyContinue }
  if (-not $npm) {
    Say "  [x] 没找到 npm，无法安装依赖。" 'Red'
    exit 1
  }
  Set-Location -LiteralPath $root
  & $npm.Source install --omit=dev --no-audit --no-fund
  if ($LASTEXITCODE -ne 0) {
    Say "  [x] 依赖安装失败，检查网络后重试。" 'Red'
    exit 1
  }
  Say "  [OK] 依赖安装完成。" 'Green'
} else {
  Say "  [OK] node_modules 已存在。" 'Green'
}

# ---------- 3. 只把该进包的东西拷到暂存目录 ----------
# 安装包里的 app.asar 只包含 package.json、src/、assets/、node_modules/，
# 不含 scripts/、test/ 这些开发用文件，这里保持一致。
$stage = Join-Path $env:TEMP ('jarvis-asar-' + ([guid]::NewGuid().ToString('N').Substring(0, 8)))
New-Item -ItemType Directory -Force -Path $stage | Out-Null

foreach ($item in @('package.json', 'src', 'assets', 'node_modules')) {
  $from = Join-Path $root $item
  if (Test-Path -LiteralPath $from) {
    Copy-Item -LiteralPath $from -Destination $stage -Recurse -Force
  }
}
Say "  [OK] 已准备暂存目录。" 'Green'

# ---------- 4. 打包 ----------
Say "  正在打包（第一次会自动下载 asar 工具）…" 'Cyan'
Set-Location -LiteralPath $root
& $npx.Source '--yes' '@electron/asar' 'pack' $stage $OutFile
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $OutFile)) {
  Say "  [x] 打包失败。多数情况是网络问题，重试一次即可。" 'Red'
  exit 1
}

$mb = [math]::Round((Get-Item -LiteralPath $OutFile).Length / 1MB, 1)
Say ""
Say ("  [完成] 新的界面包：" + $OutFile + "（" + $mb + " MB）") 'Green'
Say ("  暂存目录可以自己删掉：" + $stage) 'DarkGray'

# ---------- 5. 替换说明 ----------
$install = Join-Path $env:LOCALAPPDATA 'Programs\AI Jarvis\resources'
Say ""
Say "  == 怎么换成新界面 ==" 'Cyan'
Say "    1. 完全退出 AI Jarvis（任务管理器里确认没有残留进程）"
Say ("    2. 打开安装目录：" + $install)
Say "    3. 先把原来的 app.asar 改名备份，例如改成 app.asar.original"
Say "    4. 把新生成的 app.asar 复制进去"
Say "    5. 重新启动 AI Jarvis"
Say ""
Say "    换回去：把备份改回 app.asar 即可。" 'DarkGray'
Say ""
