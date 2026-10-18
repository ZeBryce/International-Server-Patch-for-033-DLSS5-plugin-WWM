@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0patch-033.ps1" -Action Apply %*
echo.
pause
