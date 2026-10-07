# Provenance

| | |
|---|---|
| Generator | **UCAgent** (UnityChip / 万众一芯, github.com/XS-MLVP/UCAgent) `26.9.2.dev37+gac007684b`, `langchain` backend |
| Model | `kimi-k3` (Moonshot) via `https://api.moonshot.ai/v1`, temperature 1 |
| Workflow | UCAgent's formal workflow (`ucagent/lang/zh/config/formal.yaml`), **ended after `property_generation`**: the later stages drive FormalMC, a commercial formal tool, and were removed |
| Inputs | `axi_ram.v` (verilog-axi), a README asking for AXI4 protocol-compliance properties, IHI 0022 Issue L chapters A1–A6 as text. Nothing from this repository's catalog. |
| Run | 2026-09-30, 54 min unattended. 7 function groups, 94 check points: 54 assert, 15 assume, 25 cover. |
| End of run | The provider returned HTTP 429 (account credit) just as the last stage finished. UCAgent's own completion check (every `sva_body` implemented, 94/94) and its own renderer (`generate_formal_env.py --mode full`) were then run by hand, with no model, producing `axi_ram_checker.sv` (sha256 `dc2d0ba06e3cdcc0…`). |
| Binding | `axi_checker_set.sv` connects the observed bus and, because UCAgent works white-box, axi_ram's internal registers and memory; `fv_idx` (formal symbolic index) tied to 0. See the file header. |
| `ucagent_run/` | UCAgent's plan, DUT analysis and function/check-point documents from this run (Chinese). |

## Changes needed to compile on Verilator (separate commit, every one marked `[bench compile fix]`)

UCAgent writes SVA for a commercial formal tool. Five constructs did not compile in open-source simulation:

| Where | Problem | Change |
|---|---|---|
| `CK_RESET_RESP_OKAY`, `CK_RESET_FSM_VALID_STATE` | "Comb" properties without a clock (IEEE 1800 requires one) | `@(posedge clk)` added |
| 3 memory properties | `$past`/`$stable` of `mem[fv_idx]` on an unpacked-array port crashes Verilator | read through `wire mem_at_fv = mem[fv_idx]` (identical while `fv_idx` is constant) |
| `CK_CONC_LIVE_COVER` (cover) | ranged delay inside `and`: unsupported | removed |
| `CK_CONC_LIVE_FSM_IDLE`, `CK_CONC_LIVE_WRITE_B`, `CK_CONC_LIVE_READ_RLAST` (liveness asserts) | `s_eventually`: needs `--timing` or crashes Verilator | removed (a liveness property cannot fail in a finite run) |
