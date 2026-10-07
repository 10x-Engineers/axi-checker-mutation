
# axi_ram 功能点与检测点描述

## DUT 整体功能描述

> 本文档由 `.formal_records.yaml` 自动生成，请勿手动编辑。

---

## 功能分组与检测点



### 1. 验证环境约束（AXI Manager 输入假设与符号化索引约束）

<FG-API>



#### 复位序列假设：上电后 rst 至少有效 1 个完整时钟周期再释放；复位期间 Manager 不发起 AW/AR/W 请求；rst 同步释放，保证 DUT 从已知初始状态启动

<FC-API-RESET>

**检测点：**

- <CK-API-RESET-PULSE> **(Style: Assume)** 初始复位假设：上电初始 rst 有效，并至少持续 1 个完整时钟周期后才释放（$fell(rst) 前 $past(rst)==1），保证 DUT 经复位序列进入已知状态
- <CK-API-RESET-NO-REQ> **(Style: Assume)** 复位期间静默假设：rst 有效期间 Manager 不发起任何请求，即 AWVALID==0 且 WVALID==0 且 ARVALID==0



#### Valid-Ready 稳定性假设（AXI A2.3）：AWVALID/WVALID/ARVALID 一旦置位，在对应 READY 握手完成前不得撤销；BREADY/RREADY 同步采样、允许任意翻转以覆盖背压

<FC-API-VALID-READY-STABLE>

**检测点：**

- <CK-API-AW-VALID-STABLE> **(Style: Assume)** AW 通道 Valid 稳定性：AWVALID 置位且 AWREADY 未置位时，下一拍 AWVALID 不得撤销（AWVALID && !AWREADY |=> AWVALID）
- <CK-API-W-VALID-STABLE> **(Style: Assume)** W 通道 Valid 稳定性：WVALID 置位且 WREADY 未置位时，下一拍 WVALID 不得撤销（WVALID && !WREADY |=> WVALID）
- <CK-API-AR-VALID-STABLE> **(Style: Assume)** AR 通道 Valid 稳定性：ARVALID 置位且 ARREADY 未置位时，下一拍 ARVALID 不得撤销（ARVALID && !ARREADY |=> ARVALID）



#### 输入合法性假设：VALID 有效期间 payload（ID/ADDR/LEN/SIZE/BURST/WDATA/WSTRB/WLAST）无 X 态且保持稳定；AWBURST/ARBURST ∈ {FIXED,INCR,WRAP}（2'b11 保留禁用）；AWSIZE/ARSIZE ≤ clog2(STRB_WIDTH)（Manager 不得发起超宽突发）；WLAST 在写突发最后一拍正确置位

<FC-API-PAYLOAD-KNOWN>

**检测点：**

- <CK-API-PAYLOAD-NO-X> **(Style: Assume)** 输入无 X 假设：VALID 有效期间对应 payload 不得含 X 态——AWVALID|->!$isunknown({AWID,AWADDR,AWLEN,AWSIZE,AWBURST})；WVALID|->!$isunknown({WDATA,WSTRB,WLAST})；ARVALID|->!$isunknown({ARID,ARADDR,ARLEN,ARSIZE,ARBURST})
- <CK-API-AW-PAYLOAD-STABLE> **(Style: Assume)** AW payload 稳定性：AWVALID && !AWREADY 期间 {AWID,AWADDR,AWLEN,AWSIZE,AWBURST} 逐拍保持 $stable
- <CK-API-W-PAYLOAD-STABLE> **(Style: Assume)** W payload 稳定性：WVALID && !WREADY 期间 {WDATA,WSTRB,WLAST} 逐拍保持 $stable
- <CK-API-AR-PAYLOAD-STABLE> **(Style: Assume)** AR payload 稳定性：ARVALID && !ARREADY 期间 {ARID,ARADDR,ARLEN,ARSIZE,ARBURST} 逐拍保持 $stable
- <CK-API-BURST-TYPE-LEGAL> **(Style: Assume)** 突发类型合法：AWVALID 时 AWBURST ∈ {00 FIXED, 01 INCR, 10 WRAP}；ARVALID 时 ARBURST ∈ {00,01,10}；2'b11 保留编码禁止出现
- <CK-API-SIZE-WITHIN-BUS> **(Style: Assume)** 突发位宽不越界：AWVALID 时 AWSIZE ≤ clog2(STRB_WIDTH)；ARVALID 时 ARSIZE ≤ clog2(STRB_WIDTH)（Manager 不得发起超过总线宽度的突发）
- <CK-API-WLAST-CORRECT> **(Style: Assume)** WLAST 时序正确：WLAST 必须且仅在写突发最后一拍（写计数器读回为 0 的拍）随 WVALID 置位，与 AWLEN 声明的拍数一致，不得提前或滞后



#### 符号化索引 fv_idx 假设（存储阵列验证必备）：fv_idx 在整个验证过程中保持稳定（STABLE）、取值小于存储深度（VALID）、永不出现 X 态（KNOWN），防止索引漂移造成假阳性

<FC-API-SYMBOLIC-IDX>

**检测点：**

- <CK-API-FV-IDX-STABLE> **(Style: Assume)** fv_idx 稳定性（强制）：整个验证过程中 fv_idx 保持 $stable，不发生漂移（无时序 disable，始终成立）
- <CK-API-FV-IDX-VALID> **(Style: Assume)** fv_idx 范围合法（强制）：fv_idx < 2^VALID_ADDR_WIDTH（存储字深度），确保符号化访问落在阵列边界内
- <CK-API-FV-IDX-KNOWN> **(Style: Assume)** fv_idx 无 X 态（强制）：!$isunknown(fv_idx) 始终成立


---


### 2. 复位与初始化行为

<FG-RESET>



#### 复位输出清零：rst 有效期间及复位后，所有 VALID/READY 输出（AWREADY/WREADY/BVALID/ARREADY/RVALID 及 RVALID_pipe）必须处于无效状态；BRESP/RRESP 恒为 OKAY

<FC-RESET-OUTPUT-CLEAR>

**检测点：**

- <CK-RESET-VALID-CLEAR> **(Style: Seq)** 复位清 VALID：rst 有效时，下一拍 BVALID==0 且 RVALID==0 且 RVALID_pipe==0（@(posedge clk) rst |=> !BVALID && !RVALID && !RVALID_pipe）
- <CK-RESET-READY-CLEAR> **(Style: Seq)** 复位清 READY：rst 有效时，下一拍 AWREADY==0 且 WREADY==0 且 ARREADY==0
- <CK-RESET-RESP-OKAY> **(Style: Comb)** 响应码恒 OKAY（组合恒等式）：s_axi_bresp == 2'b00 且 s_axi_rresp == 2'b00 在任意时刻成立，不含时序操作符



#### 复位 FSM 初始化：rst 有效时写 FSM 回到 WRITE_STATE_IDLE、读 FSM 回到 READ_STATE_IDLE；存储阵列由 initial 块清零而非复位逻辑，复位不破坏已写入的存储内容

<FC-RESET-FSM-INIT>

**检测点：**

- <CK-RESET-WR-FSM-IDLE> **(Style: Seq)** 写 FSM 复位回 IDLE：rst 有效时，下一拍 write_state_reg == WRITE_STATE_IDLE
- <CK-RESET-RD-FSM-IDLE> **(Style: Seq)** 读 FSM 复位回 IDLE：rst 有效时，下一拍 read_state_reg == READ_STATE_IDLE
- <CK-RESET-FSM-VALID-STATE> **(Style: Comb)** FSM 编码合法性（组合）：write_state_reg ∈ {IDLE,BURST,RESP} 且 read_state_reg ∈ {IDLE,BURST}，永不进入未定义编码
- <CK-RESET-MEM-PRESERVE> **(Style: Seq)** 复位不破坏存储（Symbolic 帧条件）：rst 有效期间 mem[fv_idx] 保持 $stable，即复位逻辑不写入存储阵列
- <CK-RESET-IDLE-COVER> **(Style: Cover)** 复位后空闲态可达（活性/死锁路径探测）：复位释放后存在写 FSM==IDLE 且读 FSM==IDLE 且全部 VALID/READY 为 0 的状态，证明复位路径无死锁


---


### 3. 写通道（AW/W/B）事务流程与协议合规

<FG-WRITE>



#### AW 通道握手与上下文锁存：WRITE_STATE_IDLE 且 AWREADY 时接收 AWVALID，同拍锁存 AWID/AWADDR/AWLEN（作为初值计数）/AWSIZE(钳位至 clog2(STRB_WIDTH))/AWBURST，次态拉低 AWREADY、拉高 WREADY，写 FSM 进入 BURST

<FC-WRITE-AW-HANDSHAKE>

**检测点：**

- <CK-WRITE-AW-LATCH> **(Style: Seq)** AW 上下文锁存（正向）：AW 握手（AWVALID && AWREADY，写 FSM==IDLE）后，下一拍 write_id_reg==$past(AWID)、write_addr_reg==$past(AWADDR)、write_count_reg==$past(AWLEN)、write_burst_reg==$past(AWBURST)
- <CK-WRITE-AW-SIZE-CLAMP> **(Style: Seq)** AWSIZE 钳位：AW 握手后 write_size_reg == min($past(AWSIZE), clog2(STRB_WIDTH))（默认配置且环境约束 SIZE 不越界时等于 $past(AWSIZE)）
- <CK-WRITE-AW-FSM-ENTER-BURST> **(Style: Seq)** 写 FSM 进入 BURST（正向状态转移）：写 FSM==IDLE 且 AW 握手 |=> write_state_reg==WRITE_STATE_BURST 且 AWREADY 拉低且 WREADY 拉高
- <CK-WRITE-AW-IDLE-FRAME> **(Style: Seq)** 写上下文帧条件（负向）：写 FSM==IDLE 且无 AW 握手 |=> {write_id_reg,write_addr_reg,write_count_reg,write_size_reg,write_burst_reg} 保持 $stable
- <CK-WRITE-AW-HANDSHAKE-COVER> **(Style: Cover)** AW 握手可达：写 FSM==IDLE 且 AWVALID && AWREADY 同拍成立的场景可达，证明环境未禁掉写地址通道



#### W 通道数据拍接收：WRITE_STATE_BURST 且 WREADY 时逐拍接收 WVALID，产生 mem_wr_en，按 WSTRB 字节选通写入 mem[write_addr_valid]，写计数器自减；非最后一拍保持 BURST 与 WREADY

<FC-WRITE-DATA-BEAT>

**检测点：**

- <CK-WRITE-BEAT-COUNT-DEC> **(Style: Seq)** 写计数器自减（正向）：写 FSM==BURST 且 W 握手（WVALID && WREADY）且 write_count_reg>0 |=> write_count_reg == $past(write_count_reg)-1
- <CK-WRITE-BEAT-NONLAST-STAY> **(Style: Seq)** 非最后一拍保持 BURST：写 FSM==BURST 且 W 握手且 write_count_reg>0 |=> write_state_reg==WRITE_STATE_BURST 且 WREADY 保持拉高
- <CK-WRITE-BEAT-LAST-EXIT> **(Style: Seq)** 最后一拍退出 BURST（正向）：写 FSM==BURST 且 W 握手且 write_count_reg==0 |=> WREADY 拉低且写 FSM 离开 BURST（进入 RESP 或回 IDLE）
- <CK-WRITE-BEAT-NOHS-FRAME> **(Style: Seq)** 无 W 握手帧条件（负向）：写 FSM==BURST 且无 W 握手 |=> {write_count_reg,write_addr_reg} 保持 $stable
- <CK-WRITE-BEAT-MULTI-COVER> **(Style: Cover)** 多拍写突发可达：存在写 FSM==BURST 且连续多拍 W 握手的场景（AWLEN>0 的突发被完整接收），证明多拍路径无死锁



#### 写突发地址递推与边界：非 FIXED 突发每拍地址 += (1 << write_size_reg)，FIXED 突发地址保持不变；INCR 顺序递增；WRAP 应做边界回卷（RTL 未掩码，疑似缺陷）；计数器到 0 判定突发结束

<FC-WRITE-ADDR-SEQ>

**检测点：**

- <CK-WRITE-ADDR-INCR> **(Style: Seq)** INCR 地址递增（正向）：写 FSM==BURST 且 W 握手且 write_burst_reg==INCR |=> write_addr_reg == $past(write_addr_reg) + (1 << write_size_reg)
- <CK-WRITE-ADDR-FIXED> **(Style: Seq)** FIXED 地址保持（负向帧条件）：写 FSM==BURST 且 W 握手且 write_burst_reg==FIXED |=> write_addr_reg == $past(write_addr_reg)
- <CK-WRITE-ADDR-WRAP> **(Style: Seq)** WRAP 边界回卷：write_burst_reg==WRAP 时每拍地址应在 (burst_len × 2^size) 边界内回卷（缺陷线索：RTL 仅 += 1<<size 未做掩码，本属性预期 Fail 以暴露 WRAP 缺陷）
- <CK-WRITE-ADDR-BURST-COVER> **(Style: Cover)** 写各突发类型可达：FIXED、INCR、WRAP 三种写突发各自至少完成一次完整突发，证明地址递推路径均可达



#### B 通道响应生成：最后一个 W 拍握手完成后 BID 回写 write_id_reg（=AWID）、BRESP 固定 OKAY、BVALID 置位；可被 BREADY 背压进入 RESP 态；BVALID 置位后在 BREADY 前不得撤销且 BID 保持稳定（AXI A2.3）；WRITE_STATE_RESP 分支存在 BVALID 依赖前态的缺陷线索

<FC-WRITE-B-RESP>

**检测点：**

- <CK-WRITE-B-VALID-SET> **(Style: Seq)** BVALID 置位时机（正向）：写 FSM==BURST 且最后一拍 W 握手（write_count_reg==0）|=> BVALID==1；且 BVALID 不得在任何最后一拍 W 握手之前置位
- <CK-WRITE-B-ID-REFLECT> **(Style: Seq)** BID 反射：BVALID 置位时 s_axi_bid == write_id_reg（等于对应事务的 AWID）
- <CK-WRITE-B-VALID-STABLE> **(Style: Seq)** BVALID 不撤销（AXI A2.3）：BVALID && !BREADY |=> BVALID 保持置位
- <CK-WRITE-B-PAYLOAD-STABLE> **(Style: Seq)** B payload 稳定（AXI A2.3 帧条件）：BVALID && !BREADY |=> s_axi_bid 保持 $stable
- <CK-WRITE-B-HANDSHAKE-EXIT> **(Style: Seq)** B 握手完成退出（正向）：BVALID && BREADY |=> BVALID 拉低且写 FSM 回到 WRITE_STATE_IDLE
- <CK-WRITE-B-RESP-COVER> **(Style: Cover)** B 背压 RESP 态可达（死锁路径探测）：存在 BVALID==1 且 BREADY==0 且写 FSM==WRITE_STATE_RESP 的状态，证明背压路径可达且无 TRIVIALLY_TRUE


---


### 4. 读通道（AR/R）事务流程与协议合规

<FG-READ>



#### AR 通道握手与上下文锁存：READ_STATE_IDLE 且 ARREADY 时接收 ARVALID，同拍锁存 ARID/ARADDR/ARLEN/ARSIZE(钳位)/ARBURST，次态拉低 ARREADY，读 FSM 进入 BURST

<FC-READ-AR-HANDSHAKE>

**检测点：**

- <CK-READ-AR-LATCH> **(Style: Seq)** AR 上下文锁存（正向）：AR 握手（ARVALID && ARREADY，读 FSM==IDLE）后，下一拍 read_id_reg==$past(ARID)、read_addr_reg==$past(ARADDR)、read_count_reg==$past(ARLEN)、read_burst_reg==$past(ARBURST)
- <CK-READ-AR-SIZE-CLAMP> **(Style: Seq)** ARSIZE 钳位：AR 握手后 read_size_reg == min($past(ARSIZE), clog2(STRB_WIDTH))（默认配置且环境约束 SIZE 不越界时等于 $past(ARSIZE)）
- <CK-READ-AR-FSM-ENTER-BURST> **(Style: Seq)** 读 FSM 进入 BURST（正向状态转移）：读 FSM==IDLE 且 AR 握手 |=> read_state_reg==READ_STATE_BURST 且 ARREADY 拉低
- <CK-READ-AR-IDLE-FRAME> **(Style: Seq)** 读上下文帧条件（负向）：读 FSM==IDLE 且无 AR 握手 |=> {read_id_reg,read_addr_reg,read_count_reg,read_size_reg,read_burst_reg} 保持 $stable
- <CK-READ-AR-HANDSHAKE-COVER> **(Style: Cover)** AR 握手可达：读 FSM==IDLE 且 ARVALID && ARREADY 同拍成立的场景可达，证明环境未禁掉读地址通道



#### R 通道数据拍输出：READ_STATE_BURST 且可输出时 mem_rd_en 置位，将 mem[read_addr_valid] 打入 rdata_reg，RID 回写 read_id_reg（=ARID），RVALID 置位并逐拍推进；读计数器自减

<FC-READ-DATA-BEAT>

**检测点：**

- <CK-READ-BEAT-VALID-SET> **(Style: Seq)** RVALID 置位（正向）：读 FSM==BURST 且无输出阻塞时发起读拍，下一拍 RVALID==1，读数据打入输出寄存器
- <CK-READ-BEAT-COUNT-DEC> **(Style: Seq)** 读计数器自减（正向）：读 FSM==BURST 且 R 拍成功输出（内部读使能有效）且 read_count_reg>0 |=> read_count_reg == $past(read_count_reg)-1
- <CK-READ-BEAT-ID-REFLECT> **(Style: Seq)** RID 反射：RVALID 置位时 s_axi_rid == read_id_reg（等于对应事务的 ARID）
- <CK-READ-BEAT-VALID-STABLE> **(Style: Seq)** RVALID 不撤销（AXI A2.3）：RVALID && !RREADY |=> RVALID 保持置位
- <CK-READ-BEAT-PAYLOAD-STABLE> **(Style: Seq)** R payload 稳定（AXI A2.3 帧条件）：RVALID && !RREADY |=> {s_axi_rid,s_axi_rdata,s_axi_rlast} 保持 $stable
- <CK-READ-BEAT-MULTI-COVER> **(Style: Cover)** 多拍读突发可达：存在读 FSM==BURST 且连续多拍 R 输出的场景（ARLEN>0 的突发被完整输出），证明多拍读路径无死锁



#### RLAST 精确生成：RLAST 必须且仅在读突发最后一拍（read_count_reg==0）随 RVALID 置位，与最后一拍数据对齐，不得提前或滞后

<FC-READ-RLAST>

**检测点：**

- <CK-READ-RLAST-ON-LAST> **(Style: Seq)** RLAST 最后一拍置位（正向）：读 FSM==BURST 且 read_count_reg==0 且发起最后一拍读 |=> RVALID==1 且 RLAST==1
- <CK-READ-RLAST-NOT-EARLY> **(Style: Seq)** RLAST 不提前（负向）：RVALID 置位但 read_count_reg>0（非最后一拍）时 RLAST==0
- <CK-READ-RLAST-WITH-VALID> **(Style: Seq)** RLAST 与 RVALID 对齐：RLAST==1 当且仅当对应拍 RVALID==1，RLAST 不得脱离 RVALID 单独出现
- <CK-READ-RLAST-COVER> **(Style: Cover)** RLAST 终止读突发可达：存在 RVALID==1 且 RLAST==1 的拍，证明读突发可正常收尾，无悬挂读事务



#### 读突发地址递推与边界：非 FIXED 突发每拍地址 += (1 << read_size_reg)，FIXED 保持不变；INCR 顺序递增；WRAP 应做边界回卷（RTL 未掩码，疑似缺陷）；计数器到 0 判定突发结束

<FC-READ-ADDR-SEQ>

**检测点：**

- <CK-READ-ADDR-INCR> **(Style: Seq)** INCR 地址递增（正向）：读 FSM==BURST 且读拍推进且 read_burst_reg==INCR |=> read_addr_reg == $past(read_addr_reg) + (1 << read_size_reg)
- <CK-READ-ADDR-FIXED> **(Style: Seq)** FIXED 地址保持（负向帧条件）：读 FSM==BURST 且读拍推进且 read_burst_reg==FIXED |=> read_addr_reg == $past(read_addr_reg)
- <CK-READ-ADDR-WRAP> **(Style: Seq)** WRAP 边界回卷：read_burst_reg==WRAP 时每拍地址应在 (burst_len × 2^size) 边界内回卷（缺陷线索：RTL 仅 += 1<<size 未做掩码，本属性预期 Fail 以暴露 WRAP 缺陷）
- <CK-READ-ADDR-BURST-COVER> **(Style: Cover)** 读各突发类型可达：FIXED、INCR、WRAP 三种读突发各自至少完成一次完整突发，证明读地址递推路径均可达



#### PIPELINE_OUTPUT=1 时 R 通道流水寄存器：rid/rdata/rlast/rvalid 经一级 pipe_reg 输出，背压条件为 (rready || !rvalid_pipe_reg)；RVALID/RDATA/RID/RLAST 在 RVALID && !RREADY 期间必须保持稳定，空闲时可预取，需单独验证

<FC-READ-PIPELINE>

**检测点：**

- <CK-READ-PIPE-VALID-STABLE> **(Style: Seq)** 流水 RVALID 不撤销（AXI A2.3，PIPELINE_OUTPUT=1）：RVALID_pipe && !RREADY |=> RVALID_pipe 保持置位
- <CK-READ-PIPE-PAYLOAD-STABLE> **(Style: Seq)** 流水 R payload 稳定（帧条件，PIPELINE_OUTPUT=1）：RVALID_pipe && !RREADY |=> {RID_pipe,RDATA_pipe,RLAST_pipe} 保持 $stable
- <CK-READ-PIPE-BACKPRESSURE> **(Style: Seq)** 流水背压条件：PIPELINE_OUTPUT=1 时内部读数据仅在 (RREADY || !RVALID_pipe) 时打入流水寄存器，背压期间内部数据被正确保持而不丢拍
- <CK-READ-PIPE-PATH-COVER> **(Style: Cover)** 流水路径可达（PIPELINE_OUTPUT=1）：存在 RVALID_pipe==1 且 RREADY==0 的背压状态，及背压解除后 R 拍正常完成的场景，证明流水背压路径无死锁


---


### 5. 存储阵列数据完整性与符号化索引验证

<FG-MEMORY>



#### WSTRB 字节选通写入：mem_wr_en 有效时，仅当 wstrb[i]==1 才将 wdata 对应字节写入 mem[write_addr_valid] 的对应字节通道；wstrb[i]==0 的字节保持原值不变（符号化索引 fv_idx 定位）

<FC-MEM-WRITE-STRB>

**检测点：**

- <CK-MEM-STRB-BYTE-WRITE> **(Style: Seq)** 选通字节写入（正向，Symbolic）：mem_wr_en 且写地址索引==fv_idx 且 wstrb[i]==1 |=> mem[fv_idx] 的第 i 字节 == $past(wdata) 的第 i 字节
- <CK-MEM-STRB-BYTE-KEEP> **(Style: Seq)** 未选通字节保持（负向帧条件，Symbolic）：mem_wr_en 且写地址索引==fv_idx 且 wstrb[i]==0 |=> mem[fv_idx] 的第 i 字节保持 $stable
- <CK-MEM-STRB-PARTIAL-COVER> **(Style: Cover)** 部分选通写可达：存在 mem_wr_en 且 wstrb 既非全 1 也非全 0 的写拍，证明字节选通路径被真实激励，无 TRIVIALLY_TRUE



#### 写后读数据一致性：对同一地址（fv_idx 指向）先写后读，读回数据应与写入数据一致（按 WSTRB 掩码逐字节合并），证明存储阵列读写通路正确

<FC-MEM-READ-AFTER-WRITE>

**检测点：**

- <CK-MEM-RAW-DATA> **(Style: Seq)** 写后读一致（Symbolic）：对 fv_idx 指向的地址先完成写（按 WSTRB 合并后记录 fv_mon_data），之后对该地址的读，其 RDATA 对应字节应与 fv_mon_data 一致
- <CK-MEM-RAW-COVER> **(Style: Cover)** 写后读场景可达：存在先写 fv_idx 指向地址、再对同一地址读并输出 RVALID 的完整序列，证明 RAW 验证场景真实可达



#### 非目标地址帧条件（负向）：当写入地址不等于 fv_idx 或 mem_wr_en 无效时，mem[fv_idx] 必须保持 $stable，证明无意外覆盖、无地址译码越写

<FC-MEM-FRAME>

**检测点：**

- <CK-MEM-FRAME-NO-WRITE> **(Style: Seq)** 无写使能保持（负向，Symbolic）：mem_wr_en 无效 |=> mem[fv_idx] 保持 $stable
- <CK-MEM-FRAME-DIFF-ADDR> **(Style: Seq)** 异地址写入不影响（负向，Symbolic）：mem_wr_en 有效但写地址索引 != fv_idx |=> mem[fv_idx] 保持 $stable（防地址译码越写）
- <CK-MEM-FRAME-COVER> **(Style: Cover)** 异地址写场景可达：存在 mem_wr_en 且写地址索引 != fv_idx 的写拍，证明帧条件的前提可被触发，非 TRIVIALLY_TRUE


---


### 6. 读写并发独立性与活性（无死锁/无饥饿）

<FG-CONCURRENCY>



#### 读写通道独立性：写 FSM 与读 FSM 完全独立，写事务进行中可同时接收并完成读事务，互不阻塞、互不干扰状态或数据

<FC-CONC-RW-INDEPENDENT>

**检测点：**

- <CK-CONC-READ-DURING-WRITE> **(Style: Seq)** 写进行中可读（正向）：写 FSM==BURST 且 AR 握手 |=> 读 FSM 进入 BURST，写 FSM 状态与写上下文寄存器保持 $stable，不受读通道影响
- <CK-CONC-WRITE-DURING-READ> **(Style: Seq)** 读进行中可写（正向）：读 FSM==BURST 且 AW 握手 |=> 写 FSM 进入 BURST，读 FSM 状态与读上下文寄存器保持 $stable，不受写通道影响
- <CK-CONC-RW-COVER> **(Style: Cover)** 读写并发可达：存在写 FSM==BURST 且读 FSM==BURST 的交叠状态，证明并发路径真实可达，独立性检查非 TRIVIALLY_TRUE



#### 背压处理：BREADY/RREADY 拉低期间，B/R 通道输出（BID/RID/RDATA/RLAST）保持 $stable 且 VALID 不撤销；背压解除后事务正确完成，不丢数据、不重复

<FC-CONC-BACKPRESSURE>

**检测点：**

- <CK-CONC-B-BACKPRESSURE-HOLD> **(Style: Seq)** B 背压保持（负向）：BVALID && !BREADY |=> {s_axi_bid,s_axi_bvalid} 保持 $stable，背压期间不丢响应、不重复
- <CK-CONC-R-BACKPRESSURE-HOLD> **(Style: Seq)** R 背压保持（负向）：RVALID && !RREADY |=> {s_axi_rid,s_axi_rdata,s_axi_rlast,s_axi_rvalid} 保持 $stable，背压期间读数据不丢拍、不重拍
- <CK-CONC-BP-RESUME> **(Style: Seq)** 背压解除正确完成（正向）：背压（BVALID&&!BREADY 或 RVALID&&!RREADY）后一旦对应 READY 拉高，下一拍对应 VALID 拉低且 FSM 正确推进，完成该事务
- <CK-CONC-BP-COVER> **(Style: Cover)** 背压场景可达（死锁路径探测）：存在 BVALID&&!BREADY 持续多拍后成功握手、以及 RVALID&&!RREADY 持续多拍后成功握手的场景，证明背压路径无死锁



#### 活性与无死锁：任何被接收的写事务最终产生 BVALID 并完成 B 握手；任何被接收的读事务最终输出全部 R 拍（含 RLAST）；读写 FSM 最终能回到 IDLE，不存在死锁或饥饿（s_eventually）

<FC-CONC-LIVENESS>

**检测点：**

- <CK-CONC-LIVE-WRITE-B> **(Style: Seq)** 写事务活性：写 FSM==BURST（已接收写地址）|-> s_eventually (BVALID && BREADY)（在 BREADY 最终会为高的公平性前提下，写事务最终完成 B 握手）
- <CK-CONC-LIVE-READ-RLAST> **(Style: Seq)** 读事务活性：读 FSM==BURST（已接收读地址）|-> s_eventually (RVALID && RLAST)（在 RREADY 最终会为高的公平性前提下，读事务最终输出末拍）
- <CK-CONC-LIVE-FSM-IDLE> **(Style: Seq)** FSM 归位活性（无死锁）：写 FSM 离开 IDLE |-> s_eventually 写 FSM==IDLE；读 FSM 离开 IDLE |-> s_eventually 读 FSM==IDLE
- <CK-CONC-LIVE-COVER> **(Style: Cover)** 完整事务收尾可达：存在一次写事务从 AW 握手到 B 握手完成、一次读事务从 AR 握手到 RLAST 握手完成的完整序列，证明活性目标状态可达


---


### 7. 可达性覆盖（关键状态与典型场景可达性证明）

<FG-COVERAGE>



#### 写场景可达性：单拍写事务、多拍突发写、最大长度突发（AWLEN=255）、INCR/FIXED/WRAP 各突发类型、WSTRB 部分选通写、B 通道背压（WRITE_STATE_RESP 态）均可达

<FC-COV-WRITE>

**检测点：**

- <CK-COV-WRITE-SINGLE> **(Style: Cover)** 单拍写事务可达：AWLEN==0 的写事务完整完成（AW 握手→单拍 W 握手→B 握手）
- <CK-COV-WRITE-MAXLEN> **(Style: Cover)** 最大长度写突发可达：AWLEN==255（256 拍）的写突发被完整接收并产生 BVALID，验证长突发计数路径无死锁
- <CK-COV-WRITE-RESP-BP> **(Style: Cover)** 写 RESP 背压态可达：写 FSM 进入 WRITE_STATE_RESP（BVALID 等待 BREADY），证明 B 背压路径可达



#### 读场景可达性：单拍读事务、多拍突发读、最大长度突发（ARLEN=255）、INCR/FIXED/WRAP 各突发类型、R 通道背压、PIPELINE_OUTPUT=1 流水路径均可达

<FC-COV-READ>

**检测点：**

- <CK-COV-READ-SINGLE> **(Style: Cover)** 单拍读事务可达：ARLEN==0 的读事务完整完成（AR 握手→单拍 RVALID&&RLAST&&RREADY）
- <CK-COV-READ-MAXLEN> **(Style: Cover)** 最大长度读突发可达：ARLEN==255（256 拍）的读突发完整输出至末拍 RLAST，验证长突发读路径无死锁
- <CK-COV-READ-R-BP> **(Style: Cover)** R 背压可达：存在 RVALID==1 且 RREADY==0 持续多拍后恢复的场景，证明读背压路径可达



#### 背压与并发场景可达性：BVALID 期间 BREADY 拉低、RVALID 期间 RREADY 拉低、读写事务同时进行（写 BURST 与读 BURST 交叠）等关键状态可达，证明环境未过约束（无 TRIVIALLY_TRUE）

<FC-COV-BACKPRESSURE>

**检测点：**

- <CK-COV-BP-BREADY-LOW> **(Style: Cover)** B 通道背压可达：存在 BVALID==1 且 BREADY==0 的状态，证明环境允许 Manager 对 B 通道施加背压
- <CK-COV-BP-RREADY-LOW> **(Style: Cover)** R 通道背压可达：存在 RVALID==1 且 RREADY==0 的状态，证明环境允许 Manager 对 R 通道施加背压
- <CK-COV-RW-CONCURRENT> **(Style: Cover)** 读写交叠可达（环境健康性）：存在写 FSM==BURST 且读 FSM==BURST 的同拍状态，证明读写并发未被环境约束禁掉，整体无过约束（防 TRIVIALLY_TRUE）


---

