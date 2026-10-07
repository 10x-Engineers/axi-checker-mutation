// DUT-independent AXI4 mutation interposer.
//
//   manager --m_*--> [ interposer ] --s_*--> subordinate
//                          |
//                          +--obs_*--> checkers under qualification
//
// Disarmed (no +mut_chan), m_* and s_* are wired straight through and obs_* equals
// the bus, so a clean run is cycle-identical to having no interposer.
//
// Armed, exactly one channel carries one mutation, selected at time 0 by plusargs:
//   +mut_id=<name>  +mut_chan=AW|W|B|AR|R  +mut_op=VALID_DROP|GLITCH|OVERRIDE|HS_DELAY|STALL|SWAP
//   +mut_nth=<n>                 hit the n-th beat that matches the trigger (default 1)
//   +mut_tfield=<F> +mut_tval=<hex>   trigger: beat with field F == tval (default: any beat)
//   +mut_xfield=<F> +mut_xval=<hex>   GLITCH: bits of F to flip; OVERRIDE: value forced into F
//   +mut2_<same keys>            optional legal companion on another channel (no INJECT)
//   +mut_stall=<n>               back-pressure cycles for VALID_DROP/GLITCH, or the obs
//                                handshake delay for HS_DELAY (default 3)
// The mutation is applied only to obs_*, so the manager and subordinate exchange
// unchanged data; the real path sees nothing but legal back-pressure.

module axi_mut_interposer #(
  parameter int ID_W   = 8,
  parameter int ADDR_W = 32,
  parameter int DATA_W = 32,
  parameter int USER_W = 1
) (
  input  logic               aclk,
  input  logic               aresetn,

  // manager-facing
  input  logic [ID_W-1:0]    m_awid,    input  logic [ADDR_W-1:0] m_awaddr,
  input  logic [7:0]         m_awlen,   input  logic [2:0]        m_awsize,
  input  logic [1:0]         m_awburst, input  logic              m_awlock,
  input  logic [3:0]         m_awcache, input  logic [2:0]        m_awprot,
  input  logic [3:0]         m_awqos,   input  logic [3:0]        m_awregion,
  input  logic [USER_W-1:0]  m_awuser,  input  logic              m_awvalid,
  output logic               m_awready,
  input  logic [DATA_W-1:0]  m_wdata,   input  logic [DATA_W/8-1:0] m_wstrb,
  input  logic               m_wlast,   input  logic [USER_W-1:0]  m_wuser,
  input  logic               m_wvalid,  output logic               m_wready,
  output logic [ID_W-1:0]    m_bid,     output logic [1:0]         m_bresp,
  output logic [USER_W-1:0]  m_buser,   output logic               m_bvalid,
  input  logic               m_bready,
  input  logic [ID_W-1:0]    m_arid,    input  logic [ADDR_W-1:0] m_araddr,
  input  logic [7:0]         m_arlen,   input  logic [2:0]        m_arsize,
  input  logic [1:0]         m_arburst, input  logic              m_arlock,
  input  logic [3:0]         m_arcache, input  logic [2:0]        m_arprot,
  input  logic [3:0]         m_arqos,   input  logic [3:0]        m_arregion,
  input  logic [USER_W-1:0]  m_aruser,  input  logic              m_arvalid,
  output logic               m_arready,
  output logic [ID_W-1:0]    m_rid,     output logic [DATA_W-1:0] m_rdata,
  output logic [1:0]         m_rresp,   output logic              m_rlast,
  output logic [USER_W-1:0]  m_ruser,   output logic              m_rvalid,
  input  logic               m_rready,

  // subordinate-facing
  output logic [ID_W-1:0]    s_awid,    output logic [ADDR_W-1:0] s_awaddr,
  output logic [7:0]         s_awlen,   output logic [2:0]        s_awsize,
  output logic [1:0]         s_awburst, output logic              s_awlock,
  output logic [3:0]         s_awcache, output logic [2:0]        s_awprot,
  output logic [3:0]         s_awqos,   output logic [3:0]        s_awregion,
  output logic [USER_W-1:0]  s_awuser,  output logic              s_awvalid,
  input  logic               s_awready,
  output logic [DATA_W-1:0]  s_wdata,   output logic [DATA_W/8-1:0] s_wstrb,
  output logic               s_wlast,   output logic [USER_W-1:0]  s_wuser,
  output logic               s_wvalid,  input  logic               s_wready,
  input  logic [ID_W-1:0]    s_bid,     input  logic [1:0]         s_bresp,
  input  logic [USER_W-1:0]  s_buser,   input  logic               s_bvalid,
  output logic               s_bready,
  output logic [ID_W-1:0]    s_arid,    output logic [ADDR_W-1:0] s_araddr,
  output logic [7:0]         s_arlen,   output logic [2:0]        s_arsize,
  output logic [1:0]         s_arburst, output logic              s_arlock,
  output logic [3:0]         s_arcache, output logic [2:0]        s_arprot,
  output logic [3:0]         s_arqos,   output logic [3:0]        s_arregion,
  output logic [USER_W-1:0]  s_aruser,  output logic              s_arvalid,
  input  logic               s_arready,
  input  logic [ID_W-1:0]    s_rid,     input  logic [DATA_W-1:0] s_rdata,
  input  logic [1:0]         s_rresp,   input  logic              s_rlast,
  input  logic [USER_W-1:0]  s_ruser,   input  logic              s_rvalid,
  output logic               s_rready,

  // observed bus: each channel as seen at its source's port, mutation applied
  output logic [ID_W-1:0]    obs_awid,    output logic [ADDR_W-1:0] obs_awaddr,
  output logic [7:0]         obs_awlen,   output logic [2:0]        obs_awsize,
  output logic [1:0]         obs_awburst, output logic              obs_awlock,
  output logic [3:0]         obs_awcache, output logic [2:0]        obs_awprot,
  output logic [3:0]         obs_awqos,   output logic [3:0]        obs_awregion,
  output logic [USER_W-1:0]  obs_awuser,  output logic              obs_awvalid,
  output logic               obs_awready,
  output logic [DATA_W-1:0]  obs_wdata,   output logic [DATA_W/8-1:0] obs_wstrb,
  output logic               obs_wlast,   output logic [USER_W-1:0]  obs_wuser,
  output logic               obs_wvalid,  output logic               obs_wready,
  output logic [ID_W-1:0]    obs_bid,     output logic [1:0]         obs_bresp,
  output logic [USER_W-1:0]  obs_buser,   output logic               obs_bvalid,
  output logic               obs_bready,
  output logic [ID_W-1:0]    obs_arid,    output logic [ADDR_W-1:0] obs_araddr,
  output logic [7:0]         obs_arlen,   output logic [2:0]        obs_arsize,
  output logic [1:0]         obs_arburst, output logic              obs_arlock,
  output logic [3:0]         obs_arcache, output logic [2:0]        obs_arprot,
  output logic [3:0]         obs_arqos,   output logic [3:0]        obs_arregion,
  output logic [USER_W-1:0]  obs_aruser,  output logic              obs_arvalid,
  output logic               obs_arready,
  output logic [ID_W-1:0]    obs_rid,     output logic [DATA_W-1:0] obs_rdata,
  output logic [1:0]         obs_rresp,   output logic              obs_rlast,
  output logic [USER_W-1:0]  obs_ruser,   output logic              obs_rvalid,
  output logic               obs_rready
);
  import axi_mut_pkg::*;

  localparam int STRB_W = DATA_W / 8;

  // Payload layouts, LSB first.
  localparam int AX_USER = 0,          AX_REGION = USER_W,     AX_QOS  = USER_W + 4,
                 AX_PROT = USER_W + 8, AX_CACHE  = USER_W + 11, AX_LOCK = USER_W + 15,
                 AX_BURST = USER_W + 16, AX_SIZE = USER_W + 18, AX_LEN  = USER_W + 21,
                 AX_ADDR = USER_W + 29, AX_ID     = USER_W + 29 + ADDR_W,
                 AX_W    = USER_W + 29 + ADDR_W + ID_W;
  localparam int W_USER = 0, W_LAST = USER_W, W_STRB = USER_W + 1,
                 W_DATA = USER_W + 1 + STRB_W, W_W = USER_W + 1 + STRB_W + DATA_W;
  localparam int B_USER = 0, B_RESP = USER_W, B_ID = USER_W + 2, B_W = USER_W + 2 + ID_W;
  localparam int R_USER = 0, R_LAST = USER_W, R_RESP = USER_W + 1, R_DATA = USER_W + 3,
                 R_ID   = USER_W + 3 + DATA_W, R_W = USER_W + 3 + DATA_W + ID_W;
  localparam int MAXW = 2048;

  function automatic void field_info(string f, output mut_chan_e ch, output int lsb,
                                     output int w);
    ch = CH_NONE; lsb = 0; w = 0;
    case (f)
      "AWID":    begin ch = CH_AW; lsb = AX_ID;     w = ID_W;   end
      "AWADDR":  begin ch = CH_AW; lsb = AX_ADDR;   w = ADDR_W; end
      "AWLEN":   begin ch = CH_AW; lsb = AX_LEN;    w = 8;      end
      "AWSIZE":  begin ch = CH_AW; lsb = AX_SIZE;   w = 3;      end
      "AWBURST": begin ch = CH_AW; lsb = AX_BURST;  w = 2;      end
      "AWLOCK":  begin ch = CH_AW; lsb = AX_LOCK;   w = 1;      end
      "AWCACHE": begin ch = CH_AW; lsb = AX_CACHE;  w = 4;      end
      "AWPROT":  begin ch = CH_AW; lsb = AX_PROT;   w = 3;      end
      "AWQOS":   begin ch = CH_AW; lsb = AX_QOS;    w = 4;      end
      "AWREGION":begin ch = CH_AW; lsb = AX_REGION; w = 4;      end
      "ARID":    begin ch = CH_AR; lsb = AX_ID;     w = ID_W;   end
      "ARADDR":  begin ch = CH_AR; lsb = AX_ADDR;   w = ADDR_W; end
      "ARLEN":   begin ch = CH_AR; lsb = AX_LEN;    w = 8;      end
      "ARSIZE":  begin ch = CH_AR; lsb = AX_SIZE;   w = 3;      end
      "ARBURST": begin ch = CH_AR; lsb = AX_BURST;  w = 2;      end
      "ARLOCK":  begin ch = CH_AR; lsb = AX_LOCK;   w = 1;      end
      "ARCACHE": begin ch = CH_AR; lsb = AX_CACHE;  w = 4;      end
      "ARPROT":  begin ch = CH_AR; lsb = AX_PROT;   w = 3;      end
      "ARQOS":   begin ch = CH_AR; lsb = AX_QOS;    w = 4;      end
      "ARREGION":begin ch = CH_AR; lsb = AX_REGION; w = 4;      end
      "WDATA":   begin ch = CH_W;  lsb = W_DATA;    w = DATA_W; end
      "WSTRB":   begin ch = CH_W;  lsb = W_STRB;    w = STRB_W; end
      "WLAST":   begin ch = CH_W;  lsb = W_LAST;    w = 1;      end
      "BID":     begin ch = CH_B;  lsb = B_ID;      w = ID_W;   end
      "BRESP":   begin ch = CH_B;  lsb = B_RESP;    w = 2;      end
      "RID":     begin ch = CH_R;  lsb = R_ID;      w = ID_W;   end
      "RDATA":   begin ch = CH_R;  lsb = R_DATA;    w = DATA_W; end
      "RRESP":   begin ch = CH_R;  lsb = R_RESP;    w = 2;      end
      "RLAST":   begin ch = CH_R;  lsb = R_LAST;    w = 1;      end
      default:   $fatal(1, "[MUT] unknown field '%s'", f);
    endcase
  endfunction

  // ---- configuration (static after time 0) ----
  // Slot 0 (+mut_*) is the mutant; slot 1 (+mut2_*) is an optional companion that is
  // legal on its own (e.g. an EXOKAY to an exclusive read) and sets up the context the
  // mutant needs. Only slot 0 reports INJECT. At most one slot per channel.
  localparam int NS = 2;
  string            mut_id;
  mut_chan_e        cfg_chan  [NS];
  mut_op_e          cfg_op    [NS];
  int unsigned      cfg_nth   [NS], cfg_stall[NS];
  logic [MAXW-1:0]  cfg_tmask [NS], cfg_tval[NS], cfg_xmask[NS], cfg_xval[NS];

  function automatic void parse_slot(int k, string pfx);
    string        s_chan, s_op, s_tfield, s_xfield;
    logic [127:0] tv, xv;
    mut_chan_e    fch;
    int           lsb, w;
    if (!$value$plusargs({pfx, "chan=%s"}, s_chan))       s_chan = "";
    if (!$value$plusargs({pfx, "op=%s"}, s_op))           s_op = "";
    if (!$value$plusargs({pfx, "nth=%d"}, cfg_nth[k]))    cfg_nth[k] = 1;
    if (!$value$plusargs({pfx, "stall=%d"}, cfg_stall[k])) cfg_stall[k] = 3;
    if (!$value$plusargs({pfx, "tfield=%s"}, s_tfield))   s_tfield = "";
    if (!$value$plusargs({pfx, "xfield=%s"}, s_xfield))   s_xfield = "";
    if (!$value$plusargs({pfx, "tval=%h"}, tv))           tv = '0;
    if (!$value$plusargs({pfx, "xval=%h"}, xv))           xv = '1;
    cfg_chan[k]  = chan_from_string(s_chan);
    cfg_op[k]    = (cfg_chan[k] == CH_NONE) ? MUT_NONE : op_from_string(s_op);
    cfg_tmask[k] = '0; cfg_tval[k] = '0; cfg_xmask[k] = '0; cfg_xval[k] = '0;
    if (cfg_op[k] == MUT_NONE) return;
    if (cfg_nth[k] == 0) $fatal(1, "[MUT] +%snth is 1-based", pfx);
    if (cfg_stall[k] < 2 && cfg_op[k] inside {MUT_VALID_DROP, MUT_GLITCH, MUT_HS_DELAY, MUT_STALL})
      $fatal(1, "[MUT] +%sstall must be >= 2 for %s", pfx, s_op);
    if (s_tfield != "") begin
      field_info(s_tfield, fch, lsb, w);
      if (fch != cfg_chan[k]) $fatal(1, "[MUT] trigger field %s is not on channel %s", s_tfield, s_chan);
      cfg_tmask[k] = ((MAXW'(1) << w) - 1) << lsb;
      cfg_tval[k]  = (MAXW'(tv) << lsb) & cfg_tmask[k];
    end
    if (s_xfield != "") begin
      field_info(s_xfield, fch, lsb, w);
      if (fch != cfg_chan[k]) $fatal(1, "[MUT] mutated field %s is not on channel %s", s_xfield, s_chan);
      if (cfg_op[k] == MUT_GLITCH) begin
        cfg_xmask[k] = (MAXW'(xv) << lsb) & (((MAXW'(1) << w) - 1) << lsb);
      end else begin
        cfg_xmask[k] = ((MAXW'(1) << w) - 1) << lsb;
        cfg_xval[k]  = (MAXW'(xv) << lsb) & cfg_xmask[k];
      end
    end else if (cfg_op[k] inside {MUT_GLITCH, MUT_OVERRIDE, MUT_SWAP}) begin
      $fatal(1, "[MUT] %s needs +%sxfield", s_op, pfx);
    end
    $display("[MUT] ARMED slot=%0d chan=%s op=%s nth=%0d tfield=%s xfield=%s",
             k, s_chan, s_op, cfg_nth[k], s_tfield, s_xfield);
  endfunction

  initial begin
    if (!$value$plusargs("mut_id=%s", mut_id)) mut_id = "";
    parse_slot(0, "mut_");
    parse_slot(1, "mut2_");
    if (cfg_op[1] != MUT_NONE && cfg_op[0] == MUT_NONE)
      $fatal(1, "[MUT] a companion (+mut2_*) needs a mutant (+mut_*)");
    if (cfg_op[1] != MUT_NONE && cfg_chan[1] == cfg_chan[0])
      $fatal(1, "[MUT] mutant and companion must be on different channels");
  end

  // Per-channel view of the slot that targets it (MUT_NONE if neither does).
  mut_op_e         ch_op   [5];
  logic            ch_prim [5];
  int unsigned     ch_nth  [5], ch_stall[5];
  logic [MAXW-1:0] ch_tmask[5], ch_tval[5], ch_xmask[5], ch_xval[5];
  always_comb begin
    for (int c = 0; c < 5; c++) begin
      ch_op[c] = MUT_NONE; ch_prim[c] = 1'b0; ch_nth[c] = 1; ch_stall[c] = 3;
      ch_tmask[c] = '0; ch_tval[c] = '0; ch_xmask[c] = '0; ch_xval[c] = '0;
      for (int k = NS - 1; k >= 0; k--) begin
        if (cfg_op[k] != MUT_NONE && int'(cfg_chan[k]) == c) begin
          ch_op[c] = cfg_op[k]; ch_prim[c] = (k == 0);
          ch_nth[c] = cfg_nth[k]; ch_stall[c] = cfg_stall[k];
          ch_tmask[c] = cfg_tmask[k]; ch_tval[c] = cfg_tval[k];
          ch_xmask[c] = cfg_xmask[k]; ch_xval[c] = cfg_xval[k];
        end
      end
    end
  end

  // ---- channels ----
  logic [AX_W-1:0] aw_src, aw_dst, aw_obs, ar_src, ar_dst, ar_obs;
  logic [W_W-1:0]  w_src,  w_dst,  w_obs;
  logic [B_W-1:0]  b_src,  b_dst,  b_obs;
  logic [R_W-1:0]  r_src,  r_dst,  r_obs;
  logic            inj_aw, inj_w, inj_b, inj_ar, inj_r;

  assign aw_src = {m_awid, m_awaddr, m_awlen, m_awsize, m_awburst, m_awlock, m_awcache,
                   m_awprot, m_awqos, m_awregion, m_awuser};
  assign ar_src = {m_arid, m_araddr, m_arlen, m_arsize, m_arburst, m_arlock, m_arcache,
                   m_arprot, m_arqos, m_arregion, m_aruser};
  assign w_src  = {m_wdata, m_wstrb, m_wlast, m_wuser};
  assign b_src  = {s_bid, s_bresp, s_buser};
  assign r_src  = {s_rid, s_rdata, s_rresp, s_rlast, s_ruser};

  axi_mut_chan #(.W(AX_W)) u_aw (
    .clk(aclk), .rst_n(aresetn),
    .src_valid(m_awvalid), .src_ready(m_awready), .src_payload(aw_src),
    .dst_valid(s_awvalid), .dst_ready(s_awready), .dst_payload(aw_dst),
    .obs_valid(obs_awvalid), .obs_ready(obs_awready), .obs_payload(aw_obs),
    .op(ch_op[CH_AW]), .nth(ch_nth[CH_AW]), .stall(ch_stall[CH_AW]),
    .tmask(ch_tmask[CH_AW][AX_W-1:0]), .tval(ch_tval[CH_AW][AX_W-1:0]),
    .xmask(ch_xmask[CH_AW][AX_W-1:0]), .xval(ch_xval[CH_AW][AX_W-1:0]), .inject(inj_aw));

  axi_mut_chan #(.W(W_W)) u_w (
    .clk(aclk), .rst_n(aresetn),
    .src_valid(m_wvalid), .src_ready(m_wready), .src_payload(w_src),
    .dst_valid(s_wvalid), .dst_ready(s_wready), .dst_payload(w_dst),
    .obs_valid(obs_wvalid), .obs_ready(obs_wready), .obs_payload(w_obs),
    .op(ch_op[CH_W]), .nth(ch_nth[CH_W]), .stall(ch_stall[CH_W]),
    .tmask(ch_tmask[CH_W][W_W-1:0]), .tval(ch_tval[CH_W][W_W-1:0]),
    .xmask(ch_xmask[CH_W][W_W-1:0]), .xval(ch_xval[CH_W][W_W-1:0]), .inject(inj_w));

  axi_mut_chan #(.W(B_W)) u_b (
    .clk(aclk), .rst_n(aresetn),
    .src_valid(s_bvalid), .src_ready(s_bready), .src_payload(b_src),
    .dst_valid(m_bvalid), .dst_ready(m_bready), .dst_payload(b_dst),
    .obs_valid(obs_bvalid), .obs_ready(obs_bready), .obs_payload(b_obs),
    .op(ch_op[CH_B]), .nth(ch_nth[CH_B]), .stall(ch_stall[CH_B]),
    .tmask(ch_tmask[CH_B][B_W-1:0]), .tval(ch_tval[CH_B][B_W-1:0]),
    .xmask(ch_xmask[CH_B][B_W-1:0]), .xval(ch_xval[CH_B][B_W-1:0]), .inject(inj_b));

  axi_mut_chan #(.W(AX_W)) u_ar (
    .clk(aclk), .rst_n(aresetn),
    .src_valid(m_arvalid), .src_ready(m_arready), .src_payload(ar_src),
    .dst_valid(s_arvalid), .dst_ready(s_arready), .dst_payload(ar_dst),
    .obs_valid(obs_arvalid), .obs_ready(obs_arready), .obs_payload(ar_obs),
    .op(ch_op[CH_AR]), .nth(ch_nth[CH_AR]), .stall(ch_stall[CH_AR]),
    .tmask(ch_tmask[CH_AR][AX_W-1:0]), .tval(ch_tval[CH_AR][AX_W-1:0]),
    .xmask(ch_xmask[CH_AR][AX_W-1:0]), .xval(ch_xval[CH_AR][AX_W-1:0]), .inject(inj_ar));

  axi_mut_chan #(.W(R_W)) u_r (
    .clk(aclk), .rst_n(aresetn),
    .src_valid(s_rvalid), .src_ready(s_rready), .src_payload(r_src),
    .dst_valid(m_rvalid), .dst_ready(m_rready), .dst_payload(r_dst),
    .obs_valid(obs_rvalid), .obs_ready(obs_rready), .obs_payload(r_obs),
    .op(ch_op[CH_R]), .nth(ch_nth[CH_R]), .stall(ch_stall[CH_R]),
    .tmask(ch_tmask[CH_R][R_W-1:0]), .tval(ch_tval[CH_R][R_W-1:0]),
    .xmask(ch_xmask[CH_R][R_W-1:0]), .xval(ch_xval[CH_R][R_W-1:0]), .inject(inj_r));

  assign {s_awid, s_awaddr, s_awlen, s_awsize, s_awburst, s_awlock, s_awcache,
          s_awprot, s_awqos, s_awregion, s_awuser} = aw_dst;
  assign {s_arid, s_araddr, s_arlen, s_arsize, s_arburst, s_arlock, s_arcache,
          s_arprot, s_arqos, s_arregion, s_aruser} = ar_dst;
  assign {s_wdata, s_wstrb, s_wlast, s_wuser}       = w_dst;
  assign {m_bid, m_bresp, m_buser}                  = b_dst;
  assign {m_rid, m_rdata, m_rresp, m_rlast, m_ruser} = r_dst;

  assign {obs_awid, obs_awaddr, obs_awlen, obs_awsize, obs_awburst, obs_awlock, obs_awcache,
          obs_awprot, obs_awqos, obs_awregion, obs_awuser} = aw_obs;
  assign {obs_arid, obs_araddr, obs_arlen, obs_arsize, obs_arburst, obs_arlock, obs_arcache,
          obs_arprot, obs_arqos, obs_arregion, obs_aruser} = ar_obs;
  assign {obs_wdata, obs_wstrb, obs_wlast, obs_wuser}       = w_obs;
  assign {obs_bid, obs_bresp, obs_buser}                    = b_obs;
  assign {obs_rid, obs_rdata, obs_rresp, obs_rlast, obs_ruser} = r_obs;

  // One line per injection; the harness grades kills against this timestamp.
  always @(posedge aclk)
    if ((inj_aw && ch_prim[CH_AW]) || (inj_w && ch_prim[CH_W]) || (inj_b && ch_prim[CH_B]) ||
        (inj_ar && ch_prim[CH_AR]) || (inj_r && ch_prim[CH_R]))
      $display("[MUT] INJECT id=%s t=%0t", mut_id, $time);

endmodule
