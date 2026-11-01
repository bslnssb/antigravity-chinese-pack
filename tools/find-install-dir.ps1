# 找出 Antigravity 的 resources 目录，供 一键安装汉化.bat 在标准路径都落空时兜底。
#
# 为什么需要它：官方 NSIS 安装包允许改安装目录（装到 D:\Apps\Antigravity 之类），
# 这时 %LOCALAPPDATA%\Programs\Antigravity 里没有东西，安装脚本会误报"没装"。
# 注册表里 Uninstall 项的 InstallLocation 常常是空串，但 UninstallString
# 一定指向 "<安装目录>\Uninstall Antigravity.exe"，从它反推最可靠。
#
# 输出：找到则打印 resources 目录的绝对路径（一行），找不到则什么都不打印。
# 退出码：0 找到 / 1 没找到。bat 里只取 stdout，不依赖退出码。

$ErrorActionPreference = 'SilentlyContinue'

$roots = @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

$dirs = New-Object System.Collections.Generic.List[string]

foreach ($root in $roots) {
    foreach ($item in (Get-ItemProperty $root -ErrorAction SilentlyContinue)) {
        if (-not ($item.DisplayName -like '*Antigravity*')) { continue }

        if ($item.InstallLocation) {
            $dirs.Add([string]$item.InstallLocation)
        }

        # UninstallString 形如: "C:\...\Antigravity\Uninstall Antigravity.exe" /currentuser
        $us = [string]$item.UninstallString
        if ($us) {
            $us = $us.Trim()
            $exe = $null
            if ($us.StartsWith('"')) {
                $end = $us.IndexOf('"', 1)
                if ($end -gt 1) { $exe = $us.Substring(1, $end - 1) }
            } elseif ($us -match '^(.+?\.exe)(\s|$)') {
                $exe = $matches[1]
            }
            if ($exe) {
                $dirs.Add((Split-Path -Parent $exe))
            }
        }
    }
}

foreach ($d in $dirs) {
    if (-not $d) { continue }
    $res = Join-Path $d 'resources'
    if (Test-Path (Join-Path $res 'app.asar')) {
        Write-Output $res
        exit 0
    }
}

exit 1
