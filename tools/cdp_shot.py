# -*- coding: utf-8 -*-
"""通过 CDP 给 Antigravity 窗口截图并读取界面文案

用法：
    python build/shot.py <输出目录> [标签]
不带标签时只截一张当前画面，用于判读；带标签时按预设序列截图。
"""
import base64
import json
import os
import re
import socket
import struct
import sys
import time
import urllib.request

sys.stdout.reconfigure(encoding='utf-8')
PORT = 9222


_opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def http_json(path):
    # 本机回环请求必须绕过系统代理（否则走 7897 会 502）
    with _opener.open(f'http://127.0.0.1:{PORT}{path}', timeout=6) as r:
        return json.loads(r.read().decode('utf-8'))


class WS:
    def __init__(self, url):
        m = re.match(r'ws://([^:/]+):(\d+)(/.*)', url)
        host, port_, path = m.group(1), int(m.group(2)), m.group(3)
        self.s = socket.create_connection((host, port_), timeout=20)
        key = base64.b64encode(os.urandom(16)).decode()
        req = (f'GET {path} HTTP/1.1\r\nHost: {host}:{port_}\r\n'
               'Upgrade: websocket\r\nConnection: Upgrade\r\n'
               f'Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n')
        self.s.sendall(req.encode())
        buf = b''
        while b'\r\n\r\n' not in buf:
            buf += self.s.recv(4096)
        assert b'101' in buf.split(b'\r\n')[0], buf[:120]
        self._id = 0

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

    def _read(self, n):
        buf = b''
        while len(buf) < n:
            chunk = self.s.recv(n - len(buf))
            if not chunk:
                raise ConnectionError('closed')
            buf += chunk
        return buf

    def recv_frame(self):
        b1, b2 = self._read(2)
        op = b1 & 0x0F
        ln = b2 & 0x7F
        if ln == 126:
            ln = struct.unpack('>H', self._read(2))[0]
        elif ln == 127:
            ln = struct.unpack('>Q', self._read(8))[0]
        return op, (self._read(ln) if ln else b'')

    def call(self, method, params=None):
        self._id += 1
        mid = self._id
        self.send_text(json.dumps({'id': mid, 'method': method, 'params': params or {}}))
        for _ in range(200):
            op, payload = self.recv_frame()
            if op == 8:
                raise ConnectionError('ws closed')
            try:
                obj = json.loads(payload.decode('utf-8', errors='replace'))
            except Exception:
                continue
            if obj.get('id') == mid:
                return obj
        raise TimeoutError(method)

    def eval(self, expr, await_promise=False):
        r = self.call('Runtime.evaluate', {
            'expression': expr, 'returnByValue': True,
            'awaitPromise': await_promise})
        return r.get('result', {}).get('result', {}).get('value')

    def shot(self, path):
        r = self.call('Page.captureScreenshot', {'format': 'png', 'fromSurface': True})
        data = r.get('result', {}).get('data')
        if not data:
            print('  截图失败:', json.dumps(r)[:200])
            return False
        with open(path, 'wb') as f:
            f.write(base64.b64decode(data))
        print(f'  已保存 {path} ({os.path.getsize(path) // 1024} KB)')
        return True


def main_page():
    pages = [t for t in http_json('/json/list')
             if t.get('type') == 'page' and not t.get('url', '').startswith('data:')]
    if not pages:
        raise SystemExit('没有找到页面 target')
    return max(pages, key=lambda t: len(t.get('url', '')))


if __name__ == '__main__':
    outdir = sys.argv[1] if len(sys.argv) > 1 else 'docs/screenshots'
    os.makedirs(outdir, exist_ok=True)
    page = main_page()
    print('target:', page.get('url', '')[:80], '|', page.get('title', '')[:40])
    ws = WS(page['webSocketDebuggerUrl'])
    ws.call('Page.enable')
    ws.call('Runtime.enable')
    text = ws.eval('document.body ? document.body.innerText.slice(0,600) : "(no body)"')
    print('--- 界面文案 ---')
    print(text)
    ws.shot(os.path.join(outdir, '_current.png'))
