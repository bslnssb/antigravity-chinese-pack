# 更新日志

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
