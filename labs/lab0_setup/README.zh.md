<!-- REVIEW: machine-drafted translation of README.md; needs a native speaker's review before release -->
# 实验 0：环境与干净运行（15 分钟）

[English](README.md)

## 0.1 检查环境

```bash
./check_env.sh
```

请在开场讲解时运行。必须显示 **ALL PASS**。看一看 `tools/sva_smoke/`：它在测试什么？检查器的作者为什么要关心它？

## 0.2 不加检查器运行测试平台

```bash
python3 harness/show.py --checkers none
```

激励在 `tb/test_axi.py` 中，全部是合法的 AXI4 流量。

## 0.3 加上检查器运行

```bash
python3 harness/show.py --checkers llm_haiku
python3 harness/show.py --checkers llm_opus
python3 harness/show.py --checkers pulp_axi
```

1. 有规则触发吗？流量是合法的，所以每一次触发都需要一个解释。
2. 对每条触发的规则，在 `checkers/<set>/axi_checker_set.sv` 中读懂它，在 IHI 0022 Issue L 中找到对应的规则，然后判断：是设计的错误，还是检查器的错误？
3. 在进入实验 1 之前，写下您认为哪个检查器集能抓到最多的违规，以及原因。

✅ 完成标志：`check_env.sh` 显示 ALL PASS，并且您回答了 0.3。
