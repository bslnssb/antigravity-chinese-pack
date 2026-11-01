# -*- coding: utf-8 -*-
"""CDP 深度验证 v2：逐帧解析 + 事件队列；进入隔离世界调用翻译引擎做 oracle 测试"""
import json
import os
import re
import struct
import sys
import time
import urllib.request
from base64 import b64encode
from socket import create_connection

sys.stdout.reconfigure(encoding='utf-8')

port = int(open(os.path.expandvars(r'%APPDATA%\Antigravity\DevToolsActivePort')).readline().strip())
targets = json.loads(urllib.request.urlopen(f'http://127.0.0.1:{port}/json/list', timeout=5).read())
page = next(t for t in targets if t.get('type') == 'page' and t.get('url', '').startswith('http'))
print('page:', page['title'], '|', page['url'][:60])


class WS:
    def __init__(self, url):
        m = re.match(r'ws://([^:/]+):(\d+)(/.*)', url)
        self.s = create_connection((m.group(1), int(m.group(2))), timeout=10)
        self.s.settimeout(10)
        key = b64encode(os.urandom(16)).decode()
        self.s.sendall((f'GET {m.group(3)} HTTP/1.1\r\nHost: {m.group(1)}:{m.group(2)}\r\n'
                        'Upgrade: websocket\r\nConnection: Upgrade\r\n'
                        f'Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n').encode())
        buf = b''
        while b'\r\n\r\n' not in buf:
            buf += self.s.recv(4096)
        assert b'101' in buf.split(b'\r\n')[0]
        self.events = []
        self.next_id = 1

    def _read(self, n):
        buf = b''
        while len(buf) < n:
            c = self.s.recv(n - len(buf))
            if not c:
                raise ConnectionError('closed')
            buf += c
        return buf

    def _frame(self):
        b = self._read(2)
        op, ln = b[0] & 0x0F, b[1] & 0x7F
        if ln == 126:
            ln = struct.unpack('>H', self._read(2))[0]
        elif ln == 127:
            ln = struct.unpack('>Q', self._read(8))[0]
        return op, self._read(ln) if ln else b''

    def send(self, method, params=None):
        mid = self.next_id
        self.next_id += 1
        payload = json.dumps({'id': mid, 'method': method, 'params': params or {}}).encode()
        mask = os.urandom(4)
        n = len(payload)
        h = b'\x81' + (bytes([0x80 | 126]) + struct.pack('>H', n) if n < 65536
                       else bytes([0x80 | 127]) + struct.pack('>Q', n))
        if n < 126:
            h = b'\x81' + bytes([0x80 | n])
        self.s.sendall(h + mask + bytes(c ^ mask[i % 4] for i, c in enumerate(payload)))
        return mid

    def wait_response(self, mid, timeout_s=10):
        end = time.time() + timeout_s
        while time.time() < end:
            self.s.settimeout(max(0.1, end - time.time()))
            try:
                op, data = self._frame()
            except TimeoutError:
                continue
            if op == 8:
                raise ConnectionError('ws closed')
            if op == 9:
                self.s.sendall(b'\x8a\x00')  # ping -> pong
                continue
            if op not in (1, 2):
                continue
            try:
                msg = json.loads(data.decode('utf-8'))
            except Exception:
                continue
            if msg.get('id') == mid:
                return msg
            if 'method' in msg:
                self.events.append(msg)
        raise TimeoutError(f'no response for id {mid}')


ws = WS(page['webSocketDebuggerUrl'])
ws.send('Runtime.enable')
time.sleep(0.5)

# 收集执行上下文（enable 后立即会有事件）
contexts = {}
end = time.time() + 2.5
while time.time() < end:
    try:
        ws.s.settimeout(0.5)
        op, data = ws._frame()
    except TimeoutError:
        continue
    if op != 1:
        continue
    try:
        msg = json.loads(data.decode('utf-8'))
    except Exception:
        continue
    if msg.get('method') == 'Runtime.executionContextCreated':
        c = msg['params']['context']
        contexts[c['id']] = (c.get('name', ''), c.get('origin', '')[:60])
print('execution contexts:', contexts)


def ev(expr, ctx_id=None):
    params = {'expression': expr, 'returnByValue': True}
    if ctx_id:
        params['contextId'] = ctx_id
    mid = ws.send('Runtime.evaluate', params)
    r = ws.wait_response(mid)
    try:
        return r['result']['result'].get('value')
    except Exception:
        return f'<{json.dumps(r)[:200]}>'


found = None
for cid, (name, origin) in list(contexts.items()) + [(None, ('default-main-world', ''))]:
    try:
        t = ev('typeof globalThis.__agyTranslateText', cid)
    except Exception as e:
        t = f'<err {e}>'
    print(f'  ctx {cid} {name!r}: __agyTranslateText = {t}')
    if t == 'function' and found is None:
        found = cid

if found is not None:
    print(f'-- oracle via ctx {found}:')
    for s in ['Settings', 'New Chat', 'No Project', 'Automations', 'Projects',
              'Updating AI Memory With File', 'Open workspace', 'Cancel']:
        r = ev(f'globalThis.__agyTranslateText({json.dumps(s)})', found)
        print(f'   {s!r} -> {r!r}')
else:
    print('!! __agyTranslateText 未在任何上下文找到')

full = ev('document.body.innerText')
cjk = len(re.findall(r'[\u4e00-\u9fff]', full or ''))
print(f'-- full innerText: {len(full or "")} chars, CJK={cjk}')
print((full or '')[:1500])
