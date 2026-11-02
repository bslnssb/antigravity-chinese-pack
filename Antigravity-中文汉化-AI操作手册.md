# Antigravity 中文汉化操作手册（面向 AI 代理 / 可复现 Runbook）

> 适用对象：替用户把 **Google Antigravity**（Electron 桌面应用）界面变成简体中文的 AI 代理。
> 本手册记录 2026-10 在 Windows 10/11 + PowerShell 5.1 + Node.js 环境下的**完整实证流程**，
> 包括所有踩过的坑和判定规则。照做即可，不必重新试错。

---

## 0. TL;DR（最短路径）

前提：已确认 Antigravity 安装路径与版本，且网络能访问 GitHub（国内需代理）。

```powershell
# 变量（按需改）
$W   = "<本仓库根目录>"          # 例：D:\Tools\Antigravity-汉化（路径含空格/括号时务必带引号）
$APP = "$env:LOCALAPPDATA\Programs\Antigravity"
$T   = "$W\tools\antigravity-zh-patch.js"      # 本手册配套工具
$NODE= "node"                                   # 或 node.exe 绝对路径

# 0) 关键：清除 ELECTRON_RUN_AS_NODE（否则 Antigravity 当 Node 跑，起不来）
[Environment]::SetEnvironmentVariable('ELECTRON_RUN_AS_NODE',$null,'Process')

# 1) 关闭应用
Get-Process Antigravity,language_server -ErrorAction SilentlyContinue | ForEach-Object { $_.Kill() }
Start-Sleep 3

# 2) 备份（更新程序会删掉旧 backup，必须每次重做）
Copy-Item "$APP\resources\app.asar" "$APP\resources\app.asar.backup" -Force

# 3) 构建（swap-map.json 见第 5 节）
& $NODE $T build  --base "$APP\resources\app.asar" --out "$W\build\app.asar.patched" --swap "$W\build\swap-map.json"
& $NODE $T verify --base "$APP\resources\app.asar" --out "$W\build\app.asar.patched" `
                  --expect "dist/preload.js,dist/main.js,dist/menu.js,dist/tray.js,dist/ipcHandlers.js,dist/ideInstall/wizardHtml.js"

# 4) 安装
Copy-Item "$W\build\app.asar.patched" "$APP\resources\app.asar" -Force

# 5) 启动 + 验证界面语言
$env:HTTP_PROXY='http://127.0.0.1:7897'; $env:HTTPS_PROXY='http://127.0.0.1:7897'; $env:NO_PROXY=''
Start-Process "$APP\Antigravity.exe"
Start-Sleep 18
& $NODE "$W\tools\verify-ui-zh.js"      # 期望输出 VERDICT: CHINESE UI CONFIRMED
```

---

## 1. 事实基线（先理解，再动手）

1. **Antigravity 是 Electron 应用**。界面代码在 `resources\app.asar` 里，主要是：
   - `dist/preload.js`：注入渲染进程的桥接层（**汉化补丁的核心翻译引擎就替换这里**）
   - `dist/main.js` / `dist/menu.js` / `dist/tray.js`：主进程、原生菜单、系统托盘
   - `dist/ideInstall/wizardHtml.js`：Antigravity IDE 引导页
2. **官方无中文**，`app.asar` 里没有任何 i18n 代码；中文只能靠社区补丁。
3. **社区补丁的原理**：只改 **6 个文件**，不增删文件：
   | 文件 | 原始大小 | 汉化后 |
   |---|---|---|
   | dist/preload.js | ~5.4 KB | ~318 KB（词库+DOM 翻译引擎）|
   | dist/main.js | ~20 KB | +20 B 左右（托盘/退出对话框中文）|
   | dist/menu.js | ~6.5 KB | +16 B |
   | dist/tray.js | ~3.7 KB | -60 B |
   | dist/ideInstall/wizardHtml.js | ~6.7 KB | +4 B |
   | dist/ipcHandlers.js | ~9 KB | 4 处可见英文（2.26 起纳入，历史缺口）|

   > 注：社区包原始范围是 5 个；本项目从 2.26 起补上 `ipcHandlers.js`，故为 6 个。
4. **汉化包发版滞后于官方**：官方发版后通常 1–3 天才出对应包。
   例：官方已到 **2.25.0** 时，最新包是 **2.24.0**。
5. **因此绝对不要整包替换**。包里 `app.asar.chinese` 是针对**某个具体版本**的完整 asar，
   直接覆盖会让主进程代码降级到旧版本。正确做法（本手册）：**以用户自己的 app.asar 为底，只换 6 个文件**。

---

## 2. 环境前置与硬性约束

### 2.1 `ELECTRON_RUN_AS_NODE` 必须清除 ⚠️ 最容易踩的坑

若启动 Antigravity 的父进程（如另一个 Electron 应用、DSH/DeepSeek Harness 的 shell）环境里存在
`ELECTRON_RUN_AS_NODE=1`，Antigravity 会**以纯 Node 模式启动**，表现为：

- 命令行报 `Antigravity.exe: bad option: --proxy-server=...`、`--enable-logging` 等参数全被拒；
- 无参数时**静默退出，退出码 0 或 9**；
- **不生成窗口、不写 main.log**（极易误判为"补丁把应用搞坏了"）。

处置：启动前执行
```powershell
[Environment]::SetEnvironmentVariable('ELECTRON_RUN_AS_NODE',$null,'Process')
```
也可用 `Get-ChildItem Env: | Where-Object Name -match 'ELECTRON'` 自查。

### 2.2 下载需要代理

GitHub Release 的下载域名（`objects.githubusercontent.com`）在国内常被阻断，
`api.github.com` 可能可直连但下载 0 字节。用本地代理：

```powershell
curl.exe -L --max-time 180 -x http://127.0.0.1:7897 -o pack.zip "<release url>"
```
务必校验 SHA256（Release API 的 `assets[].digest` 字段或发布页）。

### 2.3 PowerShell 5.1 的编码陷阱

- **`.ps1` 脚本里不要写中文**：PS 5.1 按 ANSI(GBK) 读无 BOM 文件，中文字符串会破坏引号/花括号导致
  `表达式或语句中包含意外的标记`。本手册所有脚本均为 **纯 ASCII**。
- **JSON 文件不要用 `Set-Content -Encoding UTF8`**：会加 BOM(EF BB BF)，Node `JSON.parse` 报
  `Unexpected token '﻿'`。用：
  ```powershell
  [System.IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding($false)))
  ```
  （配套工具已兼容 BOM，但生成时避免更省事。）

### 2.4 所需工具

| 工具 | 用途 |
|---|---|
| Node.js ≥ 18 | 解析/构建 asar、CDP 验证 |
| `tools/antigravity-zh-patch.js` | asar 解析 / 提取 / 构建 / 校验（本手册核心工具）|
| `tools/port-main-zh.js` | 把补丁的中文串移植到更新版本的 `main.js` |
| `tools/verify-ui-zh.js` | 通过 CDP 读取真实界面文本，验证中文是否生效 |
| curl.exe | 下载（Windows 10+ 自带）|

---

## 3. asar 格式关键知识（自己实现时的必读）

### 3.1 Antigravity 的 asar 头布局（**与标准 asar 略有不同**）

```
u32 @0  = 4
u32 @4  = headerSize            → dataStart = 8 + headerSize
u32 @8  = headerSize - 4
u32 @12 = jsonLen
json    @16 ...                 → 长度 jsonLen，随后 0 填充使 dataStart 8 字节对齐
data    @dataStart + offset
```

> 判据：`dataStart + Σ(非 unpacked 文件 size) == 文件大小`，必须成立。

### 3.2 每个文件条目可以带 `integrity`

```json
"integrity": {
  "algorithm": "SHA256",
  "hash": "<整个文件的 sha256>",
  "blockSize": 4194304,
  "blocks": ["<每个 4MB 块的 sha256>"]
}
```
- **被替换的文件必须重算 integrity**，否则 Electron 拒绝加载该归档，
  症状：应用立即退出（退出码 9）/ 白屏，且日志往往来不及写。
- 未修改文件的 integrity 必须**原样保留**（重算全部会平白扩大头部，也更容易出错）。
- 小于 4 MB 的文件：`blocks = [hash]`，`hash` 即整文件 sha256。

### 3.3 `unpacked` 条目

`node_modules/chrome-devtools-mcp` 等通过 `--unpack-dir` 外置，数据在
`resources\app.asar.unpacked\`，**header 里该条目没有 offset**。构建时必须：
- 保持其 size/offset/integrity 不动；
- 不要为它追加数据；
- 读取时若 `offset` 为空要跳过（否则 `fs.readSync` 抛 `Received NaN`）。

---

## 4. 标准流程（带验证点）

### Step 0 — 采集现状

```powershell
$APP="$env:LOCALAPPDATA\Programs\Antigravity"
(Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' |
  Where-Object DisplayName -match 'Antigravity').DisplayVersion          # 版本
Get-Item "$APP\resources\app.asar" | Select Length,LastWriteTime        # asar 大小/时间
(Get-FileHash "$APP\resources\app.asar" -Algorithm SHA256).Hash         # 指纹
Test-Path "$APP\resources\app.asar.backup"                              # 备份是否还在
```
> 记录哈希：更新后它会变，是判断"是否已升级/是否已打过补丁"的依据。

### Step 1 — 选择并下载汉化包

- 补丁来源（唯一维护活跃、MIT、有还原脚本）：
  `https://github.com/ATopos-svg/antigravity-chinese-community-pack`
- 查 releases：
  ```powershell
  curl.exe -s -x http://127.0.0.1:7897 "https://api.github.com/repos/ATopos-svg/antigravity-chinese-community-pack/releases?per_page=5"
  ```
- **版本选择规则**：
  - tag == 当前版本 → 最佳；
  - tag 比当前版本低 1 个 → 通常可用，但**必须**按 Step 3 判定；
  - 低 2 个以上 → 不建议，等新版包。
- 下载并校验 SHA256（见 2.2）。

包内固定包含：
```
app.asar.original      ← 该包对应官方版本的原始 asar（用于比对）
app.asar.chinese       ← 该版本的完整汉化 asar（不要直接用！）
一键安装汉化.bat / 一键恢复官方英文.bat 等安装/还原脚本
```

### Step 2 — 解析三份 asar

```powershell
& $NODE $T inspect "<本地 app.asar>"
& $NODE $T inspect "<包>\app.asar.original"
& $NODE $T inspect "<包>\app.asar.chinese"

& $NODE $T list "<本地 app.asar>"            "$W\build\local.json"
& $NODE $T list "<包>\app.asar.original"     "$W\build\pack-orig.json"
& $NODE $T list "<包>\app.asar.chinese"      "$W\build\pack-cn.json"
```

两组比对（用任意脚本/Excel 都行，按 `path` join，比 `hash`）：

- **比对 A：`pack-orig` vs `pack-cn`** → 得到"补丁范围"，应为 6 个文件且无增删。
  若出现其它文件，先审计（第 8 节）。
- **比对 B：`local` vs `pack-orig`** → 得到"官方新版本相对包版本的改动"。
  **重点看这 6 个补丁文件是否在其中。**

### Step 3 — 决策表（核心判定）

| 比对 B 结果 | 处理方式 | 风险 |
|---|---|---|
| 6 个补丁文件**都未变** | 直接取包里的 6 个文件替换（最简单，如 2.23→2.24）| 极低 |
| 仅 `main.js`/`menu.js`/`tray.js`/`wizardHtml.js`/`ipcHandlers.js` 变化 | **移植中文串**：diff 出 `pack-orig → pack-cn` 的字符串替换对，逐条应用到本地同版本文件上 | 低（如 2.24→2.25）|
| **`preload.js` 变化** | preload 是被**整套替换**的（5 KB→318 KB），无法合并。只能：①先用包里版本试（可能丢失新版本桥接 API，风险中）；②等对应版本包 | 中–高 |
| 版本差 ≥2 | 不要打，等新包 | — |

> 移植示例（2.24→2.25 的实际 diff，共 7 处）：
> ```
> label: 'No agents running'                      → label: '没有正在运行的智能体'
> label: `Open ${electron_1.app.getName()}`       → label: `打开 ${electron_1.app.getName()}`
> label: 'Quit'                                   → label: '退出'
> buttons: ['Cancel', 'Quit']                     → buttons: ['取消', '退出']
> title: 'Confirm Quit'                           → title: '确认退出'
> message: 'Are you sure you want to quit?'        → message: '您确定要退出吗？'
> detail: 'There may be agents or background tasks running.'
>                                                 → detail: '当前可能有正在运行的智能体或后台任务。'
> ```
> 2.25 官方对 `main.js` 的改动只是删掉了 macOS 的 `app.dock?.hide()` 分支，与上述文案不重叠 → 可安全移植。

### Step 4 — 构建（版本正确的最小改动包）

```powershell
$T = "$W\tools\antigravity-zh-patch.js"

# 4.1 从包里提取 5 个直接可用的文件
& $NODE $T extract "<包>\app.asar.chinese" "$W\build\materials" `
    "dist/preload.js" "dist/menu.js" "dist/tray.js" "dist/ipcHandlers.js" "dist/ideInstall/wizardHtml.js"

# 4.2 若 main.js 在新版本中变过：先提取三份 main.js（放不同子目录，避免同名覆盖）
& $NODE $T extract "<包>\app.asar.original" "$W\build\m\orig"  "dist/main.js"   # 旧英文（补丁基线）
& $NODE $T extract "<包>\app.asar.chinese"  "$W\build\m\cn"    "dist/main.js"   # 旧中文
& $NODE $T extract "<本地 app.asar>"        "$W\build\m\local" "dist/main.js"   # 新英文（目标）
& $NODE "$W\tools\port-main-zh.js" `
      "$W\build\m\orig\dist__main.js"  `
      "$W\build\m\cn\dist__main.js"    `
      "$W\build\m\local\dist__main.js" `
      "$W\build\materials\main-zh.js"                                  # 产物
# 期望输出: applied N/N，且 N 等于旧英文→旧中文的差异行数
# 校验移植只改了预期行数（应等于 N）：
$a = Get-Content "$W\build\m\local\dist__main.js"
$b = Get-Content "$W\build\materials\main-zh.js"
(Compare-Object $a $b | Where-Object SideIndicator -eq '<=').Count   # 期望 = N/2 左右（成对出现）
# 更严格：确认差异行都是"英文文案 -> 中文文案"的替换，而不是代码逻辑变动

# 4.3 写 swap-map.json（**无 BOM**，见 2.3）
#    {"dist/preload.js":"...","dist/menu.js":"...","dist/tray.js":"...",
#     "dist/ipcHandlers.js":"...","dist/ideInstall/wizardHtml.js":"...","dist/main.js":"<移植产物>"}
[System.IO.File]::WriteAllText("$W\build\swap-map.json", ($map | ConvertTo-Json),
    (New-Object System.Text.UTF8Encoding($false)))

# 4.4 构建 + 校验
& $NODE $T build  --base "$APP\resources\app.asar" --out "$W\build\app.asar.patched" --swap "$W\build\swap-map.json"
& $NODE $T verify --base "$APP\resources\app.asar" --out "$W\build\app.asar.patched" `
      --expect "dist/preload.js,dist/main.js,dist/menu.js,dist/tray.js,dist/ipcHandlers.js,dist/ideInstall/wizardHtml.js"
```

`verify` 必须全部为 OK：
```
file set identical (N files)                       OK
changed exactly: <那 6 个>                          OK
integrity dist/preload.js: VALID ...               OK
archive self-consistent: true
RESULT: ALL CHECKS PASSED
```
另需确认产物里的 `package.json` 版本 == 本地版本（防止版本回退）：
```powershell
& $NODE $T extract "$W\build\app.asar.patched" "$W\build\chk" "package.json"
Get-Content "$W\build\chk\package.json" -Raw     # 看 "version"
```

### Step 5 — 备份 / 安装 / 启动 / 验证

```powershell
# 5.1 备份（双份：就地给还原脚本用 + 工作区留档）
Copy-Item "$APP\resources\app.asar" "$APP\resources\app.asar.backup" -Force
Copy-Item "$APP\resources\app.asar" "$W\build\app.asar.original-<版本>.0" -Force

# 5.2 关闭并安装
[Environment]::SetEnvironmentVariable('ELECTRON_RUN_AS_NODE',$null,'Process')
Get-Process Antigravity,language_server -ErrorAction SilentlyContinue | ForEach-Object { $_.Kill() }
Start-Sleep 3
Copy-Item "$W\build\app.asar.patched" "$APP\resources\app.asar" -Force

# 5.3 启动（网络需要的代理环境变量按用户环境填）
$env:HTTP_PROXY='http://127.0.0.1:7897'; $env:HTTPS_PROXY='http://127.0.0.1:7897'; $env:NO_PROXY=''
Start-Process "$APP\Antigravity.exe"
Start-Sleep 18

# 5.4 进程与窗口
Get-Process Antigravity,language_server | Select Id,ProcessName,MainWindowTitle

# 5.5 界面语言验证（读真实 DOM 文本，最可靠）
& $NODE "$W\tools\verify-ui-zh.js"
```

成功的标志：
```
VERDICT: CHINESE UI CONFIRMED
文件 | 视图 | 窗口 | 新建对话 | 历史会话记录 | 自动化 | 自定义扩展 | 项目管理 | 设置
```

---

## 5. 坑位清单（现象 → 原因 → 处置）

| # | 现象 | 原因 | 处置 |
|---|---|---|---|
| 1 | `Antigravity.exe: bad option: --xxx`；无参数时退出码 0/9；无窗口无日志 | 父进程有 `ELECTRON_RUN_AS_NODE=1` | 清除该环境变量后重启 |
| 2 | Node 报 `Unexpected token '﻿'` | swap-map.json 带 UTF-8 BOM | 用 `UTF8Encoding($false)` 写；工具已兼容 |
| 3 | 构建/校验报 `position ... Received NaN` | `unpacked` 条目没有 offset | 跳过 unpacked；按 3.3 处理 |
| 4 | 安装后应用闪退/白屏 | integrity 未重算，或 asar 头布局不对 | 用 `verify` 确认 integrity VALID + self-consistent |
| 5 | 更新后界面变回英文 | 官方更新覆盖 `app.asar` | 每次更新后重跑本手册 |
| 6 | `app.asar.backup` 消失 | 更新程序会清理 | 每次重打前重新备份 |
| 7 | 下载 0 字节 | GitHub 下载域名被阻断 | 走本地代理 `-x` |
| 8 | PS 5.1 脚本语法错误指向中文字符串 | 无 BOM UTF-8 被按 GBK 解析 | 脚本纯 ASCII |
| 9 | 个别词条仍是英文（如 `No Project`） | 汉化包词库缺口 | 正常现象，不影响使用 |
| 10 | 应用起不来且日志为空 + 事件日志无崩溃 | 同 #1（Node 模式静默退出） | 先查 `ELECTRON_RUN_AS_NODE` |

---

## 6. 回滚

```powershell
[Environment]::SetEnvironmentVariable('ELECTRON_RUN_AS_NODE',$null,'Process')
Get-Process Antigravity,language_server -ErrorAction SilentlyContinue | ForEach-Object { $_.Kill() }
Start-Sleep 3
Copy-Item "$env:LOCALAPPDATA\Programs\Antigravity\resources\app.asar.backup" `
          "$env:LOCALAPPDATA\Programs\Antigravity\resources\app.asar" -Force
```
或双击包里的 `一键恢复官方英文.bat`（它读的也是 `app.asar.backup`）。
极端情况：重新下载安装 Antigravity（用户数据在 `%APPDATA%\Antigravity` 与 `%USERPROFILE%\.gemini`，不受影响）。

---

## 7. 安全审计（第三方补丁必做）

补丁替换的是主进程/preload 代码，而 Antigravity 持有 Google 账号 token 与用户代码。
打补丁前审计被替换的文件（本手册流程只引入 6 个文件，逐一审计即可）：

```powershell
foreach ($f in "<materials>\*.js") {
  foreach ($p in 'fetch\(','XMLHttpRequest','child_process','\bexec\(','spawn\(',
                 "require\('net'\)","require\('https?'\)",'sendBeacon','eval\(',
                 'new Function','process\.env','https?://') {
    $c = ([regex]::Matches((Get-Content $f -Raw), $p)).Count
    if ($c) { "{0,-24} {1} = {2}" -f (Split-Path $f -Leaf), $p, $c }
  }
}
```
2026-10 实测结果（v2.24.0 包 → 2.25.0）：
- `preload.js`：`fetch/XMLHttpRequest/child_process/exec/spawn/net/https/eval/process.env` **全部 0**；
  唯一 URL 是翻译文案里的 `https://stitch.withgoogle.com/docs`；含 4 万+中文字符（词库）。
- `main.js`：`process.env` 4 处（主进程正常用法），无网络调用。
- 结论：补丁为纯 DOM 文本翻译，无外传行为。

---

## 8. 验证清单

- [ ] `package.json` 版本 == 安装版本（未回退）
- [ ] `verify` 输出 `ALL CHECKS PASSED`
- [ ] 进程数正常（Antigravity 6–8 个 + `language_server` 1 个）
- [ ] 主窗口标题存在（非白屏）
- [ ] `verify-ui-zh.js` → `CHINESE UI CONFIRMED`
- [ ] 语言服务器日志最近 100 行：`EOF=0`、`dial tcp=0`、`not logged into=0`
- [ ] 历史会话列表仍在（用户数据未丢）

---

## 9. 已知限制

- 官方**没有**中文，设置里也没有语言开关；只能靠社区补丁。
- 每次官方更新都会覆盖 `app.asar` → **必须重打**；补丁包通常滞后官方 1–3 天。
- 汉化包非官方，存在词库缺口与（理论上的）兼容风险；本手册的"最小改动 + 完整校验"是为把风险压到最低。
- 汉化**不影响**登录/代理/账号地区等运行时问题；若登录报错，属另一类问题（见第 10 节）。

---

## 10. 附：本项目实测记录（2026-10-17 与 2026-10-24 两次）

| 项 | 2.24.0（10-17） | 2.25.0（10-24） |
|---|---|---|
| 官方 asar SHA256 | `bd10a0054ca3ad469142b2c2757566493ecc0afb934b9a61ce45d38a4d09316e` | `ad7fb1a177a11522490cba910c0970a117bec568cd9ad85233fa62873361ed05` |
| 官方 asar 大小 | 4,486,221 | 4,502,673（1087 文件）|
| 使用的汉化包 | v2.23.0（SHA256 `40872bf0…`）| v2.24.0（SHA256 `96c8bd7f…`）|
| 补丁文件是否在新版本中变化 | 全部未变（仅 package.json 不同）| 仅 `main.js` 变化 → 移植 7 处文案 |
| 构建产物大小 | 4,799,320 | 4,815,769 |
| 构建产物 SHA256 | `427e81c7c8d911db0058aba6d5642e59682b54047b319b495792251afab4de8f` | `3002af0b8131bd2db9c46008bde5634d6292ff610e328a7a10e089c1358269f7` |
| 结果 | CHINESE UI CONFIRMED | CHINESE UI CONFIRMED |

2.25.0 官方相对 2.24.0 的改动（供未来参考）：40 个文件修改 + 2 个新增，
绝大多数是 `node_modules/@connectrpc/connect*` 的依赖升级；应用自身代码只动了
`dist/main.js`（删除 macOS dock 分支）、`dist/main.test.js`、`dist/__mocks__/electron.js`、`package.json`。

### 10.1 代理链路实测（2026-10-24，v2.25.0，Clash Verge Rev @ 127.0.0.1:7897）

- **env 继承的判定方法**：`netstat -ano | findstr <language_server PID>`——若有多条到
  `127.0.0.1:7897` 的 ESTABLISHED 连接，即证明 Go 子进程继承了 HTTPS_PROXY（实测 6 条）。
  不要靠猜：主进程带 `--proxy-server` 不代表子进程环境变量正确。
- **出口地区是否受支持的判定方法**：`curl -x http://127.0.0.1:7897` 打 API 端点看错误类型——
  返回 401/403（身份类错误）= 出口地区受支持；返回 400 `User location is not supported`
  = 出口地区不受支持。实测出口为美国时 `generativelanguage` / `daily-cloudcode-pa` /
  `cloudcode-pa` / `aiplatform` 全部为身份类错误；不用代理直连则全部超时。
- **曾出现** `FAILED_PRECONDITION (code 400): User location is not supported for the API use`
  （agent executor / 会话标题生成）：代理链路本身正常时出现。**已确认根因（2026-10-24 用户实测）**：
  当时出口虽是美国，但属于云服务器商的机房 IP，被 Google 风控拒绝——地区检查不只看国家，
  还看出口 IP 的信誉（共享机房 IP 高频被拒）。处置：用户自购 VPS 搭建独享代理节点，切换后立即
  恢复（`streamGenerateContent` 连续流式成功，0 新增报错）。结论：遇该报错优先换**干净/独享的
  出口 IP**，而不是只换国家。模型生成端点为
  `https://daily-cloudcode-pa.googleapis.com/v1internal:streamGenerateContent?alt=sse`
  （日志里只记 URL 不记响应；连续出现带 ResponseID 的该行即生成正常）。
- 启动脚本已加固：启动前清 `ELECTRON_RUN_AS_NODE`；代理改为**自动探测**
  （tools\local-proxy.txt → 系统代理 → tools\detect-proxy.ps1 扫常见端口），探到才设
  `--proxy-server` 与环境变量，探不到就一个网络设置都不动（2026-11-03 起不再写死端口、
  也不再弹框告警，只在 %TEMP%\antigravity-launch.log 记一行）。

---

## 11. 目录与文件清单（本方案落地后的目录：`Antigravity-汉化`）

```
Antigravity-汉化\
├─ Antigravity-中文汉化-AI操作手册.md      ← 本文件
├─ tools\
│  ├─ antigravity-zh-patch.js              ← asar 解析/提取/构建/校验（核心工具）
│  ├─ port-main-zh.js                      ← main.js 中文串移植脚本（4 个参数传参）
│  └─ verify-ui-zh.js                      ← CDP 界面语言验证
├─ build\
│  ├─ swap-map.json                        ← 本版本 5 文件映射
│  ├─ materials-2.25\                      ← 2.25 的 5 个补丁文件成品（可复用）
│  ├─ app.asar.original-2.25.0             ← 官方原版留档（回滚用）
│  └─ app.asar.zh-2.25                     ← 构建产物
├─ packs\
│  └─ Antigravity-Chinese-Pack-v2.24.0.zip ← 汉化包原版（更新后重打用）
├─ start-antigravity-proxy.cmd             ← （旧·本机专用，已被 启动反重力.vbs 取代）写死代理端口启动
├─ 启动反重力.vbs                          ← 无黑窗启动器：探到本地代理才设代理 + 查自愈后拉起客户端
└─ 一键恢复官方英文.bat                       ← 一键回滚（读 resources\app.asar.backup）
```

> 注：`$W` 在 TL;DR 中已指向本目录，因此文中所有 `$W\tools\...`、`$W\build\...` 命令可直接运行。

---

## 12. 给下一个 AI 的检查顺序（避免重复试错）

1. `Get-Process Antigravity` → 应用是否在跑；版本 `DisplayVersion`。
2. `Test-Path app.asar.backup` → 备份在不在（更新会删）。
3. `ELECTRON_RUN_AS_NODE` 清了吗？（**先做这个**，否则一切"应用起不来"都是假象）
4. 有对应版本的汉化包吗？没有就走"最小改动 + 移植"路线。
5. 只构建、先 `verify`，**校验全绿再安装**。
6. 装完必须跑 CDP 验证，不要只看"进程起来了"。
