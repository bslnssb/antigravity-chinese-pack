#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""为"现场移植"预计算翻译记忆，输出 tools/patches/memory-<ver>.json。

为什么要预计算：移植器要在用户机器上跑，那里没有 Python，只有 Antigravity
自带的 Electron（可当 node 用）。Python 的 difflib.SequenceMatcher（Obershelp）
在 JS 里没有等价物，自己实现既慢又容易出错——而这一步的结果对同一对版本是
固定的，完全可以离线算好、打包进发布包。运行期只剩：读 asar → 套记忆 → 打包。

产物结构：
{
  "refVersion": "2.28.2",
  "files": { "dist/main.js": {"英文原文": "中文译文", ...}, ... },
  "engine": "<preload-engine.js 全文>"   # 单独文件更好，这里不嵌
}
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools' / 'maintainer'))
import zh_merge as Z  # noqa: E402

SIX = {
    'dist/preload.js': 'dist_preload.js',
    'dist/main.js': 'dist_main.js',
    'dist/menu.js': 'dist_menu.js',
    'dist/tray.js': 'dist_tray.js',
    'dist/ideInstall/wizardHtml.js': 'dist_ideInstall_wizardHtml.js',
    'dist/ipcHandlers.js': 'dist_ipcHandlers.js',
}

ver = sys.argv[1] if len(sys.argv) > 1 else '2.28.2'
mi = ver.split('.')[1]
off = ROOT / 'build' / f'work-{ver}' / 'official'
zh = ROOT / 'build' / f'work-{ver}' / f'zh{mi}'

out = {'refVersion': ver, 'files': {}}
total = 0
for inner, name in SIX.items():
    if name == 'dist_preload.js':
        continue  # preload 走"官方原文双行化 + 引擎"，不需要记忆
    o, z = off / name, zh / name
    if not o.is_file() or not z.is_file():
        print(f'  跳过（缺文件）: {inner}')
        continue
    mem = Z.build_memory(str(o), str(z))
    # 只保留"英文→含中文"的干净对，且长度合理（apply 侧还要再过一遍字符串区间检查）
    clean = {k: v for k, v in mem.items()
             if len(k) >= 3 and '\n' not in k and len(k) <= 600}
    out['files'][inner] = clean
    total += len(clean)
    print(f'  {inner:<34} {len(clean):>3} 条')

dest = ROOT / 'tools' / 'patches' / f'memory-{ver}.json'
dest.write_text(json.dumps(out, ensure_ascii=False, indent=0), encoding='utf-8')
print(f'\n合计 {total} 条 → {dest.relative_to(ROOT)}  ({dest.stat().st_size} 字节)')
