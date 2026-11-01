@echo off
title Antigravity Restore to Official English
echo =========================================================
echo    Antigravity Restore to Official English
echo =========================================================
echo.

set "TARGET_DIR=%LOCALAPPDATA%\Programs\antigravity\resources"
set "TARGET_ASAR=%TARGET_DIR%\app.asar"
set "BACKUP_ASAR="

rem Accept both backup names: the README tells users to rename to
rem app.asar.bak, while the maintainer script writes app.asar.backup.
if exist "%TARGET_DIR%\app.asar.backup" set "BACKUP_ASAR=%TARGET_DIR%\app.asar.backup"
if not defined BACKUP_ASAR if exist "%TARGET_DIR%\app.asar.bak" set "BACKUP_ASAR=%TARGET_DIR%\app.asar.bak"

if not defined BACKUP_ASAR (
    echo [NOTICE] No backup found. Looked for:
    echo          %TARGET_DIR%\app.asar.backup
    echo          %TARGET_DIR%\app.asar.bak
    echo          Rename the official app.asar back to app.asar manually,
    echo          or reinstall Antigravity.
    pause
    exit /b 1
)

echo [1/2] Closing Antigravity...
taskkill /f /im Antigravity.exe >nul 2>&1
timeout /t 2 /nobreak >nul

echo [2/2] Restoring official English app.asar...
copy /y "%BACKUP_ASAR%" "%TARGET_ASAR%" >nul

echo Launching official English Antigravity...
start "" "%LOCALAPPDATA%\Programs\antigravity\Antigravity.exe"
echo.
echo =========================================================
echo    Restored to official English version successfully!
echo =========================================================
timeout /t 3 >nul
