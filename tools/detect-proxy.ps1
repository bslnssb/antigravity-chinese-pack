<#
  探测本地代理：把第一个在监听的端口打到 stdout 就 exit 0；一个都没有 exit 1。

  为什么只认 127.0.0.1：代理装在别的机器上时，端口扫描没有意义，请在
  tools\local-proxy.txt 里写一行 host:port（那个文件优先于本脚本）。

  端口列表只是"候选"，不是"必须"。顺序按命中率排，别人用别的端口时
  不要改这里，改用 local-proxy.txt；想覆盖更多常见客户端可以在下面加。
#>
param([int]$TimeoutMs = 200)

$ports = @(7897, 7890, 7891, 10808, 10809, 1080, 8080, 2080, 8888)

foreach ($p in $ports) {
    $ok = $false
    $c = New-Object Net.Sockets.TcpClient
    try {
        $r = $c.BeginConnect('127.0.0.1', $p, $null, $null)
        if ($r.AsyncWaitHandle.WaitOne($TimeoutMs)) {
            $c.EndConnect($r)
            $ok = $c.Connected
        }
    } catch {
        $ok = $false
    }
    $c.Close()
    if ($ok) {
        Write-Output $p
        exit 0
    }
}

exit 1
