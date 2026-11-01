# -*- coding: utf-8 -*-
"""扫描 2.25.0 -> 2.26.0 的全量文件差异，并从变更的渲染层文件中提取新增英文文案"""
import os
import re
import sys

sys.path.insert(0, 'tools/maintainer')
sys.stdout.reconfigure(encoding='utf-8')
import zh_merge as Z

ORIG = 'build/app.asar.original-2.25.0'
NEW = os.path.join(os.environ.get('LOCALAPPDATA', ''), 'Programs', 'Antigravity', 'resources', 'app.asar')

ha, da, ra = Z.asar_read(ORIG)
hb, db, rb = Z.asar_read(NEW)
la = dict(Z.asar_leaves(ha))
lb = dict(Z.asar_leaves(hb))

changed, added, removed = [], [], []
for path, node in lb.items():
    if path not in la:
        added.append(path)
        continue
    ca = ra[da + int(la[path]['offset']): da + int(la[path]['offset']) + la[path]['size']]
    cb = rb[db + int(node['offset']): db + int(node['offset']) + node['size']]
    if len(ca) != len(cb) or ca != cb:
        changed.append(path)
for path in la:
    if path not in lb:
        removed.append(path)

print('changed: %d | added: %d | removed: %d' % (len(changed), len(added), len(removed)))
print('--- changed files:')
for p in changed:
    print('  ', p)
print('--- added files:')
for p in added:
    print('  ', p)
