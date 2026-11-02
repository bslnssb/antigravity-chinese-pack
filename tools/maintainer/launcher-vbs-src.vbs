Option Explicit
' ============================================================
'  Antigravity 中文版启动器（无黑窗口）
'
'  作用与 start-antigravity-proxy.cmd 相同：探测到本地代理就设置代理
'  环境变量后拉起 Antigravity.exe，探不到就不碰任何网络设置。
'  区别是用 wscript 运行，不会弹出 cmd 窗口。
'
'  为什么要设环境变量：界面进程认 --proxy-server 参数，但负责登录换
'  token、调用 AI 的语言服务器（Go 进程）只认 HTTPS_PROXY，必须由父
'  进程传下去。Windows 快捷方式没有"设置环境变量"的字段，所以需要这
'  一层包装。
'
'  编码：本文件是 UTF-16LE + BOM，WSH 能正确读取中文；ANSI/UTF-8 会乱码。
'  改这个文件后，务必确认保存为 UTF-16LE + BOM，否则中文会变乱码。
'
'  2026-11-02 加固：
'  - 端口探测改为隐藏窗口执行（原来用 sh.Exec 会闪一个黑框）
'  - ELECTRON_RUN_AS_NODE 必须彻底移除：非空时 exe 以纯 Node 模式启动，
'    表现为静默退出、无窗口、无日志、exit code 9
'  - 启动前先查是否已在运行；启动后 5 秒复查，没活下来就明确报错，
'    不再让用户面对"什么都没发生"
'
'  2026-11-02 自愈：
'  - 官方更新是 NSIS 全量包，会把 resources\ 整个换掉，连备份一起删，
'    所以"汉化永久存活"物理上做不到，只能做到"发现被覆盖就自动补回来"
'  - 启动前调 tools\selfheal.ps1 -Check（约 0.4 秒）：靠 resources\.zh-pack
'    标记判断。标记匹配就直接启动，不碰任何文件
'  - 不匹配才 -Heal：本地有成品就复制，没有就去 GitHub Releases 直连下载
'  - 自愈失败一律"放行启动"，绝不因为补丁问题让应用打不开
'
'  2026-11-03 代理不再写死：
'  - 原来这里写死了作者本机的 Clash 端口，而且探不到
'    还会弹框问"仍要启动吗"，别人装在不同端口只会一脸困惑
'  - 现在探到才设 --proxy-server 和环境变量；探不到就不设、不弹框，只写日志
' ============================================================

Const EXE_NAME = "Antigravity.exe"

' 代理不是"必须有的东西"：探到本地代理才设，探不到就一个网络设置都不动。
' 探测顺序见 DetectProxy()：tools\local-proxy.txt（本机专用，不进发布包）
' → 系统代理（注册表 ProxyServer）→ tools\detect-proxy.ps1 扫一批常见端口。
Const PROXY_HINT_FILE = "local-proxy.txt"

Dim fso, sh, env, tmpDir, here
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
Set env = sh.Environment("PROCESS")
tmpDir = sh.ExpandEnvironmentStrings("%TEMP%")
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

' ---------- 2. 已经在跑就说清楚，不再重复拉一个 ----------
If AppRunning() Then
    Log "already running, skip"
    MsgBox "Antigravity 已经在运行了，不再重复启动。" & vbCrLf & vbCrLf & _
           "它可能已最小化到任务栏或系统托盘，" & vbCrLf & _
           "点一下那里的图标就能看到窗口。", vbInformation, "Antigravity 中文版"
    WScript.Quit 0
End If

' ---------- 3. 找本地代理（探不到就什么都不动）----------
' 以前这里写死了作者本机的 Clash 端口——别人用别的端口就永远走错门；
' 而且探不到还会弹框问「仍要启动吗」。现在探到才设，探不到就不设也不弹框。
Dim proxyUrl
proxyUrl = DetectProxy()

' ---------- 4. 环境变量 ----------
' 只有探到代理才设。探不到时一个都不写：既不用自己猜的端口，也不覆盖
' 用户自己配好的东西（Windows 上给环境变量写空值等于删除）。
If proxyUrl <> "" Then
    Log "proxy = " & proxyUrl
    env("HTTP_PROXY")  = proxyUrl
    env("HTTPS_PROXY") = proxyUrl
    env("ALL_PROXY")   = proxyUrl
    env("http_proxy")  = proxyUrl
    env("https_proxy") = proxyUrl
    env("all_proxy")   = proxyUrl
    ' 必须清空：NO_PROXY 若覆盖 googleapis.com，等于没设代理
    env("NO_PROXY")    = ""
    env("no_proxy")    = ""
Else
    Log "proxy = none（没探到本地代理，网络设置一律不动）"
End If
' 必须彻底移除：非空时 exe 会以纯 Node 模式运行，静默退出、无窗口、无日志
ClearEnv "ELECTRON_RUN_AS_NODE"
ClearEnv "NODE_OPTIONS"

' ---------- 5. 自愈：官方更新覆盖后把中文补回来 ----------
' 放在设完代理之后：需要下载时走同一个代理。放在启动之前：覆盖 asar
' 时应用必须没在跑（第 2 步已确认）。
Dim healOut, healState, healSrc, healVer, healedRes
healOut = RunSelfheal("-Check")
healState = FieldOf(healOut, "STATE")
' 记录"这次是不是刚做了现场移植"，启动失败时要靠它决定回滚
healSrc = ""
healVer = ""
healedRes = ""

If healState = "need" Then
    healSrc = FieldOf(healOut, "SOURCE")
    healVer = FieldOf(healOut, "VER")
    Log "selfheal: need, ver=" & healVer & " source=" & healSrc

    ' 本地有成品时复制只要几十毫秒，用户感觉不到；要下载或现场移植就得几秒，
    ' 先给个提示，否则用户会以为双击没反应
    If healSrc = "download" Or healSrc = "port" Then
        sh.Popup "检测到 Antigravity 已更新到 " & healVer & "，" & vbCrLf & _
                 "正在自动准备这个版本的中文包，请稍等…", 4, "Antigravity 中文版", 64
    End If

    healOut = RunSelfheal("-Heal")
    healState = FieldOf(healOut, "STATE")
    healSrc = FieldOf(healOut, "SOURCE")
    Log "selfheal: done state=" & healState & " code=" & FieldOf(healOut, "CODE") & _
        " source=" & healSrc & " | " & FieldOf(healOut, "DETAIL")
    If healState = "ready" Then
        healedRes = FieldOf(healOut, "RES")
        healVer = FieldOf(healOut, "VER")
    End If

    If healState <> "ready" Then
        Dim hcode, hmsg, hcont
        hcode = FieldOf(healOut, "CODE")
        hmsg = FieldOf(healOut, "DETAIL")
        If hmsg = "" Then hmsg = "自愈脚本没有返回原因。"

        If hcode = "20" Then
            ' 连现场移植都没成功（例如官方改动太大、或包装在 Program Files 没有写权限）
            hcont = MsgBox("官方已经更新到 " & healVer & "。" & vbCrLf & _
                           "这个版本的中文包还没发布，用旧译文现场移植也没成功。" & vbCrLf & vbCrLf & _
                           hmsg & vbCrLf & vbCrLf & _
                           "要先用英文版启动吗？" & vbCrLf & _
                           "（中文包发布后，下次启动会自动恢复中文）", _
                           vbQuestion + vbYesNo + vbDefaultButton1, "Antigravity 中文版")
            If hcont <> vbYes Then
                Log "user cancelled (no pack for this version)"
                WScript.Quit 0
            End If
        Else
            MsgBox hmsg & vbCrLf & vbCrLf & _
                   "本次先用当前界面启动（可能是英文）。" & vbCrLf & vbCrLf & _
                   "排查日志：" & tmpDir & "\antigravity-launch.log", _
                   vbExclamation, "Antigravity 中文版"
        End If
    End If
ElseIf healState = "ready" Then
    Log "selfheal: ready (" & FieldOf(healOut, "VER") & ")"
Else
    ' 脚本不存在或没输出：老版本包 / 异常。直接放行，不影响使用。
    Log "selfheal: no output (script missing or failed), skipped"
End If

' ---------- 6. 启动 ----------
Dim cmd
cmd = """" & exePath & """"
If proxyUrl <> "" Then cmd = cmd & " --proxy-server=""" & proxyUrl & """"

Dim args, i
args = ""
For i = 0 To WScript.Arguments.Count - 1
    args = args & " " & WScript.Arguments(i)
Next
If args <> "" Then cmd = cmd & args

Log "run: " & cmd
sh.CurrentDirectory = fso.GetParentFolderName(exePath)
sh.Run cmd, 1, False

' ---------- 7. 启动后复查：没活下来就明确报错 ----------
WScript.Sleep 5000
If Not AppRunning() Then
    Log "WARN: process not alive 5s after launch"

    ' 这次是"现场移植"刚补上去的：大概率是移植产物与新版本客户端不兼容。
    ' 回滚到官方英文版并留一条"别再自动移植"的记录，否则用户会卡在反复重试里。
    If healSrc = "port" And healedRes <> "" Then
        RevertPort healedRes, healVer
        MsgBox "刚才自动移植的中文包没能启动，已回滚到官方英文版。" & vbCrLf & vbCrLf & _
               "这样至少客户端还能用。等本仓库发布 v" & healVer & " 的正式中文包后，" & vbCrLf & _
               "再跑一次 一键安装汉化.bat 即可恢复中文。" & vbCrLf & vbCrLf & _
               "想再试一次移植：删掉" & vbCrLf & _
               "  %LOCALAPPDATA%\Antigravity\zh-port-skip" & vbCrLf & _
               "后重新双击本快捷方式。" & vbCrLf & vbCrLf & _
               "排查日志：" & tmpDir & "\antigravity-launch.log", _
               vbExclamation, "Antigravity 中文版"
        Log "port rollback done (skip recorded)"
        WScript.Quit 0
    End If

    MsgBox "Antigravity 启动后立刻退出了（没有窗口，日志里也没有启动记录）。" & vbCrLf & vbCrLf & _
           "最常见的原因：" & vbCrLf & _
           "1. 有一个没退干净的 Antigravity 进程占着单实例锁" & vbCrLf & _
           "   → 打开任务管理器，结束所有 Antigravity 进程后重试" & vbCrLf & _
           "2. 环境变量 ELECTRON_RUN_AS_NODE 被继承，exe 进了纯 Node 模式" & vbCrLf & _
           "   → 本启动器已清除；若仍失败，重启一次电脑再试" & vbCrLf & vbCrLf & _
           "排查日志：" & tmpDir & "\antigravity-launch.log", _
           vbExclamation, "Antigravity 中文版"
End If


' ============================================================
'  辅助函数
' ============================================================

' ---------- 代理探测 ----------
' 顺序：本机提示文件 -> 系统代理 -> 扫一批常见端口。全都探不到就返回 ""，
' 调用方据此"一个网络设置都不动"。这里不许把任何一个端口当成"必须"，
' 只允许把常见端口当候选（列表在 tools\detect-proxy.ps1 里维护）。
'
' tools\local-proxy.txt（不进 git、不进发布包）：一行 [host:port] 或 7897，
' 给端口不常见的用户用。写错/代理没开都不会报错，只是继续往下探。
Function DetectProxy()
    Dim hint, raw, t, url, h, p, lines
    DetectProxy = ""

    ' 1) 本机提示文件
    hint = here & "\tools\" & PROXY_HINT_FILE
    raw = ""
    If fso.FileExists(hint) Then
        On Error Resume Next
        Set lines = fso.OpenTextFile(hint, 1, False)
        Do While Not lines.AtEndOfStream
            t = Trim(lines.ReadLine())
            If t <> "" And Left(t, 1) <> "#" Then
                raw = t
                Exit Do
            End If
        Loop
        lines.Close
        If Err.Number <> 0 Then Err.Clear
        On Error GoTo 0
    End If
    url = NormProxy(raw)
    If url <> "" Then
        SplitHostPort url, h, p
        If PortOpen(h, p) Then
            Log "proxy: local-proxy.txt -> " & url
            DetectProxy = url
            Exit Function
        End If
        Log "proxy: local-proxy.txt 写的 " & url & " 没在监听，继续探测"
    End If

    ' 2) 系统代理（Clash 打开"系统代理"时最准，端口往往不是默认那个）
    On Error Resume Next
    raw = ""
    If sh.RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ProxyEnable") = 1 Then
        raw = sh.RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ProxyServer")
    End If
    If Err.Number <> 0 Then
        raw = ""
        Err.Clear
    End If
    On Error GoTo 0
    url = NormProxy(raw)
    If url <> "" Then
        SplitHostPort url, h, p
        If PortOpen(h, p) Then
            Log "proxy: 系统代理 -> " & url
            DetectProxy = url
            Exit Function
        End If
        Log "proxy: 系统代理 " & url & " 没在监听，继续探测"
    End If

    ' 3) 扫常见端口：一次 PowerShell 走完，别一个端口起一个进程
    Dim ps1, out
    ps1 = here & "\tools\detect-proxy.ps1"
    If fso.FileExists(ps1) Then
        out = Trim(RunHidden("powershell -NoProfile -ExecutionPolicy Bypass -File """ & ps1 & """"))
        If IsNumeric(out) Then
            url = "http://127.0.0.1:" & CStr(CLng(out))
            Log "proxy: 端口扫描 -> " & url
            DetectProxy = url
            Exit Function
        End If
    End If

    DetectProxy = ""
End Function

' 把各种代理写法归一成 http://host:port：
' 7897 / 127.0.0.1:7897 / http://127.0.0.1:7897 / "http=h:p;https=h:p" 都认。
Function NormProxy(s)
    Dim t, parts, i, b, key, cand
    NormProxy = ""
    t = Trim(CStr(s))
    If t = "" Then Exit Function
    If InStr(1, t, "=", 1) > 0 Then
        cand = ""
        parts = Split(t, ";")
        For i = 0 To UBound(parts)
            b = InStr(1, parts(i), "=", 1)
            If b > 0 Then
                key = LCase(Trim(Left(parts(i), b - 1)))
                If key = "http" Then
                    cand = Trim(Mid(parts(i), b + 1))
                    Exit For
                End If
                If cand = "" Then cand = Trim(Mid(parts(i), b + 1))
            End If
        Next
        If cand = "" Then Exit Function
        t = cand
    End If
    If LCase(Left(t, 7)) = "http://" Then t = Mid(t, 8)
    If LCase(Left(t, 8)) = "https://" Then t = Mid(t, 9)
    b = InStr(1, t, "/", 1)
    If b > 0 Then t = Left(t, b - 1)
    t = Trim(t)
    If t = "" Then Exit Function
    If IsNumeric(t) Then t = "127.0.0.1:" & t
    If InStr(1, t, ":", 1) = 0 Then Exit Function
    NormProxy = "http://" & t
End Function

' 从 http://host:port 拆出 host 和 port（VBScript 参数默认 ByRef）
Sub SplitHostPort(url, h, p)
    Dim t, b, i, ps
    h = "127.0.0.1"
    p = 0
    t = Trim(url)
    b = InStr(1, t, "://", 1)
    If b > 0 Then t = Mid(t, b + 3)
    i = InStrRev(t, ":")
    If i = 0 Then Exit Sub
    h = Trim(Left(t, i - 1))
    ps = Trim(Mid(t, i + 1))
    If IsNumeric(ps) Then p = CLng(ps)
    If h = "" Then h = "127.0.0.1"
End Sub

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
    Dim ps1, res
    ps1 = here & "\tools\find-install-dir.ps1"
    If fso.FileExists(ps1) Then
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

' 进程是否在运行：tasklist 隐藏窗口跑，结果写到临时文件再读。
' 用 sh.Run(..., 0, True) 而不是 sh.Exec —— Exec 一定会弹控制台窗口。
Function AppRunning()
    Dim outFile, s
    AppRunning = False
    outFile = tmpDir & "\ag-proc.txt"
    On Error Resume Next
    sh.Run "cmd /c tasklist /FI ""IMAGENAME eq " & EXE_NAME & """ /NH > """ & outFile & """", 0, True
    s = ""
    If fso.FileExists(outFile) Then
        Dim f
        Set f = fso.OpenTextFile(outFile, 1, False)
        s = f.ReadAll()
        f.Close()
    End If
    If Err.Number <> 0 Then Err.Clear
    On Error GoTo 0
    AppRunning = (InStr(1, s, "Antigravity", 1) > 0)
End Function

' 代理端口是否监听：PowerShell 探一下，用 exit code 回传，窗口隐藏。
Function PortOpen(host, port)
    Dim probe, rc
    probe = "powershell -NoProfile -Command ""$c=New-Object Net.Sockets.TcpClient; " & _
            "try{$r=$c.BeginConnect('" & host & "'," & port & ",$null,$null); " & _
            "if($r.AsyncWaitHandle.WaitOne(300)){$c.EndConnect($r); exit 0}else{exit 1}}" & _
            "catch{exit 1} finally{$c.Close()}"""
    rc = 1
    On Error Resume Next
    rc = sh.Run(probe, 0, True)
    If Err.Number <> 0 Then Err.Clear
    On Error GoTo 0
    PortOpen = (rc = 0)
End Function

' 调自愈脚本。用相对路径（先切到包目录）是为了让命令行里没有中文和空格，
' 避免 cmd 解析与编码上的坑；输出是 KEY=VALUE 行。
Function RunSelfheal(sw)
    Dim ps1, oldCwd, cmdline, out
    RunSelfheal = ""
    ps1 = here & "\tools\selfheal.ps1"
    If Not fso.FileExists(ps1) Then Exit Function

    On Error Resume Next
    oldCwd = sh.CurrentDirectory
    sh.CurrentDirectory = here
    cmdline = "powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\selfheal.ps1 " & sw & " -Quiet -PackDir ."
    out = RunHidden(cmdline)
    sh.CurrentDirectory = oldCwd
    RunSelfheal = out
    If Err.Number <> 0 Then
        Log "selfheal err: " & Err.Description
        Err.Clear
        RunSelfheal = ""
    End If
    On Error GoTo 0
End Function

' 从 KEY=VALUE 文本里取某个键的值（自愈脚本的输出格式）
Function FieldOf(text, key)
    Dim re, m
    FieldOf = ""
    If text = "" Then Exit Function
    Set re = New RegExp
    re.IgnoreCase = True
    re.MultiLine = True
    re.Global = False
    ' 必须用 [^\r\n]* 而不是 .*：多行模式下 $ 落在 \n 之前，而 . 会贪婪
    ' 吃到 \r，值末尾会带一个回车，后面拼接字符串时会错位
    re.Pattern = "^" & key & "=([^\r\n]*)"
    Set m = re.Execute(text)
    If m.Count > 0 Then FieldOf = Trim(m(0).SubMatches(0))
End Function

' 隐藏窗口跑命令并取回标准输出
Function RunHidden(cmdline)
    Dim outFile
    RunHidden = ""
    outFile = tmpDir & "\ag-runout.txt"
    On Error Resume Next
    If fso.FileExists(outFile) Then fso.DeleteFile outFile, True
    sh.Run "cmd /c " & cmdline & " > """ & outFile & """ 2>&1", 0, True
    If fso.FileExists(outFile) Then
        Dim f
        Set f = fso.OpenTextFile(outFile, 1, False)
        RunHidden = f.ReadAll()
        f.Close()
    End If
    If Err.Number <> 0 Then Err.Clear
    On Error GoTo 0
End Function

' 回滚现场移植：用备份的官方 asar 覆盖回去、删掉补丁标记，并记一条
' "这个版本别再自动移植"——否则下次启动又会移植、又起不来，用户就卡循环了。
Sub RevertPort(resDir, ver)
    On Error Resume Next
    Dim bak, cur, folder, skipFile, f
    bak = resDir & "\app.asar.backup"
    cur = resDir & "\app.asar"
    If fso.FileExists(bak) Then fso.CopyFile bak, cur, True
    If fso.FileExists(resDir & "\.zh-pack") Then fso.DeleteFile resDir & "\.zh-pack", True
    If ver <> "" Then
        folder = sh.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\Antigravity"
        If Not fso.FolderExists(folder) Then fso.CreateFolder folder
        skipFile = folder & "\zh-port-skip"
        Set f = fso.OpenTextFile(skipFile, 8, True)
        f.WriteLine ver
        f.Close
    End If
    If Err.Number <> 0 Then
        Log "revert err: " & Err.Description
        Err.Clear
    End If
    On Error GoTo 0
End Sub

' 彻底移除环境变量：先置空（Windows 上等于删除），再 Remove 兜底。
' 只置空在某些宿主下会留下一个值为空的变量，Electron 可能仍把它当"已设置"。
Sub ClearEnv(name)
    On Error Resume Next
    env(name) = ""
    env.Remove(name)
    If Err.Number <> 0 Then Err.Clear
    On Error GoTo 0
End Sub

Sub Log(msg)
    On Error Resume Next
    Dim f, logPath
    logPath = tmpDir & "\antigravity-launch.log"
    Set f = fso.OpenTextFile(logPath, 8, True)
    f.WriteLine Now & "  " & msg
    f.Close
    On Error GoTo 0
End Sub
