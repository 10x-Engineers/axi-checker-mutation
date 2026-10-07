<!-- REVIEW: machine-drafted translation of README.md; needs a native speaker's review before release -->
# 实验 3：扩展目录，修复检查器（30 分钟）

[English](README.md)

## 3.1 目录条目（5 分钟）

```toml
[[mutant]]
id = "excl-len32"
class = "exclusive"
clauses = ["EXCL_LEN"]      # catalog/clauses.toml 中的键
chan = "AR"                 # 要篡改的通道
op = "OVERRIDE"             # VALID_DROP | GLITCH | OVERRIDE | HS_DELAY | SWAP
tfield = "ARADDR"           # 触发条件：该字段……
tval = "1000"               # ……等于此值的那一拍
xfield = "ARLOCK"           # 要修改的字段……
xval = "1"                  # ……改成此值（只作用于观测总线）
```

变异体必须破坏一条 **MUST** 规则，注明章节和页码，并且必须被注入（不是 `NOT_INJECTED`）。

## 3.2 写一个变异体（15 分钟）

任选其一：

| 规则（IHI 0022 Issue L） | |
|---|---|
| §A3.1.1 第 43 页 | Size 不得超过数据宽度 |
| §A3.1.4 第 47 页 | WRAP 的起始地址必须按 Size 对齐 |
| §A6.3.4 第 112 页 | 一次独占读中不得混用 OKAY 与 EXOKAY |
| 您自己的 | 任何 `tb/test_axi.py` 中的激励能触发的 MUST 规则 |

1. 如果是新条款，把它加入 `catalog/clauses.toml`。
2. 把变异体加入 `catalog/mutants.toml`。
3. 确认它被注入：
   ```bash
   python3 harness/qualify.py --checkers llm_opus --only <your-id>
   ```
4. 在各检查器集的 `rules.toml` 中，为检查这条条款的规则更新映射，然后运行所有检查器集。

## 3.3 修复一个检查器（10 分钟，进阶）

```bash
cp -r checkers/llm_opus checkers/my_fix
```

挑一个 `llm_opus` 漏掉的变异体。在 `checkers/my_fix/axi_checker_set.sv` 中添加一条规则，在 `rules.toml` 中映射它，然后运行：

```bash
python3 harness/qualify.py --checkers my_fix
```

完成标准：该变异体为 CORRECT，**并且**所有合法扰动仍为 CLEAN。

## 提前完成了？

- 为 §A4.7.2 第 84 页（区域标识）写一个变异体。
- 在 `catalog/legal.toml` 中添加一个您认为某个检查器会误报的合法扰动。
