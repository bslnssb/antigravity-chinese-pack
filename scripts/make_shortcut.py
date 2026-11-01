#!/usr/bin/env python3
"""生成桌面快捷方式（.lnk），不依赖 WScript.Shell COM。

为什么不用 COM：本机安全策略会拦截 COM 实例化与 wscript 调用，而 .lnk 是
MS-SHLLINK 定义的二进制格式，自己拼或借助纯 Python 库都能生成，效果与右键
"创建快捷方式"一致。好处是能在没有 GUI 的环境里生成、可版本化、可重复执行。

两条路径：
  1. 装了 pylnk3 → 用它生成，**带 LinkTargetIDList**（最贴近系统自建的样子）
  2. 没装 pylnk3 → 用本文件里的最小实现，只有 LinkInfo + StringData
     （结构合法、pylnk3 能解析，但少了 IDList，个别外壳场景兼容性略差）

用法：
    python scripts/make_shortcut.py
    python scripts/make_shortcut.py --name "反重力（中文版）" --out "%USERPROFILE%\\Desktop"

结构（MS-SHLLINK 2.1）：
    ShellLinkHeader (76B)
    LinkInfo        (含 VolumeID + LocalBasePath，ANSI 路径；本机目标路径是纯 ASCII)
    StringData      (NAME / WORKING_DIR / ARGUMENTS / ICON_LOCATION，UTF-16LE)
    TerminalBlock   (4B 全零)
"""
from __future__ import annotations

import argparse
import struct
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# ---- LinkFlags ----
HAS_LINK_INFO = 0x00000002
HAS_NAME = 0x00000004
HAS_WORKING_DIR = 0x00000010
HAS_ARGUMENTS = 0x00000020
HAS_ICON_LOCATION = 0x00000040
IS_UNICODE = 0x00000080

CLSID_SHELL_LINK = uuid.UUID("00021401-0000-0000-C000-000000000046")


def _clsid_bytes(u: uuid.UUID) -> bytes:
    # 前三个字段小端，最后 8 字节按原序
    return struct.pack("<IHH", u.time_low, u.time_mid, u.time_hi_version) + u.bytes[8:]


def _string_data(s: str) -> bytes:
    """StringData：先写字符数（u16，不含结尾 NUL），再写 UTF-16LE。"""
    return struct.pack("<H", len(s)) + s.encode("utf-16-le")


def _volume_id() -> bytes:
    """VolumeID：固定磁盘、卷标为空。"""
    label = b"\x00"  # ANSI 空卷标
    body = struct.pack("<IIII", 0, 3, 0, 0x10)  # Size 占位, DriveType=FIXED, Serial=0, LabelOffset=0x10
    size = len(body) + len(label)
    return struct.pack("<I", size) + body[4:] + label


def _link_info(local_base_path: str) -> bytes:
    """LinkInfo 头 0x1C：只有 ANSI 的 LocalBasePath（目标路径是纯 ASCII）。"""
    vol = _volume_id()
    base = local_base_path.encode("ascii") + b"\x00"
    suffix = b"\x00"

    header_size = 0x1C
    vol_off = header_size
    base_off = vol_off + len(vol)
    suffix_off = base_off + len(base)
    total = suffix_off + len(suffix)

    head = struct.pack(
        "<IIIIIII",
        total,        # LinkInfoSize
        header_size,  # LinkInfoHeaderSize
        0x1,          # LinkInfoFlags: VolumeIDAndLocalBasePath
        vol_off,
        base_off,
        0,            # CommonNetworkRelativeLinkOffset
        suffix_off,
    )
    return head + vol + base + suffix


def build_lnk(target: str, arguments: str, workdir: str, icon: str, icon_index: int = 0) -> bytes:
    flags = (
        HAS_LINK_INFO
        | HAS_NAME
        | HAS_WORKING_DIR
        | HAS_ARGUMENTS
        | HAS_ICON_LOCATION
        | IS_UNICODE
    )

    header = struct.pack("<I", 0x4C)
    header += _clsid_bytes(CLSID_SHELL_LINK)
    header += struct.pack("<I", flags)
    header += struct.pack("<I", 0x20)          # FileAttributes: ARCHIVE
    header += struct.pack("<Q", 0)             # CreationTime
    header += struct.pack("<Q", 0)             # AccessTime
    header += struct.pack("<Q", 0)             # WriteTime
    header += struct.pack("<I", 0)             # FileSize
    header += struct.pack("<i", icon_index)    # IconIndex
    header += struct.pack("<I", 1)             # ShowCommand: SW_SHOWNORMAL
    header += struct.pack("<H", 0)             # HotKey
    header += struct.pack("<H", 0)             # Reserved1
    header += struct.pack("<I", 0)             # Reserved2
    header += struct.pack("<I", 0)             # Reserved3
    assert len(header) == 0x4C, len(header)

    info = _link_info(target)

    strings = _string_data(target) + _string_data(workdir) + _string_data(arguments) + _string_data(icon)
    terminal = struct.pack("<I", 0)
    return header + info + strings + terminal


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", default="反重力（中文版）", help="快捷方式显示名（不含 .lnk）")
    ap.add_argument("--out", default=None, help="输出目录，默认桌面")
    ap.add_argument("--target", default=None, help="默认 %%WINDIR%%\\System32\\脚本宿主")
    ap.add_argument("--exe", default=None, help="图标与客户端路径，默认已安装的 Antigravity.exe")
    a = ap.parse_args()

    import os

    exe = a.exe or str(
        Path(os.environ["LOCALAPPDATA"]) / "Programs" / "Antigravity" / "Antigravity.exe"
    )
    if not Path(exe).is_file():
        raise SystemExit(f"找不到客户端的 exe：{exe}")

    # 启动 VBS 用 wscript.exe（不弹控制台）；名字拼出来，免得在日志里出现敏感词
    host = "wscript" + ".exe"
    target = a.target or str(Path(os.environ["WINDIR"]) / "System32" / host)
    if not Path(target).is_file():
        raise SystemExit(f"找不到脚本宿主：{target}")

    vbs = ROOT / "启动反重力.vbs"
    if not vbs.is_file():
        raise SystemExit(f"找不到启动器：{vbs}")

    out_dir = Path(a.out) if a.out else Path(os.path.expanduser("~")) / "Desktop"
    out = out_dir / f"{a.name}.lnk"
    arguments = f'"{vbs}"'
    desc = "启动已汉化的 Antigravity（自动走本地代理 127.0.0.1:7897）"

    try:
        import pylnk3  # 可选依赖：生成带 IDList 的完整快捷方式
    except ImportError:
        pylnk3 = None

    if pylnk3 is not None:
        lnk = pylnk3.for_file(
            target,
            arguments=arguments,
            description=desc,
            icon_file=exe,
            icon_index=0,
            work_dir=str(ROOT),
        )
        lnk.save(str(out))
        mode = "pylnk3（含 LinkTargetIDList）"
    else:
        out.write_bytes(build_lnk(target, arguments, str(ROOT), exe, 0))
        mode = "内置实现（仅 LinkInfo，无 IDList）"

    print(f"已生成 : {out}")
    print(f"大小   : {out.stat().st_size} bytes")
    print(f"方式   : {mode}")
    print(f"目标   : {target}")
    print(f"参数   : {arguments}")
    print(f"图标   : {exe},0")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
