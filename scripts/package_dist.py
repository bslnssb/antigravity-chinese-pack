#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
打包发布用的 zip（给 GitHub Releases 用）。

    python scripts/package_dist.py --version 2.28.2

产物：packs/Antigravity-Chinese-Pack-v<版本>.zip

要点：
- 全部成员用 UTF-8 文件名（zip 通用标志位 bit 11），中文名不会在 7-Zip /
  Windows 资源管理器里变乱码。上游 package_dist.js 用 `tar -a` 打包，
  7 个中文成员名会被写成 GBK，是踩过的坑。
- 免安装目录结构：asar 与 bat 同一层，bat 用 %~dp0 相对定位，
  tools/ 子目录放 PS 实现，压缩包解压到哪都能跑。
"""

import argparse
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

PAYLOAD_FILES = [
    "一键安装汉化.bat",
    "一键恢复官方英文.bat",
    "关闭自动更新.bat",
    "恢复自动更新.bat",
    "启动反重力.vbs",
    "tools/auto-update-toggle.ps1",
    "tools/find-install-dir.ps1",
    "tools/detect-proxy.ps1",
    "tools/make-shortcut.ps1",
    "tools/selfheal.ps1",
    # 现场移植：官方更新到新版本、本版包还没发布时，用这些素材把旧译文搬到
    # 新版本官方 asar 上（运行时借 Antigravity 自带 Electron 当 Node，用户无需装环境）
    "tools/port/port.js",
    "tools/patches/memory-{version}.json",
    "tools/preload-engine.js",
    "tools/porting-rules.json",
]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", required=True, help="版本号，如 2.28.2")
    ap.add_argument("--asar", help="汉化成品 asar（默认 build/app.asar.zh-<版本>）")
    ap.add_argument("--out", help="输出 zip 路径")
    a = ap.parse_args()

    ver = a.version
    # PAYLOAD_FILES 里的 {version} 展开成本次版本（翻译记忆是按参考版本命名的）
    payload_files = [p.replace("{version}", ver) for p in PAYLOAD_FILES]
    asar = Path(a.asar) if a.asar else ROOT / "build" / f"app.asar.zh-{ver}"
    if not asar.is_file():
        raise SystemExit(f"找不到汉化成品: {asar}")

    for rel in payload_files:
        if not (ROOT / rel).is_file():
            raise SystemExit(f"缺少打包文件: {rel}")

    readme = (ROOT / "docs" / "install-readme.txt").read_text(encoding="utf-8")
    readme = readme.replace("{version}", ver)

    out = Path(a.out) if a.out else ROOT / "packs" / f"Antigravity-Chinese-Pack-v{ver}.zip"
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists():
        out.unlink()

    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        z.write(asar, f"app.asar.zh-{ver}")
        for rel in payload_files:
            z.write(ROOT / rel, rel)
        info = zipfile.ZipInfo("安装说明.txt")
        info.compress_type = zipfile.ZIP_DEFLATED
        z.writestr(info, readme.encode("utf-8"))

    # 自检：成员名能按 UTF-8 还原、内容齐全
    with zipfile.ZipFile(out) as z:
        names = z.namelist()
        bad = z.testzip()
    need = {f"app.asar.zh-{ver}", "安装说明.txt", *payload_files}
    missing = need - set(names)

    print(f"产物 : {out}")
    print(f"体积 : {out.stat().st_size / 1024:.0f} KB")
    print(f"成员 : {len(names)} 个")
    for n in names:
        print(f"       {n}")
    if bad:
        print(f"!! 压缩包损坏: {bad}")
        return 1
    if missing:
        print(f"!! 缺失: {missing}")
        return 1
    print("\n完成。上传到 GitHub Releases 即可。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
