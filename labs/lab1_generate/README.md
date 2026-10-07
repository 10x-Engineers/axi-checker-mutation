# Lab 1: Generate a checker with your LLM (35 min)

[中文](README.zh.md)

Everyone uses the same inputs: [`checkers/llm_prompt/PROMPT.md`](../../checkers/llm_prompt/PROMPT.md)
and [`port_list.sv`](../../checkers/llm_prompt/port_list.sv).

## 1.1 Generate (15 min)

**Route A, any chat UI.** Attach the IHI 0022 Issue L PDF and say *"Use only Part A,
chapters A1–A6."* Paste `PROMPT.md`, then `port_list.sv`. Save the SystemVerilog it returns
as `~/my_checker.sv`.

**Route B, any OpenAI-compatible API.**

```bash
python3 tools/spec_text.py IHI0022L.pdf > /tmp/axi_A1-A6.txt
export LLM_API_KEY=...                  # not needed for a local model
python3 tools/gen_checker.py --name my_model --spec /tmp/axi_A1-A6.txt \
    --base-url <endpoint> --model <model-name>
```

| Provider | `--base-url` (check the provider's docs) |
|---|---|
| DeepSeek | `https://api.deepseek.com/v1` |
| Qwen (DashScope) | `https://dashscope.aliyuncs.com/compatible-mode/v1` |
| Kimi (Moonshot) | `https://api.moonshot.cn/v1` |
| Zhipu GLM | `https://open.bigmodel.cn/api/paas/v4` |
| Ollama (local) | `http://localhost:11434/v1` |

No LLM? Use `llm_haiku`, `llm_sonnet` or `llm_opus` and go to 1.3.

## 1.2 Plug it in (8 min)

```bash
python3 tools/new_checker_set.py my_model --from ~/my_checker.sv    # Route A
python3 tools/new_checker_set.py my_model                           # Route B
```

This lints the file and drafts `checkers/my_model/rules.toml`, which maps each assertion to a
clause in `catalog/clauses.toml`. **Review every line.** The mapping decides what counts as
CORRECT. If lint fails, fix only what stops compilation, and note what you changed.

## 1.3 Measure (7 min)

```bash
python3 harness/qualify.py --checkers my_model
python3 harness/matrix.py my_model llm_opus llm_haiku pulp_axi
```

## 1.4 Questions (5 min)

- Which rule class is your model weakest on?
- Any false positives?
- Pick one MISSED mutant. Find its clause in the spec. Why did the checker miss it?
- Post your model name and `summary` row in the group chat.

## Finished early?

- Generate with a second LLM and compare the two.
- Add one paragraph to your copy of `PROMPT.md`, regenerate, and measure again. Did it help?
