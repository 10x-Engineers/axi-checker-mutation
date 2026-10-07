`default_nettype none
// =============================================================================
// axi_checker_set.sv
//
// Passive AXI4 protocol checker and functional coverage model.
// Rules derived from ARM IHI 0022 Issue L, "AMBA AXI Protocol Specification",
// Part A, chapters A1-A6. AXI4 Valid-Ready transport only. AXI5 extensions
// (atomics, MTE, snoop/DVM, wakeup, poison, credited transport, ...) are out
// of scope and are not checked.
//
// The checker observes one AXI4 interface between one Manager and one
// Subordinate and flags behaviour of EITHER side that the spec forbids.
// Clocked on the ACLK rising edge; ARESETn is active-low.
//
// Notes / limitations:
//  - Assumes ADDR_W >= 12 (for the 4KB boundary check) and DATA_W a power of 2.
//  - Write data is permitted to lead the write request (A2.6 p.41); the
//    WSTRB-container check is only applied once the matching AW is known.
//  - Tracking FIFO depths are bounded (see localparams); overflow only limits
//    the checker's own bookkeeping, not the DUT.
// =============================================================================

module axi_checker_set #(
  parameter int ID_W = 8, parameter int ADDR_W = 32, parameter int DATA_W = 32, parameter int USER_W = 1
) (
  input logic aclk,
  input logic aresetn,
  input logic [ID_W-1:0] awid,
  input logic [ADDR_W-1:0] awaddr,
  input logic [8-1:0] awlen,
  input logic [3-1:0] awsize,
  input logic [2-1:0] awburst,
  input logic awlock,
  input logic [4-1:0] awcache,
  input logic [3-1:0] awprot,
  input logic [4-1:0] awqos,
  input logic [4-1:0] awregion,
  input logic [USER_W-1:0] awuser,
  input logic awvalid,
  input logic awready,
  input logic [DATA_W-1:0] wdata,
  input logic [DATA_W/8-1:0] wstrb,
  input logic wlast,
  input logic [USER_W-1:0] wuser,
  input logic wvalid,
  input logic wready,
  input logic [ID_W-1:0] bid,
  input logic [2-1:0] bresp,
  input logic [USER_W-1:0] buser,
  input logic bvalid,
  input logic bready,
  input logic [ID_W-1:0] arid,
  input logic [ADDR_W-1:0] araddr,
  input logic [8-1:0] arlen,
  input logic [3-1:0] arsize,
  input logic [2-1:0] arburst,
  input logic arlock,
  input logic [4-1:0] arcache,
  input logic [3-1:0] arprot,
  input logic [4-1:0] arqos,
  input logic [4-1:0] arregion,
  input logic [USER_W-1:0] aruser,
  input logic arvalid,
  input logic arready,
  input logic [ID_W-1:0] rid,
  input logic [DATA_W-1:0] rdata,
  input logic [2-1:0] rresp,
  input logic rlast,
  input logic [USER_W-1:0] ruser,
  input logic rvalid,
  input logic rready
);

  // =========================================================================
  // Constants and helper functions
  // =========================================================================
  localparam int DBYTES   = DATA_W/8;            // data channel width in bytes
  localparam int STRB_W   = DATA_W/8;            // WSTRB width
  localparam int MAX_SIZE = $clog2(DBYTES);      // largest legal AxSIZE
  localparam int NUM_IDS  = (1 << ID_W);

  localparam int AWF_D = 64;  localparam int AWF_A = $clog2(AWF_D); // AWs awaiting W data
  localparam int PRE_D = 64;  localparam int PRE_A = $clog2(PRE_D); // leading W bursts awaiting AW
  localparam int CMD_D = 16;  localparam int CMD_A = $clog2(CMD_D); // per-ID completed writes awaiting B
  localparam int RTK_D = 16;  localparam int RTK_A = $clog2(RTK_D); // per-ID outstanding reads

  localparam logic [63:0] DBM = 64'(DBYTES) - 64'd1; // byte-lane index mask

  // Legal AxCACHE encodings (Table A4.4); all other values are reserved.
  function automatic logic awcache_ok(input logic [3:0] c);
    case (c)
      4'b0000, 4'b0001, 4'b0010, 4'b0011,
      4'b0110, 4'b0111, 4'b1010, 4'b1011,
      4'b1110, 4'b1111 : awcache_ok = 1'b1;
      default          : awcache_ok = 1'b0;
    endcase
  endfunction

  function automatic logic arcache_ok(input logic [3:0] c);
    case (c)
      4'b0000, 4'b0001, 4'b0010, 4'b0011,
      4'b1010, 4'b1011, 4'b1110, 4'b1111 : arcache_ok = 1'b1;
      default                            : arcache_ok = 1'b0;
    endcase
  endfunction

  // =========================================================================
  // Channel handshakes
  // =========================================================================
  logic aw_hs, w_hs, b_hs, ar_hs, r_hs;
  assign aw_hs = awvalid && awready;
  assign w_hs  = wvalid  && wready;
  assign b_hs  = bvalid  && bready;
  assign ar_hs = arvalid && arready;
  assign r_hs  = rvalid  && rready;

  // =========================================================================
  // Derived request quantities (AW and AR)
  // =========================================================================
  logic [8:0]        aw_beats, ar_beats;         // transfers = AxLEN+1
  logic [15:0]       aw_tot_b, ar_tot_b;         // total bytes = (AxLEN+1)<<AxSIZE
  logic [ADDR_W-1:0] aw_size_msk, ar_size_msk;   // (1<<AxSIZE)-1
  logic [ADDR_W-1:0] aw_tot_msk, ar_tot_msk;     // total bytes - 1
  logic [16:0]       aw_page_end, ar_page_end;   // addr[11:0] + total bytes (INCR)
  logic [16:0]       aw_page_end_fx, ar_page_end_fx; // addr[11:0] + size bytes (FIXED)
  logic              aw_wrap_len_ok, ar_wrap_len_ok;
  logic              aw_excl_len_pow2, ar_excl_len_pow2;

  assign aw_beats   = {1'b0, awlen} + 9'd1;
  assign aw_tot_b   = ({7'd0, aw_beats} << awsize);
  assign aw_size_msk = (ADDR_W'(1) << awsize) - ADDR_W'(1);
  assign aw_tot_msk = ADDR_W'({1'b0, aw_tot_b}) - ADDR_W'(1);
  assign aw_page_end    = {5'd0, awaddr[11:0]} + {1'b0, aw_tot_b};
  assign aw_page_end_fx = {5'd0, awaddr[11:0]} + (17'(1) << awsize);
  assign aw_wrap_len_ok = (awlen == 8'd1) || (awlen == 8'd3) ||
                          (awlen == 8'd7) || (awlen == 8'd15);
  assign aw_excl_len_pow2 = (awlen == 8'd0)  || (awlen == 8'd1) || (awlen == 8'd3)  ||
                            (awlen == 8'd7)  || (awlen == 8'd15) || (awlen == 8'd31) ||
                            (awlen == 8'd63) || (awlen == 8'd127);

  assign ar_beats   = {1'b0, arlen} + 9'd1;
  assign ar_tot_b   = ({7'd0, ar_beats} << arsize);
  assign ar_size_msk = (ADDR_W'(1) << arsize) - ADDR_W'(1);
  assign ar_tot_msk = ADDR_W'({1'b0, ar_tot_b}) - ADDR_W'(1);
  assign ar_page_end    = {5'd0, araddr[11:0]} + {1'b0, ar_tot_b};
  assign ar_page_end_fx = {5'd0, araddr[11:0]} + (17'(1) << arsize);
  assign ar_wrap_len_ok = (arlen == 8'd1) || (arlen == 8'd3) ||
                          (arlen == 8'd7) || (arlen == 8'd15);
  assign ar_excl_len_pow2 = (arlen == 8'd0)  || (arlen == 8'd1) || (arlen == 8'd3)  ||
                            (arlen == 8'd7)  || (arlen == 8'd15) || (arlen == 8'd31) ||
                            (arlen == 8'd63) || (arlen == 8'd127);

  // =========================================================================
  // Write transaction tracking
  //  - aw_fifo: accepted AWs whose write data has not yet completed.
  //  - pre_*:   completed (WLAST-terminated) leading write data bursts that
  //             arrived before their AW (allowed by A2.6 p.41).
  //  Invariant: aw_fifo and pre FIFO are never both non-empty.
  // =========================================================================
  typedef struct packed {
    logic [ID_W-1:0]   id;
    logic [7:0]        len;
    logic [2:0]        size;
    logic [1:0]        burst;
    logic              lock;
    logic [ADDR_W-1:0] addr;
  } aw_rec_t;

  aw_rec_t          aw_fifo [0:AWF_D-1];
  logic [AWF_A-1:0] awf_wr, awf_rd;
  logic [AWF_A:0]   awf_cnt;

  logic [8:0]       pre_beats [0:PRE_D-1];
  logic [PRE_A-1:0] pre_wr, pre_rd;
  logic [PRE_A:0]   pre_cnt;

  logic [8:0]       w_beat;      // completed beats of the burst currently on W

  aw_rec_t          head_rec;
  logic [8:0]       head_beats;
  logic [8:0]       w_beat_p1;
  logic             w_final_beat;
  logic [8:0]       pre_head;

  always_comb head_rec = aw_fifo[awf_rd];
  assign head_beats   = {1'b0, head_rec.len} + 9'd1;
  assign w_beat_p1    = w_beat + 9'd1;
  assign w_final_beat = (w_beat_p1 == head_beats);
  assign pre_head     = pre_beats[pre_rd];

  // ---------------- Byte-lane calculation for the current W beat ----------
  // Implements the transfer address / byte lane equations of A3.1.6 (p.49-50).
  logic [6:0]        w_lane_lo, w_lane_hi;
  logic [STRB_W-1:0] w_lane_mask;

  always_comb begin : p_lane
    logic [63:0] start, sz, total, aligned, wrap_lo, off, addr_n;
    start   = 64'(head_rec.addr);
    sz      = 64'd1 << head_rec.size;
    total   = sz * (64'(head_rec.len) + 64'd1);
    aligned = (start >> head_rec.size) << head_rec.size;
    if ((w_beat == 9'd0) || (head_rec.burst == 2'b00)) begin
      addr_n = start;                                  // first transfer / FIXED
    end else if (head_rec.burst == 2'b10) begin        // WRAP
      wrap_lo = start & ~(total - 64'd1);
      off     = (aligned - wrap_lo) + (64'(w_beat) * sz);
      addr_n  = wrap_lo + (off & (total - 64'd1));
    end else begin                                     // INCR
      addr_n  = aligned + (64'(w_beat) * sz);
    end
    if ((w_beat == 9'd0) || (head_rec.burst == 2'b00)) begin
      // First (possibly unaligned) transfer; FIXED keeps these lanes constant.
      w_lane_lo = 7'(start & DBM);
      w_lane_hi = 7'((aligned + sz - 64'd1) & DBM);
    end else begin
      w_lane_lo = 7'(addr_n & DBM);
      w_lane_hi = 7'((addr_n + sz - 64'd1) & DBM);
    end
  end

  always_comb begin : p_mask
    w_lane_mask = '0;
    for (int i = 0; i < STRB_W; i++) begin
      if ((i >= int'(w_lane_lo)) && (i <= int'(w_lane_hi))) w_lane_mask[i] = 1'b1;
    end
  end

  // ---------------- Write tracking events --------------------------------
  logic awf_push, awf_pop, pre_push, pre_pop;
  assign awf_push = aw_hs && (pre_cnt == '0) && !awf_cnt[AWF_A];
  assign awf_pop  = w_hs && (awf_cnt != '0) && (wlast || w_final_beat);
  assign pre_push = w_hs && (awf_cnt == '0) && wlast && !pre_cnt[PRE_A];
  assign pre_pop  = aw_hs && (pre_cnt != '0);

  // A write transaction becomes complete when both its AW and its WLAST have
  // been seen. The two sources are mutually exclusive by the FIFO invariant.
  logic            cmpl_push;
  logic [ID_W-1:0] cmpl_id;
  logic            cmpl_lock;
  always_comb begin : p_cmpl
    cmpl_push = 1'b0;
    cmpl_id   = head_rec.id;
    cmpl_lock = head_rec.lock;
    if (w_hs && wlast && (awf_cnt != '0)) begin
      cmpl_push = 1'b1;                          // WLAST completes the oldest pending AW
    end else if (aw_hs && (pre_cnt != '0)) begin
      cmpl_push = 1'b1;                          // AW matches a leading data burst
      cmpl_id   = awid;
      cmpl_lock = awlock;
    end
  end

  always_ff @(posedge aclk) begin : f_wtrack
    if (!aresetn) begin
      awf_wr <= '0; awf_rd <= '0; awf_cnt <= '0;
      pre_wr <= '0; pre_rd <= '0; pre_cnt <= '0;
      w_beat <= '0;
    end else begin
      if (w_hs) begin
        if (awf_pop || ((awf_cnt == '0) && wlast)) w_beat <= '0;
        else                                       w_beat <= w_beat + 9'd1;
      end
      if (awf_push) begin
        aw_fifo[awf_wr].id    <= awid;
        aw_fifo[awf_wr].len   <= awlen;
        aw_fifo[awf_wr].size  <= awsize;
        aw_fifo[awf_wr].burst <= awburst;
        aw_fifo[awf_wr].lock  <= awlock;
        aw_fifo[awf_wr].addr  <= awaddr;
        awf_wr <= awf_wr + 1'b1;
      end
      if (awf_pop) awf_rd <= awf_rd + 1'b1;
      case ({awf_push, awf_pop})
        2'b10:   awf_cnt <= awf_cnt + 1'b1;
        2'b01:   awf_cnt <= awf_cnt - 1'b1;
        default: ;
      endcase
      if (pre_push) begin
        pre_beats[pre_wr] <= w_beat_p1;
        pre_wr <= pre_wr + 1'b1;
      end
      if (pre_pop) pre_rd <= pre_rd + 1'b1;
      case ({pre_push, pre_pop})
        2'b10:   pre_cnt <= pre_cnt + 1'b1;
        2'b01:   pre_cnt <= pre_cnt - 1'b1;
        default: ;
      endcase
    end
  end

  // =========================================================================
  // B channel tracking: per-ID FIFO of completed, unanswered write
  // transactions (B responses may be out of order across IDs, but in order
  // within an ID - A5.1 p.90, A5.3.4 p.95).
  // =========================================================================
  logic             c_lock [0:NUM_IDS-1][0:CMD_D-1];
  logic [CMD_A-1:0] c_wr   [0:NUM_IDS-1];
  logic [CMD_A-1:0] c_rd   [0:NUM_IDS-1];
  logic [CMD_A:0]   c_cnt  [0:NUM_IDS-1];
  logic [15:0]      cmpl_total;

  logic b_pend, b_head_lock, b_pop, cmpl_push_ok;
  assign b_pend       = (c_cnt[bid] != '0);
  assign b_head_lock  = c_lock[bid][c_rd[bid]];
  assign b_pop        = b_hs && b_pend;
  assign cmpl_push_ok = cmpl_push && !c_cnt[cmpl_id][CMD_A];

  always_ff @(posedge aclk) begin : f_cmpl
    if (!aresetn) begin
      for (int i = 0; i < NUM_IDS; i++) begin
        c_wr[i]  <= '0;
        c_rd[i]  <= '0;
        c_cnt[i] <= '0;
      end
      cmpl_total <= '0;
    end else begin
      if (cmpl_push_ok) begin
        c_lock[cmpl_id][c_wr[cmpl_id]] <= cmpl_lock;
        c_wr[cmpl_id] <= c_wr[cmpl_id] + 1'b1;
      end
      if (b_pop) c_rd[bid] <= c_rd[bid] + 1'b1;
      case ({cmpl_push_ok, b_pop})
        2'b10: c_cnt[cmpl_id] <= c_cnt[cmpl_id] + 1'b1;
        2'b01: c_cnt[bid]     <= c_cnt[bid] - 1'b1;
        2'b11: if (cmpl_id != bid) begin
                 c_cnt[cmpl_id] <= c_cnt[cmpl_id] + 1'b1;
                 c_cnt[bid]     <= c_cnt[bid] - 1'b1;
               end
        default: ;
      endcase
      case ({cmpl_push_ok, b_pop})
        2'b10:   cmpl_total <= cmpl_total + 16'd1;
        2'b01:   cmpl_total <= cmpl_total - 16'd1;
        default: ;
      endcase
    end
  end

  // =========================================================================
  // R channel tracking: per-ID FIFO of accepted ARs (R data is in order
  // within an ID, may interleave across IDs - A5.6/A5.6.1 p.101).
  // =========================================================================
  logic [7:0]       r_len  [0:NUM_IDS-1][0:RTK_D-1];
  logic             r_lck  [0:NUM_IDS-1][0:RTK_D-1];
  logic [RTK_A-1:0] r_wr   [0:NUM_IDS-1];
  logic [RTK_A-1:0] r_rd   [0:NUM_IDS-1];
  logic [RTK_A:0]   r_cnt  [0:NUM_IDS-1];
  logic [8:0]       r_beat [0:NUM_IDS-1];
  logic             r_exok [0:NUM_IDS-1];

  logic       r_pend, r_head_lck, r_last_beat, r_exok_cur, ar_push, r_pop;
  logic [7:0] r_head_len;

  assign r_pend      = (r_cnt[rid] != '0);
  assign r_head_len  = r_len[rid][r_rd[rid]];
  assign r_head_lck  = r_lck[rid][r_rd[rid]];
  assign r_last_beat = (r_beat[rid] == {1'b0, r_head_len});
  assign r_exok_cur  = r_exok[rid];
  assign ar_push     = ar_hs && !r_cnt[arid][RTK_A];
  assign r_pop       = r_hs && rlast && r_pend;

  always_ff @(posedge aclk) begin : f_rtrack
    if (!aresetn) begin
      for (int i = 0; i < NUM_IDS; i++) begin
        r_wr[i]   <= '0;
        r_rd[i]   <= '0;
        r_cnt[i]  <= '0;
        r_beat[i] <= '0;
        r_exok[i] <= '0;
      end
    end else begin
      if (ar_push) begin
        r_len[arid][r_wr[arid]] <= arlen;
        r_lck[arid][r_wr[arid]] <= arlock;
        r_wr[arid] <= r_wr[arid] + 1'b1;
      end
      if (r_pop) r_rd[rid] <= r_rd[rid] + 1'b1;
      case ({ar_push, r_pop})
        2'b10: r_cnt[arid] <= r_cnt[arid] + 1'b1;
        2'b01: r_cnt[rid]  <= r_cnt[rid] - 1'b1;
        2'b11: if (arid != rid) begin
                 r_cnt[arid] <= r_cnt[arid] + 1'b1;
                 r_cnt[rid]  <= r_cnt[rid] - 1'b1;
               end
        default: ;
      endcase
      if (r_hs && r_pend) begin
        if (r_beat[rid] == 9'd0) r_exok[rid] <= (rresp == 2'b01);
        if (rlast) r_beat[rid] <= '0;
        else       r_beat[rid] <= r_beat[rid] + 9'd1;
      end
    end
  end

  // =========================================================================
  // Exclusive-read-in-flight tracking (per ID), for the exclusive sequence
  // ordering rule of A6.3.2.
  // =========================================================================
  logic [7:0] xrd_cnt [0:NUM_IDS-1];
  logic       xrd_pend_aw, xrd_inc, xrd_dec;
  assign xrd_pend_aw = (xrd_cnt[awid] != '0);
  assign xrd_inc     = ar_hs && arlock;
  assign xrd_dec     = r_pop && r_head_lck && (xrd_cnt[rid] != '0);

  always_ff @(posedge aclk) begin : f_xrd
    if (!aresetn) begin
      for (int i = 0; i < NUM_IDS; i++) xrd_cnt[i] <= '0;
    end else begin
      case ({xrd_inc, xrd_dec})
        2'b10: xrd_cnt[arid] <= xrd_cnt[arid] + 8'd1;
        2'b01: xrd_cnt[rid]  <= xrd_cnt[rid] - 8'd1;
        2'b11: if (arid != rid) begin
                 xrd_cnt[arid] <= xrd_cnt[arid] + 8'd1;
                 xrd_cnt[rid]  <= xrd_cnt[rid] - 8'd1;
               end
        default: ;
      endcase
    end
  end

  // =========================================================================
  // Miscellaneous counters used by coverage
  // =========================================================================
  logic [15:0]     w_outst, r_outst;
  logic [ID_W-1:0] prev_rid, prev_bid;
  logic            prev_rid_v, prev_bid_v, prev_r_open;

  always_ff @(posedge aclk) begin : f_misc
    if (!aresetn) begin
      w_outst <= '0; r_outst <= '0;
      prev_rid <= '0; prev_bid <= '0;
      prev_rid_v <= 1'b0; prev_bid_v <= 1'b0; prev_r_open <= 1'b0;
    end else begin
      case ({aw_hs, b_hs})
        2'b10:   w_outst <= w_outst + 16'd1;
        2'b01:   if (w_outst != '0) w_outst <= w_outst - 16'd1;
        default: ;
      endcase
      case ({ar_hs, (r_hs && rlast)})
        2'b10:   r_outst <= r_outst + 16'd1;
        2'b01:   if (r_outst != '0) r_outst <= r_outst - 16'd1;
        default: ;
      endcase
      if (r_hs) begin
        prev_rid    <= rid;
        prev_rid_v  <= 1'b1;
        prev_r_open <= !rlast;
      end
      if (b_hs) begin
        prev_bid   <= bid;
        prev_bid_v <= 1'b1;
      end
    end
  end

  // =========================================================================
  //                          PROTOCOL ASSERTIONS
  // =========================================================================

  // ---------------- Reset (A2.1.2, A2.3) ----------------
  // SPEC: A2.1.2 p.27 / A2.3 p.29: VALID signals must be LOW during reset and must
  // remain deasserted at least until the rising ACLK edge after ARESETn is HIGH.
  A_RST_AWVALID_LOW: assert property (@(posedge aclk)
    (!aresetn || $rose(aresetn)) |-> !awvalid);
  // SPEC: A2.1.2 p.27 / A2.3 p.29: VALID signals must be LOW during reset (W channel).
  A_RST_WVALID_LOW: assert property (@(posedge aclk)
    (!aresetn || $rose(aresetn)) |-> !wvalid);
  // SPEC: A2.1.2 p.27 / A2.3 p.29: VALID signals must be LOW during reset (B channel).
  A_RST_BVALID_LOW: assert property (@(posedge aclk)
    (!aresetn || $rose(aresetn)) |-> !bvalid);
  // SPEC: A2.1.2 p.27 / A2.3 p.29: VALID signals must be LOW during reset (AR channel).
  A_RST_ARVALID_LOW: assert property (@(posedge aclk)
    (!aresetn || $rose(aresetn)) |-> !arvalid);
  // SPEC: A2.1.2 p.27 / A2.3 p.29: VALID signals must be LOW during reset (R channel).
  A_RST_RVALID_LOW: assert property (@(posedge aclk)
    (!aresetn || $rose(aresetn)) |-> !rvalid);

  // ---------------- VALID/READY handshake rules (A2.3) ----------------
  // SPEC: A2.3 p.29: When VALID is asserted, it must remain asserted until the
  // handshake occurs at a rising clock edge when VALID and READY are both asserted.
  A_AWVALID_HOLD: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && !awready) |=> awvalid);
  // SPEC: A2.3 p.29: Asserted VALID must remain asserted until handshake (W).
  A_WVALID_HOLD: assert property (@(posedge aclk) disable iff (!aresetn)
    (wvalid && !wready) |=> wvalid);
  // SPEC: A2.3 p.29: Asserted VALID must remain asserted until handshake (B).
  A_BVALID_HOLD: assert property (@(posedge aclk) disable iff (!aresetn)
    (bvalid && !bready) |=> bvalid);
  // SPEC: A2.3 p.29: Asserted VALID must remain asserted until handshake (AR).
  A_ARVALID_HOLD: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && !arready) |=> arvalid);
  // SPEC: A2.3 p.29: Asserted VALID must remain asserted until handshake (R).
  A_RVALID_HOLD: assert property (@(posedge aclk) disable iff (!aresetn)
    (rvalid && !rready) |=> rvalid);

  // SPEC: A2.3 p.29: The transmitter must keep its information stable until the
  // transfer occurs (AW payload).
  A_AW_STABLE: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && !awready) |=> $stable({awid, awaddr, awlen, awsize, awburst,
                                       awlock, awcache, awprot, awqos, awregion, awuser}));
  // SPEC: A2.3 p.29: Payload stable until transfer occurs (W payload).
  A_W_STABLE: assert property (@(posedge aclk) disable iff (!aresetn)
    (wvalid && !wready) |=> $stable({wdata, wstrb, wlast, wuser}));
  // SPEC: A2.3 p.29: Payload stable until transfer occurs (B payload).
  A_B_STABLE: assert property (@(posedge aclk) disable iff (!aresetn)
    (bvalid && !bready) |=> $stable({bid, bresp, buser}));
  // SPEC: A2.3 p.29: Payload stable until transfer occurs (AR payload).
  A_AR_STABLE: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && !arready) |=> $stable({arid, araddr, arlen, arsize, arburst,
                                       arlock, arcache, arprot, arqos, arregion, aruser}));
  // SPEC: A2.3 p.29: Payload stable until transfer occurs (R payload).
  A_R_STABLE: assert property (@(posedge aclk) disable iff (!aresetn)
    (rvalid && !rready) |=> $stable({rid, rdata, rresp, rlast, ruser}));

  // ---------------- Write request (AW) transaction rules ----------------
  // SPEC: A3.1.1 p.43: Size must not exceed the data width of the interface.
  A_AW_SIZE_MAX: assert property (@(posedge aclk) disable iff (!aresetn)
    awvalid |-> (awsize <= 3'(MAX_SIZE)));
  // SPEC: A3.1.4 p.46 (Table A3.9): AxBURST encoding 0b11 is RESERVED.
  A_AW_BURST_RSVD: assert property (@(posedge aclk) disable iff (!aresetn)
    awvalid |-> (awburst != 2'b11));
  // SPEC: A3.1.2 p.44 / A3.1.4 p.47: For wrapping bursts, Length can be 2, 4, 8, or 16.
  A_AW_WRAP_LEN: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && (awburst == 2'b10)) |-> aw_wrap_len_ok);
  // SPEC: A3.1.4 p.47: For WRAP the start address must be aligned to the size of each transfer.
  A_AW_WRAP_ALIGN: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && (awburst == 2'b10)) |-> ((awaddr & aw_size_msk) == '0));
  // SPEC: A3.1.2 p.44 / A3.1.4 p.47: For fixed bursts, Length can be up to 16 transfers.
  A_AW_FIXED_LEN: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && (awburst == 2'b00)) |-> (awlen <= 8'd15));
  // SPEC: A3.1 p.43 / A3.1.2 p.44: A transaction must not cross a 4KB address boundary.
  A_AW_INCR_4KB: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && (awburst == 2'b01)) |-> (aw_page_end <= 17'd4096));
  // SPEC: A3.1 p.43: A (fixed-burst) transaction must not cross a 4KB address boundary.
  A_AW_FIXED_4KB: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && (awburst == 2'b00)) |-> (aw_page_end_fx <= 17'd4096));
  // SPEC: A4.3 p.71 (Table A4.4): AxCACHE values not shown in the table are reserved.
  A_AW_CACHE_RSVD: assert property (@(posedge aclk) disable iff (!aresetn)
    awvalid |-> awcache_ok(awcache));
  // SPEC: A6.3.3 p.111: Exclusive access address must be aligned to the total number
  // of bytes in the transaction (Size * Length).
  A_AW_EXCL_ALIGN: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && awlock && aw_excl_len_pow2) |-> ((awaddr & aw_tot_msk) == '0));
  // SPEC: A6.3.3 p.111: The Length of an exclusive access must not exceed 16 transfers.
  A_AW_EXCL_LEN16: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && awlock) |-> (awlen <= 8'd15));
  // SPEC: A6.3.3 p.111: Bytes transferred in an exclusive access must be a power of 2.
  A_AW_EXCL_POW2: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && awlock) |-> aw_excl_len_pow2);
  // SPEC: A6.3.3 p.111: Exclusive access byte count is 1,2,...,128 (max 128 bytes).
  A_AW_EXCL_MAX128: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && awlock) |-> (aw_tot_b <= 16'd128));
  // SPEC: A6.3.2 p.111: A Manager must not start the write part of an exclusive
  // access sequence until the read part is complete (same ID locked read done).
  A_AW_EXCL_RD_FIRST: assert property (@(posedge aclk) disable iff (!aresetn)
    (aw_hs && awlock && !(r_hs && rlast && (rid == awid))) |-> !xrd_pend_aw);

  // ---------------- Read request (AR) transaction rules ----------------
  // SPEC: A3.1.1 p.43: Size must not exceed the data width of the interface.
  A_AR_SIZE_MAX: assert property (@(posedge aclk) disable iff (!aresetn)
    arvalid |-> (arsize <= 3'(MAX_SIZE)));
  // SPEC: A3.1.4 p.46 (Table A3.9): AxBURST encoding 0b11 is RESERVED.
  A_AR_BURST_RSVD: assert property (@(posedge aclk) disable iff (!aresetn)
    arvalid |-> (arburst != 2'b11));
  // SPEC: A3.1.2 p.44 / A3.1.4 p.47: For wrapping bursts, Length can be 2, 4, 8, or 16.
  A_AR_WRAP_LEN: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && (arburst == 2'b10)) |-> ar_wrap_len_ok);
  // SPEC: A3.1.4 p.47: For WRAP the start address must be aligned to the size of each transfer.
  A_AR_WRAP_ALIGN: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && (arburst == 2'b10)) |-> ((araddr & ar_size_msk) == '0));
  // SPEC: A3.1.2 p.44 / A3.1.4 p.47: For fixed bursts, Length can be up to 16 transfers.
  A_AR_FIXED_LEN: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && (arburst == 2'b00)) |-> (arlen <= 8'd15));
  // SPEC: A3.1 p.43 / A3.1.2 p.44: A transaction must not cross a 4KB address boundary.
  A_AR_INCR_4KB: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && (arburst == 2'b01)) |-> (ar_page_end <= 17'd4096));
  // SPEC: A3.1 p.43: A (fixed-burst) transaction must not cross a 4KB address boundary.
  A_AR_FIXED_4KB: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && (arburst == 2'b00)) |-> (ar_page_end_fx <= 17'd4096));
  // SPEC: A4.3 p.71 (Table A4.4): AxCACHE values not shown in the table are reserved.
  A_AR_CACHE_RSVD: assert property (@(posedge aclk) disable iff (!aresetn)
    arvalid |-> arcache_ok(arcache));
  // SPEC: A6.3.3 p.111: Exclusive access address must be aligned to Size * Length.
  A_AR_EXCL_ALIGN: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && arlock && ar_excl_len_pow2) |-> ((araddr & ar_tot_msk) == '0));
  // SPEC: A6.3.3 p.111: The Length of an exclusive access must not exceed 16 transfers.
  A_AR_EXCL_LEN16: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && arlock) |-> (arlen <= 8'd15));
  // SPEC: A6.3.3 p.111: Bytes transferred in an exclusive access must be a power of 2.
  A_AR_EXCL_POW2: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && arlock) |-> ar_excl_len_pow2);
  // SPEC: A6.3.3 p.111: Exclusive access transfers at most 128 bytes.
  A_AR_EXCL_MAX128: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && arlock) |-> (ar_tot_b <= 16'd128));

  // ---------------- Write data (W) rules ----------------
  // SPEC: A3.2.1 p.53: The Manager must assert WLAST while it is driving the final
  // write transfer in the transaction (beat count from AWLEN, A3.1.2 p.44).
  A_W_WLAST_ON_FINAL: assert property (@(posedge aclk) disable iff (!aresetn)
    (wvalid && (awf_cnt != '0) && w_final_beat) |-> wlast);
  // SPEC: A3.2.1 p.53 / A3.1.2 p.44: WLAST must not be asserted before the final
  // write transfer; early termination of transactions is not supported.
  A_W_WLAST_NOT_EARLY: assert property (@(posedge aclk) disable iff (!aresetn)
    (wvalid && (awf_cnt != '0) && wlast) |-> w_final_beat);
  // SPEC: A3.2.1.1 p.54: Outside of the transaction container all write strobes must
  // be LOW (container byte lanes per the equations of A3.1.6 p.49-50).
  A_W_STRB_IN_CONTAINER: assert property (@(posedge aclk) disable iff (!aresetn)
    (wvalid && (awf_cnt != '0) && (head_rec.size <= 3'(MAX_SIZE)))
      |-> ((wstrb & ~w_lane_mask) == '0));
  // SPEC: A3.1.2 p.44: A Manager must issue the number of write data transfers
  // according to Length - also when write data leads the request (A2.6 p.41).
  A_W_LEADING_LEN_MATCH: assert property (@(posedge aclk) disable iff (!aresetn)
    (aw_hs && (pre_cnt != '0)) |-> (({1'b0, awlen} + 9'd1) == pre_head));

  // ---------------- Write response (B) rules ----------------
  // SPEC: A2.3.2.1 p.31: The Subordinate must wait for AWVALID, AWREADY, WVALID,
  // WREADY and the last write data transfer before asserting BVALID.
  // SPEC: A5.5 p.100: The BID of a write response must match the AWID of the request.
  A_B_AFTER_COMPLETE: assert property (@(posedge aclk) disable iff (!aresetn)
    bvalid |-> b_pend);
  // SPEC: A3.3.1 p.62 (Table A3.28): EXOKAY is only permitted for an exclusive write.
  A_B_EXOKAY_EXCL: assert property (@(posedge aclk) disable iff (!aresetn)
    (bvalid && b_pend && (bresp == 2'b01)) |-> b_head_lock);

  // ---------------- Read data (R) rules ----------------
  // SPEC: A2.3.2.2 p.32: The Subordinate must wait for ARVALID and ARREADY before
  // asserting RVALID; A3.2.2 p.55: RVALID only in response to a request;
  // A5.6 p.101: RID must match the ARID of the request being responded to.
  A_R_AFTER_REQ: assert property (@(posedge aclk) disable iff (!aresetn)
    rvalid |-> r_pend);
  // SPEC: A3.2.2 p.55: The Subordinate must assert RLAST when it is driving the
  // final read transfer in the transaction (beat count from ARLEN, A3.1.2 p.44).
  A_R_LAST_ON_FINAL: assert property (@(posedge aclk) disable iff (!aresetn)
    (rvalid && r_pend && r_last_beat) |-> rlast);
  // SPEC: A3.2.2 p.55 / A3.1.2 p.44: RLAST must not come early; all transfers
  // indicated by Length must be completed.
  A_R_LAST_NOT_EARLY: assert property (@(posedge aclk) disable iff (!aresetn)
    (rvalid && r_pend && rlast) |-> r_last_beat);
  // SPEC: A3.3.2 p.63 (Table A3.31): EXOKAY is only permitted for an exclusive read.
  A_R_EXOKAY_EXCL: assert property (@(posedge aclk) disable iff (!aresetn)
    (rvalid && r_pend && (rresp == 2'b01)) |-> r_head_lck);
  // SPEC: A6.3.4 p.112: It is not permitted to have a mix of OKAY and EXOKAY
  // responses for a single (exclusive read) transaction.
  A_R_EXOKAY_CONSISTENT: assert property (@(posedge aclk) disable iff (!aresetn)
    (rvalid && r_pend && r_head_lck && (r_beat[rid] != '0) &&
     ((rresp == 2'b00) || (rresp == 2'b01)))
      |-> ((rresp == 2'b01) == r_exok_cur));

  // =========================================================================
  //                       FUNCTIONAL COVERAGE MODEL
  // =========================================================================

  // SPEC: A1.2 p.22-23 / A2.3 p.29: basic transfer on each of the five channels.
  C_COV_AW_HS: cover property (@(posedge aclk) disable iff (!aresetn) aw_hs);
  C_COV_AR_HS: cover property (@(posedge aclk) disable iff (!aresetn) ar_hs);
  C_COV_W_HS:  cover property (@(posedge aclk) disable iff (!aresetn) w_hs);
  C_COV_B_HS:  cover property (@(posedge aclk) disable iff (!aresetn) b_hs);
  C_COV_R_HS:  cover property (@(posedge aclk) disable iff (!aresetn) r_hs);

  // SPEC: A3.2.1 p.53 / A3.2.2 p.55: last-beat indications on the data channels.
  C_COV_WLAST_HS: cover property (@(posedge aclk) disable iff (!aresetn) (w_hs && wlast));
  C_COV_RLAST_HS: cover property (@(posedge aclk) disable iff (!aresetn) (r_hs && rlast));

  // SPEC: A3.1.4 p.46 (Table A3.9): all burst type encodings on AW and AR.
  C_COV_AW_FIXED: cover property (@(posedge aclk) disable iff (!aresetn) (aw_hs && (awburst == 2'b00)));
  C_COV_AW_INCR:  cover property (@(posedge aclk) disable iff (!aresetn) (aw_hs && (awburst == 2'b01)));
  C_COV_AW_WRAP:  cover property (@(posedge aclk) disable iff (!aresetn) (aw_hs && (awburst == 2'b10)));
  C_COV_AR_FIXED: cover property (@(posedge aclk) disable iff (!aresetn) (ar_hs && (arburst == 2'b00)));
  C_COV_AR_INCR:  cover property (@(posedge aclk) disable iff (!aresetn) (ar_hs && (arburst == 2'b01)));
  C_COV_AR_WRAP:  cover property (@(posedge aclk) disable iff (!aresetn) (ar_hs && (arburst == 2'b10)));

  // SPEC: A3.1.2 p.44 (Table A3.4): burst lengths - single transfer and maximum.
  C_COV_AW_LEN1:   cover property (@(posedge aclk) disable iff (!aresetn) (aw_hs && (awlen == 8'd0)));
  C_COV_AW_LEN256: cover property (@(posedge aclk) disable iff (!aresetn)
                     (aw_hs && (awburst == 2'b01) && (awlen == 8'd255)));
  C_COV_AR_LEN1:   cover property (@(posedge aclk) disable iff (!aresetn) (ar_hs && (arlen == 8'd0)));
  C_COV_AR_LEN256: cover property (@(posedge aclk) disable iff (!aresetn)
                     (ar_hs && (arburst == 2'b01) && (arlen == 8'd255)));

  // SPEC: A3.2.3 p.55: narrow transfers (Size < data width) and full-width transfers.
  C_COV_AW_NARROW:   cover property (@(posedge aclk) disable iff (!aresetn)
                       (aw_hs && (awsize < 3'(MAX_SIZE))));
  C_COV_AW_FULLSIZE: cover property (@(posedge aclk) disable iff (!aresetn)
                       (aw_hs && (awsize == 3'(MAX_SIZE))));
  C_COV_AR_NARROW:   cover property (@(posedge aclk) disable iff (!aresetn)
                       (ar_hs && (arsize < 3'(MAX_SIZE))));
  C_COV_AR_FULLSIZE: cover property (@(posedge aclk) disable iff (!aresetn)
                       (ar_hs && (arsize == 3'(MAX_SIZE))));

  // SPEC: A3.2.5 p.58: unaligned start address (low-order address bits nonzero
  // within the transfer size) on AW and AR.
  C_COV_AW_UNALIGNED: cover property (@(posedge aclk) disable iff (!aresetn)
                        (aw_hs && ((awaddr & aw_size_msk) != '0)));
  C_COV_AR_UNALIGNED: cover property (@(posedge aclk) disable iff (!aresetn)
                        (ar_hs && ((araddr & ar_size_msk) != '0)));

  // SPEC: A3.3.1 p.62 (Table A3.28): all BRESP encodings observed.
  C_COV_B_OKAY:   cover property (@(posedge aclk) disable iff (!aresetn) (b_hs && (bresp == 2'b00)));
  C_COV_B_EXOKAY: cover property (@(posedge aclk) disable iff (!aresetn) (b_hs && (bresp == 2'b01)));
  C_COV_B_SLVERR: cover property (@(posedge aclk) disable iff (!aresetn) (b_hs && (bresp == 2'b10)));
  C_COV_B_DECERR: cover property (@(posedge aclk) disable iff (!aresetn) (b_hs && (bresp == 2'b11)));

  // SPEC: A3.3.2 p.63 (Table A3.31): all RRESP encodings observed.
  C_COV_R_OKAY:   cover property (@(posedge aclk) disable iff (!aresetn) (r_hs && (rresp == 2'b00)));
  C_COV_R_EXOKAY: cover property (@(posedge aclk) disable iff (!aresetn) (r_hs && (rresp == 2'b01)));
  C_COV_R_SLVERR: cover property (@(posedge aclk) disable iff (!aresetn) (r_hs && (rresp == 2'b10)));
  C_COV_R_DECERR: cover property (@(posedge aclk) disable iff (!aresetn) (r_hs && (rresp == 2'b11)));

  // SPEC: A6.3 p.110 (Table A6.2): exclusive read and exclusive write requests.
  C_COV_AW_EXCLUSIVE: cover property (@(posedge aclk) disable iff (!aresetn) (aw_hs && awlock));
  C_COV_AR_EXCLUSIVE: cover property (@(posedge aclk) disable iff (!aresetn) (ar_hs && arlock));

  // SPEC: A3.2.1.1 p.54: all strobes LOW (nothing written) and partially asserted
  // strobes are both legal within the transaction container.
  C_COV_W_STRB_NONE:    cover property (@(posedge aclk) disable iff (!aresetn)
                          (w_hs && (wstrb == '0)));
  C_COV_W_STRB_PARTIAL: cover property (@(posedge aclk) disable iff (!aresetn)
                          (w_hs && (wstrb != '0) && (wstrb != {STRB_W{1'b1}})));

  // SPEC: A2.6 p.41: write data is permitted to appear before the write request.
  C_COV_W_LEADING: cover property (@(posedge aclk) disable iff (!aresetn)
                     (w_hs && (awf_cnt == '0)));

  // SPEC: A5.1 p.90: no ordering restriction between transactions with different
  // IDs - cover write responses to different IDs back to back, and a write
  // response while multiple transactions are complete and awaiting response.
  C_COV_B_DIFF_ID: cover property (@(posedge aclk) disable iff (!aresetn)
                     (b_hs && prev_bid_v && (bid != prev_bid)));
  C_COV_B_MULTI_COMPLETE: cover property (@(posedge aclk) disable iff (!aresetn)
                     (b_hs && (cmpl_total > 16'd1)));

  // SPEC: A5.6.1 p.101: read data transfers with different ID values may be
  // interleaved (a new ID starts before the previous burst finished).
  C_COV_R_INTERLEAVE: cover property (@(posedge aclk) disable iff (!aresetn)
                        (r_hs && prev_rid_v && prev_r_open && (rid != prev_rid)));

  // SPEC: A1.2 p.23: multiple outstanding transactions on write and read channels.
  C_COV_W_OUTST2: cover property (@(posedge aclk) disable iff (!aresetn)
                    (aw_hs && (w_outst >= 16'd2)));
  C_COV_R_OUTST2: cover property (@(posedge aclk) disable iff (!aresetn)
                    (ar_hs && (r_outst >= 16'd2)));

  // SPEC: A2.3 p.29 (Figure A2.2): VALID before READY handshake (one-cycle stall).
  C_COV_AW_STALL: cover property (@(posedge aclk) disable iff (!aresetn)
                    (awvalid && !awready) ##1 (awvalid && awready));
  C_COV_W_STALL:  cover property (@(posedge aclk) disable iff (!aresetn)
                    (wvalid && !wready) ##1 (wvalid && wready));
  C_COV_B_STALL:  cover property (@(posedge aclk) disable iff (!aresetn)
                    (bvalid && !bready) ##1 (bvalid && bready));
  C_COV_AR_STALL: cover property (@(posedge aclk) disable iff (!aresetn)
                    (arvalid && !arready) ##1 (arvalid && arready));
  C_COV_R_STALL:  cover property (@(posedge aclk) disable iff (!aresetn)
                    (rvalid && !rready) ##1 (rvalid && rready));

  // SPEC: A2.3 p.29 (Figure A2.3): READY before VALID handshake.
  C_COV_AW_RDY_FIRST: cover property (@(posedge aclk) disable iff (!aresetn)
                        (awready && !awvalid) ##1 (awvalid && awready));
  C_COV_W_RDY_FIRST:  cover property (@(posedge aclk) disable iff (!aresetn)
                        (wready && !wvalid) ##1 (wvalid && wready));
  C_COV_AR_RDY_FIRST: cover property (@(posedge aclk) disable iff (!aresetn)
                        (arready && !arvalid) ##1 (arvalid && arready));

  // SPEC: A2.3 p.30 (Figure A2.4): VALID with READY handshake in a single cycle.
  C_COV_AW_ZERO_WAIT: cover property (@(posedge aclk) disable iff (!aresetn)
                        (awvalid && awready && !$past(awvalid)));

  // SPEC: A3.1.3 p.45: transaction ending exactly on the 4KB boundary.
  C_COV_AW_4KB_EXACT: cover property (@(posedge aclk) disable iff (!aresetn)
                        (aw_hs && (awburst == 2'b01) && (aw_page_end == 17'd4096)));

  // SPEC: A4.8.1 p.86: non-default QoS identifiers on AW and AR.
  C_COV_AW_QOS: cover property (@(posedge aclk) disable iff (!aresetn) (aw_hs && (awqos != 4'd0)));
  C_COV_AR_QOS: cover property (@(posedge aclk) disable iff (!aresetn) (ar_hs && (arqos != 4'd0)));

  // SPEC: A4.3 p.71 (Table A4.4): Device and Write-Back memory type transactions.
  C_COV_AW_DEVICE:    cover property (@(posedge aclk) disable iff (!aresetn)
                        (aw_hs && (awcache == 4'b0000)));
  C_COV_AR_WRITEBACK: cover property (@(posedge aclk) disable iff (!aresetn)
                        (ar_hs && (arcache == 4'b1111)));

  // SPEC: A2.3 p.29: back-to-back transfers on the data channels (full throughput).
  C_COV_W_BACK2BACK: cover property (@(posedge aclk) disable iff (!aresetn) (w_hs ##1 w_hs));
  C_COV_R_BACK2BACK: cover property (@(posedge aclk) disable iff (!aresetn) (r_hs ##1 r_hs));

  // SPEC: A2.1.2 p.27: reset assertion followed by (synchronous) deassertion.
  C_COV_RESET: cover property (@(posedge aclk) $fell(aresetn) ##[1:100] $rose(aresetn));

endmodule

`default_nettype wire
