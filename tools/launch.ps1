# ============================================================
#  Antigravity 中文版启动器（PowerShell 版）
#
#  为什么要另做一份：VBS 启动器依赖 wscript.exe 和 WScript.Shell COM，
#  有些环境会拦截脚本宿主，表现为「双击没反应、连日志都没有」。
#  这份用纯 PowerShell + .NET 做同样的事，不需要任何 COM 组件。
#
#  做四件事：自愈补中文 -> 探测本地代理 -> 清掉会让客户端静默退出的
#  环境变量 -> 拉起 Antigravity.exe。任何一步失败都照常启动，
#  最差是这次先看英文，绝不让应用打不开。
#
#  用法：
#    powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File tools\launch.ps1
#    powershell ... -File tools\launch.ps1 -CheckOnly   # 只诊断，不启动（自检用）
#
#  编码：UTF-8 带 BOM。PowerShell 5.1 读无 BOM 的中文脚本会按 GBK 解码成乱码。
# ============================================================
param([switch]$CheckOnly)

$ErrorActionPreference = 'Continue'
$packDir  = Split-Path -Parent $PSScriptRoot
$selfheal = Join-Path $PSScriptRoot 'selfheal.ps1'
$findDir  = Join-Path $PSScriptRoot 'find-install-dir.ps1'
$detect   = Join-Path $PSScriptRoot 'detect-proxy.ps1'
$logPath  = Join-Path $env:TEMP 'antigravity-launch.log'

function Write-Log([string]$msg) {
    try {
        Add-Content -LiteralPath $logPath -Value ("{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg) -Encoding UTF8 -ErrorAction Stop
    } catch { }
}

function Get-Field([object[]]$lines, [string]$key) {
    foreach ($l in $lines) {
        if ("$l" -match ('^' + [regex]::Escape($key) + '=(.*)$')) { return $matches[1].Trim() }
    }
    return ''
}

function Invoke-Selfheal([string]$mode) {
    if (-not (Test-Path -LiteralPath $selfheal)) { return @() }
    # 必须用子进程：selfheal.ps1 用 exit 返回结果，直接 & 调用会把本脚本一起结束
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $selfheal $mode '-Quiet' -PackDir $packDir 2>&1
    return @($out | ForEach-Object { "$_" })
}

function Test-GoogleReachable([string]$proxyUrl, [int]$TimeoutMs = 6000, [int]$Tries = 2) {
    # 只看登录端点能不能握上手。连不上时客户端会停在英文的 OAuth 报错页，
    # 与其让人对着天书猜，不如在日志里先说清楚是代理的问题。
    # 注意：4xx / 5xx 都算「网络通了」，只有连接超时、TLS 握手失败才算不通。
    # 用 GET 不用 HEAD：部分代理对 HEAD 会一直挂到超时，会把好代理误判成坏的。
    # 偶发抖动再试一次，避免拿一次超时去吓用户。
    for ($i = 0; $i -lt $Tries; $i++) {
        try {
            $req = [System.Net.HttpWebRequest]::Create('https://accounts.google.com/')
            $req.Method = 'GET'
            $req.AllowAutoRedirect = $false
            $req.UserAgent = 'Mozilla/5.0'
            $req.Timeout = $TimeoutMs
            $req.ReadWriteTimeout = $TimeoutMs
            $req.Proxy = [System.Net.WebProxy]::new($proxyUrl, $true)
            $resp = $req.GetResponse()
            $code = [int]$resp.StatusCode
            $resp.Close()
            if ($code -gt 0) { return $true }
        } catch {
            $ex = $_.Exception
            if ($ex -is [System.Net.WebException] -and $ex.Response) { return $true }
        }
    }
    return $false
}

function Find-Exe {
    $cands = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Antigravity\Antigravity.exe'),
        (Join-Path $env:ProgramFiles 'Antigravity\Antigravity.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Antigravity\Antigravity.exe')
    )
    foreach ($c in $cands) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    if (Test-Path -LiteralPath $findDir) {
        $r = & powershell -NoProfile -ExecutionPolicy Bypass -File $findDir 2>$null
        $r = "$r".Trim()
        if ($r) {
            $e = Join-Path (Split-Path -Parent $r) 'Antigravity.exe'
            if (Test-Path -LiteralPath $e) { return $e }
        }
    }
    return ''
}

Write-Log '---- launch start (powershell) ----'

# 0. 清掉会让 Electron 变成纯 Node 模式的变量（非空 = 无窗口静默退出）
foreach ($n in 'ELECTRON_RUN_AS_NODE', 'NODE_OPTIONS') {
    [Environment]::SetEnvironmentVariable($n, $null, 'Process')
    Remove-Item ("Env:\" + $n) -ErrorAction SilentlyContinue
}

# 1. 找客户端
$exe = Find-Exe
if (-not $exe) {
    Write-Log 'ERROR: Antigravity.exe not found'
    Write-Output 'ERROR: Antigravity.exe not found'
    exit 1
}
Write-Log "exe = $exe"
Write-Output "EXE=$exe"

# 2. 自愈：标记匹配就什么都不做，不匹配才补包 / 现场移植
$healSrc = ''
$healRes = ''
$healVer = ''
$chk = Invoke-Selfheal '-Check'
$state = Get-Field $chk 'STATE'
$healVer = Get-Field $chk 'VER'
Write-Log "selfheal check: state=$state ver=$healVer source=$(Get-Field $chk 'SOURCE')"
Write-Output "CHECK_STATE=$state"

if ($state -eq 'need') {
    $healSrc = Get-Field $chk 'SOURCE'
    $heal = Invoke-Selfheal '-Heal'
    $newState = Get-Field $heal 'STATE'
    $healSrc  = Get-Field $heal 'SOURCE'
    $healRes  = Get-Field $heal 'RES'
    Write-Log "selfheal heal: state=$newState code=$(Get-Field $heal 'CODE') source=$healSrc detail=$(Get-Field $heal 'DETAIL')"
    Write-Output "HEAL_STATE=$newState"
    if ($newState -ne 'ready') {
        Write-Log 'WARN: heal failed, launch anyway (may be English this time)'
        Write-Output "HEAL_DETAIL=$(Get-Field $heal 'DETAIL')"
    }
} elseif ($state -eq 'ready') {
    Write-Log 'selfheal: already Chinese'
}

# 3. 代理：探到才设，探不到一个网络设置都不动
#    探测顺序由 detect-proxy.ps1 决定：local-proxy.txt -> 系统代理 -> 扫常见端口。
#    扫端口得到的只是「猜测」，必须自己证明能用才采信，否则宁可不设代理 ——
#    把 8080 上的开发服务器当成代理，比不设代理更糟。
$proxy = ''
$proxySrc = 'none'
$proxyNote = ''
$cands = @()
if (Test-Path -LiteralPath $detect) {
    $det = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $detect -Detailed 2>$null | ForEach-Object { "$_" })
    $proxySrc = Get-Field $det 'SOURCE'
    $rawList = Get-Field $det 'CANDIDATES'
    if ($rawList) {
        $cands = @($rawList.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
}
if (-not $proxySrc) { $proxySrc = 'none' }
Write-Log ("proxy detect: source={0} candidates={1}" -f $proxySrc, ($cands -join ' | '))

if ($proxySrc -eq 'file' -or $proxySrc -eq 'system') {
    # 用户自己写的 / 系统里配的，属于明确意图，直接用
    if ($cands.Count -gt 0) { $proxy = $cands[0] }
} elseif ($proxySrc -eq 'scan') {
    # 扫描来的：HTTP 代理要能连到 Google 才算数；SOCKS5 握手成功就足以认定是代理
    # 每次健康检查最多 3 秒，所以最多试 2 个，别让启动等成常态。
    $healthTried = 0
    foreach ($c in $cands) {
        if ($c -like 'http*') {
            if ($healthTried -ge 2) { break }
            $healthTried++
            if (Test-GoogleReachable $c 3000 1) { $proxy = $c; break }
            Write-Log "scan candidate $c 连不上 Google，跳过"
            $proxyNote = '候选端口连不上 Google，已跳过'
        } else {
            $proxy = $c
            $proxyNote = 'SOCKS5 代理，未做连通性检查'
            break
        }
    }
}

# 本地回环必须直连：登录引导页、CDP、客户端后台与本地服务之间都走 127.0.0.1。
# 以前把 NO_PROXY 设成空字符串，等于让这些请求也钻进代理，会出现
# 「There was an unexpected issue setting up your account」这类登录失败。
# Go 写的后台进程只读环境变量、不读 Windows 系统代理设置，所以这一段不能省。
$noProxyEnv = '127.0.0.1,localhost,::1,.local,10.*,192.168.*,172.16.*,172.17.*,172.18.*,172.19.*,172.20.*,172.21.*,172.22.*,172.23.*,172.24.*,172.25.*,172.26.*,172.27.*,172.28.*,172.29.*,172.30.*,172.31.*'
$proxyBypass = 'localhost;127.0.0.1;::1;*.local'
$netOk = $false
if ($proxy) {
    foreach ($n in 'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'http_proxy', 'https_proxy', 'all_proxy') {
        [Environment]::SetEnvironmentVariable($n, $proxy, 'Process')
    }
    [Environment]::SetEnvironmentVariable('NO_PROXY', $noProxyEnv, 'Process')
    [Environment]::SetEnvironmentVariable('no_proxy', $noProxyEnv, 'Process')
    Write-Log ("proxy = {0} (from {1}, no_proxy = loopback/LAN)" -f $proxy, $proxySrc)
    if ($proxy -like 'http*') {
        $netOk = Test-GoogleReachable $proxy
        if ($netOk) {
            Write-Log 'proxy health: Google 登录端点可达'
        } else {
            Write-Log 'WARN: 代理连不上 Google 登录端点。客户端会停在「设置账户失败」页；请在代理软件里切换可用节点，或开启 TUN / 全局模式接管后台进程。'
        }
    } else {
        Write-Log 'proxy health: SOCKS5 不做 HTTP 探测（.NET 5.1 不支持 SOCKS 代理对象）'
    }
} else {
    if ($proxyNote) {
        Write-Log ("proxy = none（{0}）" -f $proxyNote)
    } else {
        Write-Log 'proxy = none（没探到代理；直连时 Google 登录会超时，这属于网络环境问题）'
    }
}
Write-Output "PROXY=$proxy"
Write-Output "PROXY_SOURCE=$proxySrc"
Write-Output "PROXY_HEALTH=$netOk"

# 3.5 已经开着的窗口不会重新加载 app.asar：官方更新或刚补完中文时，
#     必须完全退出再启动，否则看到的还是旧界面（全英文）。
$running = @(Get-Process -Name 'Antigravity' -ErrorAction SilentlyContinue)
if ($running.Count -gt 0) {
    Write-Log "WARN: 已有 $($running.Count) 个 Antigravity 进程在运行；已打开的窗口不会加载磁盘上刚更新的汉化包，需完全退出后重新启动"
    Write-Output 'WARN_RESTART_NEEDED=1'
}

if ($CheckOnly) {
    Write-Log 'CheckOnly: not launching'
    Write-Output 'CHECK_ONLY=1'
    exit 0
}

# 4. 启动
$argList = @()
if ($proxy) {
    # 不能给值加引号：Start-Process 会把引号原样传进命令行，Chromium 收到
    # --proxy-server="http://..." 会当成无效地址，代理静默失效（登录就直连超时）。
    $argList += ('--proxy-server=' + $proxy)
    $argList += ('--proxy-bypass-list=' + $proxyBypass)
}
Write-Log "run: $exe $argList"
try {
    Start-Process -FilePath $exe -ArgumentList $argList -WorkingDirectory (Split-Path -Parent $exe) -ErrorAction Stop
} catch {
    Write-Log "ERROR: start failed: $($_.Exception.Message)"
    Write-Output "ERROR: start failed: $($_.Exception.Message)"
    exit 1
}

# 5. 五秒复查：现场移植的产物把客户端搞挂了就回滚到官方英文版
Start-Sleep -Seconds 5
if (-not (Get-Process -Name 'Antigravity' -ErrorAction SilentlyContinue)) {
    Write-Log 'WARN: process not alive 5s after launch'
    if ($healSrc -eq 'port' -and $healRes) {
        $bak = Join-Path $healRes 'app.asar.backup'
        $cur = Join-Path $healRes 'app.asar'
        if (Test-Path -LiteralPath $bak) { Copy-Item -LiteralPath $bak -Destination $cur -Force }
        Remove-Item -LiteralPath (Join-Path $healRes '.zh-pack') -Force -ErrorAction SilentlyContinue
        $skipDir = Join-Path $env:LOCALAPPDATA 'Antigravity'
        if (-not (Test-Path -LiteralPath $skipDir)) { New-Item -ItemType Directory -Path $skipDir -Force | Out-Null }
        Add-Content -LiteralPath (Join-Path $skipDir 'zh-port-skip') -Value $healVer -Encoding UTF8
        Write-Log 'port rollback done (skip recorded)'
    }
    Write-Output 'WARN: process exited within 5s'
}
exit 0
