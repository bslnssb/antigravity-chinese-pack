@echo off
setlocal enabledelayedexpansion

rem ============================================================
rem  Antigravity Chinese Pack - restore the official English app.asar
rem  Copies app.asar.backup (or .bak) over app.asar, drops the .zh-pack
rem  marker so the launcher stops re-applying the patch, then starts
rem  Antigravity from its own exe.
rem ============================================================

set "HERE=%~dp0"
if "%HERE:~-1%"=="\" set "HERE=%HERE:~0,-1%"

echo.
echo  Antigravity Chinese Pack - restore to official English
echo  -----------------------------------------------------
echo.

rem ---- 1. locate resources\app.asar ----
set "RT="
for %%P in ("%LOCALAPPDATA%\Programs\Antigravity\resources" "%PROGRAMFILES%\Antigravity\resources" "%PROGRAMFILES(X86)%\Antigravity\resources") do (
    if exist "%%~P\app.asar" if not defined RT set "RT=%%~P"
)
rem ---- 1b. fall back to the install path recorded in the registry ----
rem     -SetFile + call: PowerShell 5.1 writes output to a pipe as UTF-8 while
rem     cmd's for /f reads ANSI bytes, so a path with Chinese characters in it
rem     (any Chinese user name) never matched. The helper now emits a "set"
rem     line in the console code page instead.
if not defined RT if exist "%HERE%\tools\find-install-dir.ps1" (
    del /f /q "%TEMP%\antigravity-install-dir.bat" >nul 2>&1
    powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%\tools\find-install-dir.ps1" -SetFile "%TEMP%\antigravity-install-dir.bat" >nul 2>&1
    if exist "%TEMP%\antigravity-install-dir.bat" call "%TEMP%\antigravity-install-dir.bat"
    del /f /q "%TEMP%\antigravity-install-dir.bat" >nul 2>&1
)
if defined RT if not exist "%RT%\app.asar" set "RT="

if not defined RT (
    echo  [ERROR] Antigravity not found. Looked in:
    echo          %%LOCALAPPDATA%%\Programs\Antigravity\resources
    echo          %%PROGRAMFILES%%\Antigravity\resources
    echo          the install path recorded in the registry
    echo  Install Antigravity first.
    echo.
    pause
    exit /b 1
)
echo  Install dir : %RT%

set "CUR=%RT%\app.asar"
for %%A in ("%RT%\..") do set "APPDIR=%%~fA"
set "EXE=%APPDIR%\Antigravity.exe"

rem ---- 2. find the backup ----
set "BAK="
if exist "%RT%\app.asar.backup" set "BAK=%RT%\app.asar.backup"
if not defined BAK if exist "%RT%\app.asar.bak" set "BAK=%RT%\app.asar.bak"

if defined BAK goto :havebak
rem     note: keep these echoes OUT of an ( ) block - %RT% can contain
rem     parentheses (C:\Program Files (x86)\...), which would end the block
echo  [NOTICE] No backup found. Looked for:
echo           %RT%\app.asar.backup
echo           %RT%\app.asar.bak
echo  Rename the official app.asar back to app.asar manually,
echo  or reinstall Antigravity.
echo.
pause
exit /b 1

:havebak
echo  Backup      : %BAK%
echo.

rem ---- 3. refuse a backup that is itself patched ----
rem     the Chinese pack stamps this function name into app.asar, so a
rem     backup containing it would just restore the Chinese UI again
findstr /m /c:"__agyTranslateText" "%BAK%" >nul 2>&1
if not errorlevel 1 (
    echo  [ERROR] The backup is itself a Chinese-patched file
    echo          ^(it contains __agyTranslateText^), so restoring it would
    echo          not give you English back.
    echo          Reinstall Antigravity to get a clean app.asar, then run
    echo          一键安装汉化.bat again if you want Chinese later.
    echo.
    pause
    exit /b 1
)

echo  [1/3] Closing Antigravity...
taskkill /f /im Antigravity.exe >nul 2>&1
timeout /t 2 /nobreak >nul

rem ---- 4. copy the official asar back ----
echo  [2/3] Restoring the official app.asar...
set "SKIPPED="
fc /b "%CUR%" "%BAK%" >nul 2>&1
if not errorlevel 1 (
    set "SKIPPED=1"
    echo         Already identical to the backup, nothing to copy.
) else (
    copy /y "%BAK%" "%CUR%" >nul
    if errorlevel 1 (
        echo.
        echo  [ERROR] Copy failed.
        echo          Either Antigravity is still running, or this folder is not
        echo          writable by your account ^(a common case when Antigravity is
        echo          installed under C:\Program Files^).
        echo          Close Antigravity, then right-click
        echo          一键恢复官方英文.bat and choose "Run as administrator".
        echo.
        pause
        exit /b 1
    )
)

rem ---- 4b. size sanity check ----
for %%A in ("%CUR%") do set "CURSZ=%%~zA"
for %%A in ("%BAK%") do set "BAKSZ=%%~zA"
if not "%CURSZ%"=="%BAKSZ%" (
    echo.
    echo  [ERROR] Restore finished but the size does not match the backup
    echo          ^(app.asar %CURSZ% bytes vs backup %BAKSZ% bytes^).
    echo          Reinstall Antigravity, it is in an unknown state.
    echo.
    pause
    exit /b 1
)

rem ---- 5. drop the .zh-pack marker ----
rem     without this the launcher's self-heal puts Chinese back on the very
rem     next start, which looks like "the restore did not work"
echo  [3/3] Removing the .zh-pack marker...
if exist "%RT%\.zh-pack" del /f /q "%RT%\.zh-pack" >nul 2>&1
if exist "%RT%\.zh-pack" (
    echo  [WARN] Could not delete "%RT%\.zh-pack" ^(no permission^).
    echo         The pack will be re-applied on the next start until that file
    echo         is gone. Run this script as administrator to fix it.
)

echo.
echo  Launching the official English Antigravity...
if exist "%EXE%" (
    start "" "%EXE%"
) else (
    echo  [WARN] "%EXE%" not found, start Antigravity yourself.
)

echo.
echo  =========================================================
echo    Restored to the official English version.
echo  =========================================================
echo.
echo  IMPORTANT: from now on start Antigravity from its OWN desktop
echo  shortcut (or Antigravity.exe), NOT from the Chinese launcher
echo  启动反重力.vbs / 反重力（中文版）.
echo  The Chinese launcher heals the pack automatically: whatever you
echo  restore here, it puts Chinese back on the next start by design.
echo.
echo  Want Chinese again later? Just double-click 启动反重力.vbs.
echo.
pause
exit /b 0
