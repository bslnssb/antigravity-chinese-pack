Option Explicit
' ============================================================
'  Antigravity 中文版启动器（无黑窗口）
'
'  作用与 start-antigravity-proxy.cmd 相同：设置代理环境变量后拉起
'  Antigravity.exe。区别是用 wscript 运行，不会弹出 cmd 窗口。
'
'  为什么要设环境变量：界面进程认 --proxy-server 参数，但负责登录换
'  token、调用 AI 的语言服务器（Go 进程）只认 HTTPS_PROXY，必须由父
'  进程传下去。Windows 快捷方式没有"设置环境变量"的字段，所以需要这
'  一层包装。
'
'  编码：本文件是 UTF-16LE + BOM，WSH 能正确读取中文；ANSI/UTF-8 会乱码。
' ============================================================

Const PROXY = "http://127.0.0.1:7897"
Const PROXY_HOST = "127.0.0.1"
Const PROXY_PORT = 7897

Dim fso, sh, env
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
Set env = sh.Environment("PROCESS")

Dim here
here = fso.GetParentFolderName(WScript.ScriptFullName)

Log "---- launch start ----"

' ---------- 1. 查找 Antigravity.exe ----------
Dim exePath
exePath = FindExe()
If exePath = "" Then
    MsgBox "没有找到 Antigravity.exe。" & vbCrLf & vbCrLf & _
           "已经查过：" & vbCrLf & _
           "  %LOCALAPPDATA%\Programs\Antigravity" & vbCrLf & _
           "  %PROGRAMFILES%\Antigravity" & vbCrLf & _
           "  %PROGRAMFILES(X86)%\Antigravity" & vbCrLf & _
           "  注册表里记录的安装路径" & vbCrLf & vbCrLf & _
           "请先安装 Antigravity。", vbCritical, "Antigravity 中文版"
    WScript.Quit 1
End If
Log "exe = " & exePath

' ---------- 2. 代理端口检查（只提示，不强制退出）----------
If Not PortOpen(PROXY_HOST, PROXY_PORT) Then
    Dim ans
    ans = MsgBox("检测到 " & PROXY_HOST & ":" & PROXY_PORT & " 没有在监听，" & vbCrLf & _
                 "Clash Verge Rev 可能没有启动。" & vbCrLf & vbCrLf & _
                 "这种情况下启动 Antigravity 会完全没有网络" & vbCrLf & _
                 "（登录、对话都会失败）。" & vbCrLf & vbCrLf & _
                 "仍要启动吗？", vbQuestion + vbYesNo + vbDefaultButton2, "Antigravity 中文版")
    If ans <> vbYes Then
        Log "user cancelled (proxy port closed)"
        WScript.Quit 0
    End If
    Log "WARN proxy port closed, user chose to continue"
End If

' ---------- 3. 环境变量 ----------
env("HTTP_PROXY")  = PROXY
env("HTTPS_PROXY") = PROXY
env("ALL_PROXY")   = PROXY
env("http_proxy")  = PROXY
env("https_proxy") = PROXY
env("all_proxy")   = PROXY
' 必须清空：NO_PROXY 若覆盖 googleapis.com，等于没设代理
env("NO_PROXY")    = ""
env("no_proxy")    = ""
' 必须清空：被继承时 Electron 会进入纯 Node 模式，静默退出，无窗口无日志
env("ELECTRON_RUN_AS_NODE") = ""

' ---------- 4. 启动 ----------
Dim cmd
cmd = """" & exePath & """ --proxy-server=""" & PROXY & """"

Dim args, i
args = ""
For i = 0 To WScript.Arguments.Count - 1
    args = args & " " & WScript.Arguments(i)
Next
If args <> "" Then cmd = cmd & args

Log "run: " & cmd
sh.CurrentDirectory = fso.GetParentFolderName(exePath)
sh.Run cmd, 1, False


' ============================================================
'  辅助函数
' ============================================================

Function FindExe()
    Dim cands, i, p
    cands = Array( _
        sh.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\Programs\Antigravity\Antigravity.exe", _
        sh.ExpandEnvironmentStrings("%PROGRAMFILES%") & "\Antigravity\Antigravity.exe", _
        sh.ExpandEnvironmentStrings("%PROGRAMFILES(X86)%") & "\Antigravity\Antigravity.exe")

    For i = 0 To UBound(cands)
        If fso.FileExists(cands(i)) Then
            FindExe = cands(i)
            Exit Function
        End If
    Next

    ' 标准位置都没有：问注册表（复用安装脚本那支 ps1，输出 resources 目录）
    Dim ps1
    ps1 = here & "\tools\find-install-dir.ps1"
    If fso.FileExists(ps1) Then
        Dim res
        res = RunHidden("powershell -NoProfile -ExecutionPolicy Bypass -File """ & ps1 & """")
        res = Trim(res)
        If res <> "" Then
            p = fso.GetParentFolderName(res) & "\Antigravity.exe"
            If fso.FileExists(p) Then
                FindExe = p
                Exit Function
            End If
        End If
    End If

    FindExe = ""
End Function

Function PortOpen(host, port)
    Dim probe, out
    ' 用 .NET TcpClient 探一下端口，300ms 超时
    probe = "powershell -NoProfile -Command ""$c=New-Object Net.Sockets.TcpClient; " & _
            "try{$r=$c.BeginConnect('" & host & "'," & port & ",$null,$null); " & _
            "if($r.AsyncWaitHandle.WaitOne(300)){$c.EndConnect($r); '1'}else{'0'}}" & _
            "catch{'0'} finally{$c.Close()}"""
    out = RunHidden(probe)
    PortOpen = (InStr(out, "1") > 0)
End Function

Function RunHidden(cmdline)
    Dim exec
    RunHidden = ""
    On Error Resume Next
    Set exec = sh.Exec(cmdline)
    If Err.Number <> 0 Then
        Err.Clear
        Exit Function
    End If
    RunHidden = exec.StdOut.ReadAll()
    If Err.Number <> 0 Then Err.Clear
    On Error GoTo 0
End Function

Sub Log(msg)
    On Error Resume Next
    Dim f, logPath
    logPath = sh.ExpandEnvironmentStrings("%TEMP%") & "\antigravity-launch.log"
    Set f = fso.OpenTextFile(logPath, 8, True)
    f.WriteLine Now & "  " & msg
    f.Close
    On Error GoTo 0
End Sub
