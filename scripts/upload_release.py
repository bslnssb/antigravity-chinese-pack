# -*- coding: utf-8 -*-
"""把新的 zip 传到 GitHub Release（覆盖同名资产）。

用法: python scripts/upload_release.py --version 2.28.2
"""
import argparse
import json
import os
import subprocess
import sys
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO = 'bslnssb/antigravity-chinese-pack'


def token():
    p = subprocess.run(['git', 'credential', 'fill'], cwd=ROOT,
                       input='protocol=https\nhost=github.com\n\n',
                       capture_output=True, text=True)
    for line in p.stdout.splitlines():
        if line.startswith('password='):
            return line.split('=', 1)[1]
    raise SystemExit('取不到 GitHub token')


TOKEN = token()


def api(method, url, data=None, headers=None, raw=False):
    h = {'Authorization': 'token ' + TOKEN, 'Accept': 'application/vnd.github+json',
         'User-Agent': 'agy-zh-pack'}
    if headers:
        h.update(headers)
    req = urllib.request.Request(url, data=data, headers=h, method=method)
    with urllib.request.urlopen(req, timeout=180) as r:
        body = r.read()
        if not body:
            return None
        return json.loads(body) if not raw else body


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--version', default='2.28.2')
    a = ap.parse_args()

    zip_path = ROOT / 'packs' / f'Antigravity-Chinese-Pack-v{a.version}.zip'
    if not zip_path.is_file():
        raise SystemExit(f'找不到 {zip_path}')
    size = zip_path.stat().st_size

    rel = api('GET', f'https://api.github.com/repos/{REPO}/releases/tags/v{a.version}')
    print(f'release: {rel["tag_name"]}  id={rel["id"]}')

    for asset in rel.get('assets', []):
        if asset['name'] == zip_path.name:
            print(f'  删除旧资产 {asset["name"]} ({asset["size"]:,} 字节)')
            api('DELETE', f'https://api.github.com/repos/{REPO}/releases/assets/{asset["id"]}')

    url = (f'https://uploads.github.com/repos/{REPO}/releases/{rel["id"]}/assets'
           f'?name={urllib.parse.quote(zip_path.name)}')
    print(f'  上传 {zip_path.name} ({size:,} 字节) …')
    out = api('POST', url, data=zip_path.read_bytes(),
              headers={'Content-Type': 'application/zip'})
    print(f'  完成: {out["name"]} {out["size"]:,} 字节')
    print(f'  下载: {out["browser_download_url"]}')


if __name__ == '__main__':
    main()
