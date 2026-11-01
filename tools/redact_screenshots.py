#!/usr/bin/env python3
"""把 README 用的两张截图做隐私打码。

为什么单独做成脚本：这两张图里出现过 1) Google 账户头像/用户名/邮箱 2) 侧栏历史会话标题，
  第一次手工处理时只盖了邮箱、漏了用户名和头像，也漏了 settings.png 的历史列表。

做法：从 build/_shots/ 的**原始截图**重新生成，而不是在已发布的图上二次处理
  （二次处理会叠加模糊层，越糊越看不出来遮了什么）。

像素化而不是高斯模糊：16px 块把字压成色块，信息不可恢复；
  高斯模糊在被裁切放大后仍有被辨认的可能。

用法：
    python tools/redact_screenshots.py
"""
from pathlib import Path

from PIL import Image

BLOCK = 14
ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / "build" / "_shots"
OUT_DIR = ROOT / "docs" / "screenshots"

# 坐标基于 2100x1353 的原图（2x DPR 截图），单位是像素
REGIONS = {
    # 设置页：账户卡片里 头像 + 用户名 + 邮箱 两行
    "settings.png": [
        (294, 1128, 360, 1192),   # 头像
        (354, 1144, 580, 1200),   # "com π" 用户名 + a2...@gmail 邮箱
        (12, 416, 280, 628),      # 侧栏 4 条历史会话标题
    ],
    # 主界面：项目管理下的项目/会话列表
    "main.png": [
        (8, 400, 394, 642),
    ],
}

# 原始截图来源：settings 的原始件是 settings.png，主界面的原始件是 _current.png
SOURCES = {
    "settings.png": RAW_DIR / "settings.png",
    "main.png": RAW_DIR / "_current.png",
}


def mosaic(im: Image.Image, box: tuple[int, int, int, int], block: int = BLOCK) -> None:
    """原地打码：把区域缩到 1/block 再放大回原尺寸，保留大致明暗、丢掉全部细节。"""
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    if w <= 0 or h <= 0:
        raise ValueError(f"非法区域: {box}")
    region = im.crop(box)
    small = region.resize((max(1, w // block), max(1, h // block)), Image.NEAREST)
    im.paste(small.resize((w, h), Image.NEAREST), (x0, y0))


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for name, boxes in REGIONS.items():
        src = SOURCES[name]
        if not src.exists():
            print(f"[SKIP] 缺少原始截图 {src}")
            continue
        im = Image.open(src).convert("RGB")
        for box in boxes:
            mosaic(im, box)
        out = OUT_DIR / name
        im.save(out, optimize=True)
        kb = out.stat().st_size // 1024
        print(f"[OK] {name}  {im.size[0]}x{im.size[1]}  {kb} KB  打码 {len(boxes)} 处")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
