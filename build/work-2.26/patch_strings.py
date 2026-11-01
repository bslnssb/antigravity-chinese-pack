# -*- coding: utf-8 -*-
"""2.26 移植补充：main.js + ipcHandlers.js 的用户可见英文 → 中文（历史缺口一并补）"""
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding='utf-8')
W = Path('build/work-2.26')


def patch(fname, pairs):
    p = W / 'zh26' / fname
    t = p.read_text(encoding='utf-8')
    for old, new, expect in pairs:
        n = t.count(old)
        assert n == expect, f'{fname}: {old!r} count={n}, expect={expect}'
        t = t.replace(old, new)
    p.write_text(t, encoding='utf-8')
    print(f'{fname}: {len(pairs)} replacements OK')


# main.js —— 全部是 2.25.1 也存在的历史缺口（WSL/启动对话框与 dock 菜单）
patch('dist_main.js', [
    ("showErrorBox('Binary not found', msg)", "showErrorBox('未找到可执行文件', msg)", 1),
    ("label: 'New Window',", "label: '新建窗口',", 1),
    ("console.error('Startup failed:', msg)", "console.error('启动失败:', msg)", 1),
    ("showErrorBox('Startup failed', msg)", "showErrorBox('启动失败', msg)", 1),
    ("title: 'WSL distro not found'", "title: '未找到 WSL 发行版'", 1),
    ('message: `The WSL distro "${WSL_DISTRO}" is no longer installed.`',
     'message: `WSL 发行版 "${WSL_DISTRO}" 已不再安装。`', 1),
    ("detail: 'Antigravity opened on Windows instead.'",
     "detail: 'Antigravity 已改为直接在 Windows 上打开。'", 1),
    ("showErrorBox('WSL setup failed', msg)", "showErrorBox('WSL 设置失败', msg)", 1),
])

# ipcHandlers.js —— 以 2.26 官方文件为底，翻译 4 条可见文案后成为新的换装源
src = (W / 'n26' / 'dist_ipcHandlers.js').read_text(encoding='utf-8')
pairs = [
    ("showErrorBox('Cannot open folder', t.error)", "showErrorBox('无法打开文件夹', t.error)", 1),
    ("message: 'Folder is on the Windows filesystem'", "message: '文件夹位于 Windows 文件系统上'", 1),
    ("title: 'Open workspace'", "title: '打开工作区'", 1),
    ("title: 'Open workspaces'", "title: '打开工作区'", 1),
]
t = src
for old, new, expect in pairs:
    n = t.count(old)
    assert n == expect, f'ipcHandlers: {old!r} count={n}, expect={expect}'
    t = t.replace(old, new)
(W / 'zh26' / 'dist_ipcHandlers.js').write_text(t, encoding='utf-8')
print('dist_ipcHandlers.js created with 4 translations')
