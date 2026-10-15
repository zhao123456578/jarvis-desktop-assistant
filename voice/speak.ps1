param(
  [string]$TextFile,
  [string]$Text
)
Add-Type -AssemblyName System.Speech
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
try { $synth.SelectVoice('Microsoft Huihui Desktop') } catch {}
$synth.Rate = 1
$synth.Volume = 100
$content = ''
if ($TextFile -and (Test-Path -LiteralPath $TextFile)) {
  $content = [IO.File]::ReadAllText($TextFile, [Text.Encoding]::UTF8)
} elseif ($Text) {
  $content = $Text
}
if ($content) { $synth.Speak($content) }
$synth.Dispose()
