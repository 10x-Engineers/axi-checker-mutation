<!-- REVIEW: machine-drafted translation of README.md; needs a native speaker's review before release -->
# 实验 2：一次"杀死"的剖析（30 分钟）

[English](README.md)

## 2.1 插入器（5 分钟）

阅读 `rtl/axi_mut_interposer.sv` 的文件头，回答：
- 检查器观察的是哪条总线？主设备和被测设计使用的又是哪条？
- 插入器对真实流量做的唯一一件事是什么？为什么那是合法的？

## 2.2 波形上的一次违规（10 分钟）

```bash
python3 harness/show.py --checkers llm_opus --mutant aw-valid-drop --waves
surfer <它打印出的 .vcd 路径>        # 或 gtkwave
```

在 INJECT 时刻附近查看 `obs_awvalid`、`obs_awready`、`m_axi_awvalid`、`s_axi_awvalid`。
- 观测总线违反了规范中的哪一句？
- 真实的主设备和被测设计各自看到了什么？
- 哪条规则触发了？在哪个周期？

## 2.3 判定（15 分钟）

逐条运行并解释判定：

```bash
python3 harness/show.py --checkers llm_opus  --mutant aw-valid-drop
python3 harness/show.py --checkers llm_haiku --mutant b-before-wlast-hs
python3 harness/show.py --checkers llm_opus  --mutant same-id-read-swap
python3 harness/show.py --checkers llm_opus  --mutant exokay-after-intervening-write
python3 harness/show.py --checkers llm_opus  --mutant diff-id-read-swap
```

对每一条：涉及哪条条款？谁发现了？为什么？变异体的定义在 `catalog/mutants.toml` 和 `catalog/legal.toml` 中。

## 提前完成了？

运行 `python3 harness/matrix.py pulp_axi llm_opus`，比较 `ar-4kb-cross` 和 `ar-4kb-cross-after-wrap`，解释其中的差别。
