// Verify the live Antigravity UI language via Chrome DevTools Protocol.
// Usage: node verify-ui-zh.js
// Exits 0 when the visible UI text contains enough Chinese to count as patched.
const fs = require('fs');
const path = require('path');
const http = require('http');

const portFile = path.join(process.env.APPDATA, 'Antigravity', 'DevToolsActivePort');
if (!fs.existsSync(portFile)) { console.error('DevToolsActivePort not found: ' + portFile); process.exit(2); }
const port = parseInt(fs.readFileSync(portFile, 'utf8').trim().split(/\r?\n/)[0], 10);
console.log('DevTools port = ' + port);

function getJson(url) {
  return new Promise((resolve, reject) => {
    http.get(url, (res) => {
      let d = '';
      res.on('data', (c) => (d += c));
      res.on('end', () => { try { resolve(JSON.parse(d)); } catch (e) { reject(new Error('bad json')); } });
    }).on('error', reject);
  });
}

(async () => {
  const list = await getJson(`http://127.0.0.1:${port}/json/list`);
  const pages = list.filter((t) => t.type === 'page' && t.webSocketDebuggerUrl);
  if (!pages.length) { console.error('no page target'); process.exit(2); }
  const target = pages[0];
  console.log('target: ' + target.title);
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  let id = 0;
  const pending = new Map();
  const send = (method, params) => new Promise((res) => { const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); });
  ws.onmessage = (ev) => {
    const m = JSON.parse(ev.data);
    if (m.id && pending.has(m.id)) { pending.get(m.id)(m.result); pending.delete(m.id); }
  };
  ws.onopen = async () => {
    const expr = `JSON.stringify({
      title: document.title,
      text: (document.body ? document.body.innerText : '').slice(0, 4000),
      items: Array.from(document.querySelectorAll('[role=menuitem], button')).slice(0,60).map(e=>e.innerText).filter(Boolean)
    })`;
    const r = await send('Runtime.evaluate', { expression: expr, returnByValue: true });
    const raw = r && r.result && r.result.value;
    if (!raw) { console.error('no result'); process.exit(2); }
    const d = JSON.parse(raw);
    const zh = (d.text.match(/[\u4e00-\u9fff]/g) || []).length;
    console.log('title: ' + d.title);
    console.log('visible text: ' + d.text.length + ' chars, chinese: ' + zh);
    console.log('---- text ----');
    console.log(d.text.slice(0, 800));
    console.log('---- controls ----');
    console.log(d.items.slice(0, 30).join(' | '));
    const ok = zh >= 20;
    console.log('\nVERDICT: ' + (ok ? 'CHINESE UI CONFIRMED' : 'NOT CHINESE (patch not active)'));
    ws.close();
    process.exit(ok ? 0 : 1);
  };
  ws.onerror = () => process.exit(2);
  setTimeout(() => { console.error('timeout'); process.exit(2); }, 20000);
})();
