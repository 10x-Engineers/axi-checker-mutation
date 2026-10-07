# Provenance

| | |
|---|---|
| Model | `claude-haiku-4-5-20251001` (Claude Code sub-agent, model alias `haiku`) |
| Generated | 2026-09-30, one run, no retries |
| Prompt | `checkers/llm_prompt/PROMPT.md` (sha256 `7ae502bdb7c51015…`), unchanged across models |
| Inputs given | IHI 0022 Issue L Part A chapters A1–A6 as text, `port_list.sv`, `lint.sh` (Verilator `--lint-only`) |
| Isolation | Instructed to read only its sandbox directory; no access to the catalog, harness, interposer or baseline was given |
| Output | `axi_checker_set.sv` (sha256 `8088e402ea05ca65…`), committed **byte-identical** to what the model wrote |
| Hand edits | None. Any change needed to compile in the lab bench is a separate, logged commit. |
