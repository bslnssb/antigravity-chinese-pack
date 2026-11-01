#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""zh_merge.py — Antigravity 汉化维护器原型（纯 Python，无需 node）

思路（对应 outputs/B3-汉化对标报告.md）：
  1. memory  从「旧版原文件 + 旧版汉化文件」提取翻译记忆（en→zh 替换对）
  2. apply   把记忆逐条精确匹配应用到新版同名文件，产出新版汉化文件
  3. 配合既有的 antigravity-zh-patch.js（build --swap）完成 asar 重打包
     —— 本工具只负责"词条级搬运"，不碰 asar 打包

命令：
  extract <asar> <inner-path> [out]      从 asar 提取文件（只读）
  memory  <old-base> <old-zh> <out.json> 从一对新旧文件构建翻译记忆
  apply   <new-file> <memory.json> <out> 应用记忆；输出 applied/missed 统计
  selftest <old-base-asar> <materials-dir> 对 2.25 真实数据自校验：
           原文件 --memory--> 应产出与现有汉化文件一致的文本

限制（诚实声明）：
  - preload 318KB 与原始 5.4KB 非派生关系，memory 阶段直接拒绝（体积比>3 报错）
  - 精确匹配 = 上下文相同时才能搬；语境变化的词条进 missed 报告由人工核对
  - 版本间"新增英文"永远 missed，那是下一版翻译工作量的下限
"""
import difflib
import hashlib
import json
import struct
import sys
from pathlib import Path

MAX_STR = 600          # 单个替换对的最大长度
RATIO_GUARD = 3.0      # 新旧体积比护栏（防"非派生文件"）
BLOCK = 4194304        # Electron integrity 分块大小

def asar_read(asar_path):
    p = Path(asar_path)
    raw = p.read_bytes()
    u0, header_size, _, json_len = struct.unpack('<IIII', raw[:16])
    header = json.loads(raw[16:16 + json_len])
    data_start = 8 + header_size
    return header, data_start, raw

def asar_leaves(node, prefix=''):
    """按插入顺序产出 (inner_path, 节点)"""
    if 'files' in node:
        for k, v in node['files'].items():
            yield from asar_leaves(v, prefix + '/' + k)
    elif 'offset' in node:
        yield prefix.lstrip('/'), node

def integrity(data: bytes):
    blocks = [hashlib.sha256(data[i:i + BLOCK]).hexdigest()
              for i in range(0, len(data), BLOCK)]
    return {"algorithm": "SHA256", "hash": hashlib.sha256(data).hexdigest(),
            "blockSize": BLOCK, "blocks": blocks}

def asar_build(base_asar, out_asar, swap_map):
    """以 base 为底，把 swap_map={inner_path: 本地文件} 的文件替换后重打包。
    布局实测（见 format_probe.py）：@0=4 @4=headerSize @8=headerSize-4 @12=jsonLen，
    jsonLen+9=headerSize（1 字节零填充），dataStart=8+headerSize。"""
    header, data_start, raw = asar_read(base_asar)
    swap = {k: Path(v).read_bytes() for k, v in swap_map.items()}
    parts, pos = [], 0
    n_swapped = 0
    for path, node in asar_leaves(header):
        if path in swap:
            content = swap[path]
            n_swapped += 1
        else:
            content = raw[data_start + int(node['offset']):
                          data_start + int(node['offset']) + node['size']]
        node['offset'] = str(pos)
        node['size'] = len(content)
        node['integrity'] = integrity(content)
        parts.append(content)
        pos += len(content)
    payload = b''.join(parts)
    jbytes = json.dumps(header, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
    json_len = len(jbytes)
    header_size = json_len + 9
    Path(out_asar).write_bytes(
        struct.pack('<IIII', 4, header_size, header_size - 4, json_len)
        + jbytes + b'\x00' + payload)
    return n_swapped, len(payload)

def asar_compare(file_a, file_b):
    """逐文件对比两个 asar 的内容哈希 + 校验 b 的 integrity 是否自洽"""
    ha, da, ra = asar_read(file_a)
    hb, db, rb = asar_read(file_b)
    la = dict(asar_leaves(ha))
    lb = dict(asar_leaves(hb))
    same = diff = bad_int = 0
    diffs = []
    for path, node in lb.items():
        c = rb[db + int(node['offset']): db + int(node['offset']) + node['size']]
        h = hashlib.sha256(c).hexdigest()
        if node['integrity']['hash'] != h:
            bad_int += 1
        if path in la:
            ca = ra[da + int(la[path]['offset']): da + int(la[path]['offset']) + la[path]['size']]
            if hashlib.sha256(ca).hexdigest() == h:
                same += 1
            else:
                diff += 1
                diffs.append(path)
        else:
            diff += 1
            diffs.append(path + ' (仅B有)')
    only_a = [p for p in la if p not in lb]
    return same, diff, bad_int, diffs[:10], only_a[:10]

def asar_extract(asar_path, inner, out=None):
    header, data_start, raw = asar_read(asar_path)
    node = header
    for part in inner.split('/'):
        node = node['files'][part]
    chunk = raw[data_start + int(node['offset']): data_start + int(node['offset']) + node['size']]
    text = chunk.decode('utf-8', errors='replace')
    if out:
        Path(out).write_text(text, encoding='utf-8')
    return text

def build_memory(old_base, old_zh):
    a = Path(old_base).read_text(encoding='utf-8', errors='replace')
    b = Path(old_zh).read_text(encoding='utf-8', errors='replace')
    if not a or len(b) / max(len(a), 1) > RATIO_GUARD:
        raise SystemExit(f'拒绝：体积比异常（{len(a)} vs {len(b)}），疑似非派生文件，不可自动合并')
    pairs, seen = {}, set()
    sm = difflib.SequenceMatcher(None, a, b, autojunk=False)
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag != 'replace' or i2 - i1 > MAX_STR:
            continue
        old, new = a[i1:i2], b[j1:j2]
        if old == new or not old.strip():
            continue
        if any('\u4e00' <= c <= '\u9fff' for c in old) or not any('\u4e00' <= c <= '\u9fff' for c in new):
            continue  # 只要 "英文→含中文" 的干净替换
        if old in seen:
            continue
        if old in pairs and pairs[old] != new:
            continue  # 同 old 不同译法，跳过让人工裁决
        pairs[old] = new
        seen.add(old)
    return pairs

def apply_memory(new_file, memory, out):
    t = Path(new_file).read_text(encoding='utf-8', errors='replace')
    pairs = json.loads(Path(memory).read_text(encoding='utf-8'))
    applied = missed = 0
    for old in sorted(pairs, key=len, reverse=True):
        if old in t:
            t = t.replace(old, pairs[old])
            applied += 1
        else:
            missed += 1
    Path(out).write_text(t, encoding='utf-8')
    return applied, missed

def main():
    cmd = sys.argv[1]
    if cmd == 'extract':
        print(asar_extract(sys.argv[2], sys.argv[3], *sys.argv[4:6])[:200])
    elif cmd == 'memory':
        pairs = build_memory(sys.argv[2], sys.argv[3])
        Path(sys.argv[4]).write_text(json.dumps(pairs, ensure_ascii=False, indent=0), encoding='utf-8')
        print(f'memory: {len(pairs)} pairs -> {sys.argv[4]}')
    elif cmd == 'apply':
        applied, missed = apply_memory(sys.argv[2], sys.argv[3], sys.argv[4])
        print(f'apply: {applied} applied, {missed} missed -> {sys.argv[4]}')
    elif cmd == 'build':
        # build <base.asar> <out.asar> <swap.json>   swap.json = {"dist/...": "本地文件"}
        swap_map = json.loads(Path(sys.argv[4]).read_text(encoding='utf-8'))
        n, size = asar_build(sys.argv[2], sys.argv[3], swap_map)
        print(f'build: 换装 {n} 个文件, 数据区 {size/1048576:.1f}MB -> {sys.argv[3]}')
    elif cmd == 'packselftest':
        # packselftest <base.asar> <built.asar> <参考zh.asar>  逐文件对比 + integrity 自洽校验
        same, diff, bad_int, diffs, only_a = asar_compare(sys.argv[2], sys.argv[3])
        print(f'与底包相同内容: {same} | 不同: {diff} | integrity 不自洽: {bad_int}')
        print('差异文件(应全部是换装目标):', diffs)
        print('仅底包有:', only_a)
        same2, diff2, bad2, _, _ = asar_compare(sys.argv[4], sys.argv[3])
        print(f'与官方 zh 包逐文件对比: 相同 {same2} | 不同 {diff2} | {sys.argv[3]} integrity 不自洽 {bad2}')
    elif cmd == 'selftest':
        asar, matdir = sys.argv[2], Path(sys.argv[3])
        targets = {'dist/menu.js': 'dist__menu.js', 'dist/main.js': 'main25-zh.js',
                   'dist/ideInstall/wizardHtml.js': 'dist__ideInstall__wizardHtml.js'}
        rows = []
        for inner, zh_name in targets.items():
            orig = asar_extract(asar, inner)
            zh = (matdir / zh_name).read_text(encoding='utf-8', errors='replace')
            tmp_o, tmp_z = Path('_st_orig.js'), Path('_st_zh.js')
            tmp_o.write_text(orig, encoding='utf-8'); tmp_z.write_text(zh, encoding='utf-8')
            pairs = build_memory(str(tmp_o), str(tmp_z))
            Path('_st_mem.json').write_text(json.dumps(pairs, ensure_ascii=False), encoding='utf-8')
            applied, missed = apply_memory(str(tmp_o), '_st_mem.json', '_st_out.js')
            got = Path('_st_out.js').read_text(encoding='utf-8', errors='replace')
            sim = difflib.SequenceMatcher(None, zh, got, autojunk=False).ratio()
            rows.append((zh_name, len(pairs), applied, missed, sim))
        print(f'{"文件":<34}{"记忆对":>6}{"应用":>6}{"未中":>6}{"与现有汉化相似度":>12}')
        for name, np_, ap, mi, sim in rows:
            print(f'{name:<34}{np_:>6}{ap:>6}{mi:>6}{sim:>11.1%}')
        for f in ('_st_orig.js', '_st_zh.js', '_st_mem.json', '_st_out.js'):
            Path(f).unlink(missing_ok=True)
    else:
        print(__doc__)

if __name__ == '__main__':
    main()
