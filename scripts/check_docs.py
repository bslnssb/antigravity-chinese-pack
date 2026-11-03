#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
文档与代码对表：文档里声称的机制，必须在代码里真的存在。

    python scripts/check_docs.py        # 全过退出 0，否则退出 1

为什么有这个东西：汉化包有一套"文档说不清楚就会出事"的机制——启动器回滚、
zh-port-skip 熔断、自愈退出码、标记文件、哈希校验。任一环悄悄改了名或删了，
用户看到的是"中文又没了"，而维护者看到的是一份看起来还对得上的文档。
这里把两边硬绑在一起，跑一次就知道哪句话已经不成立了。

只读、纯标准库、不改任何文件。
"""

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.stdout.reconfigure(encoding="utf-8")

VBS_SRC = ROOT / "tools" / "maintainer" / "launcher-vbs-src.vbs"
VBS_OUT = ROOT / "启动反重力.vbs"
SELFHEAL = ROOT / "tools" / "selfheal.ps1"
RESTORE_BAT = ROOT / "一键恢复官方英文.bat"
INSTALL_BAT = ROOT / "一键安装汉化.bat"
PACKAGE = ROOT / "scripts" / "package_dist.py"
TEST_ENGINE = ROOT / "scripts" / "test_engine.js"
MAINTAINER = ROOT / "docs" / "MAINTAINER.md"
README = ROOT / "README.md"
RELEASE_BODY = ROOT / "docs" / "release-body.md"
PIN = ROOT / "tools" / "patches" / "sha256-2.28.2.json"

failures = []


def read(path, encoding="utf-8"):
    try:
        return path.read_text(encoding=encoding)
    except FileNotFoundError:
        raise SystemExit(f"缺文件：{path.relative_to(ROOT)}")


def vbs_out_text():
    raw = VBS_OUT.read_bytes()
    return raw.decode("utf-16-le").lstrip("\ufeff")


def check(name):
    """装饰器：注册一项检查，函数返回问题列表（空 = 通过）。"""
    def deco(fn):
        fn._check_name = name
        CHECKS.append(fn)
        return fn
    return deco


CHECKS = []


@check("启动器：回滚函数存在，且不再是 healedSrc 笔误")
def _rollback():
    bad = []
    for label, text in (("源码", read(VBS_SRC)), ("产物", vbs_out_text())):
        if "healedSrc" in text:
            bad.append(f"{label}里还有 healedSrc（未声明变量，回滚分支会直接报错）")
        if not re.search(r"^Sub RevertPort\(", text, re.M):
            bad.append(f"{label}里没有 Sub RevertPort(")
        if not re.search(r"^\s+RevertPort\s+\S+,\s*\S+", text, re.M):
            bad.append(f"{label}里没有调用 RevertPort")
    return bad


@check("熔断：zh-port-skip 由自愈写、启动器读")
def _skip():
    sh, vbs = read(SELFHEAL), read(VBS_SRC)
    bad = []
    if "zh-port-skip" not in sh:
        bad.append("selfheal.ps1 里找不到 zh-port-skip（快路径不会跳过移植失败过的版本）")
    if "zh-port-skip" not in vbs:
        bad.append("启动器里找不到 zh-port-skip（回滚后不会熔断，会反复重试）")
    if "zh-port-skip" not in read(MAINTAINER):
        bad.append("MAINTAINER 没写 zh-port-skip 熔断机制")
    return bad


@check("自愈退出码：代码里的档位与 MAINTAINER 的表一致")
def _exit_codes():
    sh = read(SELFHEAL)
    codes = sorted({int(c) for c in re.findall(r"Write-Result\s+(\d+)\s", sh)} - {0})
    bad = []
    expected = {10, 11, 20, 21, 22, 30, 31}
    missing = expected - set(codes)
    if missing:
        bad.append(f"selfheal.ps1 少了这些退出码：{sorted(missing)}")

    doc = read(MAINTAINER)
    table = {int(m) for m in re.findall(r"^\|\s*(\d{2})\s*\|", doc, re.M)}
    not_in_doc = set(codes) - table
    if not_in_doc:
        bad.append(f"MAINTAINER 退出码表缺：{sorted(not_in_doc)}")
    not_in_code = table - set(codes)
    if not_in_code:
        bad.append(f"MAINTAINER 写了但代码里没有：{sorted(not_in_code)}")
    return bad


@check("输出字段：启动器解析的 KEY，自愈真的会输出")
def _fields():
    vbs, sh = read(VBS_SRC), read(SELFHEAL)
    asked = set(re.findall(r'FieldOf\([^,]+,\s*"([A-Z]+)"\)', vbs))
    produced = set(re.findall(r"Set-Field\s+'([A-Z]+)'", sh)) | {"STATE", "CODE"}
    bad = []
    for k in sorted(asked - produced):
        bad.append(f"启动器读 {k}=… 但 selfheal.ps1 从不输出它")
    if not asked:
        bad.append("启动器里没找到任何 FieldOf 调用（解析逻辑不见了？）")
    return bad


@check("标记文件：.zh-pack 三处一致")
def _marker():
    sh, vbs, bat = read(SELFHEAL), read(VBS_SRC), read(RESTORE_BAT, "gbk")
    bad = []
    if "$MarkerName = '.zh-pack'" not in sh:
        bad.append("selfheal.ps1 的 $MarkerName 不再是 .zh-pack")
    if not re.search(r"\.zh-pack\b", vbs):
        bad.append("启动器回滚时不删 .zh-pack")
    # 必须真有 del ... .zh-pack（改名成 .zh-packx 之类的半截吻合不算）
    if not re.search(r"\bdel\b[^\r\n]*\.zh-pack\b", bat, re.I):
        bad.append("一键恢复官方英文.bat 不删 .zh-pack（恢复后会被自愈补回中文）")
    return bad


@check("恢复脚本：自己找目录、校验复制结果、提示改用官方图标")
def _restore():
    # 这个 bat 的文案是英文（与 一键安装汉化.bat 一致），只文件名是中文
    bat = read(RESTORE_BAT, "gbk")
    low = bat.lower()
    bad = []
    if "find-install-dir.ps1" not in bat:
        bad.append("没接 tools\\find-install-dir.ps1 兜底（非默认目录会找不到）")
    if "errorlevel" not in low:
        bad.append("copy 之后没校验 errorlevel")
    if "run as administrator" not in low and "以管理员身份运行" not in bat:
        bad.append("复制失败时没给 Program Files 的真因提示")
    if "its own desktop" not in low and "图标" not in bat:
        bad.append("没提示用户以后用官方图标启动")
    return bad


@check("安装脚本：Program Files 场景前置写探针")
def _installer():
    bat = read(INSTALL_BAT, "gbk")
    low = bat.lower()
    bad = []
    if ".zh-write-probe" not in bat:
        bad.append("一键安装汉化.bat 没有写权限探针")
    if "run as administrator" not in low and "以管理员身份运行" not in bat:
        bad.append("报错时没指向「以管理员身份运行」")
    return bad


@check("打包：PAYLOAD_FILES 每个成员都真实存在")
def _payloads():
    src = read(PACKAGE)
    m = re.search(r"PAYLOAD_FILES = \[(.*?)\]", src, re.S)
    if not m:
        return ["scripts/package_dist.py 里找不到 PAYLOAD_FILES"]
    items = re.findall(r'"([^"]+)"', m.group(1))
    bad = []
    for rel in items:
        rel_exp = rel.replace("{version}", "2.28.2")
        if not (ROOT / rel_exp).is_file():
            bad.append(f"打包清单里的 {rel} 不存在")
    return bad


@check("代理：启动器不写死端口，文档说的是「探到才设」")
def _proxy():
    src, doc = read(VBS_SRC), read(MAINTAINER)
    bad = []
    if re.search(r"Const\s+PROXY(?:_HOST|_PORT)?\s*=", src):
        bad.append("启动器里又有写死的代理常量了（别人的端口会对不上）")
    if "Function DetectProxy(" not in src:
        bad.append("启动器没有 DetectProxy()")
    if "local-proxy.txt" not in src:
        bad.append("启动器不读 tools\\local-proxy.txt")
    if not (ROOT / "tools" / "detect-proxy.ps1").is_file():
        bad.append("缺 tools/detect-proxy.ps1")
    if "探到才" not in doc:
        bad.append("MAINTAINER 没写「探到才设代理」")
    return bad


@check("供应链：打包写 sha256 表、自愈覆盖前比对")
def _supply_chain():
    pkg, sh, doc = read(PACKAGE), read(SELFHEAL), read(MAINTAINER)
    bad = []
    if "sha256" not in pkg or "hexdigest" not in pkg:
        bad.append("package_dist.py 不再计算哈希")
    if "sha256-{version}.json" not in pkg:
        bad.append("打包清单没带上 sha256-<版本>.json")
    if "asar_sha256" not in sh:
        bad.append("selfheal.ps1 不校验包内哈希")
    if "sha256" not in doc:
        bad.append("MAINTAINER 没写哈希校验")
    if not PIN.is_file():
        bad.append("缺 tools/patches/sha256-2.28.2.json")
    else:
        try:
            data = json.loads(PIN.read_text(encoding="utf-8"))
            if not re.fullmatch(r"[0-9a-f]{64}", data.get("asar_sha256", "")):
                bad.append("sha256-2.28.2.json 里的 asar_sha256 不是 64 位小写 hex")
        except json.JSONDecodeError as e:
            bad.append(f"sha256-2.28.2.json 不是合法 JSON：{e}")
    return bad


@check("回归用例数：文档说的和 test_engine.js 里的一致")
def _cases():
    js = read(TEST_ENGINE)
    n = len(re.findall(r"^\s*\[\s*'", js, re.M)) or len(re.findall(r"^\s*\[\s*\"", js, re.M))
    bad = []
    if n == 0:
        return ["test_engine.js 里没解析出用例（写法变了？）"]
    doc = read(MAINTAINER) + read(README)
    claimed = {int(m) for m in re.findall(r"(\d+)\s*(?:个|条)?\s*用例", doc)}
    claimed |= {int(m) for m in re.findall(r"test_engine(?:\.js)?\s*(\d+)", doc)}
    for c in claimed:
        if c != n:
            bad.append(f"文档说 {c} 条用例，test_engine.js 实际 {n} 条")
    if not claimed:
        bad.append("文档里找不到用例数的说法（改了就没人知道回归覆盖多少）")
    return bad


@check("Release 正文模板：占位符都能被 package_dist 填上")
def _template():
    tpl = read(RELEASE_BODY)
    pkg = read(PACKAGE)
    names = set(re.findall(r"\{([a-z_]+)\}", tpl))
    provided = set(re.findall(r"^\s*([a-z_]+)=", pkg, re.M)) | {
        "version", "zip_name", "zip_size", "zip_sha256",
        "asar_name", "asar_size", "asar_sha256"}
    bad = [f"模板占位符 {{{n}}} 没有对应的填充字段" for n in sorted(names - provided)]
    return bad


def main():
    failed = 0
    for fn in CHECKS:
        try:
            problems = fn() or []
        except SystemExit:
            raise
        except Exception as e:  # noqa: BLE001 - 检查脚本自己出错也要算失败
            problems = [f"检查本身出错：{type(e).__name__}: {e}"]
        if problems:
            failed += 1
            print(f"FAIL  {fn._check_name}")
            for p in problems:
                print(f"        - {p}")
        else:
            print(f"ok    {fn._check_name}")
    print()
    total = len(CHECKS)
    if failed:
        print(f"{total - failed}/{total} 通过，{failed} 项与文档不符。")
        return 1
    print(f"{total}/{total} 通过：文档里说的机制，代码里都在。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
