# -*- coding: utf-8 -*-
"""CDP 界面语言验证（纯 stdlib，替代 node 版 verify-ui-zh.js）
连接 Electron 的 DevTools 端点，读取各页面 document.body.innerText，统计中文占比。"""
import base64
import json
import os
import re
import socket
import struct
import sys
import urllib.request

sys.stdout.reconfigure(encoding='utf-8')

port = int(open(os.path.expandvars(r'%APPDATA%\Antigravity\DevToolsActivePort')).readline().strip())


def http_json(path):
    with urllib.request.urlopen(f'http://127.0.0.1:{port}{path}', timeout=5) as r:
        return json.loads(r.read().decode('utf-8'))


class WS:
    def __init__(self, url):
        m = re.match(r'ws://([^:/]+):(\d+)(/.*)', url)
        host, port_, path = m.group(1), int(m.group(2)), m.group(3)
        self.s = socket.create_connection((host, port_), timeout=8)
        key = base64.b64encode(os.urandom(16)).decode()
        req = (f'GET {path} HTTP/1.1\r\nHost: {host}:{port_}\r\n'
               'Upgrade: websocket\r\nConnection: Upgrade\r\n'
               f'Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n')
        self.s.sendall(req.encode())
        buf = b''
        while b'\r\n\r\n' not in buf:
            buf += self.s.recv(4096)
        assert b'101' in buf.split(b'\r\n')[0], buf[:120]

    def send_text(self, text):
        payload = text.encode('utf-8')
        mask = os.urandom(4)
        header = b'\x81'
        n = len(payload)
        if n < 126:
            header += bytes([0x80 | n])
        elif n < 65536:
            header += bytes([0x80 | 126]) + struct.pack('>H', n)
        else:
            header += bytes([0x80 | 127]) + struct.pack('>Q', n)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self.s.sendall(header + mask + masked)

    def recv_frame(self):
        def read(n):
            buf = b''
            while len(buf) < n:
                chunk = self.s.recv(n - len(buf))
                if not chunk:
                    raise ConnectionError('closed')
                buf += chunk
            return buf
        b1, b2 = read(2)
        op = b1 & 0x0F
        ln = b2 & 0x7F
        if ln == 126:
            ln = struct.unpack('>H', read(2))[0]
        elif ln == 127:
            ln = struct.unpack('>Q', read(8))[0]
        payload = read(ln) if ln else b''
        return op, payload

    def recv_text_until(self, needle, timeout_frames=60):
        seen = ''
        for _ in range(timeout_frames):
            op, payload = self.recv_frame()
            if op == 8:
                raise ConnectionError('ws closed')
            if op in (1, 0):
                seen += payload.decode('utf-8', errors='replace')
                if needle in seen:
                    return seen
        return seen


targets = http_json('/json/list')
pages = [t for t in targets if t.get('type') == 'page']
print(f'{len(pages)} page target(s):')
verdict = 'NO CHINESE FOUND'
for t in pages:
    url, title = t.get('url', '')[:70], t.get('title', '')[:40]
    ws_url = t.get('webSocketDebuggerUrl')
    if not ws_url:
        print(f'- {title} | {url} | (no ws url)')
        continue
    try:
        ws = WS(ws_url)
        expr = json.dumps({'id': 1, 'method': 'Runtime.evaluate',
                           'params': {'expression': 'document.body ? document.body.innerText.slice(0,3000) : ""',
                                      'returnByValue': True}})
        ws.send_text(expr)
        resp = ws.recv_text_until('"result"')
        ws.s.close()
        m = re.search(r'"value":\s*"((?:[^"\\]|\\.)*)"', resp)
        text = m.group(1).encode().decode('unicode_escape', errors='ignore') if m else ''
        text = text.encode('latin-1', errors='ignore').decode('utf-8', errors='ignore') if m else ''
        cjk = len(re.findall(r'[\u4e00-\u9fff]', text))
        print(f'- {title} | {url}')
        print(f'  text[{len(text)} chars] CJK={cjk} | sample: {text[:160]!r}')
        if cjk >= 10:
            verdict = 'CHINESE UI CONFIRMED'
    except Exception as e:
        print(f'- {title} | {url} | ERROR {type(e).__name__}: {e}')
print('VERDICT:', verdict)
