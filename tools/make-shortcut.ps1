# ============================================================
#  创建桌面快捷方式「反重力（中文版）」
#
#  目标：wscript.exe + 本包内的 启动反重力.vbs
#  原因：VBS 负责设代理环境变量再拉起客户端，且不弹 cmd 黑窗；
#        .lnk 的图标直接指向 Antigravity.exe，外观与官方一致。
#  图标：Antigravity.exe,0
#
#  用法（由 一键安装汉化.bat 调用，也可手动执行）：
#    powershell -NoProfile -ExecutionPolicy Bypass -File make-shortcut.ps1
#  参数：
#    -VbsPath  VBS 路径（默认与本脚本同级的 ..\启动反重力.vbs）
#    -ExePath  图标用的客户端 exe（默认自动探测）
#  输出：桌面上的 反重力（中文版）.lnk
# ============================================================
param(
    [string]$VbsPath = "",
    [string]$ExePath = ""
)

$ErrorActionPreference = 'Stop'

# ---- 定位 VBS ----
if (-not $VbsPath) {
    $VbsPath = Join-Path (Split-Path -Parent $PSScriptRoot) '启动反重力.vbs'
}
if (-not (Test-Path -LiteralPath $VbsPath)) {
    Write-Output "SKIP: $VbsPath not found"
    exit 1
}
$VbsPath = (Resolve-Path -LiteralPath $VbsPath).Path

# ---- 定位客户端 exe（作图标）----
if (-not $ExePath -or -not (Test-Path -LiteralPath $ExePath)) {
    $cands = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Antigravity\Antigravity.exe'),
        (Join-Path $env:ProgramFiles 'Antigravity\Antigravity.exe'),
        "${env:ProgramFiles(x86)}\Antigravity\Antigravity.exe"
    )
    $ExePath = $cands | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $ExePath) {
    # 标准位置都没有：问注册表
    $find = Join-Path $PSScriptRoot 'find-install-dir.ps1'
    if (Test-Path -LiteralPath $find) {
        $res = & powershell -NoProfile -ExecutionPolicy Bypass -File $find
        $res = "$res".Trim()
        if ($res) {
            $exe2 = Join-Path (Split-Path -Parent $res) 'Antigravity.exe'
            if (Test-Path -LiteralPath $exe2) { $ExePath = $exe2 }
        }
    }
}
if (-not $ExePath) {
    Write-Output "SKIP: Antigravity.exe not found (icon will fall back)"
}

# ---- 生成 .lnk ----
$desktop = [Environment]::GetFolderPath('Desktop')
$lnkPath = Join-Path $desktop '反重力（中文版）.lnk'

$sh = New-Object -ComObject WScript.Shell
$lnk = $sh.CreateShortcut($lnkPath)
$lnk.TargetPath        = Join-Path $env:WINDIR 'System32\wscript.exe'
$lnk.Arguments         = '"' + $VbsPath + '"'
$lnk.WorkingDirectory  = Split-Path -Parent $VbsPath
if ($ExePath) {
    $lnk.IconLocation = "$ExePath,0"
}
$lnk.Description       = '启动已汉化的 Antigravity（自动走本地代理）'
$lnk.Save()

if (Test-Path -LiteralPath $lnkPath) {
    Write-Output "OK: $lnkPath"
    exit 0
} else {
    Write-Output "FAIL: shortcut not created"
    exit 1
}
