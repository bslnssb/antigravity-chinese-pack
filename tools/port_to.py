# -*- coding: utf-8 -*-
"""把现有汉化移植到新的 Antigravity 版本。

官方用 NSIS 全量安装包更新，会把 resources\\ 整个覆盖，汉化和备份都会消失。
所以每次官方更新后都要重做一次补丁——这个脚本做的就是"重做"。

用法
----
    python tools/port_to.py --version 2.29.0                 # 自动找已安装的 app.asar
    python tools/port_to.py --version 2.29.0 --base D:\\x\\app.asar
    python tools/port_to.py --version 2.29.0 --ref 2.28.2    # 指定参考版本（默认取最新）

产物
----
    build/work-<ver>/official/   从官方 asar 抽出的 6 个原始文件
    build/work-<ver>/zh<minor>/  移植后的 6 个汉化文件
    build/work-<ver>/swap-map-<ver>.json
    build/app.asar.zh-<ver>      可直接替换 resources\\app.asar 的成品

原理
----
preload.js  汉化版 = 官方原文（每行后插一个空行）+ tools/preload-engine.js
            引擎是固定的（翻译词典 + DOM 翻译器），换版本只需换前半段官方原文
其余 5 个    用参考版本的「官方 → 汉化」差异对做替换，但只允许改字符串字面量内部

为什么不能直接 str.replace
--------------------------
自动记忆会把代码拼接处抠成碎片对，且短词（Exit/Open/Docs）同时出现在标识符里。
直接替换会得到 `is退出ting` 这种**语法合法、运行时才 ReferenceError** 的污染
（中文是合法标识符字符，node --check 拦不住）。所以必须：
  1. 跳过 // 与 /* */ 注释（注释里的撇号会让引号配对错位）
  2. 只替换落在字符串字面量区间内的出现
  3. 英文词做前后单词边界检查
  4. 打包前断言：代码区（字符串与注释之外）不允许出现中文字符
"""
import argparse
import json
import os
import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding='utf-8')

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools' / 'maintainer'))
import zh_merge as Z  # noqa: E402

QUOTES = ('"', "'", '`')
SIX = {
    'dist/preload.js': 'dist_preload.js',
    'dist/main.js': 'dist_main.js',
    'dist/menu.js': 'dist_menu.js',
    'dist/tray.js': 'dist_tray.js',
    'dist/ideInstall/wizardHtml.js': 'dist_ideInstall_wizardHtml.js',
    'dist/ipcHandlers.js': 'dist_ipcHandlers.js',
}


def minor(ver):
    parts = ver.split('.')
    return parts[1] if len(parts) > 1 else parts[0]


def default_base():
    """定位已安装的官方 app.asar"""
    cands = []
    for env in ('LOCALAPPDATA', 'PROGRAMFILES', 'PROGRAMFILES(X86)'):
        root = os.environ.get(env)
        if root:
            cands.append(Path(root) / 'Programs' / 'Antigravity' / 'resources' / 'app.asar')
            cands.append(Path(root) / 'Antigravity' / 'resources' / 'app.asar')
    for c in cands:
        if c.is_file():
            return c
    raise SystemExit('找不到已安装的 app.asar，请用 --base 指定')


def latest_ref():
    """build/work-<ver>/ 里最新、且同时有 official 与 zh<minor> 的版本"""
    best = None
    for d in (ROOT / 'build').glob('work-*'):
        ver = d.name[len('work-'):]
        zh = d / f'zh{minor(ver)}'
        if (d / 'official').is_dir() and zh.is_dir() and (zh / 'dist_preload.js').is_file():
            key = tuple(int(x) for x in re.findall(r'\d+', ver))
            if best is None or key > best[0]:
                best = (key, ver, d, zh)
    if not best:
        raise SystemExit('build/ 里没有可用的参考版本，请用 --ref 指定')
    return best[1], best[2], best[3]


def string_ranges(text):
    """字符串字面量区间，跳过 // 与 /* */ 注释"""
    ranges, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c == '/' and i + 1 < n and text[i + 1] == '/':
            j = text.find('\n', i)
            i = n if j == -1 else j + 1
            continue
        if c == '/' and i + 1 < n and text[i + 1] == '*':
            j = text.find('*/', i + 2)
            i = n if j == -1 else j + 2
            continue
        if c in QUOTES:
            q, start = c, i
            i += 1
            while i < n:
                if text[i] == '\\':
                    i += 2
                    continue
                if text[i] == q:
                    i += 1
                    break
                i += 1
            ranges.append((start, i))
            continue
        i += 1
    return ranges


def word_ok(text, pos, old):
    """英文词要求前后不紧贴标识符字符"""
    if old[0].isascii() and (old[0].isalnum() or old[0] == '_'):
        if pos > 0 and (text[pos - 1].isalnum() or text[pos - 1] == '_'):
            return False
    if old[-1].isascii() and (old[-1].isalnum() or old[-1] == '_'):
        e = pos + len(old)
        if e < len(text) and (text[e].isalnum() or text[e] == '_'):
            return False
    return True


def replace_in_strings(src, old, new):
    ranges = string_ranges(src)
    hits, i = [], src.find(old)
    while i != -1:
        inside = any(s < i and i + len(old) <= e for s, e in ranges)
        if inside and word_ok(src, i, old):
            hits.append(i)
        i = src.find(old, i + 1)
    for p in reversed(hits):
        src = src[:p] + new + src[p + len(old):]
    return src, len(hits)


def code_cjk(text):
    """代码区（字符串与注释之外）的中文字符位置——污染的特征"""
    spans = string_ranges(text)
    i, n, comments = 0, len(text), []
    while i < n:
        if text[i] == '/' and i + 1 < n and text[i + 1] == '/':
            j = text.find('\n', i)
            j = n if j == -1 else j
            comments.append((i, j))
            i = j
        elif text[i] == '/' and i + 1 < n and text[i + 1] == '*':
            j = text.find('*/', i + 2)
            j = n if j == -1 else j + 2
            comments.append((i, j))
            i = j
        else:
            i += 1
    covers = sorted(spans + comments)

    def covered(p):
        for s, e in covers:
            if s <= p < e:
                return True
            if p < s:
                return False
        return False

    return [p for p, ch in enumerate(text) if '\u4e00' <= ch <= '\u9fff' and not covered(p)]


def ensure_words(engine, words):
    """把官方新增文案补进 EXACT_WORDS 精确匹配层（幂等）"""
    anchor = 'const EXACT_WORDS = {'
    if anchor not in engine:
        return engine, []
    added = [k for k in words if json.dumps(k, ensure_ascii=False) + ':' not in engine]
    if not added:
        return engine, []
    entry = ''.join(f'{json.dumps(k, ensure_ascii=False)}:{json.dumps(v, ensure_ascii=False)},'
                    for k, v in words.items() if k in added)
    return engine.replace(anchor, anchor + entry, 1), added


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--version', required=True, help='目标版本，如 2.29.0')
    ap.add_argument('--base', help='目标版本官方 app.asar（默认取已安装的）')
    ap.add_argument('--ref', help='参考版本（提供译文记忆），默认取 build/ 里最新的')
    ap.add_argument('--out', help='输出的汉化 asar 路径')
    a = ap.parse_args()

    ver = a.version
    mi = minor(ver)
    base = Path(a.base) if a.base else default_base()
    ref_ver, ref_off, ref_zh = (a.ref, None, None) if a.ref else (None, None, None)
    if a.ref:
        d = ROOT / 'build' / f'work-{a.ref}'
        ref_off, ref_zh = d / 'official', d / f'zh{minor(a.ref)}'
        if not ref_zh.is_dir():
            raise SystemExit(f'参考版本目录不存在: {ref_zh}')
    else:
        ref_ver, ref_off, ref_zh = latest_ref()

    W = ROOT / 'build' / f'work-{ver}'
    OFF, ZH = W / 'official', W / f'zh{mi}'
    OFF.mkdir(parents=True, exist_ok=True)
    ZH.mkdir(parents=True, exist_ok=True)

    pkg = json.loads(Z.asar_extract(str(base), 'package.json'))
    print(f'底座  : {base}')
    print(f'版本  : {pkg.get("name")} {pkg.get("version")}（目标 {ver}）')
    if pkg.get('version') != ver:
        print(f'  !! 版本不符，仍按 {ver} 继续（产物名会与实物不一致）')
    print(f'参考  : {ref_ver}（{ref_zh.name}）')

    for inner, name in SIX.items():
        Z.asar_extract(str(base), inner, str(OFF / name))
    print(f'已抽出官方 6 个文件 → {OFF.relative_to(ROOT)}')

    # ---- preload：官方原文双行化 + 固定引擎 ----
    engine = (ROOT / 'tools' / 'preload-engine.js').read_text(encoding='utf-8')
    rules_path = ROOT / 'tools' / 'porting-rules.json'
    rules = json.loads(rules_path.read_text(encoding='utf-8')) if rules_path.is_file() else {}
    engine, added = ensure_words(engine, rules.get('extraWords', {}))
    if added:
        print(f'补词  : {len(added)} 条 {added}')

    off_preload = (OFF / 'dist_preload.js').read_text(encoding='utf-8')
    new_preload = off_preload.replace('\n', '\n\n') + engine
    (ZH / 'dist_preload.js').write_text(new_preload, encoding='utf-8', newline='')
    print(f'preload: 官方 {len(off_preload)} → 汉化 {len(new_preload)}（引擎 {len(engine)}）')

    # ---- 其余 5 个：译文记忆 + 手工规则 ----
    # 参考版本的原始 asar 允许写成 2.26 / 2.26.0 两种文件名
    cands = sorted((ROOT / 'build').glob(f'app.asar.original-{ref_ver}*'))
    ref_base = cands[-1] if cands else None
    total = 0
    for inner, name in SIX.items():
        if name == 'dist_preload.js':
            continue
        o_ref = ref_off / name
        z_ref = ref_zh / name
        if not o_ref.is_file() and ref_base:
            # 参考版本没留 official/ 时，从它的原始 asar 现抽
            ref_off.mkdir(parents=True, exist_ok=True)
            Z.asar_extract(str(ref_base), inner, str(o_ref))
        if not o_ref.is_file():
            print(f'  {inner:<34} 跳过（参考版本缺 original asar，翻译记忆无法建立）')
            continue
        mem = Z.build_memory(str(o_ref), str(z_ref))
        src = (OFF / name).read_text(encoding='utf-8', errors='replace')
        applied = miss = 0
        for old, new in rules.get('manual', {}).get(name, []):
            c = src.count(old)
            if c != 1:
                print(f'  !! 手工规则命中 {c} 次: {name} :: {old[:40]!r}')
            src = src.replace(old, new)
            applied += c
        for old in sorted(mem, key=len, reverse=True):
            if len(old) < 3 or '\n' in old:
                miss += 1
                continue
            src, n = replace_in_strings(src, old, mem[old])
            if n:
                applied += n
            else:
                miss += 1
        (ZH / name).write_text(src, encoding='utf-8', newline='')
        total += applied
        print(f'  {inner:<34} 记忆 {len(mem):>2} | 应用 {applied:>2} | 未搬 {miss}')

    # ---- 断言：代码区不允许出现中文 ----
    print('\n=== 代码区污染检查 ===')
    bad = 0
    for inner, name in SIX.items():
        if name == 'dist_preload.js':
            continue  # 引擎自带中文正则，不参与自动替换
        z = (ZH / name).read_text(encoding='utf-8', errors='replace')
        pos = code_cjk(z)
        if pos:
            bad += len(pos)
            print(f'  {inner}: {len(pos)} 处，样例 {z[max(0, pos[0] - 40):pos[0] + 40]!r}')
    print('  结论:', '通过' if bad == 0 else f'{bad} 处污染，请勿发布')

    swap = {inner: str((ZH / name).relative_to(ROOT)) for inner, name in SIX.items()}
    (W / f'swap-map-{ver}.json').write_text(
        json.dumps(swap, ensure_ascii=False, indent=1), encoding='utf-8')

    out = Path(a.out) if a.out else ROOT / 'build' / f'app.asar.zh-{ver}'
    n, payload = Z.asar_build(str(base), str(out), swap)
    print(f'\n打包  : {out}（换装 {n} 个，数据区 {payload} 字节）')
    same, diff, bad_int, diffs, only_a = Z.asar_compare(str(base), str(out))
    print(f'自检  : 相同 {same} | 不同 {diff} | integrity 不自洽 {bad_int} | 仅底座有 {len(only_a)}')
    print('换装  :', diffs)
    if bad_int or only_a or diff != len(SIX):
        print('!! 自检未通过，不要发布')
        return 1
    print('\n完成。安装：把该文件复制为 resources/app.asar（先备份原文件）')
    return 0


if __name__ == '__main__':
    sys.exit(main())
