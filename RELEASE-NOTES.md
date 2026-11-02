# 更新日志

## v2.28.2 修订（2026-11-02）：翻译覆盖面修复

三处真实缺陷，全部有回归用例钉死：

- **短词啃长词**：词条替换是裸 `replaceAll`，没有词边界，`Close→关闭` 把
  `Reopen Closed Tab` 翻成 `Reopen 关闭d Tab`。同类还有 `Open→Opened`、
  `Copy→Copyright`、`Edit→Editor`、`Install→Installation`。
  现在每条编译成带边界的正则（首尾为字母数字时要求前后非字母数字）
- **单字词条参与句内替换**：`Browser` 译作「浏览器设置」，于是
  `Built-in Browser Settings` 被啃成 `Built-in 浏览器设置`；`Legal Help`→`Legal 帮助`、
  `Open File Search`→`打开 File 搜索` 同理。现在纯单词词条**只做整串相等匹配**，
  永不进入句子中间
- **设置面板缺 127 条文案**：补齐 `权限预设`、`计划审核策略`、`执行`、`内置/外部浏览器设置`、
  `意见反馈`、`反馈类型`、`问题报告`、`账号与计费`、`显示选项`、`置顶会话`、`快捷键导航` 等；
  带变量的无障碍标签（`Shortcut Ctrl+K for …`、`Select project, current: …`、
  `Rules: 4,515 tokens`）改为模板处理，插值部分递归翻译

配套新增维护链（改完必跑）：

| 脚本 | 作用 |
|---|---|
| `scripts/scan_ui.js` | 连运行中客户端的 CDP，把 DOM 可见文本按「未翻译 / 半中半英」分类 |
| `scripts/test_engine.js` | 引擎离线回归，31 个用例 |
| `scripts/merge_dict.py` | 把 `tools/patches/ui-extra.json` 合并进引擎（幂等，带冲突检查） |
| `scripts/rebuild_preload.py` | 只替换 asar 里的 `preload.js`，秒级重打包 |

补词只改 `tools/patches/ui-extra.json`：`exact` 放单词（整串匹配），`phrase` 放多词短语（带边界句内替换）。

## v2.28.2（2026-11-01）

### 补丁包内容

`Antigravity-Chinese-Pack-v2.28.2.zip` 解压后：

| 文件 | 作用 |
|---|---|
| `app.asar.zh-2.28.2` | 汉化成品（6 个界面文件 + 翻译引擎，其余 726 个文件与官方逐字节一致） |
| `一键安装汉化.bat` | 自动定位安装目录、读版本、挑补丁、首次自动备份、覆盖、自检、建桌面快捷方式 |
| `启动反重力.vbs` | 无黑窗启动器：设置代理环境变量、检查自愈状态后拉起客户端（快捷方式的后端） |
| `一键恢复官方英文.bat` | 回滚到官方英文（自动识别 `app.asar.backup` / `.bak`） |
| `关闭自动更新.bat` | 关掉官方自动更新，中文不再被覆盖（可撤销） |
| `恢复自动更新.bat` | 恢复官方默认的自动更新行为 |
| `安装说明.txt` | 三步安装 + 更新后自动恢复 + 常见故障排查 |


- **新增自愈：官方更新后再也不用手动重装**。`tools/selfheal.ps1` 用 `resources\.zh-pack`
  标记（记录版本号 + asar 大小）判断补丁是否还在：官方更新把 `resources\` 整个换掉，
  标记跟着消失，下次启动就知道要补。取包顺序为本地成品 → 包内 `packs\*.zip` → 本地缓存
  → GitHub Releases 直连下载（不走 API，无限流）。启动器在拉起客户端前调用它，
  已就绪时只花约 0.4 秒、不碰任何文件；需要补时在启动前完成，用户只多等几秒
- **新增现场移植：官方跑在前面时也不掉回英文**。对应版本的包还没发布时，
  `tools/port/port.js` 以**新版本官方 asar 为底座**，把手里旧版本的译文搬过去
  （只搬字符串替换对，代码全部来自新版官方，不做整包降级）。运行时借 Antigravity
  自带的 Electron（`ELECTRON_RUN_AS_NODE=1`，实测 v24.21.0），用户不需要装 Python/Node。
  译文素材是 `tools/patches/memory-<ver>.json`（由 `scripts/build_memory_json.py`
  离线预计算），本仓库用 2.28.2 记忆做出的产物与手工成品**逐字节等价**（6 个文件全一致）
- **移植安全三道闸**：替换只发生在字符串字面量内部 + 单词边界检查（防 `isExiting`
  被换成 `is退出ting` 这类运行期才炸的污染）、打包后断言代码区无中文、
  产物重算 integrity 并自检"只有 6 个文件变了且无文件缺失"
- **移植版起不来会自动回滚**：启动后 5 秒没活下来就用备份恢复官方英文版，并在
  `%LOCALAPPDATA%\Antigravity\zh-port-skip` 记下这个版本别再自动移植——否则用户会陷进
  "每次双击都等几秒然后失败"的循环。删掉该文件即可重试
- **自愈失败一律放行启动**：补丁出任何问题都不阻止客户端起来，最差是这次先看英文，
  并在启动日志里留下可用退出码（10 找不到目录 / 20 该版本无包且移植失败 /
  21 下载失败 / 30 无写权限 / 31 被占用）
- 跟进 Antigravity 2.28.2：以官方原版 asar 为底座，只换 6 个界面文件，732 个文件原样保留
- **新增桌面快捷方式**：安装成功后自动在桌面创建「反重力（中文版）」，图标就是 Antigravity
  本体。它经 `启动反重力.vbs` 拉起客户端——设置 `HTTPS_PROXY` 等环境变量（界面进程认
  `--proxy-server`，但登录换 token 的语言服务器只认环境变量）且不弹 cmd 黑窗
- **修复一个会导致启动崩溃的问题**：旧移植脚本会把 `isExiting` 这类代码标识符里的 `Exit`
  一并换成中文，得到 `is退出ting`。中文是合法标识符字符，`node --check` 拦不住，运行时才
  报 `ReferenceError`。现在替换只发生在字符串字面量内部，并在打包前断言"代码区不允许出现中文"
- 登录页补译 3 条 2.28 新增文案：「欢迎使用 Antigravity」「使用 Google 账号继续」「登录遇到问题？」
- 翻译字典 842 → **1283 条**（并入渲染层完整词库）
- **新增 `一键安装汉化.bat`**：自动定位安装目录、读取已装版本、挑选对应补丁、首次运行自动备份。
  定位顺序为 `%LOCALAPPDATA%\Programs\Antigravity` → `%PROGRAMFILES%` → `%PROGRAMFILES(X86)%`，
  三处都没有时再查注册表 Uninstall 项反推——**改过安装目录（如装到 `D:\Apps\Antigravity`）也能识别**。
  补丁文件夹本身放在哪都行，不必与客户端同目录
- **新增 `tools/port_to.py`**：官方出新版后一条命令即可自助移植，不需要 Node.js
- **新增 `关闭自动更新.bat` / `恢复自动更新.bat`**：逆清官方更新链路后找到官方自带的
  `autoCheckForUpdates` 开关（存 `%APPDATA%\Antigravity\app_storage.json`），置 false 后
  主进程走 `stopAutoUpdateChecks()`，一个更新请求都不再发出。这是让中文长期存活的唯一干净办法——
  官方更新是 NSIS 全量包，覆盖 `resources\` 时会连 `app.asar.backup` 一起删掉
- 修正构建产物的换行符写入（旧产物会写成 `\r\r\n`）
- 实机验证：设置页 / 主界面 / 登录页均中文，逐文件 integrity 自检 732 相同 / 6 换装 / 0 不自洽

## v2.26.0（2026-10-25）

- 跟进 Antigravity 2.26.0（官方 2026-10-22 发布）：菜单 / 托盘 / 主进程 / 安装向导全部移植
- 换装范围由 5 个文件扩到 **6 个**：新增 `dist/ipcHandlers.js`（4 条可见英文，历史缺口）
- `dist/main.js` 补译 8 处历史缺口（WSL / 启动失败对话框、dock 菜单）
- 同步官方新增的 `executeJavaScriptInIsolatedWorld` 桥接 API，桥接层功能不缺失
- 翻译字典与 v2.25.1 一致（842 条）：2.26 渲染层资源官方未变，无需扩词
- 逐文件重算 integrity，`packselftest` 通过；CDP 实测界面为中文

## v2.25.1（2026-10-25）

- 界面翻译字典 807 → **842 条**：补齐 Delete / Cancel / Settings / Sign in 等常用按钮与
  状态词（此前以英文显示的 35 个界面词全部收录）
- 安装向导窗口标题汉化（"Welcome to Antigravity" → "欢迎使用 Antigravity"）
- 重打包全部文件通过 Electron integrity 逐文件哈希自检
- 新增纯 Python 维护器（翻译记忆搬运 + asar 重打包），新版发布后可自助跟进

## v2.25.0（2026-10-24）

- 跟进 Antigravity 2.25.0：菜单 / 托盘 / 安装向导 / 主进程全面汉化
- 建立运行时翻译字典（807 条）

## v2.24.0（2026-10-21）

- 首个版本：基于 2.24.0 的界面汉化
