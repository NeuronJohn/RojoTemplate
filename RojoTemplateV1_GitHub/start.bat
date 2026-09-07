@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".rojo-template\launcher.ps1"
exit /b %ERRORLEVEL%
