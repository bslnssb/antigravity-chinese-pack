#!/usr/bin/env python3
"""把 build/readme_shots/ 的原始截图压成 README 用的成品图，落到 docs/screenshots/。

打码策略（2026-11-11 起）：**在截图时就遮掉**，不再事后糊图。
scripts/shot_readme.js 会在按快门前往页面注入一段 CSS，把
  .home-greeting-title                          首页「欢迎回来，xxx」
  [data-testid="settings-nav-item-Account"]      设置面板左下角 头像 + 用户名 + 邮箱
设为 visibility:hidden，截完立刻移除。这样成品图里就没有个人信息，
也就不存在「糊得不够被还原」的问题（老做法是 14px 马赛克，还要按 2100x1353 手写坐标，
界面一改版坐标全废）。

本脚本只做三件事：等比缩到 2000px 宽、转成压缩 PNG、核对成品。

用法：
    node scripts/shot_readme.js          # 先截图（客户端需在运行）
    python tools/redact_screenshots.py   # 再压图
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = ROOT / "build" / "readme_shots"
OUT_DIR = ROOT / "docs" / "screenshots"

# README 里用到的几张，顺序即 README 出现顺序
FILES = [
    "main.png",
    "settings-general.png",
    "settings-appearance.png",
    "settings-app.png",
]

# 目标宽度：GitHub README 正文约 880px，2x 屏下 2000px 已经够清晰
TARGET_W = 2000

# 兜底：万一以后某张图又漏了敏感区域，在这里按 2000px 宽坐标系补马赛克
# 例：{"settings-app.png": [(x0, y0, x1, y1)]}
REGIONS: dict[str, list[tuple[int, int, int, int]]] = {}
BLOCK = 14


def mosaic(im: Image.Image, box: tuple[int, int, int, int], block: int = BLOCK) -> None:
    """原地打码：缩到 1/block 再放大回原尺寸，保留明暗、丢掉细节。"""
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    if w <= 0 or h <= 0:
        raise ValueError(f"非法区域: {box}")
    region = im.crop(box)
    small = region.resize((max(1, w // block), max(1, h // block)), Image.NEAREST)
    im.paste(small.resize((w, h), Image.NEAREST), (x0, y0))


def main() -> int:
    if not SRC_DIR.exists():
        print(f"[ERR] 缺少原始截图目录 {SRC_DIR}，先跑 node scripts/shot_readme.js")
        return 2
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    missing = []
    for name in FILES:
        src = SRC_DIR / name
        if not src.exists():
            missing.append(name)
            continue
        im = Image.open(src).convert("RGB")
        if im.width > TARGET_W:
            h = round(im.height * TARGET_W / im.width)
            im = im.resize((TARGET_W, h), Image.LANCZOS)
        for box in REGIONS.get(name, []):
            mosaic(im, box)
        out = OUT_DIR / name
        im.save(out, optimize=True)
        print(f"[OK] {name:26} {im.size[0]}x{im.size[1]}  {out.stat().st_size // 1024} KB")
    if missing:
        print(f"[ERR] 缺少截图: {', '.join(missing)}")
        return 1

    stale = sorted(p.name for p in OUT_DIR.glob("*.png") if p.name not in FILES)
    if stale:
        print(f"[WARN] docs/screenshots 里有 README 未引用的旧图: {', '.join(stale)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
