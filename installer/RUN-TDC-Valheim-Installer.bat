@echo off
setlocal
title TDC Valheim Installer
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0TDC-Installer-DO-NOT-RUN.ps1"
set "EXITCODE=%ERRORLEVEL%"
echo.
if not "%EXITCODE%"=="0" echo Installer exited with code %EXITCODE%.
pause
exit /b %EXITCODE%
