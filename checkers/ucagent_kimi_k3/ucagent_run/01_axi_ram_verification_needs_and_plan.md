
# axi_ram 形式化验证需求分析与规划

> 本文档由 `.formal_records.yaml` 自动生成，请勿手动编辑。

## 1. 项目概述

axi_ram is an AMBA AXI4 Subordinate: a simple RAM with one AXI4 slave port (s_axi_*: AW, W, B, AR, R channels), clk and active-high rst. The DUT implements a byte-addressable memory with parameterized data width, address width, ID width, and optional output pipelining. The goal of this formal verification effort is to write SystemVerilog Assertions (SVA) that check AXI4 protocol compliance on the s_axi_* interface, covering all rules that can be verified from the interface signals. Attribute failures (Fail) are a valuable output indicating potential design defects or environment constraint issues, and are used to drive bug discovery and root-cause analysis.


## 2. 设计规格分析

### 2.1 参数

| 参数名 | 默认值 | 取值范围 | 说明 |
|--------|--------|----------|------|
| DATA_WIDTH | 32 | 32, 64, 128, ... | Width of data bus in bits; must be evenly divisible by 8. |
| ADDR_WIDTH | 16 | 16, 32, 64, ... | Width of address bus in bits; affects memory depth 2^(ADDR_WIDTH - log2(STRB_WIDTH)). |
| STRB_WIDTH | DATA_WIDTH/8 | derived | Width of write strobe; number of byte lanes. |
| ID_WIDTH | 8 | 1..32 | Width of AXI transaction ID; impacts ordering and ID tracking logic. |
| PIPELINE_OUTPUT | 0 | 0 or 1 | Adds a pipeline register on R channel outputs; affects RVALID/RDATA timing and backpressure behavior. |


### 2.2 接口

| 信号名 | 方向 | 位宽 | 说明 |
|--------|------|------|------|
| s_axi_awid | input | ID_WIDTH | Write address ID. |
| s_axi_awaddr | input | ADDR_WIDTH | Write address. |
| s_axi_awlen | input | 8 | Burst length (0..255 => 1..256 beats). |
| s_axi_awsize | input | 3 | Burst size (bytes per beat = 2^awsize). |
| s_axi_awburst | input | 2 | Burst type (FIXED, INCR, WRAP). |
| s_axi_awlock | input | 1 | Lock type. |
| s_axi_awcache | input | 4 | Cache attributes. |
| s_axi_awprot | input | 3 | Protection attributes. |
| s_axi_awvalid | input | 1 | Write address valid. |
| s_axi_awready | output | 1 | Write address ready. |
| s_axi_wdata | input | DATA_WIDTH | Write data. |
| s_axi_wstrb | input | STRB_WIDTH | Write strobes (byte enables). |
| s_axi_wlast | input | 1 | Write last beat indicator. |
| s_axi_wvalid | input | 1 | Write data valid. |
| s_axi_wready | output | 1 | Write data ready. |
| s_axi_bid | output | ID_WIDTH | Write response ID. |
| s_axi_bresp | output | 2 | Write response (always 2'b00 = OKAY). |
| s_axi_bvalid | output | 1 | Write response valid. |
| s_axi_bready | input | 1 | Write response ready. |
| s_axi_arid | input | ID_WIDTH | Read address ID. |
| s_axi_araddr | input | ADDR_WIDTH | Read address. |
| s_axi_arlen | input | 8 | Read burst length. |
| s_axi_arsize | input | 3 | Read burst size. |
| s_axi_arburst | input | 2 | Read burst type. |
| s_axi_arlock | input | 1 | Read lock type. |
| s_axi_arcache | input | 4 | Read cache attributes. |
| s_axi_arprot | input | 3 | Read protection attributes. |
| s_axi_arvalid | input | 1 | Read address valid. |
| s_axi_arready | output | 1 | Read address ready. |
| s_axi_rid | output | ID_WIDTH | Read data ID. |
| s_axi_rdata | output | DATA_WIDTH | Read data. |
| s_axi_rresp | output | 2 | Read response (always 2'b00 = OKAY). |
| s_axi_rlast | output | 1 | Read last beat indicator. |
| s_axi_rvalid | output | 1 | Read data valid. |
| s_axi_rready | input | 1 | Read data ready. |
| clk | input | 1 | Clock; all AXI handshakes sampled on rising edge. |
| rst | input | 1 | Active-high synchronous reset. |


## 3. 设计复杂度评估

- 状态空间：The DUT contains two independent state machines: a 3-state write FSM (IDLE, BURST, RESP) and a 2-state read FSM (IDLE, BURST). Additional state includes write/read ID, address, burst length counters, burst size/type registers, output valid registers, and a large memory array. The state space is moderate and dominated by burst counters and memory contents.

- 算术复杂度：Address increment uses (1 << size_reg) addition per beat. Burst length counters decrement from AWLEN/ARLEN. No multipliers or complex arithmetic; main complexity is correct burst sequencing and boundary detection (count == 0).

- 存储结构：A single-port RAM of size 2^(ADDR_WIDTH - log2(STRB_WIDTH)) words, each DATA_WIDTH bits wide. Default configuration: 2^14 words x 32 bits = 64 KB. Formal verification of memory contents requires symbolic indexing (fv_idx) and data-consistency abstractions to avoid state explosion.

- 参数化程度：DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, and PIPELINE_OUTPUT affect interface widths, memory depth, and R-channel timing. The SVA checker must be parameterized and cover at least PIPELINE_OUTPUT=0 and PIPELINE_OUTPUT=1 configurations. Large ADDR_WIDTH (e.g., 32+) can make full memory proofs intractable; use symbolic index and assume-guarantee reasoning.


## 4. 形式化验证范围与目标

### 4.1 纳入验证范围

- AXI4 Valid-Ready handshake rules on all five channels (AW, W, B, AR, R).
- {'Reset behavior': 'all VALID and READY outputs deasserted during and after reset.'}
- {'Write transaction flow': 'AW handshake -> W data beats with WLAST -> B response with correct BID and BVALID timing.'}
- {'Read transaction flow': 'AR handshake -> R data beats with RLAST and correct RID/RDATA timing.'}
- {'Burst handling': 'FIXED, INCR, and WRAP burst types; burst length and size boundary conditions.'}
- WSTRB byte-enable correctness for partial writes.
- {'ID reflection': 'BID and RID must match the corresponding AWID/ARID.'}
- Stability and non-deassertion of VALID signals until handshake completes (A2.3).
- {'Backpressure handling': 'BREADY and RREADY stalls must not corrupt state or lose data.'}
- Output stability when stalled (e.g., RDATA stable while RVALID && !RREADY).
- {'Liveness': 'no deadlock; every accepted request eventually completes.'}
- PIPELINE_OUTPUT=0 and PIPELINE_OUTPUT=1 configurations.


### 4.2 暂不纳入验证范围

- AXI5 extensions (atomics, MTE, snoop, wakeup, poison, credited transport) as specified in README.
- Memory content exhaustiveness (full array equivalence) due to state explosion; symbolic index used instead.
- Performance metrics (latency, throughput) beyond protocol compliance.
- Multi-manager arbitration (only one slave port exists).


## 5. 假设条件与约束

- AWVALID, WVALID, ARVALID are asserted only after reset and remain asserted until their respective READY is asserted (A2.3 stability).
- AWID, AWADDR, AWLEN, AWSIZE, AWBURST, ARID, ARADDR, ARLEN, ARSIZE, ARBURST, WDATA, WSTRB, WLAST remain stable while VALID is high and READY is low.
- BREADY and RREADY can be asserted/deasserted arbitrarily but must not glitch combinationally; they are sampled synchronously.
- rst is asserted for at least one full clock cycle at start and can be asserted synchronously at any time.
- Manager does not issue AW or AR while the DUT is in reset.
- Symbolic index fv_idx used for memory read/write consistency is stable, in-range, and never X.
- WLAST is asserted by the Manager on the final write data beat of a burst; if missing, the DUT behavior is undefined and out of scope.


## 6. 验证策略

- Layer 1: Interface-level SVA for AXI4 protocol rules derived from IHI 0022 Issue L, chapters A1-A6.
- Layer 2: Channel-specific properties for AW, W, B, AR, R channels, including handshake, stability, and payload correctness.
- Layer 3: Transaction-level properties linking address, data, and response phases (e.g., BVALID after WLAST, RLAST at correct beat).
- Use symbolic index fv_idx with three mandatory assumptions (STABLE, VALID, KNOWN) to verify memory read/write consistency without exploding the state space.
- Verify both PIPELINE_OUTPUT=0 and PIPELINE_OUTPUT=1 by parameterizing the checker and running both configurations.
- Write positive assertions (condition implies expected state change) and negative frame conditions (non-condition implies $stable) for all output registers.
- Use cover properties to prove reachability of key states: back-to-back bursts, maximum burst length, stalled B/R channels, and simultaneous read/write.
- Treat every Fail as a potential bug; classify as environment under-constraint vs. RTL defect using the decision tree in Guide_Doc/env_analysis.md.


## 7. 预期交付成果

- formal_test/.formal_records.yaml (planning, basic_info, spec, run_results, analysis, bugs, summary)
- 01_axi_ram_verification_needs_and_plan.md (auto-rendered)
- checker.sv and wrapper.sv with SVA assertions, assumptions, and cover properties
- TCL formal script for the FormalMC tool
- Bug report and analysis entries for all failing properties
- COI coverage mapping and formal summary report


## 8. 风险评估与应对

- 风险：State explosion from large memory array (2^14 x 32 bits by default)
  应对：Use symbolic index fv_idx, data-consistency abstractions, and assume-guarantee decomposition; avoid enumerating all addresses.
- 风险：Environment over-constraint causing TRIVIALLY_TRUE properties
  应对：Follow P1: treat TRIVIALLY_TRUE as an environment defect, relax assumptions, and re-verify.
- 风险：Parameterization gaps (only default parameters checked)
  应对：Parameterize the checker and explicitly verify both PIPELINE_OUTPUT=0 and 1; document other parameter combinations as future work.
- 风险：False positives from symbolic index drift
  应对：Enforce M_CK_FV_IDX_STABLE, M_CK_FV_IDX_VALID, and M_CK_FV_IDX_KNOWN as mandatory assumptions.
- 风险：AXI4 spec ambiguity or misinterpretation
  应对：Cross-reference every assertion with the exact section in AXI_spec_A1-A6.txt and record the clause in the assertion comment.


## 9. 初步缺陷发现

- WRITE_STATE_BURST: when the last W beat is accepted and s_axi_bready is low while s_axi_bvalid is already high, the FSM moves to WRITE_STATE_RESP but does not assert s_axi_bvalid_next in that state; BVALID may be dropped incorrectly.
- s_axi_bresp is hardwired to 2'b00 (OKAY); no error response is ever generated, which may violate AXI if an unsupported access occurs.
- Read channel: when PIPELINE_OUTPUT=1 and s_axi_rready is low, the pipeline register update condition (!s_axi_rvalid_pipe_reg || s_axi_rready) may cause RDATA/RID instability if the internal rvalid toggles; needs formal stability check.
- Address increment for WRAP bursts is not explicitly masked to the burst boundary; RTL only adds (1 << size_reg), so WRAP behavior may be incorrect.
- No explicit check that AWSIZE/ARSIZE <= log2(STRB_WIDTH); RTL clamps size internally, but this may mask an AXI protocol violation by the Manager.

