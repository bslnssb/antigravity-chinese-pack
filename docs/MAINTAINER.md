# 维护者手册

面向要改包、补译、跟版本的人。普通用户只需要看 [README](../README.md)。

---

## 1. 原理：官方更新为什么会让汉化消失

Antigravity 用的是 electron-updater + **NSIS 全量安装包**更新：新版本会下载一个约
160 MB 的 `Antigravity-x64.exe`，退出时运行它，把整个安装目录覆盖一遍。
`resources\` 里的 `app.asar` 被换成新版官方文件，**你加的 `app.asar.backup` 也一并被清掉**。

本机 `main.log` 实录的节奏：

```
[23:20:09] Starting auto update checks      ← 启动 10 秒后开始检查
[23:20:11] Update available: 2.28.2         ← 2 秒后收到新版本
[23:20:32] Update downloaded: 2.28.2        ← 21 秒下完 160 MB
[23:21:xx] 你重启客户端 → 汉化没了
```

启动后每小时再查一次。官方不认识你改过的文件，覆盖就是它的正常行为。

官方包里**没有 i18n 资源**（1085 个文件里没有任何 locale 目录），界面字符串直接写死在
`app.asar` 的 6 个 JS 文件里，所以汉化只能在 asar 层面做，也必然会被整目录覆盖冲掉。

## 2. 自愈：靠标记判断，不靠猜

`resources\.zh-pack` 记着四行：`version` / `size` / `applied` / `source`。
官方更新把整个 `resources\` 换掉，标记跟着消失；就算只换 `app.asar`，大小对不上也会被发现。

```mermaid
flowchart TD
    A[双击 反重力中文版 快捷方式] --> B[启动器读 resources/.zh-pack 标记]
    B --> C{标记版本等于当前版本?}
    C -->|是| D[直接启动 约 0.4 秒]
    C -->|否| E[判定被官方更新覆盖]
    E --> F{本地有该版本成品?}
    F -->|有| G[备份官方 asar 然后覆盖为中文]
    F -->|没有| H[从 Releases 下载对应版本]
    H --> I{有现成包?}
    I -->|有| G
    I -->|没有| J[现场移植: 新官方底座 + 旧版译文]
    J --> K{移植成功?}
    K -->|成功| G
    K -->|失败| L[提示原因 可选先用英文]
    G --> M[写入新标记 然后启动]
```

`-Check` 走快速路径（本机实测 374 ms），不匹配才进 `-Heal`。

**自愈失败一律放行启动**——最差就是这次先看英文，绝不会因为补丁问题让应用打不开。
失败原因写进 `%TEMP%\antigravity-launch.log`，退出码分档：

| 退出码 | 含义 |
|---|---|
| 10 | 找不到安装目录 |
| 20 | 该版本无包且移植失败 |
| 21 | 下载失败 |
| 30 | 无写权限（装在 `C:\Program Files` 且非管理员） |
| 31 | 文件被占用（客户端没退干净） |

## 3. 现场移植

官方更新到 N+1、本仓库的 N+1 包还没发布时，用**新版本官方 asar 做底座，把旧版本的译文搬过去**。

- **不拿旧版汉化 asar 直接覆盖**：那会把应用代码一起降级，轻则缺功能、重则白屏。
  移植只搬「英文→中文」的字符串替换对，代码全部来自新版官方
- **不要求用户装 Python / Node**：借 Antigravity 自带的 Electron 当运行时
  （`ELECTRON_RUN_AS_NODE=1`，本机实测 v24.21.0），几百行 JS 就够
- **译文来源**：包内 `tools/patches/memory-*.json`，是「旧版官方原文 → 旧版中文」的替换对。
  本仓库用 2.28.2 的记忆做产物，与手工维护的成品**逐字节等价**
  （唯一差异是 CRLF/LF 归一化后为 0）
- **只替换字符串字面量**，并做单词边界检查——否则 `isExiting` 会被换成一个语法合法、
  运行时才报 `ReferenceError` 的标识符。打包前还会断言代码区不含中文
- **整个过程 2–4 秒**，产物重算 Electron integrity，装完自检"只有 6 个文件变了"

移植失败会自动回滚到官方英文版，并写 `%LOCALAPPDATA%\Antigravity\zh-port-skip`
记下"这个版本别再自动移植"，避免陷入"每次双击都等几秒然后失败"的死循环。删掉该文件可重试。

## 4. 覆盖率的保证方式

这套翻译最容易出的问题不是「漏翻」，而是**翻了半截**：`Built-in Browser Settings`
变成 `Built-in 浏览器设置`，`Legal Help` 变成 `Legal 帮助`。英语短词是长词的前缀，
替换时一旦不看词边界就会啃掉别人。

改完必跑的四道检查：

```
node   scripts/scan_ui.js              连运行中客户端的 CDP，列出未翻译 / 半中半英
node   scripts/test_engine.js          引擎回归（41 个用例，钉死这类事故）
python scripts/merge_dict.py           把 tools/patches/ui-extra.json 合并进引擎
python scripts/rebuild_preload.py      只替换 asar 里的 preload，秒级重打包
node   scripts/shot_settings.js        截设置面板若干页到 build/shots/，供 README 用
```

> 截图脚本截图后要手工糊掉左下角账号区（含邮箱），别把个人信息带进仓库。

补词只改 `tools/patches/ui-extra.json`，不动引擎源码：

- `exact` —— 整串完全相等才替换。**单词一律放这里**，它绝不进句子中间
- `phrase` —— 句内局部替换，带词边界。只放多词短语

引擎的两条铁律：

1. 每个词条编译成带边界的正则（首尾是字母数字时要求前后不是字母数字），
   所以 `Close` 不会命中 `Closed`
2. 纯单词词条不参与句内替换，只做整串匹配，所以 `Browser`（译作「浏览器设置」）
   不会把 `Built-in Browser Settings` 啃成 `Built-in 浏览器设置`

**第三类坑：DOM 被拆成多个文本节点。** 像
`Also includes <a>global permissions</a> when working in these conversations.`
这种句子，整句词典永远对不上，但**不能**拆成短语塞进 `phrase` 表——
短语替换跑在前面，会把 `Also includes global settings when working` 那种完整句
提前啃成「此外还包含 global settings …」。只能在引擎 1.4 区按「整节点恰好相等」锚定。

扫描脚本读 `%APPDATA%\Antigravity\DevToolsActivePort` 拿实时端口，端口每次启动都变。
写自动化时注意：启动客户端和扫描必须在**同一条命令**内跑完，否则进程会被清理，
表现为 `ECONNREFUSED`（不是包的问题）。

## 5. 自己给新版本做包

先看 Releases 有没有对应版本（首选，双击即装）。没有的话，30 秒能做出一份——
需要完整仓库和 Python 3：

```bash
git clone <本仓库> && cd antigravity-chinese-pack

# 1. 先备份官方原版（更新会删掉它，第一次一定要做）
copy "%LOCALAPPDATA%\Programs\Antigravity\resources\app.asar" ^
     "%LOCALAPPDATA%\Programs\Antigravity\resources\app.asar.backup"

# 2. 用已安装的客户端作为底座，自动搬运译文并重打包
python tools/port_to.py --version 2.29.0
```

产物是 `build/app.asar.zh-2.29.0`，改名为 `app.asar` 放进 `resources\` 即可。
脚本会自动：抽官方 6 个文件 → 套译文记忆 → 补译新增文案 → 重算 integrity → 自检。

发版：

```bash
python scripts/package_dist.py --version 2.29.0   # → packs/Antigravity-Chinese-Pack-v2.29.0.zip
python scripts/upload_release.py --version 2.29.0 # 删同名旧资产并上传
```

## 6. 仓库结构

```
tools/preload-engine.js         固定的翻译引擎（词典 + DOM 翻译器）
tools/patches/ui-extra.json     补词表（exact / phrase 两个分区）
tools/patches/memory-*.json     「旧版官方原文 → 中文」替换对，移植用的素材
tools/porting-rules.json        人工补译规则（官方新增文案、代码拼接片段）
tools/port/port.js              现场移植器：新版官方底座 + 旧版译文
tools/port_to.py                移植器（纯 Python 版，本地开发用）
tools/selfheal.ps1              自愈：比对 .zh-pack 标记后自动补回
tools/maintainer/zh_merge.py    asar 读写 / integrity 重算 / 打包自检
tools/auto-update-toggle.ps1    官方 autoCheckForUpdates 开关
tools/find-install-dir.ps1      自定义安装目录兜底（注册表 UninstallString 反推）
tools/make-shortcut.ps1         生成桌面「反重力（中文版）」快捷方式
tools/redact_screenshots.py     README 截图打码
scripts/                        维护链（扫描 / 回归 / 合并 / 重打包 / 发版）
build/work-*/                   各版本的官方原始件与换装成品
一键安装汉化.bat                 安装（识别版本 + 备份 + 建快捷方式）
启动反重力.vbs                   无黑窗启动器：设代理环境变量、查自愈状态后拉起客户端
关闭自动更新.bat / 恢复自动更新.bat
一键恢复官方英文.bat             回滚
```

## 7. 和其他汉化包的区别

社区流行的汉化包大多提供**整个替换版 `app.asar`**。它有个致命问题：如果你安装的
Antigravity 比汉化包新，替换后软件会被**静默降级**，轻则功能缺失，重则配置不兼容。

本包反着来：**以本机官方 `app.asar` 为底座，只替换 6 个界面文件，并重算 Electron
的 integrity 完整性哈希**。

| | 整包替换型汉化 | 本包 |
|---|---|---|
| 版本不匹配时 | 软件被降级 ⚠️ | 拒绝安装并提示，永不降级 ✅ |
| 完整性校验 | 多数未重算，可能报损坏 | 逐文件重算，启动自检通过 ✅ |
| 回滚 | 要自己找官方包 | 双击 `一键恢复官方英文.bat` ✅ |
| 官方更新后 | 一样被冲掉，只能手动重装 | 一样被冲掉，但下次启动**自动补回** ✅ |
| 新版本发布 | 等作者重发整包 | 有新版包就双击装；没有就现场移植 ✅ |

## 8. 手工排查

确认补丁是否在位：

```bat
findstr /m /c:"__agyTranslateText" "%LOCALAPPDATA%\Programs\Antigravity\resources\app.asar"
```

- 打印出 `...\app.asar` → 汉化版在位
- 什么都不打印 → 还是官方英文版

看自愈状态：

```powershell
powershell -ExecutionPolicy Bypass -File tools\selfheal.ps1 -Check
```

输出 `官方已更新到 x.y.z，需要重新打中文补丁` 说明标记已不匹配，
把 `-Check` 换成 `-Heal` 立刻补好。

文件大小对照：官方 2.28.2 约 4.6 MB，汉化版约 4.9 MB（多出来的是翻译引擎）。
