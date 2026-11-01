@echo off
setlocal
title Antigravity - Enable Auto Update
echo.
echo  ============================================================
echo    Enable Antigravity auto-update (undo)
echo  ============================================================
echo.
echo  Restores the official default: the client checks for updates
echo  10 seconds after launch and then once an hour.
echo.
echo  Heads-up: after the next official update lands, resources\
echo  app.asar is replaced and the Chinese patch is gone. Just run
echo  一键安装汉化.bat again afterwards.
echo.
echo  ------------------------------------------------------------
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\auto-update-toggle.ps1" -Value true
if errorlevel 1 (
    echo.
    echo  [FAILED] Nothing was changed.
    echo.
    pause
    exit /b 1
)

echo  [OK] Auto-update enabled.
echo.
pause
exit /b 0
