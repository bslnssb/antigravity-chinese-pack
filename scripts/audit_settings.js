// 设置面板全量文案审计：连 CDP，打开设置，逐个左栏入口点击并收集可见文本，
// 输出「仍是英文 / 半中半英」的清单，供补词典用。
// 用法: node scripts/audit_settings.js [输出json]
const fs = require('fs');
const path = require('path');
const http = require('http');

const portFile = path.join(process.env.APPDATA, 'Antigravity', 'DevToolsActivePort');
const portArg = (process.argv.find((a) => a.startsWith('--port=')) || '').slice('--port='.length);
let port = portArg ? parseInt(portArg, 10) : (fs.existsSync(portFile) ? parseInt(fs.readFileSync(portFile, 'utf8').trim().split(/\r?\n/)[0], 10) : 0);
if (!port) { console.error('DevToolsActivePort 不存在且未指定 --port'); process.exit(2); }

const getJson = (u) => new Promise((res, rej) => http.get(u, (r) => {
    let d = ''; r.on('data', (c) => (d += c));
    r.on('end', () => { try { res(JSON.parse(d)); } catch (e) { rej(e); } });
}).on('error', rej));

function connect(wsUrl) {
    return new Promise((resolve, reject) => {
        const ws = new WebSocket(wsUrl);
        let id = 0; const p = new Map();
        ws.onmessage = (e) => {
            const m = JSON.parse(e.data);
            if (m.id && p.has(m.id)) { p.get(m.id)(m); p.delete(m.id); }
        };
        ws.onerror = reject;
        ws.onopen = () => resolve({
            send: (method, params) => new Promise((r) => { const i = ++id; p.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); }),
            close: () => ws.close(),
        });
    });
}

const COLLECT = `(() => {
  const texts = new Set();
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  let n;
  while ((n = walker.nextNode())) {
    const el = n.parentElement; if (!el) continue;
    const tag = el.tagName;
    if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'NOSCRIPT') continue;
    const cs = getComputedStyle(el);
    if (cs.display === 'none' || cs.visibility === 'hidden' || cs.opacity === '0') continue;
    const t = (n.nodeValue || '').replace(/\\s+/g, ' ').trim();
    if (t && t.length <= 400) texts.add(t);
  }
  document.querySelectorAll('[placeholder],[title],[aria-label]').forEach((el) => {
    ['placeholder', 'title', 'aria-label'].forEach((a) => {
      const v = el.getAttribute(a);
      if (v && v.trim() && v.trim().length <= 400) texts.add(v.replace(/\\s+/g, ' ').trim());
    });
  });
  return JSON.stringify([...texts]);
})()`;

const CLICK = (label) => `(() => {
  const want = ${JSON.stringify(label)};
  const cands = [...document.querySelectorAll('button,[role="tab"],[role="menuitem"],a,div,span')];
  const hit = cands.find((el) => el.textContent.trim() === want && el.offsetParent !== null);
  if (!hit) return 'NOTFOUND';
  hit.click();
  return 'CLICKED';
})()`;

const HAS_CJK = /[\u4e00-\u9fff]/;
const WORDY = /[A-Za-z]{2,}/;
const KEEP = ['Antigravity','Google','Gemini','Claude','GPT','MCP','API','CLI','SDK','IDE','Turbo','Pro','Ultra','AI','Token','Tokens','Agent','Agents','VS Code','Git','GitHub','WSL','Docker','Python','Node','JSON','YAML','URL','Windows','macOS','Linux','Chrome','Edge','Browser','Workspace','AGENTS.md','user_global','GEMINI.md','CLAUDE.md','JavaScript','TypeScript','Catppuccin','Solarized','Jetski','Chat','Live','plan','Review','Fill','px','Sans','Default','Voice','Mode','md','js','ts','py'];
const stripKeep = (s) => { let r = s; for (const k of [...KEEP].sort((a, b) => b.length - a.length)) r = r.split(k).join(' '); return r; };
const classify = (s) => {
    const body = stripKeep(s);
    if (!WORDY.test(body)) return 'ok';
    if (!HAS_CJK.test(s)) return 'untranslated';
    return 'mixed';
};

(async () => {
    // 端口自愈：动态端口重启后 DevToolsActivePort 常停留在旧值
    const probe = (p) => new Promise((res) => {
        const req = http.get(`http://127.0.0.1:${p}/json/version`, (r) => { r.resume(); res(r.statusCode === 200); });
        req.on('error', () => res(false));
        req.setTimeout(800, () => { req.destroy(); res(false); });
    });
    if (!(await probe(port))) {
        const cands = [];
        for (let d = 1; d <= 30; d++) cands.push(port + d);
        for (let p = 10989; p <= 11020; p++) cands.push(p);
        for (const p of cands) {
            if (await probe(p)) { port = p; console.log(`端口 ${port} 可达（文件值已失效，已自动探测）`); break; }
        }
    }
    const list = await getJson(`http://127.0.0.1:${port}/json/list`);
    const t = list.find((p) => p.type === 'page' && /^https?:/.test(p.url));
    const c = await connect(t.webSocketDebuggerUrl);

    // 打开设置：先找入口，再退回 Ctrl+,
    const openExpr = `(() => {
      const hit = [...document.querySelectorAll('[aria-label],[title]')].find((el) => /^(设置|Settings)$/.test(el.getAttribute('aria-label') || el.getAttribute('title') || ''));
      if (hit) { hit.click(); return 'CLICKED'; }
      return 'NOTFOUND';
    })()`;
    let r = await c.send('Runtime.evaluate', { expression: openExpr, returnByValue: true });
    console.log('打开设置:', r.result.result.value);
    if (r.result.result.value !== 'CLICKED') {
        await c.send('Input.dispatchKeyEvent', { type: 'keyDown', modifiers: 2, key: ',', code: 'Comma', windowsVirtualKeyCode: 188 });
        await c.send('Input.dispatchKeyEvent', { type: 'keyUp', modifiers: 2, key: ',', code: 'Comma', windowsVirtualKeyCode: 188 });
    }
    await new Promise((ok) => setTimeout(ok, 1500));

    // 左栏入口（中英都试，兼容未汉化状态）
    const TABS = ['常规设置', 'General', '应用设置', 'Application', '外观设置', 'Appearance', '快捷键', 'Keyboard Shortcuts', '系统通知', 'Notifications', '模型配置', 'Models', '浏览器设置', 'Browser'];
    const seen = new Set();
    const rows = [];
    const record = (scope, texts) => {
        for (const tx of texts) {
            const k = scope + '\u0000' + tx;
            if (seen.has(k)) continue;
            seen.add(k);
            rows.push({ scope, text: tx, kind: classify(tx) });
        }
    };

    let snap = JSON.parse((await c.send('Runtime.evaluate', { expression: COLLECT, returnByValue: true })).result.result.value);
    record('(initial)', snap);

    const tabsFound = [];
    for (const label of TABS) {
        const cr = await c.send('Runtime.evaluate', { expression: CLICK(label), returnByValue: true });
        if (cr.result.result.value === 'CLICKED') {
            tabsFound.push(label);
            await new Promise((ok) => setTimeout(ok, 1200));
            snap = JSON.parse((await c.send('Runtime.evaluate', { expression: COLLECT, returnByValue: true })).result.result.value);
            record(label, snap);
        }
    }
    c.close();

    const bad = rows.filter((x) => x.kind !== 'ok');
    const out = process.argv[2] || path.join(__dirname, '..', 'build', '_settings_audit.json');
    fs.writeFileSync(out, JSON.stringify({ tabsFound, all: rows, bad }, null, 1), 'utf8');
    console.log('点到的入口:', tabsFound.join(' / '));
    console.log(`文本 ${rows.length} 条，问题 ${bad.length} 条 → ${out}\n`);
    for (const b of bad) console.log(`[${b.kind === 'untranslated' ? 'EN ' : 'MIX'}] ${JSON.stringify(b.text)}`);
})();
