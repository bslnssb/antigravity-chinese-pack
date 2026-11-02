#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
从 UTF-8 源重建 启动反重力.vbs（UTF-16LE + BOM）。

    python scripts/build_launcher.py

为什么需要这个：WSH 读 VBS 时，含中文的文件必须是 UTF-16LE + BOM，否则乱码或
解析失败；而 UTF-16 文件在编辑器/版本库里几乎没法改。所以源文件用 UTF-8 放在
tools/maintainer/launcher-vbs-src.vbs，这个脚本负责转码并生成语法自检副本。

语法自检：VBScript 会先把整个脚本编译再执行，所以在 Option Explicit 之后插入
WScript.Quit 0，既能零副作用地触发完整编译，又能暴露语法错误。
用 cscript 跑 build/_synchk.vbs：无输出且退出码 0 = 语法通过。
"""

import codecs
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "tools" / "maintainer" / "launcher-vbs-src.vbs"
OUT = ROOT / "启动反重力.vbs"
CHK = ROOT / "build" / "_synchk.vbs"


def main() -> int:
    src = SRC.read_text(encoding="utf-8-sig").replace("\r\n", "\n").replace("\n", "\r\n")

    OUT.write_bytes(codecs.BOM_UTF16_LE + src.encode("utf-16-le"))
    raw = OUT.read_bytes()
    assert raw.startswith(codecs.BOM_UTF16_LE), "BOM missing"
    print(f"written: {OUT.name}  {len(raw)} bytes  (utf-16le + bom)")

    marker = "Option Explicit\r\n"
    if not src.startswith(marker):
        raise SystemExit("源文件第一行必须是 Option Explicit")

    chk = marker + "WScript.Quit 0\r\n" + src[len(marker):]
    CHK.write_bytes(codecs.BOM_UTF16_LE + chk.encode("utf-16-le"))
    print(f"syntax-check copy: {CHK.relative_to(ROOT)}")
    print('run: cscript //nologo "build\\_synchk.vbs"   (no output + exit 0 = OK)')
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
