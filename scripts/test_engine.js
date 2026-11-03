// 引擎离线回归测试：直接加载 tools/preload-engine.js，用 __agyTranslateText 验证翻译结果
// 用法: node scripts/test_engine.js            —— 跑内置用例
//       node scripts/test_engine.js <文本文件>  —— 逐行翻译文件中的文本
const fs = require('fs');
const path = require('path');

const enginePath = path.join(__dirname, '..', 'tools', 'preload-engine.js');
new Function(fs.readFileSync(enginePath, 'utf8'))();

const T = globalThis.__agyTranslateText;
if (typeof T !== 'function') {
    console.error('引擎未导出 __agyTranslateText');
    process.exit(2);
}

const fileArg = process.argv[2];
if (fileArg) {
    const lines = fs.readFileSync(fileArg, 'utf8').split(/\r?\n/).filter((l) => l.trim());
    for (const l of lines) {
        const out = T(l);
        console.log(`${out === l ? '[MISS]' : '[ OK ]'}\t${l}\t=>\t${out}`);
    }
    process.exit(0);
}

// 键：原文；值：期望的中文（用来钉死回归）
const CASES = [
    // 曾经被短词啃坏的（v4.3 词边界修复）
    ['Reopen Closed Tab', '重新打开已关闭的标签页'],
    ['Close', '关闭'],
    ['Closed', '已关闭'],
    ['Opened', '已打开'],
    ['Editor', '编辑器'],
    ['Installation', '安装'],
    ['Copyright', '版权'],
    // 未汉化的设置页文案（补齐后应全部命中）
    ['Permission Preset', '权限预设'],
    ['Plan Review Policy', '计划审核策略'],
    ['Execution', '执行'],
    ['Built-in Browser Settings', '内置浏览器设置'],
    ['External Browser', '外部浏览器'],
    ['Open Links In', '链接打开方式'],
    ['Give Feedback', '意见反馈'],
    ['Your Plan: Google AI Pro', '当前方案: Google AI Pro'],
    ['Navigation', '导航'],
    ['New Tab', '新建标签页'],
    ['Move Conversation Up', '上移会话'],
    ['Search shortcuts...', '搜索快捷键...'],
    // 半中半英兜底：这些是远端下发、本地查不到原文的长句
    ['Configure global allowed and denied resource permissions. Learn more.', '配置全局的资源访问允许与拒绝权限。 了解更多。'],
    ['Configure link opening and built-in browser preferences.', '配置链接打开方式与内置浏览器偏好。'],
    ['Legal Help', '法律帮助'],
    ['Keyboard Shortcuts for quick navigation and control.', '快捷键指南：快速导航与操作。'],
    ['Open File Search', '打开文件搜索'],
    ['Models & Usage', '模型配置与用量'],
    ['Copy path', '复制路径'],
    ['Refresh quota and credits data', '刷新配额与额度数据'],
    ['Remote Control Issue', '远程控制问题'],
    ['Shortcut Ctrl+K for Open Conversation Picker', '打开会话选择器（Ctrl+K）'],
    ['Select project, current: No Project', '选择项目，当前：无项目'],
    ['Rules: 4,515 tokens', '规则：4,515 Tokens'],
    // v4.4：顶栏菜单 / 历史会话设置面板 / 侧边栏会话列表
    ['Workspace', '工作区'],
    ['Permission Settings', '权限设置'],
    ['Agent settings and permissions for conversations outside of projects.', '项目之外会话的智能体设置与权限。'],
    ['Also includes', '此外还包含'],
    ['when working in these conversations.', '（仅在这些会话中生效）。'],
    ['10d', '10 天前'],
    ['3h', '3 小时前'],
    ['Search Conversations', '搜索会话'],
    // 反向保护：不能把含 Workspace 的长句啃坏
    ['Use Workspace Settings', '使用工作区设置'],
    ['Also includes global settings when working', '在当前项目中工作时，同时继承并应用全局设置'],
];

// M6：总开关。第一项是开关状态：on = 正常翻译，off = 整段原样返回（连前后空格都不动）
const SWITCH_CASES = [
    ['on', 'Settings', '设置'],
    ['on', 'New Conversation', '新建会话'],
    ['on', '  Settings  ', '  设置  '],
    ['off', 'Settings', 'Settings'],
    ['off', 'New Conversation', 'New Conversation'],
    ['off', '  Settings  ', '  Settings  '],
];

// M6：启动时读 localStorage['agyZh']，只有 '0' 才算关（其它值/没写过都算开）
const STORAGE_CASES = [
    ['<unset>', true],
    ['1', true],
    ['0', false],
];

// M6：切换后要写回 localStorage，刷新页面还保持
const WRITE_CASES = [
    ['off', '0'],
    ['on', '1'],
];

// M6：用户内容区不翻。第一项是命中容器（选择器 / <editable> / class），第二项是是否应跳过
const EXCLUDE_CASES = [
    ['.surface-composer', true],
    ['.surface-composer-card', true],
    ['.no-focus-agent-input', true],
    ['[data-testid="agent-input-box"]', true],
    ['[data-testid="voice-dock-input"]', true],
    ['[data-testid="conversation-view"]', true],
    ['[data-testid="user-message-bubble"]', true],
    ['[data-testid="voice-user-message"]', true],
    ['<editable>', true],
    ['.notranslate', true],
    ['.toolbar-button', false],
    ['[data-testid="side-panel"]', false],
];

const ENG = globalThis.__agyEngine;
if (!ENG || typeof ENG.setEnabled !== 'function') {
    console.error('引擎未导出 __agyEngine（M6 开关接口缺失）');
    process.exit(2);
}

function withStorage(map, fn) {
    const prev = globalThis.localStorage;
    globalThis.localStorage = {
        getItem: (k) => (Object.prototype.hasOwnProperty.call(map, k) ? map[k] : null),
        setItem: (k, v) => { map[k] = String(v); },
        removeItem: (k) => { delete map[k]; },
    };
    try {
        return fn();
    } finally {
        if (prev === undefined) delete globalThis.localStorage;
        else globalThis.localStorage = prev;
    }
}

// 极简元素替身：只实现 isExcluded 用到的 tagName / classList / isContentEditable / closest / parentElement
function fakeEl(options) {
    const el = {
        tagName: options.tag || 'DIV',
        classList: { contains: (c) => (options.classes || []).includes(c) },
        isContentEditable: !!options.editable,
        closest(sel) {
            const hit = sel.split(',').some((s) => (options.matches || []).includes(s));
            return hit ? el : (options.parent || null);
        },
        parentElement: options.parent || null,
    };
    return el;
}

let total = 0;
let fail = 0;

function report(ok, label) {
    total++;
    if (!ok) fail++;
    console.log(`${ok ? 'PASS' : 'FAIL'}  ${label}`);
}

for (const [en, want] of CASES) {
    const got = T(en);
    report(got === want, `${JSON.stringify(en)} -> ${JSON.stringify(got)}${got === want ? '' : `  期望 ${JSON.stringify(want)}`}`);
}

ENG.setEnabled(true);
for (const [state, en, want] of SWITCH_CASES) {
    ENG.setEnabled(state === 'on');
    const got = T(en);
    report(got === want, `[开关 ${state}] ${JSON.stringify(en)} -> ${JSON.stringify(got)}${got === want ? '' : `  期望 ${JSON.stringify(want)}`}`);
}
ENG.setEnabled(true);

for (const [stored, wantOn] of STORAGE_CASES) {
    const map = stored === '<unset>' ? {} : { [ENG.storageKey]: stored };
    const on = withStorage(map, () => ENG.readEnabled());
    report(on === wantOn, `localStorage['${ENG.storageKey}']=${JSON.stringify(stored)} -> 汉化应${wantOn ? '开' : '关'}，实际${on ? '开' : '关'}`);
}

for (const [state, wantStored] of WRITE_CASES) {
    const map = {};
    withStorage(map, () => ENG.setEnabled(state === 'on'));
    const got = map[ENG.storageKey];
    report(got === wantStored, `切到 ${state} -> localStorage['${ENG.storageKey}']=${JSON.stringify(got)}`);
}
ENG.setEnabled(true);

for (const [mark, wantSkip] of EXCLUDE_CASES) {
    const el = mark === '<editable>'
        ? fakeEl({ editable: true })
        : fakeEl({ matches: [mark], classes: mark.startsWith('.') ? [mark.slice(1)] : [] });
    const node = { nodeType: 3, parentElement: el };
    const skipped = ENG.isExcluded(node) === true;
    report(skipped === wantSkip, `${JSON.stringify(mark)} -> ${skipped ? '跳过' : '翻译'}${skipped === wantSkip ? '' : `  期望${wantSkip ? '跳过' : '翻译'}`}`);
}

console.log(`\n${total - fail}/${total} 通过`);
process.exit(fail ? 1 : 0);
