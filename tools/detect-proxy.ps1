<#
  探测本地代理。两种输出模式：

    默认（给旧版 VBS 启动器用）：只打印一个端口号，例如 7897；没有就 exit 1。
    -Detailed（给 tools\launch.ps1 用）：
        SOURCE=file|system|scan|none
        CANDIDATES=http://127.0.0.1:7897,socks5://127.0.0.1:1080

  三个来源，按可信度排：
    1. tools\local-proxy.txt —— 用户自己写的，最可信（可以是别的机器）
    2. Windows 系统代理 —— ProxyEnable=1 时才采信 ProxyServer
    3. 扫常见端口 —— 只是"候选"，必须通过协议探测才算数

  为什么要做协议探测：以前只测「端口有没有人监听」，于是 8080 上的开发服务器、
  8888 上的 Jupyter 都会被当成代理塞给客户端，结果比不设代理更糟——所有请求
  都被发到一个不会转发的地方。现在只有真的能握手的 HTTP 代理 / SOCKS5 才采信。

  端口列表只是候选，不是"必须"：别人用别的端口不要改这里，让用户写
  tools\local-proxy.txt（一行 [host:]port）。写错或代理没开都不会报错，只会往下探。

  另有 -IgnoreHint / -IgnoreSystem 两个开关，只给自检用：跳过前两个来源，
  专门验证「端口扫描 + 协议探测」这一段。
#>
param([int]$TimeoutMs = 200, [switch]$Detailed, [switch]$IgnoreHint, [switch]$IgnoreSystem)

# 端口列表只是候选：按命中率排，前面的是各客户端的默认值。
$ports = @(7897, 7890, 7891, 10808, 10809, 1080, 8080, 2080, 8888)

function ConvertTo-ProxyUrl([string]$raw) {
    # 7897 / 127.0.0.1:7897 / http://h:7897 / socks5://h:1080 / "http=h:p;https=h:p" 都认
    $t = "$raw".Trim()
    if (-not $t) { return '' }

    if ($t.Contains('=')) {
        # WinINET 的多协议写法，优先取 http=，没有再取第一项
        $pick = ''
        foreach ($part in $t.Split(';')) {
            if (-not $part.Contains('=')) { continue }
            $kv = $part.Split('=', 2)
            if ($pick -eq '') { $pick = $kv[1] }
            if ($kv[0].Trim().ToLower() -eq 'http') { $pick = $kv[1]; break }
        }
        $t = $pick.Trim()
        if (-not $t) { return '' }
    }

    if ($t -match '^(?i)(https?)://(.+)$') { return ($matches[1].ToLower() + '://' + $matches[2].Trim()) }
    if ($t -match '^(?i)(socks5h?)://(.+)$') { return ('socks5://' + $matches[2].Trim()) }
    if ($t -match '^\d+$') { return "http://127.0.0.1:$t" }
    if ($t -match '^([^/:]+):(\d+)$') { return "http://$($matches[1]):$($matches[2])" }
    return ''
}

function Split-ProxyUrl([string]$url) {
    if ($url -match '^(?i)(https?)://([^:/]+):(\d+)$') { return @($matches[2], [int]$matches[3]) }
    if ($url -match '^(?i)socks5://([^:/]+):(\d+)$') { return @($matches[1], [int]$matches[2]) }
    return @()
}

function Get-ProxyKind([string]$target, [int]$port) {
    # 返回 'http' / 'socks5' / ''（不是代理，或者没在监听）

    # 1) 先当 HTTP 代理试：发一个 CONNECT，看回的是不是代理该有的状态码
    $c = New-Object Net.Sockets.TcpClient
    try {
        $ar = $c.BeginConnect($target, $port, $null, $null)
        if (-not $ar.AsyncWaitHandle.WaitOne($TimeoutMs)) { return '' }
        $c.EndConnect($ar)
        $c.ReceiveTimeout = 1200
        $ns = $c.GetStream()
        $req = "CONNECT www.gstatic.com:443 HTTP/1.1`r`nHost: www.gstatic.com:443`r`nProxy-Connection: keep-alive`r`nUser-Agent: antigravity-launcher`r`n`r`n"
        $bytes = [Text.Encoding]::ASCII.GetBytes($req)
        $ns.Write($bytes, 0, $bytes.Length)
        $buf = New-Object byte[] 256
        $n = $ns.Read($buf, 0, $buf.Length)
        if ($n -gt 0) {
            $line = [Text.Encoding]::ASCII.GetString($buf, 0, $n)
            if ($line -match '^HTTP/1\.[01]\s+(\d{3})') {
                $code = [int]$matches[1]
                # 200 隧道通了 / 403 被拒 / 407 要认证 / 502 上游不通 —— 这些都是代理
                # 400 / 404 / 405 / 501 是普通 web 服务器对 CONNECT 的拒绝，不是代理
                if ($code -in @(200, 403, 407, 502, 503, 504)) { return 'http' }
            }
        }
    } catch {
    } finally {
        try { $c.Close() } catch { }
    }

    # 2) 再当 SOCKS5 试：发握手，回 0x05 才认
    $c2 = New-Object Net.Sockets.TcpClient
    try {
        $ar = $c2.BeginConnect($target, $port, $null, $null)
        if (-not $ar.AsyncWaitHandle.WaitOne($TimeoutMs)) { return '' }
        $c2.EndConnect($ar)
        $c2.ReceiveTimeout = 1200
        $ns = $c2.GetStream()
        $hello = [byte[]](0x05, 0x01, 0x00)
        $ns.Write($hello, 0, 3)
        $buf = New-Object byte[] 2
        $n = $ns.Read($buf, 0, 2)
        if ($n -eq 2 -and $buf[0] -eq 0x05) { return 'socks5' }
    } catch {
    } finally {
        try { $c2.Close() } catch { }
    }

    return ''
}

$source = 'none'
$found = @()

# 1) tools\local-proxy.txt：用户自己指定的，优先
$hint = Join-Path $PSScriptRoot 'local-proxy.txt'
if ((Test-Path -LiteralPath $hint) -and (-not $IgnoreHint)) {
    $raw = ''
    foreach ($line in (Get-Content -LiteralPath $hint -ErrorAction SilentlyContinue)) {
        $t = "$line".Trim()
        if ($t -and $t[0] -ne '#') { $raw = $t; break }
    }
    $url = ConvertTo-ProxyUrl $raw
    if ($url) {
        $hp = Split-ProxyUrl $url
        if ($hp.Count -eq 2) {
            $kind = Get-ProxyKind $hp[0] $hp[1]
            if ($kind) {
                $found = @(($kind + '://' + $hp[0] + ':' + $hp[1]))
                $source = 'file'
            }
        }
    }
}

# 2) Windows 系统代理（Clash / v2rayN 开了"系统代理"时最准，端口往往不是默认那个）
if (($source -eq 'none') -and (-not $IgnoreSystem)) {
    try {
        $ie = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        if ("$($ie.ProxyEnable)" -eq '1') {
            $url = ConvertTo-ProxyUrl "$($ie.ProxyServer)"
            $hp = Split-ProxyUrl $url
            if ($hp.Count -eq 2) {
                $kind = Get-ProxyKind $hp[0] $hp[1]
                if ($kind) {
                    $found = @(($kind + '://' + $hp[0] + ':' + $hp[1]))
                    $source = 'system'
                }
            }
        }
    } catch { }
}

# 3) 扫常见端口：只是候选，逐个验协议
if ($source -eq 'none') {
    $http = @()
    $socks = @()
    foreach ($p in $ports) {
        $kind = Get-ProxyKind '127.0.0.1' $p
        if ($kind -eq 'http') { $http += "http://127.0.0.1:$p" }
        elseif ($kind -eq 'socks5') { $socks += "socks5://127.0.0.1:$p" }
    }
    # HTTP 代理优先：环境变量和 --proxy-server 都最稳
    $found = @($http + $socks)
    if ($found.Count -gt 0) { $source = 'scan' }
}

if ($Detailed) {
    Write-Output "SOURCE=$source"
    Write-Output ("CANDIDATES=" + ($found -join ','))
    exit 0
}

# 旧模式：只给一个端口号，VBS 启动器按 IsNumeric 判断
foreach ($u in $found) {
    if ($u -match ':(\d+)$') { Write-Output $matches[1]; exit 0 }
}
exit 1
