<!-- REVIEW: machine-drafted translation of README.md; needs a native speaker's review before release -->
# 实验 1：用您的大模型生成检查器（35 分钟）

[English](README.md)

所有人使用相同的输入：[`checkers/llm_prompt/PROMPT.md`](../../checkers/llm_prompt/PROMPT.md)
和 [`port_list.sv`](../../checkers/llm_prompt/port_list.sv)。

## 1.1 生成（15 分钟）

**方式 A，任意对话界面。** 上传 IHI 0022 Issue L 的 PDF，并说明："只使用 Part A 第 A1–A6 章。" 粘贴 `PROMPT.md`，再粘贴 `port_list.sv`。把返回的 SystemVerilog 保存为 `~/my_checker.sv`。

**方式 B，任意兼容 OpenAI 的 API。**

```bash
python3 tools/spec_text.py IHI0022L.pdf > /tmp/axi_A1-A6.txt
export LLM_API_KEY=...                  # 本地模型不需要
python3 tools/gen_checker.py --name my_model --spec /tmp/axi_A1-A6.txt \
    --base-url <endpoint> --model <model-name>
```

| 服务商 | `--base-url`（以服务商文档为准） |
|---|---|
| DeepSeek | `https://api.deepseek.com/v1` |
| 通义千问（DashScope） | `https://dashscope.aliyuncs.com/compatible-mode/v1` |
| Kimi（Moonshot） | `https://api.moonshot.cn/v1` |
| 智谱 GLM | `https://open.bigmodel.cn/api/paas/v4` |
| Ollama（本地） | `http://localhost:11434/v1` |

没有大模型？使用 `llm_haiku`、`llm_sonnet` 或 `llm_opus`，直接跳到 1.3。

## 1.2 接入（8 分钟）

```bash
python3 tools/new_checker_set.py my_model --from ~/my_checker.sv    # 方式 A
python3 tools/new_checker_set.py my_model                           # 方式 B
```

它会对文件做 lint，并起草 `checkers/my_model/rules.toml`，把每条断言映射到 `catalog/clauses.toml` 中的一条条款。**逐行审核。** 映射决定了什么算作 CORRECT。如果 lint 失败，只修改阻止编译的部分，并记下改动。

## 1.3 度量（7 分钟）

```bash
python3 harness/qualify.py --checkers my_model
python3 harness/matrix.py my_model llm_opus llm_haiku pulp_axi
```

## 1.4 问题（5 分钟）

- 您的模型在哪一类规则上最弱？
- 有误报吗？
- 挑一个 MISSED 的变异体，在规范中找到它的条款。检查器为什么漏掉了它？
- 把模型名和 `summary` 那一行发到会场群里。

## 提前完成了？

- 用第二个大模型生成，并比较两者。
- 在您的 `PROMPT.md` 副本中加一段话，重新生成并再次度量。有帮助吗？
