# -*- coding: utf-8 -*-
"""校验 zh-2.26 产物：preload 字典规模、新 API、main.js 中文串、IPC 通道完整性"""
import json
import re
import sys

sys.stdout.reconfigure(encoding='utf-8')
CHK = 'build/work-2.26/chk'
N26 = 'build/work-2.26/n26'

t = open(f'{CHK}/dist_preload.js', encoding='utf-8').read()
pairs = re.findall(r'\["((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)"\]', t)
cjk = [p for p in pairs if re.search(r'[\u4e00-\u9fff]', p[1])]
print('preload dict-like pairs: %d (with Chinese: %d)' % (len(pairs), len(cjk)))
print('new API present:', 'executeJavaScriptInIsolatedWorld' in t)

new = open(f'{N26}/dist_preload.js', encoding='utf-8').read()
channels = set(re.findall(r"invoke\('([a-zA-Z:-]+)'", new))
missing = [c for c in sorted(channels) if c not in t]
print('2.26 preload IPC channels: %d | missing in zh26: %s' % (len(channels), missing or 'NONE'))

m = open(f'{CHK}/dist_main.js', encoding='utf-8').read()
for s in ['没有正在运行的智能体', '确认退出', '您确定要退出吗？', '打开 ']:
    print('main.js has', repr(s), ':', s in m)

# 2.26 新增英文扫描：main/menu 里引号内的英文短句（候选 UI 文案）
for name in ('dist_main.js', 'dist_menu.js'):
    txt = open(f'{CHK}/{name}', encoding='utf-8').read()
    strs = set(re.findall(r"['\"]([A-Z][a-zA-Z ,''\.\?!&/-]{3,60})['\"]", txt))
    # 排除明显的代码标识符/路径
    junk = re.compile(r"[./\\]|require|http|electron|ipc|undefined|true|false", re.I)
    cand = sorted(s for s in strs if not junk.search(s))
    print(f'--- {name} remaining English candidates ({len(cand)}):')
    for c in cand[:20]:
        print('   ', c)
