@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo AI Jarvis 语音问答已启动：对着笔记本正常说话即可。
echo （关闭这个窗口就会停止）
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0voice-loop.ps1"
pause
