#!/usr/bin/env node
/*
 * Antigravity 中文包 —— 现场移植器
 *
 * 解决的问题：官方更新到 N+1，本仓库的 N+1 中文包还没发布。以前的处理是
 * "先用英文版"，对看不懂英文的人等于废掉。这个脚本用**新版本官方 asar 做底座**，
 * 把手里旧版本的译文搬过去 —— 功能是新版的，界面是中文的。
 *
 * 为什么不是整包替换：旧版 asar 会把应用代码一起降级，轻则缺功能重则白屏。
 * 这里只搬"英文→中文"的字符串替换对，代码全部来自新版官方。
 *
 * 运行环境：不需要装 Node/Python。Antigravity 自带 Electron，设
 * ELECTRON_RUN_AS_NODE=1 后它就是一个 Node（实测 v24.21.0）：
 *
 *     Antigravity.exe tools\port\port.js --base <新版官方asar> --out <输出> --ref 2.28.2
 *
 * 为什么翻译记忆是预计算的（tools/patches/memory-<ref>.json）：
 * 提取记忆要用 Python difflib.SequenceMatcher（Ratcliff/Obershelp），JS 没有
 * 等价物，自己实现又慢又容易偏。同一对版本的结果是固定的，所以离线算好、随包
 * 分发；运行期只剩"读 asar → 套替换 → 重打包"，几百行纯 JS 就够。
 *
 * 输出：stdout 只打 ASCII 的 KEY=VALUE（Windows 控制台按 GBK 解 UTF-8，中文会乱），
 * 详细过程写进 --log 指定的文件（UTF-8）。
 */

'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const BLOCK = 4194304; // Electron asar integrity 分块大小
const QUOTES = new Set(['"', "'", '`']);
const MAX_STR = 600;

const SIX = {
    'dist/preload.js': 'dist_preload.js',
    'dist/main.js': 'dist_main.js',
    'dist/menu.js': 'dist_menu.js',
    'dist/tray.js': 'dist_tray.js',
    'dist/ideInstall/wizardHtml.js': 'dist_ideInstall_wizardHtml.js',
    'dist/ipcHandlers.js': 'dist_ipcHandlers.js',
};

// ---------------------------------------------------------------- 输出

let logLines = [];
function log(...args) {
    logLines.push(args.join(' '));
}
function emit(kv) {
    // 同时写进 stdout 和日志文件：Electron 是 GUI 子系统，被 PowerShell 的
    // & 调用时 stdout 有可能拿不到，所以「结果以日志文件为准，stdout 只是辅助」
    log('RESULT ' + JSON.stringify(kv));
    for (const k of Object.keys(kv)) process.stdout.write(`${k}=${kv[k]}\n`);
}
function die(code, msg) {
    log('FAIL: ' + msg);
    emit({ RESULT: 'error', CODE: code, DETAIL: msg.replace(/[\r\n]+/g, ' ') });
    flushLog();
    process.exit(code);
}
function flushLog() {
    if (FLAGS.log) {
        try {
            fs.writeFileSync(FLAGS.log, logLines.join('\n') + '\n', 'utf8');
        } catch (e) {
            /* 日志写不了不影响主流程 */
        }
    }
}

// ---------------------------------------------------------------- asar 读写

function readAsar(p) {
    const raw = fs.readFileSync(p);
    // 布局：@0=4 @4=headerSize @8=headerSize-4 @12=jsonLen；dataStart=8+headerSize
    const headerSize = raw.readUInt32LE(4);
    const jsonLen = raw.readUInt32LE(12);
    const header = JSON.parse(raw.slice(16, 16 + jsonLen).toString('utf8'));
    return { header, dataStart: 8 + headerSize, raw };
}

function* leaves(node, prefix) {
    prefix = prefix || '';
    if (node.files) {
        for (const k of Object.keys(node.files)) {
            yield* leaves(node.files[k], prefix + '/' + k);
        }
    } else if (node.offset !== undefined) {
        yield [prefix.replace(/^\//, ''), node];
    }
}

function integrity(buf) {
    const blocks = [];
    for (let i = 0; i < buf.length; i += BLOCK) {
        blocks.push(crypto.createHash('sha256').update(buf.slice(i, i + BLOCK)).digest('hex'));
    }
    return {
        algorithm: 'SHA256',
        hash: crypto.createHash('sha256').update(buf).digest('hex'),
        blockSize: BLOCK,
        blocks: blocks,
    };
}

function extract(parsed, inner) {
    let node = parsed.header;
    for (const part of inner.split('/')) node = node.files[part];
    const off = Number(node.offset);
    return parsed.raw.slice(parsed.dataStart + off, parsed.dataStart + off + node.size);
}

function buildAsar(basePath, outPath, swap) {
    const { header, dataStart, raw } = readAsar(basePath);
    const parts = [];
    let pos = 0;
    let n = 0;
    for (const [p, node] of leaves(header)) {
        let content;
        if (Object.prototype.hasOwnProperty.call(swap, p)) {
            content = swap[p];
            n++;
        } else {
            const off = Number(node.offset);
            content = raw.slice(dataStart + off, dataStart + off + node.size);
        }
        node.offset = String(pos); // 与 Python 侧一致：写成字符串
        node.size = content.length;
        node.integrity = integrity(content);
        parts.push(content);
        pos += content.length;
    }
    const payload = Buffer.concat(parts);
    const jbytes = Buffer.from(JSON.stringify(header), 'utf8');
    const headerSize = jbytes.length + 9;
    const head = Buffer.alloc(16);
    head.writeUInt32LE(4, 0);
    head.writeUInt32LE(headerSize, 4);
    head.writeUInt32LE(headerSize - 4, 8);
    head.writeUInt32LE(jbytes.length, 12);
    fs.writeFileSync(outPath, Buffer.concat([head, jbytes, Buffer.from([0]), payload]));
    return { swapped: n, payloadSize: payload.length };
}

/** 自检：out 与 base 逐文件比，统计不同项与 integrity 是否自洽 */
function compareAsar(basePath, outPath) {
    const a = readAsar(basePath);
    const b = readAsar(outPath);
    const la = new Map(leaves(a.header));
    const lb = new Map(leaves(b.header));
    let same = 0;
    const diffs = [];
    let badInt = 0;
    for (const [p, node] of lb) {
        const off = Number(node.offset);
        const c = b.raw.slice(b.dataStart + off, b.dataStart + off + node.size);
        const h = crypto.createHash('sha256').update(c).digest('hex');
        if (!node.integrity || node.integrity.hash !== h) badInt++;
        if (la.has(p)) {
            const na = la.get(p);
            const oa = Number(na.offset);
            const ca = a.raw.slice(a.dataStart + oa, a.dataStart + oa + na.size);
            if (crypto.createHash('sha256').update(ca).digest('hex') === h) same++;
            else diffs.push(p);
        } else {
            diffs.push(p + ' (only in output)');
        }
    }
    const onlyBase = [...la.keys()].filter((p) => !lb.has(p));
    return { same, diffs, badInt, onlyBase };
}

// ---------------------------------------------------------------- 字符串安全替换
// 与 tools/port_to.py 逐条对应。为什么不能 str.replace 全局替换：
// 短词（Exit / Open / Docs）同时出现在代码标识符里，直接换会把 isExiting 变成
// is退出ting —— 中文是合法标识符字符，node --check 拦不住，运行时才 ReferenceError。

const isIdentChar = (ch) => /^[A-Za-z0-9_]$/.test(ch);

function stringRanges(text) {
    const ranges = [];
    let i = 0;
    const n = text.length;
    while (i < n) {
        const c = text[i];
        if (c === '/' && text[i + 1] === '/') {
            const j = text.indexOf('\n', i);
            i = j === -1 ? n : j + 1;
            continue;
        }
        if (c === '/' && text[i + 1] === '*') {
            const j = text.indexOf('*/', i + 2);
            i = j === -1 ? n : j + 2;
            continue;
        }
        if (QUOTES.has(c)) {
            const q = c;
            const start = i;
            i += 1;
            while (i < n) {
                if (text[i] === '\\') {
                    i += 2;
                    continue;
                }
                if (text[i] === q) {
                    i += 1;
                    break;
                }
                i += 1;
            }
            ranges.push([start, i]);
            continue;
        }
        i += 1;
    }
    return ranges;
}

function wordOk(text, pos, old) {
    if (isIdentChar(old[0])) {
        if (pos > 0 && isIdentChar(text[pos - 1])) return false;
    }
    const last = old[old.length - 1];
    if (isIdentChar(last)) {
        const e = pos + old.length;
        if (e < text.length && isIdentChar(text[e])) return false;
    }
    return true;
}

function replaceInStrings(src, old, replacement) {
    if (!old) return [src, 0];
    const ranges = stringRanges(src);
    const hits = [];
    let i = src.indexOf(old);
    while (i !== -1) {
        let inside = false;
        for (const [s, e] of ranges) {
            if (s < i && i + old.length <= e) {
                inside = true;
                break;
            }
        }
        if (inside && wordOk(src, i, old)) hits.push(i);
        i = src.indexOf(old, i + 1);
    }
    for (let k = hits.length - 1; k >= 0; k--) {
        const p = hits[k];
        src = src.slice(0, p) + replacement + src.slice(p + old.length);
    }
    return [src, hits.length];
}

function codeCjk(text) {
    const spans = stringRanges(text);
    const comments = [];
    let i = 0;
    const n = text.length;
    while (i < n) {
        if (text[i] === '/' && text[i + 1] === '/') {
            let j = text.indexOf('\n', i);
            j = j === -1 ? n : j;
            comments.push([i, j]);
            i = j;
        } else if (text[i] === '/' && text[i + 1] === '*') {
            let j = text.indexOf('*/', i + 2);
            j = j === -1 ? n : j + 2;
            comments.push([i, j]);
            i = j;
        } else {
            i += 1;
        }
    }
    const covers = spans.concat(comments).sort((x, y) => x[0] - y[0]);
    const covered = (p) => {
        for (const [s, e] of covers) {
            if (s <= p && p < e) return true;
            if (p < s) return false;
        }
        return false;
    };
    const bad = [];
    for (let p = 0; p < text.length; p++) {
        const ch = text[p];
        if (ch >= '\u4e00' && ch <= '\u9fff' && !covered(p)) bad.push(p);
    }
    return bad;
}

// ---------------------------------------------------------------- 参数

function parseArgs(argv) {
    const out = {};
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        if (a.startsWith('--')) out[a.slice(2)] = argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[++i] : true;
    }
    return out;
}

const FLAGS = parseArgs(process.argv.slice(2));

function resolveAsset(p) {
    if (!p) return null;
    if (fs.existsSync(p)) return p;
    const alt = path.resolve(__dirname, '..', '..', p);
    if (fs.existsSync(alt)) return alt;
    return p;
}

function main() {
    const base = FLAGS.base;
    const out = FLAGS.out;
    const ref = FLAGS.ref || '2.28.2';
    const packdir = FLAGS.packdir || path.resolve(__dirname, '..', '..');

    if (!base || !out) die(2, 'missing --base or --out');
    if (!fs.existsSync(base)) die(3, 'base asar not found');

    const memPath = resolveAsset(path.join(packdir, 'tools', 'patches', `memory-${ref}.json`));
    const engPath = resolveAsset(path.join(packdir, 'tools', 'preload-engine.js'));
    const rulesPath = resolveAsset(path.join(packdir, 'tools', 'porting-rules.json'));
    if (!fs.existsSync(memPath)) die(4, 'memory json not found');
    if (!fs.existsSync(engPath)) die(5, 'preload engine not found');

    const mem = JSON.parse(fs.readFileSync(memPath, 'utf8'));
    const engine = fs.readFileSync(engPath, 'utf8');
    const rules = fs.existsSync(rulesPath) ? JSON.parse(fs.readFileSync(rulesPath, 'utf8')) : {};
    // 跨版本通用的补词：只落在字符串字面量内，且带词边界，不会碰代码标识符。
    // 旧包用它也能翻到新版才出现的文案（记忆文件是按版本冻结的，规则表不是）。
    const globalPairs = rules.globalPairs || {};
    const pairKeys = Object.keys(globalPairs).sort((a, b) => b.length - a.length);

    log(`base   : ${base}`);
    log(`out    : ${out}`);
    log(`ref    : ${ref}`);
    log(`engine : ${path.basename(engPath)} ${engine.length} chars`);

    const parsed = readAsar(base);
    const swap = {};
    let totalApplied = 0;
    let totalMissed = 0;
    let badTotal = 0;

    // ---- preload：官方原文双行化 + 固定引擎 ----
    let offPreload;
    try {
        offPreload = extract(parsed, 'dist/preload.js').toString('utf8');
    } catch (e) {
        die(6, 'cannot extract dist/preload.js from base');
    }
    // 2.28.2 的 preload 用 '\n' 双行化；换行风格以实际内容为准，CRLF 也能正确处理
    const preloadNew = offPreload.replace(/\n/g, '\n\n') + engine;
    swap['dist/preload.js'] = Buffer.from(preloadNew, 'utf8');
    log(`preload: official ${offPreload.length} -> ${preloadNew.length}`);

    // ---- 其余 5 个：手工规则 + 翻译记忆 ----
    for (const inner of Object.keys(SIX)) {
        if (inner === 'dist/preload.js') continue;
        const name = SIX[inner];
        let src;
        try {
            src = extract(parsed, inner).toString('utf8');
        } catch (e) {
            log(`  ${inner}: 底座里没有这个文件，跳过`);
            continue;
        }

        let applied = 0;
        const manual = (rules.manual && rules.manual[name]) || [];
        for (const pair of manual) {
            const [oldStr, newStr] = pair;
            const count = src.split(oldStr).length - 1;
            if (count !== 1) log(`  !! manual rule hit ${count}x: ${inner} :: ${oldStr.slice(0, 40)}`);
            src = src.split(oldStr).join(newStr);
            applied += count;
        }

        // 2.31.0 起官方新增的菜单 / 对话框文案，用规则表跨版本补齐
        for (const oldStr of pairKeys) {
            const res = replaceInStrings(src, oldStr, globalPairs[oldStr]);
            src = res[0];
            if (res[1]) applied += res[1];
        }

        const pairs = (mem.files && mem.files[inner]) || {};
        const keys = Object.keys(pairs).sort((a, b) => b.length - a.length);
        let missed = 0;
        for (const oldStr of keys) {
            if (oldStr.length < 3 || oldStr.indexOf('\n') !== -1) {
                missed++;
                continue;
            }
            const res = replaceInStrings(src, oldStr, pairs[oldStr]);
            src = res[0];
            if (res[1]) applied += res[1];
            else missed++;
        }

        // 代码区不允许出现中文（出现了就是把标识符改坏了）
        const bad = codeCjk(src);
        if (bad.length) {
            badTotal += bad.length;
            log(`  !! POLLUTION ${inner}: ${bad.length} at ${JSON.stringify(bad.slice(0, 5))}`);
        }

        swap[inner] = Buffer.from(src, 'utf8');
        totalApplied += applied;
        totalMissed += missed;
        log(`  ${inner.padEnd(34)} mem ${String(keys.length).padStart(2)} | applied ${applied} | missed ${missed}`);
    }

    // ---- 新版才出现的模块（2.31.0 一口气加了 27 个文件，含可见文案的那几个） ----
    // 只在真的命中补词时才写回：没改过的文件若也塞进 swap，末尾的
    // 「diff 数 == swap 数」自检会把它当成漏改而报错。
    for (const inner of (rules.extraFiles || [])) {
        if (Object.prototype.hasOwnProperty.call(SIX, inner)) continue;
        let src;
        try {
            src = extract(parsed, inner).toString('utf8');
        } catch (e) {
            log(`  extra ${inner}: 底座里没有这个文件，跳过`);
            continue;
        }
        const before = src;
        let applied = 0;
        for (const oldStr of pairKeys) {
            const res = replaceInStrings(src, oldStr, globalPairs[oldStr]);
            src = res[0];
            if (res[1]) applied += res[1];
        }
        if (src === before) {
            log(`  extra ${inner.padEnd(28)} 无命中，跳过`);
            continue;
        }
        const bad = codeCjk(src);
        if (bad.length) {
            badTotal += bad.length;
            log(`  !! POLLUTION extra ${inner}: ${bad.length} at ${JSON.stringify(bad.slice(0, 5))}`);
            continue;
        }
        swap[inner] = Buffer.from(src, 'utf8');
        totalApplied += applied;
        log(`  extra ${inner.padEnd(28)} applied ${applied}`);
    }

    if (badTotal > 0) {
        die(7, `code pollution detected (${badTotal} chars in code region)`);
    }

    // ---- 打包 ----
    const built = buildAsar(base, out, swap);
    log(`build: swapped ${built.swapped}, payload ${built.payloadSize}`);

    const cmp = compareAsar(base, out);
    log(`check: same ${cmp.same}, diffs ${cmp.diffs.length}, badIntegrity ${cmp.badInt}, onlyBase ${cmp.onlyBase.length}`);
    if (cmp.diffs.length) log('  diffs: ' + cmp.diffs.join(', '));

    if (cmp.badInt > 0) die(8, `integrity mismatch (${cmp.badInt})`);
    if (cmp.diffs.length !== Object.keys(swap).length) {
        die(9, `expected ${Object.keys(swap).length} swapped files, got ${cmp.diffs.length}`);
    }
    if (cmp.onlyBase.length) die(10, 'output is missing files present in base');

    emit({
        RESULT: 'ok',
        REF: ref,
        APPLIED: totalApplied,
        MISSED: totalMissed,
        FILES: Object.keys(swap).length,
        SIZE: fs.statSync(out).size,
    });
    flushLog();
    return 0;
}

try {
    process.exitCode = main();
} catch (e) {
    log('EXCEPTION: ' + (e && e.stack ? e.stack : String(e)));
    die(11, 'exception: ' + (e && e.message ? e.message : String(e)));
}
