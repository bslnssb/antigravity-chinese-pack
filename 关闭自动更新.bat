@echo off
setlocal
title Antigravity - Disable Auto Update
echo.
echo  ============================================================
echo    Disable Antigravity auto-update
echo  ============================================================
echo.
echo  Why: a full official update overwrites resources\app.asar and
echo  deletes app.asar.backup, so the Chinese patch disappears.
echo  This switches off the official setting autoCheckForUpdates,
echo  so the client stops contacting the update server.
echo.
echo  Safe and reversible: run 恢复自动更新.bat to turn it back on.
echo  You can still update manually from the app menu any time.
echo.
echo  ------------------------------------------------------------
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\auto-update-toggle.ps1" -Value false
if errorlevel 1 (
    echo.
    echo  [FAILED] Nothing was changed.
    echo.
    pause
    exit /b 1
)

echo  [OK] Auto-update disabled.
echo.
echo  Now start Antigravity. The Chinese patch will stay put
echo  across restarts, because no update is ever downloaded.
echo.
pause
exit /b 0
