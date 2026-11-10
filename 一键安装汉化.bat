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
rem     -SetFile + call, not for /f: PowerShell writes UTF-8 into a pipe while
rem     cmd's for /f reads ANSI bytes, so an install path containing Chinese
rem     characters never matched. The helper now emits a "set" line instead.
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

rem ---- 1c. write permission probe ----
rem     Antigravity installed under Program Files is not writable by a normal
rem     account. Say so now, instead of letting the user reach a generic
rem     "Copy failed" later and guess.
set "WPROBE=%RT%\.zh-write-probe"
2>nul > "%WPROBE%" echo x
if not exist "%WPROBE%" goto :nowrite
del /f /q "%WPROBE%" >nul 2>&1
if exist "%WPROBE%" goto :nowrite
goto :writable

:nowrite
echo.
echo  [ERROR] This account cannot write to:
echo          %RT%
echo  Antigravity is installed under Program Files, so a normal user
echo  cannot replace app.asar there.
echo  Fix: close Antigravity, then right-click 一键安装汉化.bat and choose
echo       "Run as administrator" ^(one time is enough^).
echo  Or reinstall Antigravity to its default per-user location.
echo.
pause
exit /b 1

:writable

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

echo  [OK] 已为 %IVER% 打上中文包。
echo.
goto :finish

:finish
rem ---- 5b. 写 .zh-pack 标记；版本对不上时由自愈在这里现场移植 ----
rem     成功路径只是重复覆盖一次（无害），不匹配路径会把译文搬到新版文件上。
if exist "%HERE%\tools\selfheal.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%\tools\selfheal.ps1" -Heal -Resources "%RT%" -PackDir "%HERE%" >nul 2>&1
)
rem ---- 6. 桌面启动入口：两条路，任一成功都能双击启动 ----
rem 6a. 带官方图标的 .lnk（需要 COM；被安全软件拦了也不影响 6b）
if exist "%HERE%\tools\make-shortcut.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%\tools\make-shortcut.ps1" -VbsPath "%HERE%\启动反重力.vbs" -ExePath "%RT%\..\Antigravity.exe" >nul 2>&1
)
rem 6b. 纯文本兜底：完全不依赖脚本宿主 / COM，桌面上一定有一个能点的入口
set "ENTRY=%USERPROFILE%\Desktop\反重力（中文版）.cmd"
> "%ENTRY%" echo @echo off
>> "%ENTRY%" echo start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%HERE%\tools\launch.ps1"
echo  [OK] 桌面启动入口已建好：反重力（中文版）
echo.
echo  以后双击桌面上的「反重力（中文版）」启动；也可以双击本文件夹里的 启动反重力.cmd
echo  首次打开等 30-60 秒中文才全部出现，属正常，别太早下结论。
echo.
echo  ------------------------------------------------------------
echo  官方更新会整目录覆盖，把中文冲掉（不是装错了）。
echo  用「反重力（中文版）」启动会自动补回来；想彻底不被打断，
echo  先完全退出 Antigravity，再双击 关闭自动更新.bat
echo  （随时可用 恢复自动更新.bat 撤销）。
echo  ------------------------------------------------------------
echo.
echo  想回到英文原版：双击 一键恢复官方英文.bat
echo.
pause
exit /b 0

:nopayload
echo  [提示] 没有和这一版完全对应的现成中文包，这是正常的（官方比本包新）。
echo         不会把旧文件强加到新客户端上，也就不会卡在加载界面。
echo         下面照常建好桌面启动入口。第一次启动时，会把已有译文搬到你
echo         这版官方文件上，界面继续是中文（首次多等几秒）。
echo.
goto :finish
