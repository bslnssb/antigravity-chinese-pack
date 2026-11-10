# -*- coding: utf-8 -*-
"""github.com 的 HTTPS 被网络掐断时，用 api.github.com 把本地提交推上去。

背景：`git push` 走 https://github.com，实测在部分网络下 TLS 握手被重置
（schannel / openssl 两条后端都报 unexpected eof），但 api.github.com 正常。
这里用 REST 的 git data 接口重建同一个提交：blob → tree → commit → 更新 ref。

用法:
    python scripts/push_via_api.py                 # 推 HEAD 到 origin/main
    python scripts/push_via_api.py --dry-run       # 只打印将要做什么

限制：父提交必须与远端一致（不 force）；上一次也是用本脚本推的，远端父提交 sha
     会和本地不同（API 重建的提交没有原始时间戳），这时加 --allow-diverge，
     以远端为父重建一个内容相同的提交。
"""
import argparse
import base64
import json
import subprocess
import sys
import urllib.error
import urllib.request

sys.stdout.reconfigure(encoding='utf-8')

REPO = 'bslnssb/antigravity-chinese-pack'
BRANCH = 'main'


def token():
    p = subprocess.run(['git', 'credential', 'fill'], input='protocol=https\nhost=github.com\n\n',
                       capture_output=True, text=True)
    for line in p.stdout.splitlines():
        if line.startswith('password='):
            return line.split('=', 1)[1]
    raise SystemExit('取不到 GitHub token')


TOKEN = token()


def api(method, path, data=None):
    url = path if path.startswith('http') else f'https://api.github.com/repos/{REPO}{path}'
    body = json.dumps(data, ensure_ascii=False).encode('utf-8') if data is not None else None
    req = urllib.request.Request(url, data=body, method=method, headers={
        'Authorization': 'token ' + TOKEN,
        'Accept': 'application/vnd.github+json',
        'Content-Type': 'application/json',
        'User-Agent': 'agy-zh-pack',
    })
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            raw = r.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        raise SystemExit(f'{method} {path} -> HTTP {e.code}: {e.read().decode("utf-8", "replace")[:400]}')


def git(*args, binary=False):
    out = subprocess.run(['git'] + list(args), capture_output=True)
    if out.returncode:
        raise SystemExit(f'git {" ".join(args)} 失败: {out.stderr.decode("utf-8", "replace")}')
    return out.stdout if binary else out.stdout.decode('utf-8').strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--allow-diverge', action='store_true',
                    help='远端 HEAD 与本地父提交不一致时，仍以远端为父重建提交（内容一致、sha 不同）')
    a = ap.parse_args()

    head = git('rev-parse', 'HEAD')
    parents = git('rev-list', '--parents', '-n', '1', head).split()[1:]
    if len(parents) != 1:
        raise SystemExit('只支持单父提交（合并提交请用 git push）')
    parent = parents[0]

    remote = api('GET', f'/git/ref/heads/{BRANCH}')
    remote_sha = remote['object']['sha']
    print(f'本地 HEAD   : {head[:12]}')
    print(f'本地父提交  : {parent[:12]}')
    print(f'远端 {BRANCH:<6}: {remote_sha[:12]}')
    if remote_sha != parent:
        if not a.allow_diverge:
            raise SystemExit('远端和本地父提交不一致，先 git pull / 不要用本脚本强推')
        print('  ⚠ 远端与本地父提交不同（上次是 API 重建的提交），'
              '以远端为父新建一个内容相同的提交')

    # --name-status：A/M 上传 blob，D 在 tree 里把 sha 置空即删除。
    # 必须关掉重命名检测，否则「改名」会输出成一条 R100 old new，旧路径删不掉。
    changed = []
    for line in git('diff', '--name-status', '--no-renames', parent, head).splitlines():
        parts = line.split('\t')
        status, path = parts[0], parts[-1]
        changed.append((status, path))
    print(f'待推送文件  : {len(changed)} 个')

    msg = git('log', '-1', '--pretty=%B', head)
    author_name = git('log', '-1', '--pretty=%an', head)
    author_email = git('log', '-1', '--pretty=%ae', head)

    if a.dry_run:
        for s, p in changed:
            print(f'  {s}  {p}')
        print('--dry-run，未写入远端')
        return

    blobs = []
    for status, path in changed:
        if status.startswith('D'):
            blobs.append({'path': path, 'mode': '100644', 'type': 'blob', 'sha': None})
            print(f'  del  {path}')
            continue
        content = git('show', f'{head}:{path}', binary=True)
        out = api('POST', '/git/blobs', {
            'content': base64.b64encode(content).decode('ascii'),
            'encoding': 'base64',
        })
        blobs.append({'path': path, 'mode': '100644', 'type': 'blob', 'sha': out['sha']})
        print(f'  blob {path} {len(content):,} 字节')

    base_tree = api('GET', f'/git/commits/{remote_sha}')['tree']['sha']
    tree = api('POST', '/git/trees', {'base_tree': base_tree, 'tree': blobs})
    commit = api('POST', '/git/commits', {
        'message': msg,
        'tree': tree['sha'],
        'parents': [remote_sha],
        'author': {'name': author_name, 'email': author_email},
        'committer': {'name': author_name, 'email': author_email},
    })
    api('PATCH', f'/git/refs/heads/{BRANCH}', {'sha': commit['sha'], 'force': False})
    print(f'\n已推送: {commit["sha"][:12]}  {commit["html_url"]}')
    print('本地与远端内容一致，但提交 sha 不同（API 重建的提交没有原始时间戳/签名）')


if __name__ == '__main__':
    main()
