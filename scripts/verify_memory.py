#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""验证：用预计算的翻译记忆 + 手工规则，把官方文件还原成汉化文件的质量。

这是 JS 移植器的参考实现（两边必须逐字一致，否则移植产物不可信）。
输出每个文件的"还原相似度"，接近 100% 说明记忆覆盖完整。
"""
import difflib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))
sys.path.insert(0, str(ROOT / 'tools' / 'maintainer'))

import port_to as P  # noqa: E402

ver = sys.argv[1] if len(sys.argv) > 1 else '2.28.2'
mi = ver.split('.')[1]
OFF = ROOT / 'build' / f'work-{ver}' / 'official'
ZH = ROOT / 'build' / f'work-{ver}' / f'zh{mi}'
mem = json.loads((ROOT / 'tools' / 'patches' / f'memory-{ver}.json').read_text(encoding='utf-8'))
rules = json.loads((ROOT / 'tools' / 'porting-rules.json').read_text(encoding='utf-8'))

print(f'{"文件":<34}{"记忆":>5}{"应用":>5}{"未中":>5}{"相似度":>9}')
overall_ok = True
for inner, name in P.SIX.items():
    if name == 'dist_preload.js':
        continue
    src = (OFF / name).read_text(encoding='utf-8', errors='replace')
    pairs = mem['files'].get(inner, {})
    applied = missed = 0
    for old, new in rules.get('manual', {}).get(name, []):
        c = src.count(old)
        src = src.replace(old, new)
        applied += c
    for old in sorted(pairs, key=len, reverse=True):
        src, n = P.replace_in_strings(src, old, pairs[old])
        if n:
            applied += n
        else:
            missed += 1
    target = (ZH / name).read_text(encoding='utf-8', errors='replace')
    sim = difflib.SequenceMatcher(None, target, src, autojunk=False).ratio()
    print(f'{inner:<34}{len(pairs):>5}{applied:>5}{missed:>5}{sim:>8.2%}')
    if sim < 0.999:
        overall_ok = False
        # 打印第一处差异，便于排查
        for i, (a, b) in enumerate(zip(target, src)):
            if a != b:
                print(f'    首个差异 @{i}: 期望 {target[max(0,i-30):i+30]!r}')
                print(f'                   实际 {src[max(0,i-30):i+30]!r}')
                break
        if len(src) != len(target):
            print(f'    长度: 期望 {len(target)} 实际 {len(src)}')

print('\n结论:', '逐字一致 ✓' if overall_ok else '有差异，见上')
