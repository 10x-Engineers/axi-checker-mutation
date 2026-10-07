
# axi_ram 基本信息文档

> 本文档由 `.formal_records.yaml` 自动生成，请勿手动编辑。

## 1. 模块概述

| 项目 | 内容 |
|------|------|
| 模块名称 | axi_ram |
| 模块类型 | AXI4 Subordinate RAM (single-port memory slave) |
| 顶层模块 | True |
| 设计类型 | 时序逻辑（两个独立 FSM + 同步 RAM），含可选输出流水线 |

## 2. 接口信号详细定义

### 2.1 输入端口

| 信号名 | 位宽 | 类型 | 功能描述 |
|--------|------|------|----------|
| clk | 1 | clock | 主时钟；所有 AXI 握手与状态寄存器均在上升沿采样 |
| rst | 1 | reset | 高电平有效同步复位；仅复位 FSM 与 VALID/READY 输出，不复位存储阵列 |
| s_axi_awid | ID_WIDTH | data | 写地址通道事务 ID |
| s_axi_awaddr | ADDR_WIDTH | data | 写地址（字节地址） |
| s_axi_awlen | 8 | data | 写突发长度（0..255 对应 1..256 拍） |
| s_axi_awsize | 3 | data | 写突发每拍字节数编码（2^awsize） |
| s_axi_awburst | 2 | data | 写突发类型（00 FIXED, 01 INCR, 10 WRAP） |
| s_axi_awlock | 1 | control | 写锁定属性（DUT 内部未使用） |
| s_axi_awcache | 4 | control | 写缓存属性（DUT 内部未使用） |
| s_axi_awprot | 3 | control | 写保护属性（DUT 内部未使用） |
| s_axi_awvalid | 1 | valid | 写地址有效 |
| s_axi_wdata | DATA_WIDTH | data | 写数据 |
| s_axi_wstrb | STRB_WIDTH | data | 写字节选通（byte enable） |
| s_axi_wlast | 1 | control | 写突发最后一拍指示（DUT 内部未使用，存在协议检查缺口） |
| s_axi_wvalid | 1 | valid | 写数据有效 |
| s_axi_bready | 1 | ready | 写响应就绪（Manager 施加背压） |
| s_axi_arid | ID_WIDTH | data | 读地址通道事务 ID |
| s_axi_araddr | ADDR_WIDTH | data | 读地址（字节地址） |
| s_axi_arlen | 8 | data | 读突发长度（0..255 对应 1..256 拍） |
| s_axi_arsize | 3 | data | 读突发每拍字节数编码（2^arsize） |
| s_axi_arburst | 2 | data | 读突发类型（00 FIXED, 01 INCR, 10 WRAP） |
| s_axi_arlock | 1 | control | 读锁定属性（DUT 内部未使用） |
| s_axi_arcache | 4 | control | 读缓存属性（DUT 内部未使用） |
| s_axi_arprot | 3 | control | 读保护属性（DUT 内部未使用） |
| s_axi_arvalid | 1 | valid | 读地址有效 |
| s_axi_rready | 1 | ready | 读数据就绪（Manager 施加背压） |


### 2.2 输出端口

| 信号名 | 位宽 | 类型 | 功能描述 | 潜在问题 |
|--------|------|------|----------|----------|
| s_axi_awready | 1 | ready | 写地址就绪 | 由写 FSM 状态决定，组合生成；需验证复位后与 B 通道握手时序 |
| s_axi_wready | 1 | ready | 写数据就绪 | 最后一拍接收后立即拉低；需验证与 BVALID 的交叠关系 |
| s_axi_bid | ID_WIDTH | data | 写响应 ID（回写 AWID） | BVALID 有效期间 BID 必须保持稳定 |
| s_axi_bresp | 2 | data | 写响应码，硬连 2'b00 (OKAY) | 永远不会返回错误响应；对非法访问无 SLVERR/DECERR |
| s_axi_bvalid | 1 | valid | 写响应有效 | WRITE_STATE_RESP 分支依赖 bvalid_reg 已置位；需验证 BVALID 不可在握手前撤销 |
| s_axi_arready | 1 | ready | 读地址就绪 | 由读 FSM 状态决定，组合生成 |
| s_axi_rid | ID_WIDTH | data | 读数据 ID（回写 ARID） | RVALID 有效且未握手期间必须稳定 |
| s_axi_rdata | DATA_WIDTH | data | 读数据 | RVALID && !RREADY 期间必须保持稳定；PIPELINE_OUTPUT=1 时多一级寄存器 |
| s_axi_rresp | 2 | data | 读响应码，硬连 2'b00 (OKAY) | 永远不会返回错误响应 |
| s_axi_rlast | 1 | control | 读突发最后一拍指示 | 必须在突发最后一拍精确置位，且与 RVALID 对齐 |
| s_axi_rvalid | 1 | valid | 读数据有效 | 握手完成前不可撤销；PIPELINE_OUTPUT=1 时背压路径更复杂 |


### 2.3 参数定义

| 参数名 | 默认值 | 取值范围 | 说明 |
|--------|--------|----------|------|
| DATA_WIDTH | 32 | 8, 16, 32, 64, 128...（必须能被 8 整除） | 数据总线位宽（bit） |
| ADDR_WIDTH | 16 | 任意正整数（典型 16~32） | 地址总线位宽；存储字深度 = 2^(ADDR_WIDTH - clog2(STRB_WIDTH)) |
| STRB_WIDTH | (DATA_WIDTH/8) | 派生参数，必须是 2 的幂 | 写选通位宽（字节通道数） |
| ID_WIDTH | 8 | 1~32 | AXI 事务 ID 位宽 |
| PIPELINE_OUTPUT | 0 | 0 或 1 | 为 1 时在 R 通道输出增加一级流水寄存器，影响 R 时序与背压行为 |


## 3. 功能描述

### 3.1 核心功能

- AW 通道：IDLE 态接收写地址，锁存 AWID/AWADDR/AWLEN/AWSIZE(clamp)/AWBURST 后进入 BURST
- W 通道：BURST 态逐拍接收写数据，按 WSTRB 字节选通写入 mem[write_addr_valid]
- 写地址递推：非 FIXED 突发每拍地址 += (1 << write_size_reg)；计数器自减至 0 结束
- B 通道：最后一拍 W 握手后产生 BVALID，BID 回写 AWID，BRESP 固定 OKAY；可被 BREADY 背压（RESP 态）
- AR 通道：IDLE 态接收读地址，锁存 ARID/ARADDR/ARLEN/ARSIZE(clamp)/ARBURST 后进入 BURST
- R 通道：BURST 态逐拍输出 mem[read_addr_valid]，RID 回写 ARID，最后一拍置 RLAST；支持 RREADY 背压
- PIPELINE_OUTPUT=1 时 R 通道经一级流水寄存器输出，空闲时可继续预取
- 读写通道完全独立，可并发进行
- 复位：同步高有效，复位 FSM/VALID/READY 输出；存储阵列由 initial 块清零


### 3.2 功能正确性要求

- VALID 信号（BVALID/RVALID）一旦置位，在对应 READY 握手完成前不得撤销（AXI A2.3）
- VALID && !READY 期间所有 payload（BID/RID/RDATA/RLAST）必须保持 $stable
- 复位期间及复位后，所有 VALID/READY 输出必须处于无效状态
- BID 必须等于对应写事务的 AWID；RID 必须等于对应读事务的 ARID
- RLAST 必须且仅在读突发最后一拍随 RVALID 置位
- BVALID 必须在突发最后一个 W 拍握手完成后才置位
- WSTRB 每位对应一个字节通道，仅当选通位为 1 时对应字节写入存储器
- 突发地址递推与长度计数必须与 AWLEN/ARLEN、AWSIZE/ARSIZE、AWBURST/ARBURST 一致
- 写后读数据一致性：对同一地址先写后读，读回数据应与写入数据一致（按 WSTRB 掩码）
- 活性：任何被接收的读写事务最终必须完成，不得死锁


## 4. 时钟域与复位策略

### 4.1 时钟域分析

| 项目 | 分析结果 |
|------|----------|
| 主时钟信号 | clk |
| 时钟数量 | 1 |
| 时钟类型 | 单时钟 |
| 同步/异步 | 无跨时钟域；全部信号同步于 clk 上升沿 |

### 4.2 复位策略分析

| 项目 | 分析结果 |
|------|----------|
| 复位信号 | rst |
| 复位类型 | 同步（高电平有效） |
| 初始值 | rst 有效时写 FSM 回 IDLE、AWREADY/WREADY/BVALID 清 0；读 FSM 回 IDLE、ARREADY/RVALID/RVALID_pipe 清 0；存储阵列由 initial 块清零而非复位逻辑 |

## 5. 核心组成部分

### 5.1 模块结构图

```text
+---------------------------------------------------------------+
|                           axi_ram                             |
|  AW --+--> Write FSM (IDLE/BURST/RESP) --> B (bid/bvalid)     |
|  W  --+--> mem_wr_en, wstrb 掩码写 --> mem[write_addr_valid]  |
|                                                               |
|  AR --+--> Read FSM (IDLE/BURST) --------> R (rid/rdata/rlast |
|  mem[read_addr_valid] --> rdata_reg --> [pipe_reg]  /rvalid)  |
|                                                               |
|  mem: reg[DATA_WIDTH-1:0] mem[0:2**VALID_ADDR_WIDTH-1]        |
+---------------------------------------------------------------+

```

### 5.2 数据通路

写通路：WDATA 经 WSTRB 掩码在 mem_wr_en 时写入 mem[write_addr >> clog2(STRB_WIDTH)]；读通路：mem[read_addr >> clog2(STRB_WIDTH)] 在 mem_rd_en 时打入 rdata_reg，PIPELINE_OUTPUT=1 时再经一级 pipe_reg 输出。地址高位右移 (ADDR_WIDTH-VALID_ADDR_WIDTH) 位得到字索引。

### 5.3 控制逻辑

写 FSM 三态（IDLE/BURST/RESP）控制 AWREADY/WREADY/BVALID；读 FSM 两态（IDLE/BURST）控制 ARREADY/RVALID/RLAST。突发长度计数器从 LEN 递减至 0；地址按 1<<size 递增（FIXED 除外）。两 FSM 完全独立、组合次态逻辑 + 同步寄存器。

## 6. 参数化分析

### 6.1 参数影响分析

- DATA_WIDTH 增大 -> STRB_WIDTH 增大 -> 存储字深度 2^(ADDR_WIDTH-clog2(STRB_WIDTH)) 减小；形式化状态空间随位宽指数增长
- ADDR_WIDTH 增大 -> 存储深度指数增长 -> 必须使用符号化索引 fv_idx 抽象存储内容
- ID_WIDTH 仅影响 ID 位宽与反射检查，不影响控制逻辑
- PIPELINE_OUTPUT=1 增加 R 通道一级流水：RVALID/RDATA/RLAST/RID 全部改由 pipe_reg 驱动，背压条件变为 (rready || !rvalid_pipe_reg)，需单独验证
- STRB_WIDTH 必须为 2 的幂且 WORD_SIZE*STRB_WIDTH==DATA_WIDTH，否则 initial 块报错终止


## 7. 需要特殊处理的单元

### 7.1 算术运算单元

| 单元类型 | 是否存在 | 说明 |
|----------|----------|------|
| 地址递增器 (1 << size_reg) | True | 非 FIXED 突发每拍地址 += 2^size；WRAP 未做边界回卷掩码，疑似缺陷 |
| 突发长度递减计数器 | True | 从 AWLEN/ARLEN 递减至 0 判定突发结束 |
| size 钳位逻辑 (min(size, clog2(STRB_WIDTH))) | True | AWSIZE/ARSIZE 超过总线宽度时静默钳位，可能掩盖 Manager 协议违规 |


### 7.2 存储单元

| 单元类型 | 是否存在 | 说明 |
|----------|----------|------|
| RAM 阵列 mem[2**VALID_ADDR_WIDTH] | True | 默认 2^14 x 32bit = 64KB；initial 块清零；形式化需符号化索引 |
| 事务上下文寄存器组 (id/addr/count/size/burst) | True | 读写各一组，握手时锁存，突发期间递推 |
| R 通道流水寄存器 (rid/rdata/rlast/rvalid pipe) | True | 仅 PIPELINE_OUTPUT=1 时接入输出路径 |


## 8. 形式化验证环境配置要点

### 8.1 环境配置建议

| 配置项 | 设置 |
|--------|------|
| 时钟约束 | 单一主时钟 clk，推荐 period 10ns (100MHz)，形式化工具以周期语义建模；无门控时钟、无衍生时钟，无需多时钟约束 |
| 复位序列 | 上电后先置 rst=1 至少 1 个完整时钟周期再释放；形式化中要求初始状态经复位序列进入已知状态；存储阵列依赖 initial 清零，建议复位后再假设内容已知 |

### 8.2 特殊输入约束

- P3 稳定性约束：AWVALID/WVALID/ARVALID 置位后在 READY 前不得撤销，payload 保持稳定
- WLAST 必须由 Manager 在突发最后一拍正确置位（DUT 不检查 WLAST）
- AWSIZE/ARSIZE 建议约束 <= clog2(STRB_WIDTH)，越界行为（钳位）单独分析
- 符号化索引 fv_idx 三个强制 Assume：STABLE / VALID(<深度) / KNOWN
- AWBURST/ARBURST 约束在 00/01/10 范围内，11 保留
- BREADY/RREADY 可任意变化（同步采样），用于覆盖背压场景


## 9. 总结

axi_ram 是一个单时钟、同步复位的 AXI4 Subordinate RAM，读写通道由两个独立 FSM 控制，存储阵列需符号化索引抽象。验证核心为 AXI4 五通道协议合规性（握手、稳定性、ID 反射、RLAST/BVALID 时序）与写后读数据一致性；已识别的明显缺陷线索包括：WRAP 突发未做边界回卷、BRESP/RRESP 硬连 OKAY、WLAST 未被检查、SIZE 静默钳位、WRITE_STATE_RESP 中 BVALID 依赖前态。时钟 clk 与同步复位 rst 已明确，可直接进入功能分组与 SVA 规划阶段。
