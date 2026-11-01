# Antigravity 汉化维护器（原型）

解决社区汉化包的共同死穴：**Antigravity 一升级，旧汉化包整包失效**。
本工具把"旧版的翻译"搬进"新版文件"，让汉化跟随版本自动延续。

## 与本包其他工具的分工

```
新版 Antigravity 发布
   │
   ▼
zh_merge.py memory  旧原版文件 + 旧汉化文件 → 翻译记忆(en→zh 替换对)
   │
zh_merge.py apply   翻译记忆 → 新版同名文件（精确匹配搬运，报 missed 清单）
   │
zh_merge.py selftest（开发/回归用，对已知数据自校验）
   │
zh_merge.py build   重打包新版 app.asar（纯 Python，重新计算 integrity 哈希）
   │
zh_merge.py packselftest  逐文件比对 + integrity 自洽校验（发版前必跑）
   │
zh_merge.py 不做的事：逐条人工核对新增英文（missed 清单就是工作量清单）
```

## 用法（升级日三步）

```bash
# 1. 从旧版原 asar 和你手里的汉化材料构建记忆（一次性，或每次升级前刷新）
python zh_merge.py memory 旧版原始文件.js 旧版汉化文件.js memory-menu.json

# 2. 新版装好后，从新版 asar 提取同名文件，应用记忆
python zh_merge.py extract 新版app.asar dist/menu.js new-menu.js
python zh_merge.py apply new-menu.js memory-menu.json new-menu-zh.js

# 3. 重打包（纯 Python，无需 Node.js）
python zh_merge.py build 新版app.asar 新版zh.asar swap-map.json

# 4. 发版前校验：应显示差异文件恰为换装目标、integrity 不自洽 0 个
python zh_merge.py packselftest 底包.asar 新版zh.asar 参考zh.asar
```

需要 Node 的等价工具是 `tools/antigravity-zh-patch.js`（`build` / `verify` / `extract` / `inspect`），
两条链路产物一致，任选其一。

## 自校验结果（2026-10-24，真实 2.25 数据）

对 `app.asar.original-2.25.0` 重建记忆并重放，对照现有汉化材料：

| 文件 | 记忆对 | 应用 | 未中 | 与现有汉化相似度 |
|---|---|---|---|---|
| dist__menu.js | 4 | 4 | 0 | 99.3% |
| main25-zh.js | 7 | 7 | 0 | 99.9% |
| dist__ideInstall__wizardHtml.js | 7 | 7 | 0 | 96.5% |

- 相似度未到 100% 的原因：SequenceMatcher 替换边界噪声 + 汉化材料含 10-24 手工标题补丁
- **护栏实测**：preload（原 5.4KB vs 材料 318KB，非派生关系）被体积比护栏正确拒绝，
  不会产出垃圾合并

## 已知限制（诚实版）

1. `dist/preload.js` 的汉化材料与 asar 内原始文件**不是派生关系**（体积 5.4KB vs 318KB），
   自动合并不适用——它按"整套替换"维护，新增词条直接往字典里加
2. 新版新增英文永远在 missed 清单里——这是每版翻译的真实工作量，工具只能搬运存量
3. 同一原文多种译法时跳过（等人工裁决），避免随机覆盖
4. 换装文件清单必须齐（含 `dist/ipcHandlers.js`），漏一个就会残留英文界面
