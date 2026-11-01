// ============================================================================
// antigravity-zh-patch.js
// Version-correct Chinese patch builder for Antigravity (Electron app.asar).
//
// WHY: community Chinese packs ship a WHOLE replacement app.asar built for one
// specific Antigravity version. Dropping that in downgrades the app when the
// installed version is newer. This tool instead keeps the user's own app.asar as
// the base and swaps in only the few files a pack modifies, recomputing the
// per-file `integrity` hashes Electron validates.
//
// COMMANDS
//   inspect <asar> [asar2 ...]
//       Print header/file stats for one or more asar files.
//   list <asar> <out.json>
//       Dump every file entry (path,size,hash) to JSON, for diffing.
//   extract <asar> <outdir> <path> [path ...]
//       Extract files (useful to grab the pack's patched files).
//   build --base <asar> --out <asar> --swap <map.json>
//       Build a new asar: user's base with the map's files replaced.
//       map.json = { "dist/preload.js": "C:\\path\\to\\file", ... }
//   verify --base <asar> --out <asar> --expect <path,path,...>
//       Assert the output differs from base in exactly the expected files and
//       that every written file's integrity hash matches its content.
//
// ASAR HEADER LAYOUT OBSERVED IN ANTIGRAVITY (differs slightly from stock asar):
//   u32 @0  = 4
//   u32 @4  = headerSize  (dataStart = 8 + headerSize)
//   u32 @8  = headerSize - 4
//   u32 @12 = jsonLen
//   json    @16, zero padded so dataStart is 8-byte aligned
//
// INTEGRITY: each file entry may carry
//   integrity: { algorithm:"SHA256", hash:<sha256 of file>, blockSize:4194304,
//                blocks:[<sha256 per block>] }
// Swapped files MUST get a recomputed integrity object or Electron rejects the
// archive (symptom: app exits immediately, often code 9 or a silent quit).
// ============================================================================
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

function parseAsar(file) {
  const fd = fs.openSync(file, 'r');
  const probe = Buffer.alloc(64);
  fs.readSync(fd, probe, 0, 64, 0);
  let jsonStart = -1;
  for (let i = 4; i < 48; i++) {
    if (probe[i] === 0x7b && probe[i + 1] === 0x22) { jsonStart = i; break; }
  }
  if (jsonStart < 0) throw new Error('cannot locate JSON header in ' + file);
  const jsonLen = probe.readUInt32LE(jsonStart - 4);
  const headerSize = probe.readUInt32LE(4);
  const dataStart = 8 + headerSize;
  const jb = Buffer.alloc(jsonLen);
  fs.readSync(fd, jb, 0, jsonLen, jsonStart);
  const header = JSON.parse(jb.toString('utf8').replace(/\0+$/g, ''));
  return { fd, file, header, jsonStart, jsonLen, headerSize, dataStart, fileSize: fs.statSync(file).size };
}

function walk(asar) {
  const out = new Map();
  (function go(node, prefix) {
    for (const [name, meta] of Object.entries(node.files || {})) {
      const rel = prefix ? prefix + '/' + name : name;
      if (meta.files) { go(meta, rel); continue; }
      out.set(rel, meta);
    }
  })(asar.header, '');
  return out;
}

function readEntry(asar, meta) {
  const n = parseInt(meta.size, 10) || 0;
  const off = parseInt(meta.offset, 10);
  if (n > 0 && Number.isNaN(off)) return null; // unpacked entry: data lives in app.asar.unpacked
  const b = Buffer.alloc(n);
  if (n > 0) fs.readSync(asar.fd, b, 0, n, asar.dataStart + off);
  return b;
}

function entryHash(asar, meta) {
  if (meta.unpacked) return 'unpacked:' + (parseInt(meta.size, 10) || 0);
  const b = readEntry(asar, meta);
  return b === null ? 'noread:' + (parseInt(meta.size, 10) || 0) : sha256(b);
}

function sha256(buf) {
  return crypto.createHash('sha256').update(buf).digest('hex');
}

// ---------------------------------------------------------------- commands
function cmdInspect(asars) {
  for (const f of asars) {
    const a = parseAsar(f);
    const files = walk(a);
    let payload = 0;
    for (const [, m] of files) if (!m.unpacked) payload += parseInt(m.size, 10) || 0;
    console.log(`${f}`);
    console.log(`  files=${files.size} payload=${payload} dataStart=${a.dataStart} fileSize=${a.fileSize} selfConsistent=${a.dataStart + payload === a.fileSize}`);
    console.log(`  sha256=${sha256(fs.readFileSync(f))}`);
  }
}

function cmdList(asarFile, outJson) {
  const a = parseAsar(asarFile);
  const files = [];
  for (const [rel, m] of walk(a)) {
    files.push({ path: rel, size: parseInt(m.size, 10) || 0, hash: m.unpacked ? 'unpacked' : sha256(readEntry(a, m)), unpacked: !!m.unpacked });
  }
  files.sort((x, y) => x.path.localeCompare(y.path));
  fs.writeFileSync(outJson, JSON.stringify({ asar: asarFile, files }, null, 1));
  console.log(`wrote ${outJson} (${files.length} files)`);
}

function cmdExtract(asarFile, outDir, targets) {
  const a = parseAsar(asarFile);
  const files = walk(a);
  fs.mkdirSync(outDir, { recursive: true });
  for (const rel of targets) {
    const m = files.get(rel);
    if (!m) { console.error('MISSING ' + rel); continue; }
    const buf = readEntry(a, m);
    const out = path.join(outDir, rel.replace(/\//g, '__'));
    fs.writeFileSync(out, buf);
    console.log(`extracted ${rel} -> ${out} (${buf.length} bytes)`);
  }
}

function cmdBuild(opts) {
  const base = parseAsar(opts.base);
  const files = walk(base);
  const swaps = new Map();
  // strip UTF-8 BOM: PowerShell 5.1's Set-Content -Encoding UTF8 adds one
  const mapText = fs.readFileSync(opts.swap, 'utf8').replace(/^\uFEFF/, '');
  const map = JSON.parse(mapText);
  for (const [rel, localFile] of Object.entries(map)) {
    if (!files.has(rel)) { console.error(`ERROR: ${rel} not present in base asar`); process.exit(2); }
    swaps.set(rel, fs.readFileSync(localFile));
    console.error(`swap ${rel} <- ${localFile} (${swaps.get(rel).length} bytes)`);
  }

  // Rebuild data region in the same traversal order, reassigning offsets.
  const order = [];
  (function go(node, prefix) {
    for (const [name, meta] of Object.entries(node.files || {})) {
      const rel = prefix ? prefix + '/' + name : name;
      if (meta.files) { go(meta, rel); continue; }
      order.push(rel);
    }
  })(base.header, '');

  const chunks = [];
  let offset = 0;
  let unpackedKept = 0;
  for (const rel of order) {
    const meta = files.get(rel);
    const hasOffset = meta.offset !== undefined && meta.offset !== null && !Number.isNaN(parseInt(meta.offset, 10));
    const size = parseInt(meta.size, 10) || 0;
    if (meta.unpacked) { unpackedKept++; continue; } // lives in app.asar.unpacked, leave header as-is
    const data = swaps.has(rel) ? swaps.get(rel) : readEntry(base, meta);
    if (!hasOffset && size > 0 && !swaps.has(rel)) console.error(`  WARN no offset for ${rel}`);
    if (swaps.has(rel) && meta.integrity) {
      const h = sha256(data);
      meta.integrity = { algorithm: 'SHA256', hash: h, blockSize: meta.integrity.blockSize || 4194304, blocks: [h] };
    }
    meta.size = data.length;
    meta.offset = String(offset);
    chunks.push(data);
    offset += data.length;
  }
  console.error(`unpacked entries kept as-is: ${unpackedKept}`);

  const jsonStr = JSON.stringify(base.header);
  const jsonLen = Buffer.byteLength(jsonStr, 'utf8');
  let pad = 0;
  while ((16 + jsonLen + pad) % 8 !== 0) pad++;
  const headerSize = 8 + jsonLen + pad;
  const dataStart = 8 + headerSize;
  const prologue = Buffer.alloc(dataStart);
  prologue.writeUInt32LE(4, 0);
  prologue.writeUInt32LE(headerSize, 4);
  prologue.writeUInt32LE(headerSize - 4, 8);
  prologue.writeUInt32LE(jsonLen, 12);
  prologue.write(jsonStr, 16, 'utf8');

  const fdOut = fs.openSync(opts.out, 'w');
  fs.writeSync(fdOut, prologue, 0, prologue.length, 0);
  let pos = dataStart;
  for (const c of chunks) { fs.writeSync(fdOut, c, 0, c.length, pos); pos += c.length; }
  fs.closeSync(fdOut);
  const st = fs.statSync(opts.out);
  console.error(`WROTE ${opts.out} size=${st.size} dataStart=${dataStart} payload=${offset} selfConsistent=${st.size === pos}`);
}

function cmdVerify(opts) {
  const base = parseAsar(opts.base);
  const out = parseAsar(opts.out);
  const bf = walk(base), of = walk(out);
  const expect = new Set((opts.expect || '').split(',').map((s) => s.trim()).filter(Boolean));
  let ok = true;
  const added = [...of.keys()].filter((k) => !bf.has(k));
  const removed = [...bf.keys()].filter((k) => !of.has(k));
  if (added.length || removed.length) { ok = false; console.log(`FAIL added=${JSON.stringify(added)} removed=${JSON.stringify(removed)}`); }
  else console.log(`file set identical (${of.size} files)  OK`);

  const changed = [];
  for (const [rel, bm] of bf) {
    const om = of.get(rel);
    if (!om) continue;
    if (entryHash(base, bm) !== entryHash(out, om)) changed.push(rel);
  }
  const unexpected = changed.filter((c) => !expect.has(c));
  const missing = [...expect].filter((c) => !changed.includes(c));
  if (unexpected.length || missing.length) { ok = false; console.log(`FAIL unexpected=${JSON.stringify(unexpected)} expectedButUnchanged=${JSON.stringify(missing)}`); }
  else console.log(`changed exactly: ${changed.join(', ')}  OK`);

  for (const rel of expect) {
    const om = of.get(rel);
    if (!om) { ok = false; continue; }
    const h = sha256(readEntry(out, om));
    const good = om.integrity ? om.integrity.hash === h : false;
    if (!good) ok = false;
    console.log(`  integrity ${rel}: ${good ? 'VALID' : 'MISSING/MISMATCH'} size=${om.size}`);
  }
  const st = fs.statSync(opts.out);
  const payload = [...of.values()].filter((m) => !m.unpacked).reduce((s, m) => s + (parseInt(m.size, 10) || 0), 0);
  const consistent = out.dataStart + payload === st.size;
  if (!consistent) ok = false;
  console.log(`  archive self-consistent: ${consistent}`);
  console.log(ok ? '\nRESULT: ALL CHECKS PASSED' : '\nRESULT: FAILED - DO NOT INSTALL');
  process.exit(ok ? 0 : 1);
}

// ---------------------------------------------------------------- cli
const [cmd, ...rest] = process.argv.slice(2);
const opt = (name) => { const i = rest.indexOf('--' + name); return i >= 0 ? rest[i + 1] : undefined; };
try {
  if (cmd === 'inspect') cmdInspect(rest.length ? rest : []);
  else if (cmd === 'list') cmdList(rest[0], rest[1]);
  else if (cmd === 'extract') cmdExtract(rest[0], rest[1], rest.slice(2));
  else if (cmd === 'build') cmdBuild({ base: opt('base'), out: opt('out'), swap: opt('swap') });
  else if (cmd === 'verify') cmdVerify({ base: opt('base'), out: opt('out'), expect: opt('expect') });
  else { console.error('usage: inspect|list|extract|build|verify (see file header)'); process.exit(1); }
} catch (e) {
  console.error('ERROR: ' + e.message);
  process.exit(2);
}
