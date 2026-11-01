# Antigravity（反重力）中文汉化包

> Google Antigravity（中文社区常称「反重力」）桌面客户端的简体中文汉化补丁。**不降级、可校验、一键回滚、跟随版本升级。**
>
> 关键词：反重力汉化 · Antigravity 汉化 · Antigravity 中文 · 界面汉化 · 中文补丁 · Chinese localization pack

当前支持：**官方 2.28.2**（旧版本包仍保留，见 [版本动态](#版本动态)）

## 界面预览

| 主界面 | 设置页 |
|---|---|
| ![主界面](docs/screenshots/main.png) | ![设置](docs/screenshots/settings.png) |

（截图取自 2.28.2 实机，左侧历史会话标题已模糊处理。个别官方新增文案可能仍显示英文，
遇到可在 Issues 反馈。）

## 为什么选这个包（和其他汉化包的区别）

社区流行的汉化包大多提供**整个替换版 `app.asar`**。它有个致命问题：如果你安装的 Antigravity
比汉化包新，替换后软件会被**静默降级**，轻则功能缺失，重则配置不兼容。

本包反着来：**以你自己电脑上的官方 `app.asar` 为底座，只替换 6 个界面文件，并重算 Electron
的 integrity 完整性哈希**。因此：

| | 整包替换型汉化 | 本包 |
|---|---|---|
| 版本不匹配时 | 软件被降级 ⚠️ | 永不降级 ✅ |
| 完整性校验 | 多数未重算，可能报损坏 | 逐文件重算，启动自检通过 ✅ |
| 回滚 | 要自己找官方包 | 双击 `一键恢复官方英文.bat` ✅ |
| 新版本发布 | 等作者重发整包 | `tools/port_to.py` 一条命令自动搬运 ✅ |

## 官方更新为什么会让汉化消失（重要）

Antigravity 用的是 electron-updater + **NSIS 全量安装包**更新：新版本会下载一个约
160 MB 的 `Antigravity-x64.exe`，退出时运行它，把整个安装目录覆盖一遍。
`resources\` 里的 `app.asar` 被换成新版官方文件，**你加的 `app.asar.backup` 也一并被清掉**。

这不是本包的缺陷，是所有 asar 补丁的共同命运——官方不认识你改过的文件，覆盖就是它的正常行为。
唯一能避免的办法是**永不更新客户端**，那代价太大。

所以本包把"更新后重装"这件事做成了一键操作：

```bat
一键安装汉化.bat
```

脚本会自动找到安装目录、读出已装版本、挑出对应版本的补丁、首次运行时自动备份官方 asar，
然后覆盖。整个过程不需要你记路径、不需要手动改名。

如果脚本提示「没有匹配当前版本的补丁」，说明官方比本包新，见下一节。

## 安装（1 步）

1. 完全退出 Antigravity（托盘图标也要右键退出）
2. 双击 `一键安装汉化.bat`
3. 启动 Antigravity —— 首屏水合需 30–60 秒，中文才全部出现，别太早下结论

**卸载/回滚**：双击 `一键恢复官方英文.bat`（自动识别 `app.asar.bak` / `app.asar.backup`）；
或手动把 `app.asar.backup` 改回 `app.asar`。

## 官方比本包新怎么办

不用等发版，自己 30 秒就能做出一份：

```bash
# 1. 先备份官方原版（更新会删掉它，第一次一定要做）
copy "%LOCALAPPDATA%\Programs\Antigravity\resources\app.asar" ^
     "%LOCALAPPDATA%\Programs\Antigravity\resources\app.asar.backup"

# 2. 用已安装的客户端作为底座，自动搬运译文并重打包
python tools/port_to.py --version 2.29.0
```

产物是 `build/app.asar.zh-2.29.0`，改名为 `app.asar` 放进 `resources\` 即可。
脚本会自动：抽出官方 6 个文件 → 套用译文记忆 → 补译官方新增文案 → 重算 integrity → 自检。

只在 Windows、只依赖 Python 3（不需要 Node.js）。原理见
[`Antigravity-中文汉化-AI操作手册.md`](Antigravity-中文汉化-AI操作手册.md)。

## 汉化覆盖范围

- 应用菜单 / 托盘菜单 / 安装向导 / 主进程提示，全部完成
- 界面层内置 **1283 条运行时翻译字典**（设置、自动化、插件、技能、账户等界面文案）
- 登录页、设置页、主界面、侧栏均为中文；专有名词（Antigravity、Gemini、Google）保持原样

## 仓库结构

```
tools/port_to.py                移植器：把译文搬到新版官方 asar（纯 Python）
tools/preload-engine.js         固定的翻译引擎（词典 + DOM 翻译器）
tools/porting-rules.json        人工补译规则（官方新增文案、代码拼接片段）
tools/maintainer/zh_merge.py    asar 读写 / integrity 重算 / 打包自检
tools/patches/                  换装映射、翻译字典、历次安装说明
build/work-2.26/zh26/           2.26 的 6 个换装源文件
build/work-2.28.2/              2.28.2 的官方原始件与换装成品
一键安装汉化.bat                 一键安装（自动识别版本 + 自动备份）
一键恢复官方英文.bat             一键回滚
Antigravity-中文汉化-AI操作手册.md  完整可复现流程（asar 结构、踩坑清单）
```

## 版本动态

- **2.28.2**（2026-11-01）：跟随官方 2.28.2；修复译文误改代码标识符导致启动崩溃的问题；
  补译登录页 3 条新文案；新增 `一键安装汉化.bat` 与 `tools/port_to.py`
- **2.26.0**（2026-10-25）↔ 官方 2.26.0
- **2.25.1**（2026-10-25）↔ 官方 2.25.0

官方默认自动更新，会把 `app.asar` 覆盖回英文并删掉备份——重新跑一次 `一键安装汉化.bat` 即可。

## 常见问题

**Q: 更新后界面变回英文了？**
A: 正常现象，官方全量安装覆盖了 `app.asar`。重新运行 `一键安装汉化.bat`。备份也被删了的话，
脚本会从当前这份官方 asar 重新建一个。

**Q: 替换后启动白屏 / 卡在 Loading？**
A: 说明补丁版本和客户端版本不一致。用 `app.asar.backup` 回滚，然后用
`python tools/port_to.py --version <你的版本>` 重新生成。

**Q: 会被封号吗？**
A: 汉化只改本地界面文件，不上传任何数据，不影响账号。

**Q: IDE 部分（VS Code 套壳）也汉化了吗？**
A: 桌面客户端已汉化；IDE 侧建议走官方 NLS 语言包方案（本仓库暂不含）。

## 许可

MIT（见 `LICENSE`），**仅覆盖本仓库内本项目编写的脚本与译文材料**。

本仓库不包含 Antigravity 本体及其 `app.asar`。Antigravity 及其二进制文件的版权归 Google 所有；
汉化成品（`app.asar` 形式）只在 Releases 以补丁包形式提供，请自行备份后用于个人本地界面翻译，
并支持官方正版。
