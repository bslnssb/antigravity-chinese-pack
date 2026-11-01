// Port Chinese string edits from a community pack's main.js onto the local
// (newer) main.js, preserving local logic changes.
//
// Usage:
//   node port-main-zh.js <pack-orig-main.js> <pack-cn-main.js> <local-main.js> <out-main.js>
//
// How it works: pack-orig (English, version X) and pack-cn (Chinese, version X)
// have the same line count; every differing line pair is an English->Chinese
// replacement. Each pair is applied to <local-main.js> (version X+n). If a
// source line is absent locally it is skipped and reported.
const fs = require('fs');
const path = require('path');

const [origPath, cnPath, localPath, outPath] = process.argv.slice(2);
if (!origPath || !cnPath || !localPath || !outPath) {
  console.error('usage: node port-main-zh.js <pack-orig-main.js> <pack-cn-main.js> <local-main.js> <out-main.js>');
  process.exit(1);
}

const orig = fs.readFileSync(origPath, 'utf8');
const cn = fs.readFileSync(cnPath, 'utf8');
const local = fs.readFileSync(localPath, 'utf8');

const o = orig.split('\n');
const c = cn.split('\n');
let pairs = [];
if (o.length === c.length) {
  for (let i = 0; i < o.length; i++) if (o[i] !== c[i]) pairs.push([o[i], c[i]]);
} else {
  // fall back: pair up the differing regions by trimming order
  console.error(`WARN line counts differ (${o.length} vs ${c.length}); using trimmed-line alignment`);
  const ot = o.map((s) => s.trim()).filter(Boolean);
  const ct = c.map((s) => s.trim()).filter(Boolean);
  if (ot.length !== ct.length) { console.error('cannot align: trimmed line counts differ too'); process.exit(2); }
  for (let i = 0; i < ot.length; i++) if (ot[i] !== ct[i]) pairs.push([ot[i], ct[i]]);
}

console.log(`replacement pairs found: ${pairs.length}`);
let out = local;
let applied = 0;
for (const [en, zh] of pairs) {
  if (out.includes(en)) { out = out.split(en).join(zh); applied++; }
  else console.log(`  SKIP (not present locally): ${en.trim().slice(0, 100)}`);
}
console.log(`applied ${applied}/${pairs.length}`);

fs.mkdirSync(path.dirname(outPath), { recursive: true });
fs.writeFileSync(outPath, out, 'utf8');
console.log(`wrote ${outPath} (${Buffer.byteLength(out, 'utf8')} bytes; local was ${Buffer.byteLength(local, 'utf8')})`);
if (applied === 0) { console.error('ERROR: nothing applied — version may be incompatible'); process.exit(3); }
