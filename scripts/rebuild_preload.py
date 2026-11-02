# -*- coding: utf-8 -*-
"""把 tools/preload-engine.js 的最新内容重新打进已有汉化 asar（只换 preload 一个文件）

用途：改了翻译引擎/词典之后，不必跑完整 port_to.py 流程。
用法: python scripts/rebuild_preload.py [版本，默认 2.28.2]
"""
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools' / 'maintainer'))
import zh_merge as Z  # noqa: E402

MARK = '(function initChineseLocalization() {'


def main():
    ver = sys.argv[1] if len(sys.argv) > 1 else '2.28.2'
    src = ROOT / 'build' / f'app.asar.zh-{ver}'
    if not src.is_file():
        raise SystemExit(f'找不到汉化成品: {src}')

    # 关键：永远从「未替换过引擎的干净底包」重建。
    # 若基于上一次的产物剥离，引擎前的注释块会被当成官方内容一次次累积，
    # 实测连跑两次官方部分就从 8,271 涨到 8,425 字节。
    bak = ROOT / 'build' / f'_base-zh-{ver}.asar'
    if not bak.is_file():
        shutil.copy2(src, bak)
        print(f'建立干净底包: {bak.name}')
    base = bak

    cur = Z.asar_extract(str(base), 'dist/preload.js')
    engine_path = ROOT / 'tools' / 'preload-engine.js'
    engine = engine_path.read_text(encoding='utf-8')

    i = cur.find(MARK)
    if i < 0:
        raise SystemExit('成品 preload.js 里找不到引擎起点，无法剥离旧引擎')
    official_part = cur[:i]
    old_engine_len = len(cur) - i

    new_preload = official_part + engine
    tmp = ROOT / 'build' / '_preload_new.js'
    tmp.write_text(new_preload, encoding='utf-8', newline='')

    out = ROOT / 'build' / f'_zh-{ver}.tmp'
    n, size = Z.asar_build(str(base), str(out), {'dist/preload.js': str(tmp)})

    # 自检：新包里 preload 必须等于刚写的内容，且其余文件数量不变
    h1, _, _ = Z.asar_read(str(base))
    h2, _, _ = Z.asar_read(str(out))
    n1 = len(list(Z.asar_leaves(h1)))
    n2 = len(list(Z.asar_leaves(h2)))
    back = Z.asar_extract(str(out), 'dist/preload.js')
    if back != new_preload:
        raise SystemExit('自检失败：重打包后 preload 内容不一致')
    if n1 != n2:
        raise SystemExit(f'自检失败：文件数从 {n1} 变成 {n2}')

    shutil.move(str(out), str(src))
    tmp.unlink(missing_ok=True)

    print(f'版本    : {ver}')
    print(f'替换    : {n} 个文件（dist/preload.js）')
    print(f'旧引擎  : {old_engine_len:,} 字节 → 新引擎 {len(engine):,} 字节')
    print(f'preload : {len(official_part):,} + {len(engine):,} = {len(new_preload):,} 字节')
    print(f'asar    : {src.stat().st_size:,} 字节，{n2} 个文件（与原来一致）')


if __name__ == '__main__':
    main()
