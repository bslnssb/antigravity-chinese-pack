# swap-map.relative.json 使用说明

`swap-map.relative.json` 是**换装映射**：左边是 asar 内的路径，右边是本地译文文件。
路径全部相对**仓库根目录**，所以整个文件夹挪到哪都能用（早期版本写死过
`C:\Users\<用户名>\Documents\...` 绝对路径，换机器即失效，已废弃）。

## 用法

纯 Python（推荐，无需 Node.js）：

```bash
# 在仓库根目录执行
python tools/maintainer/zh_merge.py build <新版app.asar> <输出zh.asar> \
  tools/patches/swap-map.relative.json

# 发版前校验：差异文件应恰为换装目标、integrity 不自洽 0 个
python tools/maintainer/zh_merge.py packselftest <新版app.asar> <输出zh.asar> <参考zh.asar>
```

Node 等价（产物一致）：

```bash
node tools/antigravity-zh-patch.js build \
  --base <新版app.asar> --out <输出zh.asar> --swap tools/patches/swap-map.relative.json
```

注意：换用新版 Antigravity 时，`build/materials-*/` 里的换装文件需先经
`zh_merge.py memory` / `apply` 更新到新版（见 `tools/maintainer/README.md`），
否则等于用旧版文件覆盖新版，会丢功能。

## 相关文件

- `preload-dict.json`：842 条界面翻译字典（英文为键，**不要翻键**）
- `安装说明-v2.26.0.txt` / `安装说明-v2.25.1.txt`：随包给最终用户的说明
