@echo off
setlocal enabledelayedexpansion

rem ============================================================
rem  Antigravity Chinese Pack - installer
rem  Applies app.asar.zh-^<version^> to the installed Antigravity.
rem  Auto-detects the install directory and checks the version.
rem  A backup is created as app.asar.backup on first run.
rem ============================================================

set "HERE=%~dp0"
if "%HERE:~-1%"=="\" set "HERE=%HERE:~0,-1%"

echo.
echo  Antigravity Chinese Pack - installer
echo  ------------------------------------
echo.

rem ---- 1. locate resources\app.asar ----
set "RT="
for %%P in ("%LOCALAPPDATA%\Programs\Antigravity\resources" "%PROGRAMFILES%\Antigravity\resources" "%PROGRAMFILES(X86)%\Antigravity\resources") do (
    if exist "%%~P\app.asar" if not defined RT set "RT=%%~P"
)
rem ---- 1b. fall back to the install path recorded in the registry ----
rem     covers custom install dirs (D:\Apps\Antigravity etc.) where the
rem     three standard locations above do not exist
if not defined RT (
    if exist "%HERE%\tools\find-install-dir.ps1" (
        for /f "usebackq delims=" %%P in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%\tools\find-install-dir.ps1"`) do set "RT=%%P"
    )
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

rem ---- 2. read installed version from the exe ----
rem     ProductVersion comes back as 2.28.2.0 (four parts), so try
rem     both the full string and the first three parts.
set "IVER="
for /f "usebackq delims=" %%v in (`powershell -NoProfile -Command "(Get-Item '%RT%\..\Antigravity.exe').VersionInfo.ProductVersion"`) do set "IVER=%%v"
set "IVER=%IVER: =%"

set "PAYLOAD="
if defined IVER (
    if exist "%HERE%\app.asar.zh-%IVER%" set "PAYLOAD=%HERE%\app.asar.zh-%IVER%"
    if not defined PAYLOAD (
        for /f "tokens=1,2,3 delims=." %%a in ("%IVER%") do (
            if exist "%HERE%\app.asar.zh-%%a.%%b.%%c" set "PAYLOAD=%HERE%\app.asar.zh-%%a.%%b.%%c"
        )
    )
) else (
    echo  [WARN] Could not read version from Antigravity.exe
    for %%F in ("%HERE%\app.asar.zh-*") do set "PAYLOAD=%%~fF"
)
echo  Version     : %IVER%
echo.

rem ---- 3. pick the matching payload ----
if not defined PAYLOAD goto :nopayload
if not exist "%PAYLOAD%" goto :nopayload

echo  Payload     : %PAYLOAD%
echo.

rem ---- 4. backup the official asar (only once) ----
set "CUR=%RT%\app.asar"
set "BAK=%RT%\app.asar.backup"
for %%A in ("%CUR%") do set "CURSZ=%%~zA"
for %%A in ("%PAYLOAD%") do set "PAYSZ=%%~zA"

if exist "%BAK%" (
    echo  Backup      : app.asar.backup already exists, kept as is
) else (
    if "%CURSZ%"=="%PAYSZ%" (
        echo  [WARN] Current app.asar looks like a patched file (same size as payload^).
        echo         No clean backup available. Re-install Antigravity to get one.
    ) else (
        copy /y "%CUR%" "%BAK%" >nul
        echo  Backup      : app.asar -^> app.asar.backup
    )
)
echo.

rem ---- 5. apply ----
copy /y "%PAYLOAD%" "%CUR%" >nul
if errorlevel 1 (
    echo  [ERROR] Copy failed. Is Antigravity running? Close it and retry.
    echo.
    pause
    exit /b 1
)

echo  [OK] Chinese pack applied for version %IVER%.
echo.
rem ---- 6. desktop shortcut (best-effort) ----
if exist "%HERE%\启动反重力.vbs" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%\tools\make-shortcut.ps1" -VbsPath "%HERE%\启动反重力.vbs" -ExePath "%RT%\..\Antigravity.exe"
    echo.
)
echo  Start Antigravity from the desktop shortcut (反重力（中文版）)
echo  or by double-clicking 启动反重力.vbs in this folder.
echo  The first screen takes 30-60 seconds to hydrate
echo  before Chinese text appears - that is normal, do not judge too early.
echo.
echo  ------------------------------------------------------------
echo  IMPORTANT: the next official update will overwrite app.asar and
echo  delete app.asar.backup, wiping this patch. To stop that for good,
echo  close Antigravity and run:  关闭自动更新.bat
echo  (reversible any time with 恢复自动更新.bat)
echo  ------------------------------------------------------------
echo.
echo  To roll back, run the restore script in this folder.
echo.
pause
exit /b 0

:nopayload
echo  [ERROR] No patch file matching this Antigravity version.
if defined IVER echo          Installed: %IVER%
echo.
echo  Files found in this folder:
for %%F in ("%HERE%\app.asar.zh-*") do echo          %%~nxF
echo.
echo  This pack only patches the exact version it was built for.
echo  Options:
echo    1. Download the release matching your version from the project page
echo    2. Rebuild the patch yourself - needs the full repo + Python 3:
echo         python tools\port_to.py --version ^<installed ver^>
echo    3. Do NOT force an older pack onto a newer client - it hangs on Loading
echo.
pause
exit /b 1
