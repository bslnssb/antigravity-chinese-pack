# -*- coding: utf-8 -*-
"""把 tools/patches/ui-extra.json 合并进 tools/preload-engine.js（幂等）

exact  -> EXACT_WORDS（整串精确匹配，安全）
phrase -> PHRASES（句内局部替换，带词边界）

用法: python scripts/merge_dict.py [--check]
--check 只报告差异，不写文件
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ENGINE = ROOT / 'tools' / 'preload-engine.js'
EXTRA = ROOT / 'tools' / 'patches' / 'ui-extra.json'

CJK = re.compile(r'[\u4e00-\u9fff]')

EXACT_RE = re.compile(r'const EXACT_WORDS = (\{.*?\});', re.S)
PHRASES_RE = re.compile(r'const PHRASES = (\[.*?\]);\n', re.S)


def load_extra():
    data = json.loads(EXTRA.read_text(encoding='utf-8'))
    exact = {k: v for k, v in data.get('exact', {}).items()}
    phrase = {k: v for k, v in data.get('phrase', {}).items()}
    problems = []

    # 同一条目同时出现在两个分区 → 只保留 exact（更安全）
    dup = set(exact) & set(phrase)
    for k in dup:
        problems.append(f'两个分区重复，已按 exact 处理: {k!r}')
        phrase.pop(k)

    for name, table in (('exact', exact), ('phrase', phrase)):
        for k, v in table.items():
            if not k.strip():
                problems.append(f'{name}: 空原文')
            if not CJK.search(v):
                problems.append(f'{name}: 译文不含中文 -> {k!r} => {v!r}')
            if v.count('"') or '\\' in v:
                problems.append(f'{name}: 译文含引号/反斜杠，可能破坏 JS 字面量 -> {k!r}')
    return exact, phrase, problems


def main():
    check = '--check' in sys.argv
    exact, phrase, problems = load_extra()
    for p in problems:
        print('  ! ' + p)

    src = ENGINE.read_text(encoding='utf-8')

    m = EXACT_RE.search(src)
    if not m:
        raise SystemExit('找不到 const EXACT_WORDS = {...};')
    cur_exact = json.loads(m.group(1))

    m2 = PHRASES_RE.search(src)
    if not m2:
        raise SystemExit('找不到 const PHRASES = [...];')
    cur_phrases = json.loads(m2.group(1))

    added_exact, changed_exact = [], []
    for k, v in exact.items():
        if k not in cur_exact:
            added_exact.append(k)
            cur_exact[k] = v
        elif cur_exact[k] != v:
            changed_exact.append((k, cur_exact[k], v))
            cur_exact[k] = v

    have = {k for k, _ in cur_phrases}
    added_phrase = [k for k in phrase if k not in have]
    for k in added_phrase:
        cur_phrases.append([k, phrase[k]])

    print(f'EXACT_WORDS: {len(cur_exact)} 条（新增 {len(added_exact)}，改译 {len(changed_exact)}）')
    print(f'PHRASES    : {len(cur_phrases)} 条（新增 {len(added_phrase)}）')
    for k, old, new in changed_exact:
        print(f'  改译 {k!r}: {old!r} -> {new!r}')

    if check:
        print('\n--check 模式，未写文件')
        return

    if not added_exact and not changed_exact and not added_phrase:
        print('无变化')
        return

    new_exact = 'const EXACT_WORDS = ' + json.dumps(cur_exact, ensure_ascii=False, separators=(',', ':')) + ';'
    new_phrases = 'const PHRASES = ' + json.dumps(cur_phrases, ensure_ascii=False, separators=(',', ':')) + ';\n'
    src = EXACT_RE.sub(lambda _: new_exact, src, count=1)
    src = PHRASES_RE.sub(lambda _: new_phrases, src, count=1)
    ENGINE.write_text(src, encoding='utf-8', newline='')
    print(f'\n已写回 {ENGINE.relative_to(ROOT)}')


if __name__ == '__main__':
    main()
