// 扫真实界面：连上 Antigravity 的 CDP，收集窗口内所有可见文本，列出仍未翻译 / 半中半英的条目。
// 引擎跑在 preload 隔离上下文，CDP 主世界访问不到它，所以不做引擎判定——
// DOM 里呈现的就是翻译后的结果，直接对结果做语言判定。
// 用法: node scripts/scan_ui.js [输出json] [--click=文本]
const fs = require('fs');
const path = require('path');
const http = require('http');

const portFile = path.join(process.env.APPDATA, 'Antigravity', 'DevToolsActivePort');
if (!fs.existsSync(portFile)) { console.error('DevToolsActivePort 不存在'); process.exit(2); }
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

const COLLECT = `(() => {
  const texts = new Set();
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  let n;
  while ((n = walker.nextNode())) {
    const el = n.parentElement;
    if (!el) continue;
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
  return JSON.stringify({ texts: [...texts], title: document.title });
})()`;

const clickExpr = (label) => `(() => {
  const want = ${JSON.stringify(label)};
  const all = [...document.querySelectorAll('*')];
  const hit = all.find((el) => el.children.length === 0 && el.textContent.trim() === want);
  if (!hit) return 'NOTFOUND';
  hit.click();
  return 'CLICKED';
})()`;

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
            evaluate: (expr) => new Promise((res, rej) => {
                const i = ++id;
                pending.set(i, (m) => {
                    if (m.error) return rej(new Error(JSON.stringify(m.error)));
                    const r = m.result && m.result.result;
                    if (!r) return rej(new Error('no result'));
                    if (r.subtype === 'error') return rej(new Error(r.description || 'eval error'));
                    res(r.value);
                });
                ws.send(JSON.stringify({ id: i, method: 'Runtime.evaluate', params: { expression: expr, returnByValue: true, awaitPromise: true } }));
            }),
            close: () => ws.close(),
        });
    });
}

const HAS_CJK = /[\u4e00-\u9fff]/;
const WORDY = /[A-Za-z]{2,}/;

// 品牌 / 技术名词白名单：出现在中文里不算「没翻」
const KEEP = [
    'Antigravity', 'Google', 'Gemini', 'Claude', 'GPT', 'MCP', 'API', 'CLI', 'SDK', 'IDE',
    'Turbo', 'Pro', 'Ultra', 'AI', 'Token', 'Tokens', 'Agent', 'Agents', 'Gemini API',
    'VS Code', 'Git', 'GitHub', 'WSL', 'Docker', 'Python', 'Node', 'JSON', 'YAML', 'URL',
    'Windows', 'macOS', 'Linux', 'Chrome', 'Edge', 'Browser', 'Workspace',
    'AGENTS.md', 'user_global', 'GEMINI.md', 'CLAUDE.md', 'md', 'js', 'ts', 'py',
    'Catppuccin', 'One', 'Solarized', 'Light', 'Dark', 'Remote', 'Preview',
    'Oracle', 'Sequential', 'Thinking', 'Sonatype', 'Firebase', 'Android', 'Dart', 'Flutter',
    'Kubernetes', 'Engine', 'Bigtable', 'Apigee', 'Home', 'Developer', 'Catalog',
];

function stripKeep(s) {
    let r = s;
    // 长的先剥，避免 "Gemini API" 被 "Gemini" 提前剥掉一半
    for (const k of [...KEEP].sort((a, b) => b.length - a.length)) {
        r = r.split(k).join(' ');
    }
    return r;
}

function classify(s) {
    const body = stripKeep(s);
    if (!WORDY.test(body)) return 'ok';
    // 去掉剩余英文后，若还剩 2 个字母以上的连续英文 → 有问题
    if (!HAS_CJK.test(s)) return 'untranslated';
    return 'mixed';
}

(async () => {
    const list = await getJson(`http://127.0.0.1:${port}/json/list`);
    const pages = list.filter((t) => t.type === 'page' && t.webSocketDebuggerUrl);
    if (!pages.length) { console.error('没有可用的页面目标'); process.exit(2); }
    const target = pages.find((p) => !/devtools/.test(p.url)) || pages[0];
    console.log('目标页面: ' + (target.title || target.url));

    const c = await connect(target.webSocketDebuggerUrl);
    await c.evaluate('1');

    const clickArgs = process.argv.filter((a) => a.startsWith('--click=')).map((a) => a.slice('--click='.length));
    for (const label of clickArgs) {
        const r = await c.evaluate(clickExpr(label));
        console.log(`点击「${label}」: ${r}`);
        await new Promise((ok) => setTimeout(ok, 1200));
    }

    const snap = JSON.parse(await c.evaluate(COLLECT));
    c.close();

    const rows = snap.texts.map((t) => ({ text: t, kind: classify(t) }));
    const untranslated = rows.filter((r) => r.kind === 'untranslated').map((r) => r.text);
    const mixed = rows.filter((r) => r.kind === 'mixed').map((r) => r.text);

    const outFile = process.argv[2] && !process.argv[2].startsWith('--')
        ? process.argv[2]
        : path.join(__dirname, '..', 'build', '_ui_scan.json');
    fs.mkdirSync(path.dirname(outFile), { recursive: true });
    fs.writeFileSync(outFile, JSON.stringify({ title: snap.title, all: snap.texts, untranslated, mixed }, null, 2), 'utf8');

    console.log(`\n窗口标题: ${snap.title}   可见文本 ${rows.length} 条`);
    console.log(`\n=== 整条未翻译（${untranslated.length}）===`);
    for (const t of untranslated) console.log('  ' + JSON.stringify(t));
    console.log(`\n=== 半中半英（${mixed.length}）===`);
    for (const t of mixed) console.log('  ' + JSON.stringify(t));
    console.log(`\n已写入 ${outFile}`);
})();
