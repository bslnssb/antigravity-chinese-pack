// 生成 README 用的界面截图：连运行中客户端的 CDP，按固定视口截主界面与设置面板。
//
// 用法:
//   node scripts/shot_readme.js [输出目录]
//   默认输出 build/readme_shots/
//
// 说明：截图前会用 Emulation.setDeviceMetricsOverride 把渲染视口临时放大到
// 1600x1150（dpr 2），这样设置面板能一屏放下、不被滚动条截断；截完立即清除，
// 用户窗口本身不变化。
const fs = require('fs');
const path = require('path');
const http = require('http');

const portFile = path.join(process.env.APPDATA, 'Antigravity', 'DevToolsActivePort');
let port = parseInt(fs.readFileSync(portFile, 'utf8').trim().split(/\r?\n/)[0], 10);

const outDir = process.argv[2] || path.join(__dirname, '..', 'build', 'readme_shots');
// 1250 是「常规设置」一屏放得下（无滚动条）的最小高度，实测 1150 会截断
const VIEW = { width: 1600, height: 1250, deviceScaleFactor: 2, mobile: false };

// 截图前临时隐藏个人信息：首页问候语带账户名，设置面板左下角带头像/邮箱。
// 只做展示用，截完立即移除，不改动用户数据。
const CLEAN_CSS = `
.home-greeting-title, [data-testid="settings-nav-item-Account"] { visibility: hidden !important; }
`;
const INJECT = `(() => {
  let s = document.getElementById('rd-clean');
  if (!s) { s = document.createElement('style'); s.id = 'rd-clean'; document.head.appendChild(s); }
  s.textContent = ${JSON.stringify(CLEAN_CSS)};
  return 'INJECTED';
})()`;
const REMOVE = `(() => { const s = document.getElementById('rd-clean'); if (s) s.remove(); return 'REMOVED'; })()`;

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
        ws.onerror = () => reject(new Error('websocket 连接失败'));
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

// 点击文本完全相等的可见叶子节点，取面积最大的那个
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
    // 端口自愈：动态端口重启后 DevToolsActivePort 常停留在旧值
    const probe = (p) => new Promise((res) => {
        const req = http.get(`http://127.0.0.1:${p}/json/version`, (r) => { r.resume(); res(r.statusCode === 200); });
        req.on('error', () => res(false));
        req.setTimeout(800, () => { req.destroy(); res(false); });
    });
    if (!(await probe(port))) {
        const cands = [];
        for (let d = 1; d <= 40; d++) cands.push(port + d);
        for (let p = 10989; p <= 11020; p++) cands.push(p);
        for (const p of cands) {
            if (await probe(p)) { console.log(`端口 ${p} 可达（文件值已失效，自动探测）`); port = p; break; }
        }
    }

    const list = await getJson(`http://127.0.0.1:${port}/json/list`);
    const pages = list.filter((t) => t.type === 'page' && /^https:/.test(t.url));
    const target = pages.find((p) => p.title === 'Antigravity') || pages[0];
    if (!target) throw new Error('找不到客户端页面，请先启动 Antigravity');

    const c = await connect(target.webSocketDebuggerUrl);
    await c.call('Page.enable');
    fs.mkdirSync(outDir, { recursive: true });

    const shoot = async (name) => {
        const shot = await c.call('Page.captureScreenshot', { format: 'png', fromSurface: true });
        const file = path.join(outDir, name + '.png');
        fs.writeFileSync(file, Buffer.from(shot.data, 'base64'));
        console.log(`  已保存 ${path.basename(file)} (${Math.round(fs.statSync(file).size / 1024)} KB)`);
    };

    await c.call('Emulation.setDeviceMetricsOverride', VIEW);
    await sleep(1200);

    // 1. 回主界面（关掉可能开着的设置面板/弹层）
    for (let i = 0; i < 2; i++) {
        await c.call('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 });
        await c.call('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 });
        await sleep(350);
    }
    await c.evaluate(clickExpr('关闭'));
    await sleep(1200);
    // 新建会话 -> 空白首页
    console.log('新建会话: ' + (await c.evaluate(clickExpr('新建会话'))));
    await sleep(1200);
    console.log('隐藏账户信息: ' + (await c.evaluate(INJECT)));
    await sleep(400);
    console.log('主界面:');
    await shoot('main');

    // 2. 设置面板逐页
    console.log('打开设置: ' + (await c.evaluate(clickExpr('设置'))));
    await sleep(1500);
    const PANELS = [
        ['settings-general', '常规设置'],
        ['settings-appearance', '外观设置'],
        ['settings-app', '应用设置'],
        ['settings-browser', '浏览器设置'],
    ];
    for (const [file, label] of PANELS) {
        console.log(`切到「${label}」: ` + (await c.evaluate(clickExpr(label))));
        await sleep(1200);
        await shoot(file);
    }

    console.log('恢复界面: ' + (await c.evaluate(REMOVE)));
    await c.call('Emulation.clearDeviceMetricsOverride', {});
    c.close();
    console.log(`\n完成，输出目录 ${outDir}`);
})().catch((e) => { console.error('失败: ' + e.message); process.exit(1); });
