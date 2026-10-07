# Provenance

| | |
|---|---|
| Model | `claude-sonnet-5-5` (Claude Code sub-agent, model alias `sonnet`) |
| Generated | 2026-09-30, one run, no retries |
| Prompt | `checkers/llm_prompt/PROMPT.md` (sha256 `7ae502bdb7c51015…`), unchanged across models |
| Inputs given | IHI 0022 Issue L Part A chapters A1–A6 as text, `port_list.sv`, `lint.sh` (Verilator `--lint-only`) |
| Isolation | Instructed to read only its sandbox directory; no access to the catalog, harness, interposer or baseline was given |
| Output | `axi_checker_set.sv` (sha256 `1009cf47be4bc8c4…`), committed **byte-identical** to what the model wrote |
| Hand edits | None. Any change needed to compile in the lab bench is a separate, logged commit. |
