// 截当前窗口一帧，用于人工判读界面残留英文。
// 用法: node scripts/shot_now.js [输出png]
const fs = require('fs');
const path = require('path');
const http = require('http');

const portFile = path.join(process.env.APPDATA, 'Antigravity', 'DevToolsActivePort');
const port = parseInt(fs.readFileSync(portFile, 'utf8').trim().split(/\r?\n/)[0], 10);

function getJson(url) {
    return new Promise((resolve, reject) => {
        http.get(url, (res) => {
            let d = '';
            res.on('data', (c) => (d += c));
            res.on('end', () => { try { resolve(JSON.parse(d)); } catch (e) { reject(e); } });
        }).on('error', reject);
    });
}

function connect(wsUrl) {
    return new Promise((resolve, reject) => {
        const ws = new WebSocket(wsUrl);
        let id = 0;
        const pending = new Map();
        ws.onmessage = (ev) => {
            const m = JSON.parse(ev.data);
            if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
        };
        ws.onerror = reject;
        ws.onopen = () => resolve({
            call: (method, params) => new Promise((res, rej) => {
                const i = ++id;
                pending.set(i, (m) => (m.error ? rej(new Error(JSON.stringify(m.error))) : res(m.result)));
                ws.send(JSON.stringify({ id: i, method, params: params || {} }));
            }),
            close: () => ws.close(),
        });
    });
}

(async () => {
    const out = process.argv[2] || path.join(__dirname, '..', 'build', '_shot_now.png');
    const list = await getJson(`http://127.0.0.1:${port}/json/list`);
    const pages = list.filter((t) => t.type === 'page' && t.webSocketDebuggerUrl && !/devtools/.test(t.url));
    const target = pages.find((p) => p.title === 'Antigravity') || pages[0];
    const c = await connect(target.webSocketDebuggerUrl);
    await c.call('Page.enable');
    const r = await c.call('Page.captureScreenshot', { format: 'png', fromSurface: true });
    fs.mkdirSync(path.dirname(out), { recursive: true });
    fs.writeFileSync(out, Buffer.from(r.data, 'base64'));
    console.log('已保存 ' + out + ' (' + Math.round(fs.statSync(out).size / 1024) + ' KB)');
    c.close();
})().catch((e) => { console.error(e.message); process.exit(1); });
