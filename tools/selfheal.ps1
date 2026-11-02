# ============================================================
#  Antigravity 中文包自愈脚本
#
#  解决的问题：官方更新是 NSIS 全量包，安装时整个 resources\ 被替换，
#  连 app.asar.backup 一起删。手动重装一次就掉一次中文。
#
#  判断依据不靠猜，靠标记文件 resources\.zh-pack：
#    - 标记里的版本 == 当前安装版本，且 app.asar 大小 == 标记记录的大小
#      → 已就绪，直接放行（快速路径，不动任何文件）
#    - 否则视为被更新覆盖了 → 找包、备份、覆盖、重写标记
#
#  取包顺序：汉化包目录的成品 → 包目录里的 packs\*.zip → 本地缓存
#            → GitHub Releases 直连下载（不走 API，无频率限制）
#
#  用法：
#    powershell -File tools\selfheal.ps1 -Check -Quiet   只报告状态
#    powershell -File tools\selfheal.ps1 -Heal           真正打补丁
#
#  退出码：
#    0  已就绪（无需操作，或本次已成功补好）
#   10  找不到 Antigravity 安装目录
#   11  读不到版本号
#   20  该版本还没有汉化包（Release 404）
#   21  下载失败（网络 / 代理）
#   22  包损坏或解压失败
#   30  没有写权限（装在 Program Files，需要管理员）
#   31  app.asar 被占用（Antigravity 正在运行）
#
#  输出（-Quiet 时只有这些 KEY=VALUE 行，供启动器解析）：
#    STATE=ready|need|error
#    CODE=<退出码>
#    VER=<x.y.z>
#    RES=<resources 路径>
#    SOURCE=local|zip|download|marker
#    DETAIL=<人类可读的一句话>
# ============================================================

param(
    [string]$Resources = '',
    [string]$PackDir = '',
    [switch]$Check,
    [switch]$Heal,
    [switch]$Quiet,
    [string]$Version = ''
)

$ErrorActionPreference = 'Stop'

$RepoOwner  = 'bslnssb'
$RepoName   = 'antigravity-chinese-pack'
$MarkerName = '.zh-pack'

# ---------------- 输出 ----------------

$script:Fields = [ordered]@{}

function Set-Field([string]$k, [string]$v) {
    $script:Fields[$k] = [string]$v
}

function Write-Result([int]$code, [string]$state, [string]$detail, [string]$source = '') {
    Set-Field 'STATE'  $state
    Set-Field 'CODE'   $code
    if ($source) { Set-Field 'SOURCE' $source }
    Set-Field 'DETAIL' $detail

    if (-not $Quiet) {
        $color = 'Gray'
        if ($state -eq 'ready') { $color = 'Green' }
        if ($state -eq 'error') { $color = 'Red' }
        if ($state -eq 'need')  { $color = 'Yellow' }
        Write-Host ''
        Write-Host ("  {0}" -f $detail) -ForegroundColor $color
        if ($state -eq 'ready') {
            Write-Host ("  版本 {0} · {1}" -f $script:Fields['VER'], $script:Fields['RES'])
        }
        Write-Host ''
    } else {
        foreach ($k in $script:Fields.Keys) {
            Write-Output ("{0}={1}" -f $k, $script:Fields[$k])
        }
    }
    exit $code
}

# ---------------- 定位安装目录 ----------------

function Get-ResourcesDir([string]$hint) {
    if ($hint) {
        if (Test-Path (Join-Path $hint 'app.asar')) { return (Resolve-Path $hint).Path }
        return ''
    }

    $cands = @()
    if ($env:LOCALAPPDATA) { $cands += (Join-Path $env:LOCALAPPDATA 'Programs\Antigravity\resources') }
    if ($env:ProgramFiles) { $cands += (Join-Path $env:ProgramFiles 'Antigravity\resources') }
    $x86 = ${env:ProgramFiles(x86)}
    if ($x86) { $cands += (Join-Path $x86 'Antigravity\resources') }

    foreach ($c in $cands) {
        if (Test-Path (Join-Path $c 'app.asar')) { return $c }
    }

    # 注册表兜底：InstallLocation 常为空，从 UninstallString 反推
    $roots = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $dirs = New-Object System.Collections.Generic.List[string]
    foreach ($root in $roots) {
        $items = Get-ItemProperty $root -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            if (-not ($item.DisplayName -like '*Antigravity*')) { continue }
            if ($item.InstallLocation) { $dirs.Add([string]$item.InstallLocation) }
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
                if ($exe) { $dirs.Add((Split-Path -Parent $exe)) }
            }
        }
    }
    foreach ($d in $dirs) {
        if (-not $d) { continue }
        $res = Join-Path $d 'resources'
        if (Test-Path (Join-Path $res 'app.asar')) { return $res }
    }
    return ''
}

function Get-InstalledVersion([string]$resDir) {
    $exe = Join-Path (Split-Path -Parent $resDir) 'Antigravity.exe'
    if (-not (Test-Path $exe)) { return '' }
    $raw = (Get-Item $exe).VersionInfo.ProductVersion
    if (-not $raw) { return '' }
    $raw = $raw.Trim()
    $parts = $raw.Split('.')
    if ($parts.Count -ge 3) { return ($parts[0..2] -join '.') }
    return $raw
}

# ---------------- 标记文件 ----------------

function Read-Marker([string]$resDir) {
    $p = Join-Path $resDir $MarkerName
    $m = @{ version = ''; size = ''; applied = ''; source = '' }
    if (-not (Test-Path $p)) { return $m }
    foreach ($line in (Get-Content $p -ErrorAction SilentlyContinue)) {
        $i = $line.IndexOf('=')
        if ($i -lt 1) { continue }
        $k = $line.Substring(0, $i).Trim()
        $v = $line.Substring($i + 1).Trim()
        if ($m.ContainsKey($k)) { $m[$k] = $v }
    }
    return $m
}

function Write-Marker([string]$resDir, [string]$ver, [long]$size, [string]$source) {
    $p = Join-Path $resDir $MarkerName
    $lines = @(
        "version=$ver",
        "size=$size",
        ("applied={0}" -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')),
        "source=$source"
    )
    # 必须是 UTF-8 无 BOM：BOM 会让某些解析器把首行键名读成 "\ufeffversion"
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($p, ($lines -join "`r`n") + "`r`n", $utf8)
}

# ---------------- 取包 ----------------

function Get-CacheDir {
    $d = Join-Path $env:LOCALAPPDATA 'Antigravity\zh-cache'
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    return $d
}

# 本地三种来源，按可靠性排序
function Find-LocalPayload([string]$ver) {
    $name = "app.asar.zh-$ver"

    # 1) 汉化包目录里的成品（离线可用，最快）
    if ($PackDir) {
        $p = Join-Path $PackDir $name
        if (Test-Path $p) { return @{ path = $p; source = 'local' } }
        $z = Join-Path $PackDir "packs\Antigravity-Chinese-Pack-v$ver.zip"
        if (Test-Path $z) { return @{ path = $z; source = 'zip' } }
        $z2 = Join-Path $PackDir "Antigravity-Chinese-Pack-v$ver.zip"
        if (Test-Path $z2) { return @{ path = $z2; source = 'zip' } }
    }

    # 2) 上次下载留下的缓存
    $cache = Get-CacheDir
    $c = Join-Path $cache $name
    if (Test-Path $c) { return @{ path = $c; source = 'local' } }
    $cz = Join-Path $cache "Antigravity-Chinese-Pack-v$ver.zip"
    if (Test-Path $cz) { return @{ path = $cz; source = 'zip' } }

    return $null
}

function Get-ProxyUrl {
    if ($env:HTTPS_PROXY) { return $env:HTTPS_PROXY }
    if ($env:https_proxy) { return $env:https_proxy }
    if ($env:HTTP_PROXY) { return $env:HTTP_PROXY }
    if ($env:http_proxy) { return $env:http_proxy }
    return ''
}

# 返回 'ok' / 'notfound' / 抛异常
function Invoke-Download([string]$url, [string]$dest) {
    $proxyUrl = Get-ProxyUrl
    $attempts = @()
    if ($proxyUrl) { $attempts += $proxyUrl }
    $attempts += $null   # 直连兜底

    $lastMsg = ''
    foreach ($p in $attempts) {
        try {
            $req = [System.Net.HttpWebRequest]::Create($url)
            $req.UserAgent = 'Antigravity-Chinese-Pack'
            $req.Timeout = 20000
            $req.ReadWriteTimeout = 60000
            $req.AllowAutoRedirect = $true
            if ($p) { $req.Proxy = New-Object System.Net.WebProxy($p) } else { $req.Proxy = $null }

            $resp = $req.GetResponse()
            try {
                $rs = $resp.GetResponseStream()
                $fs = [System.IO.File]::Create($dest)
                try { $rs.CopyTo($fs) } finally { $fs.Close(); $rs.Close() }
            } finally { $resp.Close() }
            return 'ok'
        } catch [System.Net.WebException] {
            $we = $_.Exception
            if ($we.Response) {
                $code = 0
                try { $code = [int]$we.Response.StatusCode } catch { $code = 0 }
                if ($code -eq 404) { return 'notfound' }
                $lastMsg = "HTTP $code"
            } else {
                $lastMsg = $we.Message
            }
        } catch {
            $lastMsg = $_.Exception.Message
        }
    }
    throw $lastMsg
}

function Expand-PayloadFromZip([string]$zipPath, [string]$ver, [string]$destDir) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = $null
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
        $want = "app.asar.zh-$ver"
        $entry = $null
        foreach ($e in $zip.Entries) {
            if ($e.FullName -eq $want) { $entry = $e; break }
        }
        if (-not $entry) { throw "压缩包里没有 $want" }
        $dest = Join-Path $destDir $want
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $dest, $true)
        return $dest
    } finally {
        if ($zip) { $zip.Dispose() }
    }
}

# ---------------- 主流程 ----------------

$resDir = Get-ResourcesDir $Resources
if (-not $resDir) {
    Write-Result 10 'error' '没有找到 Antigravity 的安装目录（resources\app.asar 不存在）'
}
Set-Field 'RES' $resDir

if (-not $Version) { $Version = Get-InstalledVersion $resDir }
if (-not $Version) {
    Write-Result 11 'error' '读不到 Antigravity.exe 的版本号'
}
Set-Field 'VER' $Version

$asar = Join-Path $resDir 'app.asar'
$curSize = (Get-Item $asar).Length

# ---- 快速路径：标记匹配就放行 ----
if (-not $Heal) {
    $m = Read-Marker $resDir
    if ($m.version -eq $Version -and $m.size -eq "$curSize") {
        Write-Result 0 'ready' ("已是中文版（{0}），无需重新打补丁" -f $Version) 'marker'
    }
    $local = Find-LocalPayload $Version
    if ($local) {
        Set-Field 'SOURCE' $local.source
        Write-Result 0 'need' ("官方已更新到 {0}，需要重新打中文补丁" -f $Version) $local.source
    }
    Write-Result 0 'need' ("官方已更新到 {0}，需要重新打中文补丁（本地无此版本，将尝试下载）" -f $Version) 'download'
}

# ---- 打补丁 ----
$local = Find-LocalPayload $Version
if (-not $local) {
    $url = "https://github.com/$RepoOwner/$RepoName/releases/download/v$Version/Antigravity-Chinese-Pack-v$Version.zip"
    $cache = Get-CacheDir
    $zipPath = Join-Path $cache "Antigravity-Chinese-Pack-v$Version.zip"
    $tmpZip = "$zipPath.part"
    if (Test-Path $tmpZip) { Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue }

    $res = $null
    try {
        $res = Invoke-Download $url $tmpZip
    } catch {
        if (Test-Path $tmpZip) { Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue }
        Write-Result 21 'error' ("下载汉化包失败：{0}" -f $_.Exception.Message) 'download'
    }
    if ($res -eq 'notfound') {
        if (Test-Path $tmpZip) { Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue }
        Write-Result 20 'error' ("v{0} 的汉化包还没有发布（官方太新，我们还没跟上）" -f $Version) 'download'
    }
    Move-Item $tmpZip $zipPath -Force
    $local = @{ path = $zipPath; source = 'download' }
}

# 拿到的是 zip 就解出 asar
if ($local.source -ne 'local') {
    $cache = Get-CacheDir
    try {
        $payload = Expand-PayloadFromZip $local.path $Version $cache
    } catch {
        Write-Result 22 'error' ("汉化包损坏或解压失败：{0}" -f $_.Exception.Message) $local.source
    }
} else {
    $payload = $local.path
}

if (-not (Test-Path $payload)) {
    Write-Result 22 'error' ("汉化成品不存在：{0}" -f $payload) $local.source
}
$paySize = (Get-Item $payload).Length

# ---- 写权限预检 ----
$probe = Join-Path $resDir '.zh-write-probe'
try {
    [System.IO.File]::WriteAllText($probe, 'x')
    Remove-Item $probe -Force
} catch {
    Write-Result 30 'error' '没有写入权限（Antigravity 装在 Program Files，请右键“以管理员身份运行”启动器）' 'local'
}

# ---- 被占用检查 ----
$lock = Join-Path $resDir 'app.asar'
try {
    $fs = [System.IO.File]::Open($lock, 'Open', 'ReadWrite', 'None')
    $fs.Close()
} catch {
    Write-Result 31 'error' 'app.asar 正被占用（Antigravity 还在运行）' 'local'
}

# ---- 备份官方 asar（只在还没有备份、且当前不是补丁版时做）----
$bak = Join-Path $resDir 'app.asar.backup'
if (-not (Test-Path $bak)) {
    if ($curSize -ne $paySize) {
        Copy-Item $asar $bak -Force
    }
}

# ---- 覆盖 ----
try {
    Copy-Item $payload $asar -Force
} catch {
    Write-Result 31 'error' ("覆盖 app.asar 失败：{0}" -f $_.Exception.Message) $local.source
}

$newSize = (Get-Item $asar).Length
if ($newSize -ne $paySize) {
    Write-Result 22 'error' ("覆盖后大小不符（期望 {0}，实际 {1}）" -f $paySize, $newSize) $local.source
}

Write-Marker $resDir $Version $newSize $local.source
Write-Result 0 'ready' ("已把 {0} 重新打上中文包" -f $Version) $local.source
