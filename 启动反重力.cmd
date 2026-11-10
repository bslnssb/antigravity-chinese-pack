@echo off
rem ============================================================
rem  Antigravity 中文版启动器（双击这个也能用，不依赖脚本宿主）
rem  桌面「反重力（中文版）」快捷方式指向的是同一个 PowerShell 脚本；
rem  这个文件给「快捷方式丢了 / VBS 被安全软件拦了」时兜底用。
rem ============================================================
set "ELECTRON_RUN_AS_NODE="
set "NODE_OPTIONS="
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0tools\launch.ps1" %*
exit /b 0
