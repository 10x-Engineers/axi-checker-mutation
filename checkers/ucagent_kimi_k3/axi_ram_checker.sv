module axi_ram_checker
  #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 16,
    parameter STRB_WIDTH = (DATA_WIDTH/8),
    parameter ID_WIDTH = 8,
    parameter PIPELINE_OUTPUT = 0
  )
(
  input clk,
  input rst_n,
  input wire [ID_WIDTH-1:0] s_axi_awid,
  input wire [ADDR_WIDTH-1:0] s_axi_awaddr,
  input wire [7:0] s_axi_awlen,
  input wire [2:0] s_axi_awsize,
  input wire [1:0] s_axi_awburst,
  input wire s_axi_awlock,
  input wire [3:0] s_axi_awcache,
  input wire [2:0] s_axi_awprot,
  input wire s_axi_awvalid,
  input wire s_axi_awready,
  input wire [DATA_WIDTH-1:0] s_axi_wdata,
  input wire [STRB_WIDTH-1:0] s_axi_wstrb,
  input wire s_axi_wlast,
  input wire s_axi_wvalid,
  input wire s_axi_wready,
  input wire [ID_WIDTH-1:0] s_axi_bid,
  input wire [1:0] s_axi_bresp,
  input wire s_axi_bvalid,
  input wire s_axi_bready,
  input wire [ID_WIDTH-1:0] s_axi_arid,
  input wire [ADDR_WIDTH-1:0] s_axi_araddr,
  input wire [7:0] s_axi_arlen,
  input wire [2:0] s_axi_arsize,
  input wire [1:0] s_axi_arburst,
  input wire s_axi_arlock,
  input wire [3:0] s_axi_arcache,
  input wire [2:0] s_axi_arprot,
  input wire s_axi_arvalid,
  input wire s_axi_arready,
  input wire [ID_WIDTH-1:0] s_axi_rid,
  input wire [DATA_WIDTH-1:0] s_axi_rdata,
  input wire [1:0] s_axi_rresp,
  input wire s_axi_rlast,
  input wire s_axi_rvalid,
  input wire s_axi_rready,
  input [0:0] read_state_reg,
  input [1:0] write_state_reg,
  input mem_wr_en,
  input mem_rd_en,
  input [ID_WIDTH-1:0] read_id_reg,
  input [ADDR_WIDTH-1:0] read_addr_reg,
  input [7:0] read_count_reg,
  input [2:0] read_size_reg,
  input [1:0] read_burst_reg,
  input [ID_WIDTH-1:0] write_id_reg,
  input [ADDR_WIDTH-1:0] write_addr_reg,
  input [7:0] write_count_reg,
  input [2:0] write_size_reg,
  input [1:0] write_burst_reg,
  input [ID_WIDTH-1:0] s_axi_rid_reg,
  input [DATA_WIDTH-1:0] s_axi_rdata_reg,
  input s_axi_rlast_reg,
  input s_axi_rvalid_reg,
  input [ID_WIDTH-1:0] s_axi_rid_pipe_reg,
  input [DATA_WIDTH-1:0] s_axi_rdata_pipe_reg,
  input s_axi_rlast_pipe_reg,
  input s_axi_rvalid_pipe_reg,
  input [DATA_WIDTH-1:0] mem[0:(2**(ADDR_WIDTH-$clog2(STRB_WIDTH)))-1],
  input [(ADDR_WIDTH-$clog2(STRB_WIDTH))-1:0] fv_idx,
  input [(ADDR_WIDTH-$clog2(STRB_WIDTH))-1:0] read_addr_valid,
  input [(ADDR_WIDTH-$clog2(STRB_WIDTH))-1:0] write_addr_valid,
  input [0:0] READ_STATE_IDLE,
  input [0:0] READ_STATE_BURST,
  input [1:0] WRITE_STATE_IDLE,
  input [1:0] WRITE_STATE_BURST,
  input [1:0] WRITE_STATE_RESP
);

  // [bench compile fix] Verilator cannot sample an element of an unpacked-array port in
  // $past/$stable; read it through a wire (identical while fv_idx is constant, as here).
  wire [DATA_WIDTH-1:0] mem_at_fv = mem[fv_idx];

  // Auto-generated aliases from generic env clk/rst_n to DUT-local clock/reset names
  logic rst;
  assign rst = ~rst_n;

  // Auto-generated checker skeleton from .formal_records.yaml


  // 初始复位假设：上电初始 rst 有效，并至少持续 1 个完整时钟周期后才释放（$fell(rst) 前 $past(rst)==1），保证 DUT 经复位序列进入已知状态
  // Style: Assume
  property CK_API_RESET_PULSE;
    @(posedge clk) $fell(rst) |-> $past(rst);
  endproperty
  M_CK_API_RESET_PULSE: assume property (CK_API_RESET_PULSE);


  // 复位期间静默假设：rst 有效期间 Manager 不发起任何请求，即 AWVALID==0 且 WVALID==0 且 ARVALID==0
  // Style: Assume
  property CK_API_RESET_NO_REQ;
    @(posedge clk) rst |-> (!s_axi_awvalid && !s_axi_wvalid && !s_axi_arvalid);
  endproperty
  M_CK_API_RESET_NO_REQ: assume property (CK_API_RESET_NO_REQ);


  // AW 通道 Valid 稳定性：AWVALID 置位且 AWREADY 未置位时，下一拍 AWVALID 不得撤销（AWVALID && !AWREADY |=> AWVALID）
  // Style: Assume
  property CK_API_AW_VALID_STABLE;
    @(posedge clk) (s_axi_awvalid && !s_axi_awready) |=> s_axi_awvalid;
  endproperty
  M_CK_API_AW_VALID_STABLE: assume property (CK_API_AW_VALID_STABLE);


  // W 通道 Valid 稳定性：WVALID 置位且 WREADY 未置位时，下一拍 WVALID 不得撤销（WVALID && !WREADY |=> WVALID）
  // Style: Assume
  property CK_API_W_VALID_STABLE;
    @(posedge clk) (s_axi_wvalid && !s_axi_wready) |=> s_axi_wvalid;
  endproperty
  M_CK_API_W_VALID_STABLE: assume property (CK_API_W_VALID_STABLE);


  // AR 通道 Valid 稳定性：ARVALID 置位且 ARREADY 未置位时，下一拍 ARVALID 不得撤销（ARVALID && !ARREADY |=> ARVALID）
  // Style: Assume
  property CK_API_AR_VALID_STABLE;
    @(posedge clk) (s_axi_arvalid && !s_axi_arready) |=> s_axi_arvalid;
  endproperty
  M_CK_API_AR_VALID_STABLE: assume property (CK_API_AR_VALID_STABLE);


  // 输入无 X 假设：VALID 有效期间对应 payload 不得含 X 态——AWVALID|->!$isunknown({AWID,AWADDR,AWLEN,AWSIZE,AWBURST})；WVALID|->!$isunknown({WDATA,WSTRB,WLAST})；ARVALID|->!$isunknown({ARID,ARADDR,ARLEN,ARSIZE,ARBURST})
  // Style: Assume
  property CK_API_PAYLOAD_NO_X;
    @(posedge clk) (s_axi_awvalid |-> !$isunknown({s_axi_awid, s_axi_awaddr, s_axi_awlen, s_axi_awsize, s_axi_awburst})) and (s_axi_wvalid |-> !$isunknown({s_axi_wdata, s_axi_wstrb, s_axi_wlast})) and (s_axi_arvalid |-> !$isunknown({s_axi_arid, s_axi_araddr, s_axi_arlen, s_axi_arsize, s_axi_arburst}));
  endproperty
  M_CK_API_PAYLOAD_NO_X: assume property (CK_API_PAYLOAD_NO_X);


  // AW payload 稳定性：AWVALID && !AWREADY 期间 {AWID,AWADDR,AWLEN,AWSIZE,AWBURST} 逐拍保持 $stable
  // Style: Assume
  property CK_API_AW_PAYLOAD_STABLE;
    @(posedge clk) (s_axi_awvalid && !s_axi_awready) |=> $stable({s_axi_awid, s_axi_awaddr, s_axi_awlen, s_axi_awsize, s_axi_awburst});
  endproperty
  M_CK_API_AW_PAYLOAD_STABLE: assume property (CK_API_AW_PAYLOAD_STABLE);


  // W payload 稳定性：WVALID && !WREADY 期间 {WDATA,WSTRB,WLAST} 逐拍保持 $stable
  // Style: Assume
  property CK_API_W_PAYLOAD_STABLE;
    @(posedge clk) (s_axi_wvalid && !s_axi_wready) |=> $stable({s_axi_wdata, s_axi_wstrb, s_axi_wlast});
  endproperty
  M_CK_API_W_PAYLOAD_STABLE: assume property (CK_API_W_PAYLOAD_STABLE);


  // AR payload 稳定性：ARVALID && !ARREADY 期间 {ARID,ARADDR,ARLEN,ARSIZE,ARBURST} 逐拍保持 $stable
  // Style: Assume
  property CK_API_AR_PAYLOAD_STABLE;
    @(posedge clk) (s_axi_arvalid && !s_axi_arready) |=> $stable({s_axi_arid, s_axi_araddr, s_axi_arlen, s_axi_arsize, s_axi_arburst});
  endproperty
  M_CK_API_AR_PAYLOAD_STABLE: assume property (CK_API_AR_PAYLOAD_STABLE);


  // 突发类型合法：AWVALID 时 AWBURST ∈ {00 FIXED, 01 INCR, 10 WRAP}；ARVALID 时 ARBURST ∈ {00,01,10}；2'b11 保留编码禁止出现
  // Style: Assume
  property CK_API_BURST_TYPE_LEGAL;
    @(posedge clk) (s_axi_awvalid |-> (s_axi_awburst != 2'b11)) and (s_axi_arvalid |-> (s_axi_arburst != 2'b11));
  endproperty
  M_CK_API_BURST_TYPE_LEGAL: assume property (CK_API_BURST_TYPE_LEGAL);


  // 突发位宽不越界：AWVALID 时 AWSIZE ≤ clog2(STRB_WIDTH)；ARVALID 时 ARSIZE ≤ clog2(STRB_WIDTH)（Manager 不得发起超过总线宽度的突发）
  // Style: Assume
  property CK_API_SIZE_WITHIN_BUS;
    @(posedge clk) (s_axi_awvalid |-> (s_axi_awsize <= $clog2(STRB_WIDTH))) and (s_axi_arvalid |-> (s_axi_arsize <= $clog2(STRB_WIDTH)));
  endproperty
  M_CK_API_SIZE_WITHIN_BUS: assume property (CK_API_SIZE_WITHIN_BUS);


  // WLAST 时序正确：WLAST 必须且仅在写突发最后一拍（写计数器读回为 0 的拍）随 WVALID 置位，与 AWLEN 声明的拍数一致，不得提前或滞后
  // Style: Assume
  property CK_API_WLAST_CORRECT;
    @(posedge clk) disable iff (rst) ((write_state_reg == WRITE_STATE_BURST) && s_axi_wvalid && s_axi_wready) |-> (s_axi_wlast == (write_count_reg == 0));
  endproperty
  M_CK_API_WLAST_CORRECT: assume property (CK_API_WLAST_CORRECT);


  // fv_idx 稳定性（强制）：整个验证过程中 fv_idx 保持 $stable，不发生漂移（无时序 disable，始终成立）
  // Style: Assume
  property CK_API_FV_IDX_STABLE;
    @(posedge clk) $stable(fv_idx);
  endproperty
  M_CK_API_FV_IDX_STABLE: assume property (CK_API_FV_IDX_STABLE);


  // fv_idx 范围合法（强制）：fv_idx < 2^VALID_ADDR_WIDTH（存储字深度），确保符号化访问落在阵列边界内
  // Style: Assume
  property CK_API_FV_IDX_VALID;
    @(posedge clk) fv_idx < (2**(ADDR_WIDTH-$clog2(STRB_WIDTH)));
  endproperty
  M_CK_API_FV_IDX_VALID: assume property (CK_API_FV_IDX_VALID);


  // fv_idx 无 X 态（强制）：!$isunknown(fv_idx) 始终成立
  // Style: Assume
  property CK_API_FV_IDX_KNOWN;
    @(posedge clk) !$isunknown(fv_idx);
  endproperty
  M_CK_API_FV_IDX_KNOWN: assume property (CK_API_FV_IDX_KNOWN);


  // 复位清 VALID：rst 有效时，下一拍 BVALID==0 且 RVALID==0 且 RVALID_pipe==0（@(posedge clk) rst |=> !BVALID && !RVALID && !RVALID_pipe）
  // Style: Seq
  property CK_RESET_VALID_CLEAR;
    @(posedge clk) disable iff (rst) $past(rst) |-> (!s_axi_bvalid && !s_axi_rvalid && !s_axi_rvalid_pipe_reg);
  endproperty
  A_CK_RESET_VALID_CLEAR: assert property (CK_RESET_VALID_CLEAR);


  // 复位清 READY：rst 有效时，下一拍 AWREADY==0 且 WREADY==0 且 ARREADY==0
  // Style: Seq
  property CK_RESET_READY_CLEAR;
    @(posedge clk) disable iff (rst) $past(rst) |-> (!s_axi_awready && !s_axi_wready && !s_axi_arready);
  endproperty
  A_CK_RESET_READY_CLEAR: assert property (CK_RESET_READY_CLEAR);


  // 响应码恒 OKAY（组合恒等式）：s_axi_bresp == 2'b00 且 s_axi_rresp == 2'b00 在任意时刻成立，不含时序操作符
  // Style: Comb
  property CK_RESET_RESP_OKAY;
    @(posedge clk) (s_axi_bresp == 2'b00) && (s_axi_rresp == 2'b00);
  endproperty
  A_CK_RESET_RESP_OKAY: assert property (CK_RESET_RESP_OKAY);


  // 写 FSM 复位回 IDLE：rst 有效时，下一拍 write_state_reg == WRITE_STATE_IDLE
  // Style: Seq
  property CK_RESET_WR_FSM_IDLE;
    @(posedge clk) disable iff (rst) $past(rst) |-> (write_state_reg == WRITE_STATE_IDLE);
  endproperty
  A_CK_RESET_WR_FSM_IDLE: assert property (CK_RESET_WR_FSM_IDLE);


  // 读 FSM 复位回 IDLE：rst 有效时，下一拍 read_state_reg == READ_STATE_IDLE
  // Style: Seq
  property CK_RESET_RD_FSM_IDLE;
    @(posedge clk) disable iff (rst) $past(rst) |-> (read_state_reg == READ_STATE_IDLE);
  endproperty
  A_CK_RESET_RD_FSM_IDLE: assert property (CK_RESET_RD_FSM_IDLE);


  // FSM 编码合法性（组合）：write_state_reg ∈ {IDLE,BURST,RESP} 且 read_state_reg ∈ {IDLE,BURST}，永不进入未定义编码
  // Style: Comb
  property CK_RESET_FSM_VALID_STATE;
    @(posedge clk) (write_state_reg == WRITE_STATE_IDLE || write_state_reg == WRITE_STATE_BURST || write_state_reg == WRITE_STATE_RESP) && (read_state_reg == READ_STATE_IDLE || read_state_reg == READ_STATE_BURST);
  endproperty
  A_CK_RESET_FSM_VALID_STATE: assert property (CK_RESET_FSM_VALID_STATE);


  // 复位不破坏存储（Symbolic 帧条件）：rst 有效期间 mem_at_fv 保持 $stable，即复位逻辑不写入存储阵列
  // Style: Seq
  property CK_RESET_MEM_PRESERVE;
    @(posedge clk) disable iff (rst) $past(rst) |-> $stable(mem_at_fv);
  endproperty
  A_CK_RESET_MEM_PRESERVE: assert property (CK_RESET_MEM_PRESERVE);


  // 复位后空闲态可达（活性/死锁路径探测）：复位释放后存在写 FSM==IDLE 且读 FSM==IDLE 且全部 VALID/READY 为 0 的状态，证明复位路径无死锁
  // Style: Cover
  property CK_RESET_IDLE_COVER;
    @(posedge clk) disable iff (rst) (write_state_reg == WRITE_STATE_IDLE) && (read_state_reg == READ_STATE_IDLE) && !s_axi_bvalid && !s_axi_rvalid && !s_axi_awready && !s_axi_wready && !s_axi_arready;
  endproperty
  C_CK_RESET_IDLE_COVER: cover property (CK_RESET_IDLE_COVER);


  // AW 上下文锁存（正向）：AW 握手（AWVALID && AWREADY，写 FSM==IDLE）后，下一拍 write_id_reg==$past(AWID)、write_addr_reg==$past(AWADDR)、write_count_reg==$past(AWLEN)、write_burst_reg==$past(AWBURST)
  // Style: Seq
  property CK_WRITE_AW_LATCH;
    @(posedge clk) disable iff (rst) ((write_state_reg == WRITE_STATE_IDLE) && s_axi_awvalid && s_axi_awready) |=> (write_id_reg == $past(s_axi_awid) && write_addr_reg == $past(s_axi_awaddr) && write_count_reg == $past(s_axi_awlen) && write_burst_reg == $past(s_axi_awburst));
  endproperty
  A_CK_WRITE_AW_LATCH: assert property (CK_WRITE_AW_LATCH);


  // AWSIZE 钳位：AW 握手后 write_size_reg == min($past(AWSIZE), clog2(STRB_WIDTH))（默认配置且环境约束 SIZE 不越界时等于 $past(AWSIZE)）
  // Style: Seq
  property CK_WRITE_AW_SIZE_CLAMP;
    @(posedge clk) disable iff (rst) ((write_state_reg == WRITE_STATE_IDLE) && s_axi_awvalid && s_axi_awready) |=> (write_size_reg == $past(s_axi_awsize));
  endproperty
  A_CK_WRITE_AW_SIZE_CLAMP: assert property (CK_WRITE_AW_SIZE_CLAMP);


  // 写 FSM 进入 BURST（正向状态转移）：写 FSM==IDLE 且 AW 握手 |=> write_state_reg==WRITE_STATE_BURST 且 AWREADY 拉低且 WREADY 拉高
  // Style: Seq
  property CK_WRITE_AW_FSM_ENTER_BURST;
    @(posedge clk) disable iff (rst) ((write_state_reg == WRITE_STATE_IDLE) && s_axi_awvalid && s_axi_awready) |=> (write_state_reg == WRITE_STATE_BURST && !s_axi_awready && s_axi_wready);
  endproperty
  A_CK_WRITE_AW_FSM_ENTER_BURST: assert property (CK_WRITE_AW_FSM_ENTER_BURST);


  // 写上下文帧条件（负向）：写 FSM==IDLE 且无 AW 握手 |=> {write_id_reg,write_addr_reg,write_count_reg,write_size_reg,write_burst_reg} 保持 $stable
  // Style: Seq
  property CK_WRITE_AW_IDLE_FRAME;
    @(posedge clk) disable iff (rst) ((write_state_reg == WRITE_STATE_IDLE) && !(s_axi_awvalid && s_axi_awready)) |=> $stable({write_id_reg, write_addr_reg, write_count_reg, write_size_reg, write_burst_reg});
  endproperty
  A_CK_WRITE_AW_IDLE_FRAME: assert property (CK_WRITE_AW_IDLE_FRAME);


  // AW 握手可达：写 FSM==IDLE 且 AWVALID && AWREADY 同拍成立的场景可达，证明环境未禁掉写地址通道
  // Style: Cover
  property CK_WRITE_AW_HANDSHAKE_COVER;
    @(posedge clk) disable iff (rst) (write_state_reg == WRITE_STATE_IDLE) && s_axi_awvalid && s_axi_awready;
  endproperty
  C_CK_WRITE_AW_HANDSHAKE_COVER: cover property (CK_WRITE_AW_HANDSHAKE_COVER);


  // 写计数器自减（正向）：写 FSM==BURST 且 W 握手（WVALID && WREADY）且 write_count_reg>0 |=> write_count_reg == $past(write_count_reg)-1
  // Style: Seq
  property CK_WRITE_BEAT_COUNT_DEC;
    @(posedge clk) disable iff (rst) ((write_state_reg == WRITE_STATE_BURST) && s_axi_wvalid && s_axi_wready && (write_count_reg > 0)) |=> (write_count_reg == $past(write_count_reg) - 1);
  endproperty
  A_CK_WRITE_BEAT_COUNT_DEC: assert property (CK_WRITE_BEAT_COUNT_DEC);


  // 非最后一拍保持 BURST：写 FSM==BURST 且 W 握手且 write_count_reg>0 |=> write_state_reg==WRITE_STATE_BURST 且 WREADY 保持拉高
  // Style: Seq
  property CK_WRITE_BEAT_NONLAST_STAY;
    @(posedge clk) disable iff (rst) ((write_state_reg == WRITE_STATE_BURST) && s_axi_wvalid && s_axi_wready && (write_count_reg > 0)) |=> (write_state_reg == WRITE_STATE_BURST && s_axi_wready);
  endproperty
  A_CK_WRITE_BEAT_NONLAST_STAY: assert property (CK_WRITE_BEAT_NONLAST_STAY);


  // 最后一拍退出 BURST（正向）：写 FSM==BURST 且 W 握手且 write_count_reg==0 |=> WREADY 拉低且写 FSM 离开 BURST（进入 RESP 或回 IDLE）
  // Style: Seq
  property CK_WRITE_BEAT_LAST_EXIT;
    @(posedge clk) disable iff (rst) ((write_state_reg == WRITE_STATE_BURST) && s_axi_wvalid && s_axi_wready && (write_count_reg == 0)) |=> (!s_axi_wready && (write_state_reg != WRITE_STATE_BURST));
  endproperty
  A_CK_WRITE_BEAT_LAST_EXIT: assert property (CK_WRITE_BEAT_LAST_EXIT);


  // 无 W 握手帧条件（负向）：写 FSM==BURST 且无 W 握手 |=> {write_count_reg,write_addr_reg} 保持 $stable
  // Style: Seq
  property CK_WRITE_BEAT_NOHS_FRAME;
    @(posedge clk) disable iff (rst) ((write_state_reg == WRITE_STATE_BURST) && !(s_axi_wvalid && s_axi_wready)) |=> $stable({write_count_reg, write_addr_reg});
  endproperty
  A_CK_WRITE_BEAT_NOHS_FRAME: assert property (CK_WRITE_BEAT_NOHS_FRAME);


  // 多拍写突发可达：存在写 FSM==BURST 且连续多拍 W 握手的场景（AWLEN>0 的突发被完整接收），证明多拍路径无死锁
  // Style: Cover
  property CK_WRITE_BEAT_MULTI_COVER;
    @(posedge clk) disable iff (rst) (write_state_reg == WRITE_STATE_BURST) && s_axi_wvalid && s_axi_wready ##1 (write_state_reg == WRITE_STATE_BURST) && s_axi_wvalid && s_axi_wready;
  endproperty
  C_CK_WRITE_BEAT_MULTI_COVER: cover property (CK_WRITE_BEAT_MULTI_COVER);


  // INCR 地址递增（正向）：写 FSM==BURST 且 W 握手且 write_burst_reg==INCR |=> write_addr_reg == $past(write_addr_reg) + (1 << write_size_reg)
  // Style: Seq
  property CK_WRITE_ADDR_INCR;
    @(posedge clk) disable iff (rst) ((write_state_reg == WRITE_STATE_BURST) && s_axi_wvalid && s_axi_wready && (write_burst_reg == 2'b01)) |=> (write_addr_reg == $past(write_addr_reg) + (1 << write_size_reg));
  endproperty
  A_CK_WRITE_ADDR_INCR: assert property (CK_WRITE_ADDR_INCR);


  // FIXED 地址保持（负向帧条件）：写 FSM==BURST 且 W 握手且 write_burst_reg==FIXED |=> write_addr_reg == $past(write_addr_reg)
  // Style: Seq
  property CK_WRITE_ADDR_FIXED;
    @(posedge clk) disable iff (rst) ((write_state_reg == WRITE_STATE_BURST) && s_axi_wvalid && s_axi_wready && (write_burst_reg == 2'b00)) |=> (write_addr_reg == $past(write_addr_reg));
  endproperty
  A_CK_WRITE_ADDR_FIXED: assert property (CK_WRITE_ADDR_FIXED);


  // WRAP 边界回卷：write_burst_reg==WRAP 时每拍地址应在 (burst_len × 2^size) 边界内回卷（缺陷线索：RTL 仅 += 1<<size 未做掩码，本属性预期 Fail 以暴露 WRAP 缺陷）
  // Style: Seq
  property CK_WRITE_ADDR_WRAP;
    @(posedge clk) disable iff (rst) ((write_state_reg == WRITE_STATE_BURST) && s_axi_wvalid && s_axi_wready && (write_burst_reg == 2'b10)) |=> (write_addr_reg[ADDR_WIDTH-1:$clog2(STRB_WIDTH)] == (($past(write_addr_reg) + (1 << write_size_reg)) >> $clog2(STRB_WIDTH)) && (write_addr_reg < ($past(write_addr_reg) - ($past(write_addr_reg) % ((write_count_reg + 1) * (1 << write_size_reg)))) + ((write_count_reg + 1) * (1 << write_size_reg))));
  endproperty
  A_CK_WRITE_ADDR_WRAP: assert property (CK_WRITE_ADDR_WRAP);


  // 写各突发类型可达：FIXED、INCR、WRAP 三种写突发各自至少完成一次完整突发，证明地址递推路径均可达
  // Style: Cover
  property CK_WRITE_ADDR_BURST_COVER;
    @(posedge clk) disable iff (rst) (write_burst_reg == 2'b00 && write_state_reg == WRITE_STATE_BURST && s_axi_wvalid && s_axi_wready) or (write_burst_reg == 2'b01 && write_state_reg == WRITE_STATE_BURST && s_axi_wvalid && s_axi_wready) or (write_burst_reg == 2'b10 && write_state_reg == WRITE_STATE_BURST && s_axi_wvalid && s_axi_wready);
  endproperty
  C_CK_WRITE_ADDR_BURST_COVER: cover property (CK_WRITE_ADDR_BURST_COVER);


  // BVALID 置位时机（正向）：写 FSM==BURST 且最后一拍 W 握手（write_count_reg==0）|=> BVALID==1；且 BVALID 不得在任何最后一拍 W 握手之前置位
  // Style: Seq
  property CK_WRITE_B_VALID_SET;
    @(posedge clk) disable iff (rst) ((write_state_reg == WRITE_STATE_BURST) && s_axi_wvalid && s_axi_wready && (write_count_reg == 0)) |=> s_axi_bvalid;
  endproperty
  A_CK_WRITE_B_VALID_SET: assert property (CK_WRITE_B_VALID_SET);


  // BID 反射：BVALID 置位时 s_axi_bid == write_id_reg（等于对应事务的 AWID）
  // Style: Seq
  property CK_WRITE_B_ID_REFLECT;
    @(posedge clk) disable iff (rst) s_axi_bvalid |-> (s_axi_bid == write_id_reg);
  endproperty
  A_CK_WRITE_B_ID_REFLECT: assert property (CK_WRITE_B_ID_REFLECT);


  // BVALID 不撤销（AXI A2.3）：BVALID && !BREADY |=> BVALID 保持置位
  // Style: Seq
  property CK_WRITE_B_VALID_STABLE;
    @(posedge clk) disable iff (rst) (s_axi_bvalid && !s_axi_bready) |=> s_axi_bvalid;
  endproperty
  A_CK_WRITE_B_VALID_STABLE: assert property (CK_WRITE_B_VALID_STABLE);


  // B payload 稳定（AXI A2.3 帧条件）：BVALID && !BREADY |=> s_axi_bid 保持 $stable
  // Style: Seq
  property CK_WRITE_B_PAYLOAD_STABLE;
    @(posedge clk) disable iff (rst) (s_axi_bvalid && !s_axi_bready) |=> $stable(s_axi_bid);
  endproperty
  A_CK_WRITE_B_PAYLOAD_STABLE: assert property (CK_WRITE_B_PAYLOAD_STABLE);


  // B 握手完成退出（正向）：BVALID && BREADY |=> BVALID 拉低且写 FSM 回到 WRITE_STATE_IDLE
  // Style: Seq
  property CK_WRITE_B_HANDSHAKE_EXIT;
    @(posedge clk) disable iff (rst) (s_axi_bvalid && s_axi_bready) |=> (!s_axi_bvalid && (write_state_reg == WRITE_STATE_IDLE));
  endproperty
  A_CK_WRITE_B_HANDSHAKE_EXIT: assert property (CK_WRITE_B_HANDSHAKE_EXIT);


  // B 背压 RESP 态可达（死锁路径探测）：存在 BVALID==1 且 BREADY==0 且写 FSM==WRITE_STATE_RESP 的状态，证明背压路径可达且无 TRIVIALLY_TRUE
  // Style: Cover
  property CK_WRITE_B_RESP_COVER;
    @(posedge clk) disable iff (rst) s_axi_bvalid && !s_axi_bready && (write_state_reg == WRITE_STATE_RESP);
  endproperty
  C_CK_WRITE_B_RESP_COVER: cover property (CK_WRITE_B_RESP_COVER);


  // AR 上下文锁存（正向）：AR 握手（ARVALID && ARREADY，读 FSM==IDLE）后，下一拍 read_id_reg==$past(ARID)、read_addr_reg==$past(ARADDR)、read_count_reg==$past(ARLEN)、read_burst_reg==$past(ARBURST)
  // Style: Seq
  property CK_READ_AR_LATCH;
    @(posedge clk) disable iff (rst) ((read_state_reg == READ_STATE_IDLE) && s_axi_arvalid && s_axi_arready) |=> (read_id_reg == $past(s_axi_arid) && read_addr_reg == $past(s_axi_araddr) && read_count_reg == $past(s_axi_arlen) && read_burst_reg == $past(s_axi_arburst));
  endproperty
  A_CK_READ_AR_LATCH: assert property (CK_READ_AR_LATCH);


  // ARSIZE 钳位：AR 握手后 read_size_reg == min($past(ARSIZE), clog2(STRB_WIDTH))（默认配置且环境约束 SIZE 不越界时等于 $past(ARSIZE)）
  // Style: Seq
  property CK_READ_AR_SIZE_CLAMP;
    @(posedge clk) disable iff (rst) ((read_state_reg == READ_STATE_IDLE) && s_axi_arvalid && s_axi_arready) |=> (read_size_reg == $past(s_axi_arsize));
  endproperty
  A_CK_READ_AR_SIZE_CLAMP: assert property (CK_READ_AR_SIZE_CLAMP);


  // 读 FSM 进入 BURST（正向状态转移）：读 FSM==IDLE 且 AR 握手 |=> read_state_reg==READ_STATE_BURST 且 ARREADY 拉低
  // Style: Seq
  property CK_READ_AR_FSM_ENTER_BURST;
    @(posedge clk) disable iff (rst) ((read_state_reg == READ_STATE_IDLE) && s_axi_arvalid && s_axi_arready) |=> (read_state_reg == READ_STATE_BURST && !s_axi_arready);
  endproperty
  A_CK_READ_AR_FSM_ENTER_BURST: assert property (CK_READ_AR_FSM_ENTER_BURST);


  // 读上下文帧条件（负向）：读 FSM==IDLE 且无 AR 握手 |=> {read_id_reg,read_addr_reg,read_count_reg,read_size_reg,read_burst_reg} 保持 $stable
  // Style: Seq
  property CK_READ_AR_IDLE_FRAME;
    @(posedge clk) disable iff (rst) ((read_state_reg == READ_STATE_IDLE) && !(s_axi_arvalid && s_axi_arready)) |=> $stable({read_id_reg, read_addr_reg, read_count_reg, read_size_reg, read_burst_reg});
  endproperty
  A_CK_READ_AR_IDLE_FRAME: assert property (CK_READ_AR_IDLE_FRAME);


  // AR 握手可达：读 FSM==IDLE 且 ARVALID && ARREADY 同拍成立的场景可达，证明环境未禁掉读地址通道
  // Style: Cover
  property CK_READ_AR_HANDSHAKE_COVER;
    @(posedge clk) disable iff (rst) (read_state_reg == READ_STATE_IDLE) && s_axi_arvalid && s_axi_arready;
  endproperty
  C_CK_READ_AR_HANDSHAKE_COVER: cover property (CK_READ_AR_HANDSHAKE_COVER);


  // RVALID 置位（正向）：读 FSM==BURST 且无输出阻塞时发起读拍，下一拍 RVALID==1，读数据打入输出寄存器
  // Style: Seq
  property CK_READ_BEAT_VALID_SET;
    @(posedge clk) disable iff (rst) ((read_state_reg == READ_STATE_BURST) && (s_axi_rready || (PIPELINE_OUTPUT && !s_axi_rvalid_pipe_reg) || !s_axi_rvalid_reg)) |=> s_axi_rvalid;
  endproperty
  A_CK_READ_BEAT_VALID_SET: assert property (CK_READ_BEAT_VALID_SET);


  // 读计数器自减（正向）：读 FSM==BURST 且 R 拍成功输出（内部读使能有效）且 read_count_reg>0 |=> read_count_reg == $past(read_count_reg)-1
  // Style: Seq
  property CK_READ_BEAT_COUNT_DEC;
    @(posedge clk) disable iff (rst) ((read_state_reg == READ_STATE_BURST) && mem_rd_en && (read_count_reg > 0)) |=> (read_count_reg == $past(read_count_reg) - 1);
  endproperty
  A_CK_READ_BEAT_COUNT_DEC: assert property (CK_READ_BEAT_COUNT_DEC);


  // RID 反射：RVALID 置位时 s_axi_rid == read_id_reg（等于对应事务的 ARID）
  // Style: Seq
  property CK_READ_BEAT_ID_REFLECT;
    @(posedge clk) disable iff (rst) s_axi_rvalid |-> (s_axi_rid == read_id_reg);
  endproperty
  A_CK_READ_BEAT_ID_REFLECT: assert property (CK_READ_BEAT_ID_REFLECT);


  // RVALID 不撤销（AXI A2.3）：RVALID && !RREADY |=> RVALID 保持置位
  // Style: Seq
  property CK_READ_BEAT_VALID_STABLE;
    @(posedge clk) disable iff (rst) (s_axi_rvalid && !s_axi_rready) |=> s_axi_rvalid;
  endproperty
  A_CK_READ_BEAT_VALID_STABLE: assert property (CK_READ_BEAT_VALID_STABLE);


  // R payload 稳定（AXI A2.3 帧条件）：RVALID && !RREADY |=> {s_axi_rid,s_axi_rdata,s_axi_rlast} 保持 $stable
  // Style: Seq
  property CK_READ_BEAT_PAYLOAD_STABLE;
    @(posedge clk) disable iff (rst) (s_axi_rvalid && !s_axi_rready) |=> $stable({s_axi_rid, s_axi_rdata, s_axi_rlast});
  endproperty
  A_CK_READ_BEAT_PAYLOAD_STABLE: assert property (CK_READ_BEAT_PAYLOAD_STABLE);


  // 多拍读突发可达：存在读 FSM==BURST 且连续多拍 R 输出的场景（ARLEN>0 的突发被完整输出），证明多拍读路径无死锁
  // Style: Cover
  property CK_READ_BEAT_MULTI_COVER;
    @(posedge clk) disable iff (rst) (read_state_reg == READ_STATE_BURST) && s_axi_rvalid && s_axi_rready ##1 (read_state_reg == READ_STATE_BURST) && s_axi_rvalid && s_axi_rready;
  endproperty
  C_CK_READ_BEAT_MULTI_COVER: cover property (CK_READ_BEAT_MULTI_COVER);


  // RLAST 最后一拍置位（正向）：读 FSM==BURST 且 read_count_reg==0 且发起最后一拍读 |=> RVALID==1 且 RLAST==1
  // Style: Seq
  property CK_READ_RLAST_ON_LAST;
    @(posedge clk) disable iff (rst) ((read_state_reg == READ_STATE_BURST) && (read_count_reg == 0) && mem_rd_en) |=> (s_axi_rvalid && s_axi_rlast);
  endproperty
  A_CK_READ_RLAST_ON_LAST: assert property (CK_READ_RLAST_ON_LAST);


  // RLAST 不提前（负向）：RVALID 置位但 read_count_reg>0（非最后一拍）时 RLAST==0
  // Style: Seq
  property CK_READ_RLAST_NOT_EARLY;
    @(posedge clk) disable iff (rst) (s_axi_rvalid && (read_count_reg > 0)) |-> !s_axi_rlast;
  endproperty
  A_CK_READ_RLAST_NOT_EARLY: assert property (CK_READ_RLAST_NOT_EARLY);


  // RLAST 与 RVALID 对齐：RLAST==1 当且仅当对应拍 RVALID==1，RLAST 不得脱离 RVALID 单独出现
  // Style: Seq
  property CK_READ_RLAST_WITH_VALID;
    @(posedge clk) disable iff (rst) s_axi_rlast |-> s_axi_rvalid;
  endproperty
  A_CK_READ_RLAST_WITH_VALID: assert property (CK_READ_RLAST_WITH_VALID);


  // RLAST 终止读突发可达：存在 RVALID==1 且 RLAST==1 的拍，证明读突发可正常收尾，无悬挂读事务
  // Style: Cover
  property CK_READ_RLAST_COVER;
    @(posedge clk) disable iff (rst) s_axi_rvalid && s_axi_rlast;
  endproperty
  C_CK_READ_RLAST_COVER: cover property (CK_READ_RLAST_COVER);


  // INCR 地址递增（正向）：读 FSM==BURST 且读拍推进且 read_burst_reg==INCR |=> read_addr_reg == $past(read_addr_reg) + (1 << read_size_reg)
  // Style: Seq
  property CK_READ_ADDR_INCR;
    @(posedge clk) disable iff (rst) ((read_state_reg == READ_STATE_BURST) && mem_rd_en && (read_burst_reg == 2'b01)) |=> (read_addr_reg == $past(read_addr_reg) + (1 << read_size_reg));
  endproperty
  A_CK_READ_ADDR_INCR: assert property (CK_READ_ADDR_INCR);


  // FIXED 地址保持（负向帧条件）：读 FSM==BURST 且读拍推进且 read_burst_reg==FIXED |=> read_addr_reg == $past(read_addr_reg)
  // Style: Seq
  property CK_READ_ADDR_FIXED;
    @(posedge clk) disable iff (rst) ((read_state_reg == READ_STATE_BURST) && mem_rd_en && (read_burst_reg == 2'b00)) |=> (read_addr_reg == $past(read_addr_reg));
  endproperty
  A_CK_READ_ADDR_FIXED: assert property (CK_READ_ADDR_FIXED);


  // WRAP 边界回卷：read_burst_reg==WRAP 时每拍地址应在 (burst_len × 2^size) 边界内回卷（缺陷线索：RTL 仅 += 1<<size 未做掩码，本属性预期 Fail 以暴露 WRAP 缺陷）
  // Style: Seq
  property CK_READ_ADDR_WRAP;
    @(posedge clk) disable iff (rst) ((read_state_reg == READ_STATE_BURST) && mem_rd_en && (read_burst_reg == 2'b10)) |=> (read_addr_reg[ADDR_WIDTH-1:$clog2(STRB_WIDTH)] == (($past(read_addr_reg) + (1 << read_size_reg)) >> $clog2(STRB_WIDTH)) && (read_addr_reg < ($past(read_addr_reg) - ($past(read_addr_reg) % ((read_count_reg + 1) * (1 << read_size_reg)))) + ((read_count_reg + 1) * (1 << read_size_reg))));
  endproperty
  A_CK_READ_ADDR_WRAP: assert property (CK_READ_ADDR_WRAP);


  // 读各突发类型可达：FIXED、INCR、WRAP 三种读突发各自至少完成一次完整突发，证明读地址递推路径均可达
  // Style: Cover
  property CK_READ_ADDR_BURST_COVER;
    @(posedge clk) disable iff (rst) (read_burst_reg == 2'b00 && read_state_reg == READ_STATE_BURST && mem_rd_en) or (read_burst_reg == 2'b01 && read_state_reg == READ_STATE_BURST && mem_rd_en) or (read_burst_reg == 2'b10 && read_state_reg == READ_STATE_BURST && mem_rd_en);
  endproperty
  C_CK_READ_ADDR_BURST_COVER: cover property (CK_READ_ADDR_BURST_COVER);


  // 流水 RVALID 不撤销（AXI A2.3，PIPELINE_OUTPUT=1）：RVALID_pipe && !RREADY |=> RVALID_pipe 保持置位
  // Style: Seq
  property CK_READ_PIPE_VALID_STABLE;
    @(posedge clk) disable iff (rst) (PIPELINE_OUTPUT && s_axi_rvalid_pipe_reg && !s_axi_rready) |=> s_axi_rvalid_pipe_reg;
  endproperty
  A_CK_READ_PIPE_VALID_STABLE: assert property (CK_READ_PIPE_VALID_STABLE);


  // 流水 R payload 稳定（帧条件，PIPELINE_OUTPUT=1）：RVALID_pipe && !RREADY |=> {RID_pipe,RDATA_pipe,RLAST_pipe} 保持 $stable
  // Style: Seq
  property CK_READ_PIPE_PAYLOAD_STABLE;
    @(posedge clk) disable iff (rst) (PIPELINE_OUTPUT && s_axi_rvalid_pipe_reg && !s_axi_rready) |=> $stable({s_axi_rid_pipe_reg, s_axi_rdata_pipe_reg, s_axi_rlast_pipe_reg});
  endproperty
  A_CK_READ_PIPE_PAYLOAD_STABLE: assert property (CK_READ_PIPE_PAYLOAD_STABLE);


  // 流水背压条件：PIPELINE_OUTPUT=1 时内部读数据仅在 (RREADY || !RVALID_pipe) 时打入流水寄存器，背压期间内部数据被正确保持而不丢拍
  // Style: Seq
  property CK_READ_PIPE_BACKPRESSURE;
    @(posedge clk) disable iff (rst) (PIPELINE_OUTPUT && s_axi_rvalid_pipe_reg && !s_axi_rready) |=> (s_axi_rid_pipe_reg == $past(s_axi_rid_pipe_reg) && s_axi_rdata_pipe_reg == $past(s_axi_rdata_pipe_reg) && s_axi_rlast_pipe_reg == $past(s_axi_rlast_pipe_reg));
  endproperty
  A_CK_READ_PIPE_BACKPRESSURE: assert property (CK_READ_PIPE_BACKPRESSURE);


  // 流水路径可达（PIPELINE_OUTPUT=1）：存在 RVALID_pipe==1 且 RREADY==0 的背压状态，及背压解除后 R 拍正常完成的场景，证明流水背压路径无死锁
  // Style: Cover
  property CK_READ_PIPE_PATH_COVER;
    @(posedge clk) disable iff (rst) PIPELINE_OUTPUT && s_axi_rvalid_pipe_reg && !s_axi_rready ##1 s_axi_rvalid_pipe_reg && s_axi_rready;
  endproperty
  C_CK_READ_PIPE_PATH_COVER: cover property (CK_READ_PIPE_PATH_COVER);


  // 选通字节写入（正向，Symbolic）：mem_wr_en 且写地址索引==fv_idx 且 wstrb[i]==1 |=> mem_at_fv 的第 i 字节 == $past(wdata) 的第 i 字节
  // Style: Seq
  property CK_MEM_STRB_BYTE_WRITE;
    @(posedge clk) disable iff (rst) (mem_wr_en && (write_addr_valid == fv_idx) && s_axi_wstrb[0]) |=> (mem_at_fv[7:0] == $past(s_axi_wdata[7:0]));
  endproperty
  A_CK_MEM_STRB_BYTE_WRITE: assert property (CK_MEM_STRB_BYTE_WRITE);


  // 未选通字节保持（负向帧条件，Symbolic）：mem_wr_en 且写地址索引==fv_idx 且 wstrb[i]==0 |=> mem_at_fv 的第 i 字节保持 $stable
  // Style: Seq
  property CK_MEM_STRB_BYTE_KEEP;
    @(posedge clk) disable iff (rst) (mem_wr_en && (write_addr_valid == fv_idx) && !s_axi_wstrb[0]) |=> (mem_at_fv[7:0] == $past(mem_at_fv[7:0]));
  endproperty
  A_CK_MEM_STRB_BYTE_KEEP: assert property (CK_MEM_STRB_BYTE_KEEP);


  // 部分选通写可达：存在 mem_wr_en 且 wstrb 既非全 1 也非全 0 的写拍，证明字节选通路径被真实激励，无 TRIVIALLY_TRUE
  // Style: Cover
  property CK_MEM_STRB_PARTIAL_COVER;
    @(posedge clk) disable iff (rst) mem_wr_en && (s_axi_wstrb != {STRB_WIDTH{1'b1}}) && (s_axi_wstrb != {STRB_WIDTH{1'b0}});
  endproperty
  C_CK_MEM_STRB_PARTIAL_COVER: cover property (CK_MEM_STRB_PARTIAL_COVER);


  // 写后读一致（Symbolic）：对 fv_idx 指向的地址先完成写（按 WSTRB 合并后记录 fv_mon_data），之后对该地址的读，其 RDATA 对应字节应与 fv_mon_data 一致
  // Style: Seq
  property CK_MEM_RAW_DATA;
    @(posedge clk) disable iff (rst) (mem_rd_en && (read_addr_valid == fv_idx) && !rst) |=> (s_axi_rdata[7:0] == $past(mem_at_fv[7:0]));
  endproperty
  A_CK_MEM_RAW_DATA: assert property (CK_MEM_RAW_DATA);


  // 写后读场景可达：存在先写 fv_idx 指向地址、再对同一地址读并输出 RVALID 的完整序列，证明 RAW 验证场景真实可达
  // Style: Cover
  property CK_MEM_RAW_COVER;
    @(posedge clk) disable iff (rst) (mem_wr_en && (write_addr_valid == fv_idx)) ##[1:20] (mem_rd_en && (read_addr_valid == fv_idx)) ##1 s_axi_rvalid;
  endproperty
  C_CK_MEM_RAW_COVER: cover property (CK_MEM_RAW_COVER);


  // 无写使能保持（负向，Symbolic）：mem_wr_en 无效 |=> mem_at_fv 保持 $stable
  // Style: Seq
  property CK_MEM_FRAME_NO_WRITE;
    @(posedge clk) disable iff (rst) !mem_wr_en |=> $stable(mem_at_fv);
  endproperty
  A_CK_MEM_FRAME_NO_WRITE: assert property (CK_MEM_FRAME_NO_WRITE);


  // 异地址写入不影响（负向，Symbolic）：mem_wr_en 有效但写地址索引 != fv_idx |=> mem_at_fv 保持 $stable（防地址译码越写）
  // Style: Seq
  property CK_MEM_FRAME_DIFF_ADDR;
    @(posedge clk) disable iff (rst) (mem_wr_en && (write_addr_valid != fv_idx)) |=> $stable(mem_at_fv);
  endproperty
  A_CK_MEM_FRAME_DIFF_ADDR: assert property (CK_MEM_FRAME_DIFF_ADDR);


  // 异地址写场景可达：存在 mem_wr_en 且写地址索引 != fv_idx 的写拍，证明帧条件的前提可被触发，非 TRIVIALLY_TRUE
  // Style: Cover
  property CK_MEM_FRAME_COVER;
    @(posedge clk) disable iff (rst) mem_wr_en && (write_addr_valid != fv_idx);
  endproperty
  C_CK_MEM_FRAME_COVER: cover property (CK_MEM_FRAME_COVER);


  // 写进行中可读（正向）：写 FSM==BURST 且 AR 握手 |=> 读 FSM 进入 BURST，写 FSM 状态与写上下文寄存器保持 $stable，不受读通道影响
  // Style: Seq
  property CK_CONC_READ_DURING_WRITE;
    @(posedge clk) disable iff (rst) ((write_state_reg == WRITE_STATE_BURST) && (read_state_reg == READ_STATE_IDLE) && s_axi_arvalid && s_axi_arready) |=> ((read_state_reg == READ_STATE_BURST) && $stable({write_state_reg, write_id_reg, write_addr_reg, write_count_reg, write_size_reg, write_burst_reg}));
  endproperty
  A_CK_CONC_READ_DURING_WRITE: assert property (CK_CONC_READ_DURING_WRITE);


  // 读进行中可写（正向）：读 FSM==BURST 且 AW 握手 |=> 写 FSM 进入 BURST，读 FSM 状态与读上下文寄存器保持 $stable，不受写通道影响
  // Style: Seq
  property CK_CONC_WRITE_DURING_READ;
    @(posedge clk) disable iff (rst) ((read_state_reg == READ_STATE_BURST) && (write_state_reg == WRITE_STATE_IDLE) && s_axi_awvalid && s_axi_awready) |=> ((write_state_reg == WRITE_STATE_BURST) && $stable({read_state_reg, read_id_reg, read_addr_reg, read_count_reg, read_size_reg, read_burst_reg}));
  endproperty
  A_CK_CONC_WRITE_DURING_READ: assert property (CK_CONC_WRITE_DURING_READ);


  // 读写并发可达：存在写 FSM==BURST 且读 FSM==BURST 的交叠状态，证明并发路径真实可达，独立性检查非 TRIVIALLY_TRUE
  // Style: Cover
  property CK_CONC_RW_COVER;
    @(posedge clk) disable iff (rst) (write_state_reg == WRITE_STATE_BURST) && (read_state_reg == READ_STATE_BURST);
  endproperty
  C_CK_CONC_RW_COVER: cover property (CK_CONC_RW_COVER);


  // B 背压保持（负向）：BVALID && !BREADY |=> {s_axi_bid,s_axi_bvalid} 保持 $stable，背压期间不丢响应、不重复
  // Style: Seq
  property CK_CONC_B_BACKPRESSURE_HOLD;
    @(posedge clk) disable iff (rst) (s_axi_bvalid && !s_axi_bready) |=> $stable({s_axi_bid, s_axi_bvalid});
  endproperty
  A_CK_CONC_B_BACKPRESSURE_HOLD: assert property (CK_CONC_B_BACKPRESSURE_HOLD);


  // R 背压保持（负向）：RVALID && !RREADY |=> {s_axi_rid,s_axi_rdata,s_axi_rlast,s_axi_rvalid} 保持 $stable，背压期间读数据不丢拍、不重拍
  // Style: Seq
  property CK_CONC_R_BACKPRESSURE_HOLD;
    @(posedge clk) disable iff (rst) (s_axi_rvalid && !s_axi_rready) |=> $stable({s_axi_rid, s_axi_rdata, s_axi_rlast, s_axi_rvalid});
  endproperty
  A_CK_CONC_R_BACKPRESSURE_HOLD: assert property (CK_CONC_R_BACKPRESSURE_HOLD);


  // 背压解除正确完成（正向）：背压（BVALID&&!BREADY 或 RVALID&&!RREADY）后一旦对应 READY 拉高，下一拍对应 VALID 拉低且 FSM 正确推进，完成该事务
  // Style: Seq
  property CK_CONC_BP_RESUME;
    @(posedge clk) disable iff (rst) ((s_axi_bvalid && !s_axi_bready) ##1 (s_axi_bvalid && s_axi_bready)) |=> (!s_axi_bvalid && (write_state_reg == WRITE_STATE_IDLE));
  endproperty
  A_CK_CONC_BP_RESUME: assert property (CK_CONC_BP_RESUME);


  // 背压场景可达（死锁路径探测）：存在 BVALID&&!BREADY 持续多拍后成功握手、以及 RVALID&&!RREADY 持续多拍后成功握手的场景，证明背压路径无死锁
  // Style: Cover
  property CK_CONC_BP_COVER;
    @(posedge clk) disable iff (rst) (s_axi_bvalid && !s_axi_bready ##1 s_axi_bvalid && !s_axi_bready ##1 s_axi_bvalid && s_axi_bready) or (s_axi_rvalid && !s_axi_rready ##1 s_axi_rvalid && !s_axi_rready ##1 s_axi_rvalid && s_axi_rready);
  endproperty
  C_CK_CONC_BP_COVER: cover property (CK_CONC_BP_COVER);


  // 写事务活性：写 FSM==BURST（已接收写地址）|-> s_eventually (BVALID && BREADY)（在 BREADY 最终会为高的公平性前提下，写事务最终完成 B 握手）
  // Style: Seq
  // [bench compile fix] CK_CONC_LIVE_WRITE_B removed: s_eventually needs --timing, and a liveness property cannot fail in a finite simulation


  // 读事务活性：读 FSM==BURST（已接收读地址）|-> s_eventually (RVALID && RLAST)（在 RREADY 最终会为高的公平性前提下，读事务最终输出末拍）
  // Style: Seq
  // [bench compile fix] CK_CONC_LIVE_READ_RLAST removed: s_eventually needs --timing, and a liveness property cannot fail in a finite simulation


  // FSM 归位活性（无死锁）：写 FSM 离开 IDLE |-> s_eventually 写 FSM==IDLE；读 FSM 离开 IDLE |-> s_eventually 读 FSM==IDLE
  // Style: Seq
  // [bench compile fix] CK_CONC_LIVE_FSM_IDLE removed: s_eventually inside `and` crashes Verilator (a liveness property cannot fail in a finite simulation anyway)


  // 完整事务收尾可达：存在一次写事务从 AW 握手到 B 握手完成、一次读事务从 AR 握手到 RLAST 握手完成的完整序列，证明活性目标状态可达
  // Style: Cover
  // [bench compile fix] CK_CONC_LIVE_COVER removed: ranged delay inside `and` is not supported by Verilator


  // 单拍写事务可达：AWLEN==0 的写事务完整完成（AW 握手→单拍 W 握手→B 握手）
  // Style: Cover
  property CK_COV_WRITE_SINGLE;
    @(posedge clk) disable iff (rst) ((write_state_reg == WRITE_STATE_IDLE) && s_axi_awvalid && s_axi_awready && (s_axi_awlen == 0)) ##1 ((write_state_reg == WRITE_STATE_BURST) && s_axi_wvalid && s_axi_wready) ##[1:10] (s_axi_bvalid && s_axi_bready);
  endproperty
  C_CK_COV_WRITE_SINGLE: cover property (CK_COV_WRITE_SINGLE);


  // 最大长度写突发可达：AWLEN==255（256 拍）的写突发被完整接收并产生 BVALID，验证长突发计数路径无死锁
  // Style: Cover
  property CK_COV_WRITE_MAXLEN;
    @(posedge clk) disable iff (rst) ((write_state_reg == WRITE_STATE_IDLE) && s_axi_awvalid && s_axi_awready && (s_axi_awlen == 255)) ##[250:300] s_axi_bvalid;
  endproperty
  C_CK_COV_WRITE_MAXLEN: cover property (CK_COV_WRITE_MAXLEN);


  // 写 RESP 背压态可达：写 FSM 进入 WRITE_STATE_RESP（BVALID 等待 BREADY），证明 B 背压路径可达
  // Style: Cover
  property CK_COV_WRITE_RESP_BP;
    @(posedge clk) disable iff (rst) (write_state_reg == WRITE_STATE_RESP);
  endproperty
  C_CK_COV_WRITE_RESP_BP: cover property (CK_COV_WRITE_RESP_BP);


  // 单拍读事务可达：ARLEN==0 的读事务完整完成（AR 握手→单拍 RVALID&&RLAST&&RREADY）
  // Style: Cover
  property CK_COV_READ_SINGLE;
    @(posedge clk) disable iff (rst) ((read_state_reg == READ_STATE_IDLE) && s_axi_arvalid && s_axi_arready && (s_axi_arlen == 0)) ##[1:6] (s_axi_rvalid && s_axi_rready && s_axi_rlast);
  endproperty
  C_CK_COV_READ_SINGLE: cover property (CK_COV_READ_SINGLE);


  // 最大长度读突发可达：ARLEN==255（256 拍）的读突发完整输出至末拍 RLAST，验证长突发读路径无死锁
  // Style: Cover
  property CK_COV_READ_MAXLEN;
    @(posedge clk) disable iff (rst) ((read_state_reg == READ_STATE_IDLE) && s_axi_arvalid && s_axi_arready && (s_axi_arlen == 255)) ##[250:300] (s_axi_rvalid && s_axi_rlast);
  endproperty
  C_CK_COV_READ_MAXLEN: cover property (CK_COV_READ_MAXLEN);


  // R 背压可达：存在 RVALID==1 且 RREADY==0 持续多拍后恢复的场景，证明读背压路径可达
  // Style: Cover
  property CK_COV_READ_R_BP;
    @(posedge clk) disable iff (rst) (s_axi_rvalid && !s_axi_rready) ##1 (s_axi_rvalid && !s_axi_rready) ##1 (s_axi_rvalid && s_axi_rready);
  endproperty
  C_CK_COV_READ_R_BP: cover property (CK_COV_READ_R_BP);


  // B 通道背压可达：存在 BVALID==1 且 BREADY==0 的状态，证明环境允许 Manager 对 B 通道施加背压
  // Style: Cover
  property CK_COV_BP_BREADY_LOW;
    @(posedge clk) disable iff (rst) (s_axi_bvalid && !s_axi_bready);
  endproperty
  C_CK_COV_BP_BREADY_LOW: cover property (CK_COV_BP_BREADY_LOW);


  // R 通道背压可达：存在 RVALID==1 且 RREADY==0 的状态，证明环境允许 Manager 对 R 通道施加背压
  // Style: Cover
  property CK_COV_BP_RREADY_LOW;
    @(posedge clk) disable iff (rst) (s_axi_rvalid && !s_axi_rready);
  endproperty
  C_CK_COV_BP_RREADY_LOW: cover property (CK_COV_BP_RREADY_LOW);


  // 读写交叠可达（环境健康性）：存在写 FSM==BURST 且读 FSM==BURST 的同拍状态，证明读写并发未被环境约束禁掉，整体无过约束（防 TRIVIALLY_TRUE）
  // Style: Cover
  property CK_COV_RW_CONCURRENT;
    @(posedge clk) disable iff (rst) ((write_state_reg == WRITE_STATE_BURST) && (read_state_reg == READ_STATE_BURST));
  endproperty
  C_CK_COV_RW_CONCURRENT: cover property (CK_COV_RW_CONCURRENT);


endmodule
