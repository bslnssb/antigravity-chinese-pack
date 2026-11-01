# Antigravity 中文汉化包

> Google Antigravity 桌面客户端的简体中文汉化。**不降级、可校验、一键回滚、跟随版本升级。**

当前支持：**v2.26.0**（v2.25.1 保留兼容，见 [版本动态](#版本动态)）

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
| 新版本发布 | 等作者重发整包 | 翻译记忆自动搬运（见下）✅ |

## 安装（3 步，1 分钟）

1. 确认 Antigravity 版本为 **2.26.0**（设置 → 关于）；若你还是 **2.25**，请改用 v2.25.1 包
2. 完全退出 Antigravity（托盘图标也右键退出），把 `app.asar.zh-2.26.0` 复制到安装目录的 `resources\` 下，
   **先把官方 `app.asar` 重命名为 `app.asar.bak`**（这就是你的回滚保险），再把汉化文件改名为 `app.asar`
   - 安装目录一般在 `%LOCALAPPDATA%\Programs\Antigravity\resources\`
3. 启动 Antigravity，界面即中文
   - 首屏水合需 30–60 秒，稍等片刻中文才全部出现

**卸载/回滚**：双击包内 `一键恢复官方英文.bat`（自动识别 `app.asar.bak` / `app.asar.backup`）；
或手动把 `app.asar.bak` 改回 `app.asar`。

## 汉化覆盖范围

- 应用菜单 / 托盘菜单 / 安装向导 / 主进程提示，全部完成
- 界面层内置 **842 条运行时翻译字典**（设置、自动化、插件、技能、账户等界面文案）
- 翻译质量：无机器翻译痕迹，术语统一

## 版本升级时怎么办（本包独有）

Antigravity 出了新版不想等？`tools/maintainer/` 里是一套**纯 Python 维护器**，把现有翻译
自动搬运到新版文件（翻译记忆 + 精确匹配），再以新版为底座重打包并重算 integrity 哈希——
不需要 Node.js。用法见 `tools/maintainer/README.md`。

## 仓库结构

```
tools/antigravity-zh-patch.js   asar 解析 / 提取 / 构建 / 校验（Node 版）
tools/maintainer/zh_merge.py    同上的纯 Python 实现（构建、翻译记忆搬运、自检）
tools/patches/                  换装映射、842 条翻译字典、安装说明
build/materials-2.25/           2.25 的 5 个换装源文件（当时还没纳入 ipcHandlers.js）
build/work-2.26/zh26/           2.26 的 6 个换装源文件
一键恢复官方英文.bat              Windows 一键回滚（认 app.asar.bak / app.asar.backup）
Antigravity-中文汉化-AI操作手册.md  面向 AI 代理/高级用户的完整可复现流程（含 asar 结构、踩坑清单）
```

## 版本动态

- **本包 v2.26.0（2026-10-25）** ↔ 官方 Antigravity 2.26.0（2026-10-22）：当前推荐版本
- **本包 v2.25.1（2026-10-25）** ↔ 官方 Antigravity 2.25.0：仍可用，等你升级 2.26 后可换新包
- 官方默认自动更新，会把 `app.asar` 覆盖回英文（并删掉你的 `app.asar.bak`）。
  若本包还没跟上你被更新到的版本，可先关闭自动更新，避免界面回英文。
- 本包更新发布在 Releases，更新日志见 `RELEASE-NOTES.md`。

## 常见问题

**Q: 替换后启动白屏/报损坏？**
A: 说明版本不匹配或哈希没对上。用 `app.asar.bak` 回滚，然后用维护器的 `verify`/
`packselftest` 重新核对。本包构建时已通过逐文件哈希自检。

**Q: 会被封号吗？**
A: 汉化只改本地界面文件，不上传任何数据，不影响账号。

**Q: IDE 部分（VS Code 套壳）也汉化了吗？**
A: 桌面客户端已汉化；IDE 侧建议走官方 NLS 语言包方案（本仓库暂不含）。

## 许可

MIT（见 `LICENSE`），**仅覆盖本仓库内本项目编写的脚本与译文材料**。

本仓库不包含 Antigravity 本体及其 `app.asar`。Antigravity 及其二进制文件的版权归 Google 所有；
汉化成品（`app.asar` 形式）只在 Releases 以补丁包形式提供，请自行备份后用于个人本地界面翻译，
并支持官方正版。
