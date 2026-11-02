// 连运行中客户端的 CDP，打开设置面板并按页截图，用于 README 展示。
//
// 用法:
//   node scripts/shot_settings.js <输出目录> [页签名...]
//   node scripts/shot_settings.js build/shots 常规设置 外观设置
//
// 不传页签名时，默认截「常规设置」。截图前会点一次左下角「设置」。
const fs = require('fs');
const path = require('path');
const http = require('http');

const portFile = path.join(process.env.APPDATA, 'Antigravity', 'DevToolsActivePort');
const port = parseInt(fs.readFileSync(portFile, 'utf8').trim().split(/\r?\n/)[0], 10);

const outDir = process.argv[2] || path.join(__dirname, '..', 'build', 'shots');
const panels = process.argv.slice(3);
if (!panels.length) panels.push('常规设置');

const sleep = (ms) => new Promise((ok) => setTimeout(ok, ms));

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
            evaluate: (expr) => new Promise((res, rej) => {
                const i = ++id;
                pending.set(i, (m) => {
                    if (m.error) return rej(new Error(JSON.stringify(m.error)));
                    const r = m.result && m.result.result;
                    if (!r) return rej(new Error('no result'));
                    if (r.subtype === 'error') return rej(new Error(r.description || 'eval error'));
                    res(r.value);
                });
                ws.send(JSON.stringify({
                    id: i,
                    method: 'Runtime.evaluate',
                    params: { expression: expr, returnByValue: true, awaitPromise: true },
                }));
            }),
            close: () => ws.close(),
        });
    });
}

// 点击文本完全相等的叶子节点。优先在可见容器内找，避免点到背后页面。
const clickExpr = (label) => `(() => {
  const want = ${JSON.stringify(label)};
  const vis = [...document.querySelectorAll('*')].filter((el) => {
    if (el.children.length) return false;
    if (el.textContent.trim() !== want) return false;
    const r = el.getBoundingClientRect();
    if (r.width < 4 || r.height < 4) return false;
    const s = getComputedStyle(el);
    return s.visibility !== 'hidden' && s.display !== 'none' && s.opacity !== '0';
  });
  if (!vis.length) return 'NOTFOUND';
  // 取面积最大的那个（通常是真正的按钮/导航项，而不是内层 span）
  vis.sort((a, b) => {
    const ra = a.getBoundingClientRect(), rb = b.getBoundingClientRect();
    return rb.width * rb.height - ra.width * ra.height;
  });
  const el = vis[0];
  el.scrollIntoView({ block: 'center' });
  el.click();
  return 'CLICKED';
})()`;

(async () => {
    const list = await getJson(`http://127.0.0.1:${port}/json/list`);
    const pages = list.filter((t) => t.type === 'page' && t.webSocketDebuggerUrl && !/devtools/.test(t.url));
    const target = pages.find((p) => p.title === 'Antigravity') || pages[0];
    if (!target) throw new Error('找不到客户端页面，请先启动 Antigravity');

    const c = await connect(target.webSocketDebuggerUrl);
    await c.call('Page.enable');
    fs.mkdirSync(outDir, { recursive: true });

    // 1. 打开设置（已打开时点击无副作用）
    const opened = await c.evaluate(clickExpr('设置'));
    console.log('打开设置: ' + opened);
    if (opened === 'NOTFOUND') {
        // 已经在设置面板里也算正常
        console.log('  提示: 未找到「设置」按钮，假设面板已打开');
    }
    await sleep(1500);

    // 2. 逐页截图
    for (const [i, panel] of panels.entries()) {
        const r = await c.evaluate(clickExpr(panel));
        console.log(`切到「${panel}」: ${r}`);
        await sleep(1100);
        const shot = await c.call('Page.captureScreenshot', { format: 'png', fromSurface: true });
        const file = path.join(outDir, `${String(i + 1).padStart(2, '0')}-${panel}.png`);
        fs.writeFileSync(file, Buffer.from(shot.data, 'base64'));
        console.log(`  已保存 ${file} (${Math.round(fs.statSync(file).size / 1024)} KB)`);
    }

    c.close();
})().catch((e) => { console.error('失败: ' + e.message); process.exit(1); });
