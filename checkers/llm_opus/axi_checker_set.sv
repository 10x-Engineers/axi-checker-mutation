// Passive AXI4 protocol checker + functional coverage model.
// Source: ARM IHI 0022 Issue L, Part A (chapters A1-A6). AXI4 subset only (no AXI5 extensions).
// Every assertion / cover carries a `// SPEC: <section> p.<page>: <rule>` tag.
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

  // ---------------------------------------------------------------------------------------------
  // Constants and helpers
  // ---------------------------------------------------------------------------------------------
  localparam int DB      = DATA_W / 8;           // Data_Bytes (A3.1.6)
  localparam int DB_LOG2 = $clog2(DB);
  // ASSUMPTION: the checker tracks at most TD outstanding write and TD outstanding read
  // transactions. On overflow the tracker-dependent assertions are disabled (with a warning),
  // never silently mis-attributed.
  localparam int TD = 64;
  localparam int TW = $clog2(TD);

  localparam logic [1:0] BURST_FIXED = 2'b00;
  localparam logic [1:0] BURST_INCR  = 2'b01;
  localparam logic [1:0] BURST_WRAP  = 2'b10;
  localparam logic [1:0] BURST_RSVD  = 2'b11;

  localparam logic [1:0] RESP_OKAY   = 2'b00;
  localparam logic [1:0] RESP_EXOKAY = 2'b01;
  localparam logic [1:0] RESP_SLVERR = 2'b10;
  localparam logic [1:0] RESP_DECERR = 2'b11;

  // Table A4.4 memory types (identical legal set for ARCACHE and AWCACHE).
  localparam logic [9:0][3:0] CACHE_TYPES = {4'b1111, 4'b1110, 4'b1011, 4'b1010, 4'b0111,
                                             4'b0110, 4'b0011, 4'b0010, 4'b0001, 4'b0000};

  wire aw_hs = awvalid && awready;
  wire w_hs  = wvalid  && wready;
  wire b_hs  = bvalid  && bready;
  wire ar_hs = arvalid && arready;
  wire r_hs  = rvalid  && rready;

  function automatic int unsigned sz_bytes(input logic [2:0] sz);
    return 32'd1 << sz;
  endfunction

  function automatic logic [11:0] lo12(input logic [ADDR_W-1:0] a);
    return 12'(a);
  endfunction

  function automatic logic cache_legal(input logic [3:0] c);
    return c inside {4'b0000, 4'b0001, 4'b0010, 4'b0011, 4'b0110,
                     4'b0111, 4'b1010, 4'b1011, 4'b1110, 4'b1111};
  endfunction

  // A3.1: an INCR transaction must not cross a 4KB boundary (WRAP/FIXED cannot when legal).
  function automatic logic incr_crosses_4k(input logic [11:0] a, input logic [2:0] sz,
                                           input logic [7:0] len);
    int unsigned sb, al;
    sb = sz_bytes(sz);
    al = 32'(a) & ~(sb - 1);
    return (al + (32'(len) + 1) * sb) > 32'd4096;
  endfunction

  function automatic int unsigned total_bytes(input logic [2:0] sz, input logic [7:0] len);
    return (32'(len) + 1) * sz_bytes(sz);
  endfunction

  // Size-aligned address of transfer n (0-based), low 12 bits, per A3.1.6 / A3.1.7.
  function automatic int unsigned beat_addr(input logic [11:0] a, input logic [2:0] sz,
                                            input logic [7:0] len, input logic [1:0] bu,
                                            input int unsigned n);
    int unsigned sb, al, cs, wb, an;
    sb = sz_bytes(sz);
    al = 32'(a) & ~(sb - 1);
    cs = sb * (32'(len) + 1);
    wb = (32'(a) / cs) * cs;
    if (bu == BURST_FIXED || n == 0) begin
      an = al;
    end else begin
      an = al + n * sb;
      if (bu == BURST_WRAP && an >= wb + cs) an = an - cs;
    end
    return an;
  endfunction

  // Byte lanes of the Size-aligned window that holds transfer n.
  // SPEC-AMBIGUITY: A3.1.6 p.50 puts the first unaligned transfer's Lower_Byte_Lane at Start_Addr,
  // but A3.2.1.1 p.54 lets any strobe inside the container (which starts at Aligned_Addr) be HIGH;
  // the window therefore starts at the Size-aligned address so neither reading is over-flagged.
  function automatic logic [DB-1:0] beat_lanes(input logic [11:0] a, input logic [2:0] sz,
                                               input logic [7:0] len, input logic [1:0] bu,
                                               input int unsigned n);
    int unsigned sb, lo;
    logic [DB-1:0] m;
    sb = sz_bytes(sz);
    m  = '0;
    if (sb > 32'(DB)) return '1;
    lo = beat_addr(a, sz, len, bu, n) % 32'(DB);
    for (int b = 0; b < DB; b++) if (32'(b) >= lo && 32'(b) < lo + sb) m[b] = 1'b1;
    return m;
  endfunction

  // Byte lanes of transfer n that fall inside the transaction container (INCR / WRAP only).
  function automatic logic [DB-1:0] container_lanes(input logic [11:0] a, input logic [2:0] sz,
                                                    input logic [7:0] len, input logic [1:0] bu,
                                                    input int unsigned n);
    int unsigned sb, al, cs, lower, upper, blk;
    logic [DB-1:0] m;
    sb = sz_bytes(sz);
    m  = '0;
    if (sb > 32'(DB)) return '1;
    al    = 32'(a) & ~(sb - 1);
    cs    = sb * (32'(len) + 1);
    lower = (bu == BURST_WRAP) ? (32'(a) / cs) * cs : al;
    upper = lower + cs;
    blk   = beat_addr(a, sz, len, bu, n);
    blk   = blk - (blk % 32'(DB));
    for (int b = 0; b < DB; b++)
      if (blk + 32'(b) >= lower && blk + 32'(b) < upper) m[b] = 1'b1;
    return m;
  endfunction

  // Lanes of the first transfer below an unaligned start address (for coverage only).
  function automatic logic [DB-1:0] below_start_lanes(input logic [11:0] a, input logic [2:0] sz);
    int unsigned sb, al;
    logic [DB-1:0] m;
    sb = sz_bytes(sz);
    m  = '0;
    if (sb > 32'(DB)) return '0;
    al = 32'(a) & ~(sb - 1);
    for (int b = 0; b < DB; b++)
      if (32'(b) >= al % 32'(DB) && 32'(b) < 32'(a) % 32'(DB)) m[b] = 1'b1;
    return m;
  endfunction

  // ---------------------------------------------------------------------------------------------
  // Reset tracking
  // ---------------------------------------------------------------------------------------------
  logic rst_q;   // 0 during reset and at the first rising edge that samples ARESETn HIGH
  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) rst_q <= 1'b0;
    else          rst_q <= 1'b1;
  end

  // ---------------------------------------------------------------------------------------------
  // Write tracker: AW table (any free entry, tagged with the request sequence number) + in-order
  // W burst counter.
  // A5.5: write data is issued in request order, so W burst k belongs to AW request k.
  // ---------------------------------------------------------------------------------------------
  logic              aw_v    [TD];
  logic [31:0]       aw_seq  [TD];
  logic [ID_W-1:0]   aw_idq  [TD];
  logic [7:0]        aw_lenq [TD];
  logic [2:0]        aw_szq  [TD];
  logic [1:0]        aw_buq  [TD];
  logic [11:0]       aw_aq   [TD];
  logic              aw_lkq  [TD];
  logic [8:0]        wl_beats[TD];   // beat count of W bursts that completed before their AW,
                                     // indexed by burst sequence number modulo TD

  logic [31:0] aw_cnt;    // number of AW handshakes (sequence number of the next request)
  logic [31:0] wb_cnt;    // number of completed W bursts
  logic [8:0]  w_beat;    // beats already accepted in the current W burst
  logic        wr_ovf;

  logic          w_known;
  logic [7:0]    w_len;
  logic [2:0]    w_sz;
  logic [1:0]    w_bu;
  logic [11:0]   w_a;
  logic [TW-1:0] w_slot;

  assign w_slot = wb_cnt[TW-1:0];

  always_comb begin
    w_known = 1'b0;
    w_len   = '0;
    w_sz    = '0;
    w_bu    = '0;
    w_a     = '0;
    for (int i = 0; i < TD; i++) begin
      if (aw_v[i] && aw_seq[i] == wb_cnt) begin
        w_known = 1'b1;
        w_len   = aw_lenq[i];
        w_sz    = aw_szq[i];
        w_bu    = aw_buq[i];
        w_a     = aw_aq[i];
      end
    end
    if (!w_known && aw_hs && aw_cnt == wb_cnt) begin
      w_known = 1'b1;
      w_len   = awlen;
      w_sz    = awsize;
      w_bu    = awburst;
      w_a     = lo12(awaddr);
    end
  end

  wire              w_end        = w_hs && (wlast || (w_known && w_beat == {1'b0, w_len}));
  wire [DB-1:0]     w_lanes      = beat_lanes(w_a, w_sz, w_len, w_bu, 32'(w_beat));
  wire [DB-1:0]     w_cont_lanes = container_lanes(w_a, w_sz, w_len, w_bu, 32'(w_beat));
  wire [DB-1:0]     w_below      = below_start_lanes(w_a, w_sz);
  wire              aw_lead      = aw_hs && (aw_cnt < wb_cnt);
  wire [8:0]        aw_lead_beats = wl_beats[aw_cnt[TW-1:0]];

  logic          b_found;
  logic [TW-1:0] b_slot;
  logic [31:0]   b_seq;
  logic          b_lock;
  logic          wr_any;
  logic [31:0]   wr_old_seq;
  logic [7:0]    wr_out;
  logic          aw_id_busy;
  logic          aw_free_ok;
  logic [TW-1:0] aw_free;

  always_comb begin
    aw_free_ok = 1'b0;
    aw_free    = '0;
    b_found    = 1'b0;
    b_slot     = '0;
    b_seq      = '0;
    b_lock     = 1'b0;
    wr_any     = 1'b0;
    wr_old_seq = '0;
    wr_out     = '0;
    aw_id_busy = 1'b0;
    for (int i = TD - 1; i >= 0; i--) begin
      if (!aw_v[i]) begin
        aw_free_ok = 1'b1;
        aw_free    = TW'(i);
      end
    end
    for (int i = 0; i < TD; i++) begin
      if (aw_v[i]) begin
        wr_out = wr_out + 8'd1;
        if (!wr_any || aw_seq[i] < wr_old_seq) begin
          wr_any     = 1'b1;
          wr_old_seq = aw_seq[i];
        end
        if (aw_idq[i] == bid && (!b_found || aw_seq[i] < b_seq)) begin
          b_found = 1'b1;
          b_slot  = TW'(i);
          b_seq   = aw_seq[i];
          b_lock  = aw_lkq[i];
        end
        if (aw_idq[i] == awid) aw_id_busy = 1'b1;
      end
    end
  end

  // Same-ID responses are in request order (A5.3.5), so a B belongs to the oldest same-ID write.
  wire b_data_done = b_found && (b_seq < wb_cnt);
  wire b_retire    = b_hs && b_data_done;
  // Entry the next AW takes: a free one, else the one a B retires in this cycle.
  wire           aw_alloc_ok = aw_free_ok || b_retire;
  wire [TW-1:0]  aw_alloc    = aw_free_ok ? aw_free : b_slot;

  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      aw_cnt <= '0;
      wb_cnt <= '0;
      w_beat <= '0;
      wr_ovf <= 1'b0;
      for (int i = 0; i < TD; i++) begin
        aw_v[i]     <= 1'b0;
        aw_seq[i]   <= '0;
        aw_idq[i]   <= '0;
        aw_lenq[i]  <= '0;
        aw_szq[i]   <= '0;
        aw_buq[i]   <= '0;
        aw_aq[i]    <= '0;
        aw_lkq[i]   <= 1'b0;
        wl_beats[i] <= '0;
      end
    end else begin
      if (b_retire) aw_v[b_slot] <= 1'b0;
      if (aw_hs) begin
        if (!aw_alloc_ok) wr_ovf <= 1'b1;
        if (aw_lead && (wb_cnt - aw_cnt) > 32'(TD)) wr_ovf <= 1'b1;
        aw_v   [aw_alloc] <= 1'b1;
        aw_seq [aw_alloc] <= aw_cnt;
        aw_idq [aw_alloc] <= awid;
        aw_lenq[aw_alloc] <= awlen;
        aw_szq [aw_alloc] <= awsize;
        aw_buq [aw_alloc] <= awburst;
        aw_aq  [aw_alloc] <= lo12(awaddr);
        aw_lkq [aw_alloc] <= awlock;
        aw_cnt <= aw_cnt + 32'd1;
      end
      if (w_hs) begin
        if (w_end) begin
          wb_cnt <= wb_cnt + 32'd1;
          w_beat <= '0;
          if (!w_known) begin
            wl_beats[w_slot] <= w_beat + 9'd1;
            if ((wb_cnt - aw_cnt) >= 32'(TD)) wr_ovf <= 1'b1;
          end
        end else if (w_beat != '1) begin
          w_beat <= w_beat + 9'd1;
        end
      end
    end
  end

  // ---------------------------------------------------------------------------------------------
  // Read tracker: AR table; R beats go to the oldest outstanding AR with the same ID (A5.3.5).
  // ---------------------------------------------------------------------------------------------
  logic              ar_v   [TD];
  logic [31:0]       ar_seq [TD];
  logic [ID_W-1:0]   ar_idq [TD];
  logic [ADDR_W-1:0] ar_adq [TD];
  logic [7:0]        ar_lenq[TD];
  logic              ar_lkq [TD];
  logic [8:0]        ar_bts [TD];   // beats already accepted
  logic              ar_sx  [TD];   // an earlier beat was EXOKAY
  logic              ar_so  [TD];   // an earlier beat was OKAY

  logic [31:0] ar_cnt;
  logic        rd_ovf;

  logic          r_found;
  logic [TW-1:0] r_slot;
  logic [31:0]   r_seq;
  logic [7:0]    r_len;
  logic [8:0]    r_bts;
  logic          r_lock;
  logic          r_sx;
  logic          r_so;
  logic          rd_any;
  logic [31:0]   rd_old_seq;
  logic [7:0]    rd_out;
  logic          ar_id_busy;
  logic          ex_rd_pend_aw;   // exclusive read, same ID and address as AW, still outstanding
  logic          ar_free_ok;
  logic [TW-1:0] ar_free;

  always_comb begin
    ar_free_ok    = 1'b0;
    ar_free       = '0;
    r_found       = 1'b0;
    r_slot        = '0;
    r_seq         = '0;
    r_len         = '0;
    r_bts         = '0;
    r_lock        = 1'b0;
    r_sx          = 1'b0;
    r_so          = 1'b0;
    rd_any        = 1'b0;
    rd_old_seq    = '0;
    rd_out        = '0;
    ar_id_busy    = 1'b0;
    ex_rd_pend_aw = arvalid && arlock && arid == awid && araddr == awaddr;
    for (int i = TD - 1; i >= 0; i--) begin
      if (!ar_v[i]) begin
        ar_free_ok = 1'b1;
        ar_free    = TW'(i);
      end
    end
    for (int i = 0; i < TD; i++) begin
      if (ar_v[i]) begin
        rd_out = rd_out + 8'd1;
        if (!rd_any || ar_seq[i] < rd_old_seq) begin
          rd_any     = 1'b1;
          rd_old_seq = ar_seq[i];
        end
        if (ar_idq[i] == rid && (!r_found || ar_seq[i] < r_seq)) begin
          r_found = 1'b1;
          r_slot  = TW'(i);
          r_seq   = ar_seq[i];
          r_len   = ar_lenq[i];
          r_bts   = ar_bts[i];
          r_lock  = ar_lkq[i];
          r_sx    = ar_sx[i];
          r_so    = ar_so[i];
        end
        if (ar_idq[i] == arid) ar_id_busy = 1'b1;
        if (ar_lkq[i] && ar_idq[i] == awid && ar_adq[i] == awaddr) ex_rd_pend_aw = 1'b1;
      end
    end
  end

  wire r_final  = r_found && (r_bts == {1'b0, r_len});
  wire r_retire = r_hs && r_final;
  wire           ar_alloc_ok = ar_free_ok || r_retire;
  wire [TW-1:0]  ar_alloc    = ar_free_ok ? ar_free : r_slot;

  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      ar_cnt <= '0;
      rd_ovf <= 1'b0;
      for (int i = 0; i < TD; i++) begin
        ar_v[i]    <= 1'b0;
        ar_seq[i]  <= '0;
        ar_idq[i]  <= '0;
        ar_adq[i]  <= '0;
        ar_lenq[i] <= '0;
        ar_lkq[i]  <= 1'b0;
        ar_bts[i]  <= '0;
        ar_sx[i]   <= 1'b0;
        ar_so[i]   <= 1'b0;
      end
    end else begin
      if (r_hs && r_found) begin
        ar_bts[r_slot] <= r_bts + 9'd1;
        if (rresp == RESP_EXOKAY) ar_sx[r_slot] <= 1'b1;
        if (rresp == RESP_OKAY)   ar_so[r_slot] <= 1'b1;
        if (r_final) ar_v[r_slot] <= 1'b0;
      end
      if (ar_hs) begin
        if (!ar_alloc_ok) rd_ovf <= 1'b1;
        ar_v   [ar_alloc] <= 1'b1;
        ar_seq [ar_alloc] <= ar_cnt;
        ar_idq [ar_alloc] <= arid;
        ar_adq [ar_alloc] <= araddr;
        ar_lenq[ar_alloc] <= arlen;
        ar_lkq [ar_alloc] <= arlock;
        ar_bts [ar_alloc] <= '0;
        ar_sx  [ar_alloc] <= 1'b0;
        ar_so  [ar_alloc] <= 1'b0;
        ar_cnt <= ar_cnt + 32'd1;
      end
    end
  end

  always_ff @(posedge aclk) begin
    if (aresetn && aw_hs && !wr_ovf && !aw_alloc_ok)
      $warning("axi_checker_set: write tracker full (%0d); write-tracking checks disabled", TD);
    if (aresetn && ar_hs && !rd_ovf && !ar_alloc_ok)
      $warning("axi_checker_set: read tracker full (%0d); read-tracking checks disabled", TD);
  end

  // ---------------------------------------------------------------------------------------------
  // Misc. auxiliary state
  // ---------------------------------------------------------------------------------------------
  logic aw_wait_q;   // AWVALID was HIGH without handshake in the previous cycle
  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) aw_wait_q <= 1'b0;
    else          aw_wait_q <= awvalid && !awready;
  end
  wire aw_new = awvalid && !aw_wait_q;   // first cycle of a write request

  // Last observed request page -> region (A4.7.2).
  wire [ADDR_W-1:0] aw_pg = awaddr >> 12;
  wire [ADDR_W-1:0] ar_pg = araddr >> 12;
  logic              rg_v;
  logic [ADDR_W-1:0] rg_pg;
  logic [3:0]        rg_val;
  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      rg_v   <= 1'b0;
      rg_pg  <= '0;
      rg_val <= '0;
    end else if (aw_hs) begin
      rg_v   <= 1'b1;
      rg_pg  <= aw_pg;
      rg_val <= awregion;
    end else if (ar_hs) begin
      rg_v   <= 1'b1;
      rg_pg  <= ar_pg;
      rg_val <= arregion;
    end
  end

  // Previous R beat (coverage of interleaving and per-beat response variation).
  logic            r_mid_q;
  logic [ID_W-1:0] r_prev_id;
  logic [1:0]      r_prev_resp;
  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      r_mid_q     <= 1'b0;
      r_prev_id   <= '0;
      r_prev_resp <= '0;
    end else if (r_hs) begin
      r_mid_q     <= !r_final;
      r_prev_id   <= rid;
      r_prev_resp <= rresp;
    end
  end

  // =============================================================================================
  // ASSERTIONS
  // =============================================================================================

  // ---- Reset -----------------------------------------------------------------------------------
  // SPEC: A2.3 p.29: AWVALID must be LOW during reset.
  ap_aw_valid_low_in_reset: assert property (@(posedge aclk) !aresetn |-> !awvalid);
  // SPEC: A2.3 p.29: WVALID must be LOW during reset.
  ap_w_valid_low_in_reset: assert property (@(posedge aclk) !aresetn |-> !wvalid);
  // SPEC: A2.3 p.29: BVALID must be LOW during reset.
  ap_b_valid_low_in_reset: assert property (@(posedge aclk) !aresetn |-> !bvalid);
  // SPEC: A2.3 p.29: ARVALID must be LOW during reset.
  ap_ar_valid_low_in_reset: assert property (@(posedge aclk) !aresetn |-> !arvalid);
  // SPEC: A2.3 p.29: RVALID must be LOW during reset.
  ap_r_valid_low_in_reset: assert property (@(posedge aclk) !aresetn |-> !rvalid);

  // SPEC: A2.1.2 p.27: AWVALID stays LOW until the first rising edge after ARESETn is HIGH.
  ap_aw_valid_low_reset_exit: assert property (@(posedge aclk) (aresetn && !rst_q) |-> !awvalid);
  // SPEC: A2.1.2 p.27: WVALID stays LOW until the first rising edge after ARESETn is HIGH.
  ap_w_valid_low_reset_exit: assert property (@(posedge aclk) (aresetn && !rst_q) |-> !wvalid);
  // SPEC: A2.1.2 p.27: BVALID stays LOW until the first rising edge after ARESETn is HIGH.
  ap_b_valid_low_reset_exit: assert property (@(posedge aclk) (aresetn && !rst_q) |-> !bvalid);
  // SPEC: A2.1.2 p.27: ARVALID stays LOW until the first rising edge after ARESETn is HIGH.
  ap_ar_valid_low_reset_exit: assert property (@(posedge aclk) (aresetn && !rst_q) |-> !arvalid);
  // SPEC: A2.1.2 p.27: RVALID stays LOW until the first rising edge after ARESETn is HIGH.
  ap_r_valid_low_reset_exit: assert property (@(posedge aclk) (aresetn && !rst_q) |-> !rvalid);

  // ---- Known values ----------------------------------------------------------------------------
  // SPEC: A2.3 p.29: AWVALID/AWREADY carry a defined handshake state out of reset.
  ap_aw_handshake_known: assert property (@(posedge aclk) disable iff (!aresetn)
    !$isunknown({awvalid, awready}));
  // SPEC: A2.3 p.29: WVALID/WREADY carry a defined handshake state out of reset.
  ap_w_handshake_known: assert property (@(posedge aclk) disable iff (!aresetn)
    !$isunknown({wvalid, wready}));
  // SPEC: A2.3 p.29: BVALID/BREADY carry a defined handshake state out of reset.
  ap_b_handshake_known: assert property (@(posedge aclk) disable iff (!aresetn)
    !$isunknown({bvalid, bready}));
  // SPEC: A2.3 p.29: ARVALID/ARREADY carry a defined handshake state out of reset.
  ap_ar_handshake_known: assert property (@(posedge aclk) disable iff (!aresetn)
    !$isunknown({arvalid, arready}));
  // SPEC: A2.3 p.29: RVALID/RREADY carry a defined handshake state out of reset.
  ap_r_handshake_known: assert property (@(posedge aclk) disable iff (!aresetn)
    !$isunknown({rvalid, rready}));

  // SPEC: A2.3 p.29: AWVALID indicates the AW control information is available (no X).
  ap_aw_ctrl_known: assert property (@(posedge aclk) disable iff (!aresetn)
    awvalid |-> !$isunknown({awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot,
                             awqos, awregion}));
  // SPEC: A2.3 p.29: WVALID indicates WSTRB/WLAST are available (no X).
  ap_w_ctrl_known: assert property (@(posedge aclk) disable iff (!aresetn)
    wvalid |-> !$isunknown({wstrb, wlast}));
  // SPEC: A2.3 p.29: BVALID indicates the write response information is available (no X).
  ap_b_ctrl_known: assert property (@(posedge aclk) disable iff (!aresetn)
    bvalid |-> !$isunknown({bid, bresp}));
  // SPEC: A2.3 p.29: ARVALID indicates the AR control information is available (no X).
  ap_ar_ctrl_known: assert property (@(posedge aclk) disable iff (!aresetn)
    arvalid |-> !$isunknown({arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot,
                             arqos, arregion}));
  // SPEC: A3.3.2 p.62: RRESP (and RID/RLAST) must be valid when RVALID is asserted.
  ap_r_ctrl_known: assert property (@(posedge aclk) disable iff (!aresetn)
    rvalid |-> !$isunknown({rid, rresp, rlast}));

  // ---- VALID held until handshake --------------------------------------------------------------
  // SPEC: A2.3 p.29: once asserted, AWVALID remains asserted until the handshake.
  ap_aw_valid_hold: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && !awready) |=> awvalid);
  // SPEC: A2.3 p.29: once asserted, WVALID remains asserted until the handshake.
  ap_w_valid_hold: assert property (@(posedge aclk) disable iff (!aresetn)
    (wvalid && !wready) |=> wvalid);
  // SPEC: A2.3 p.29: once asserted, BVALID remains asserted until the handshake.
  ap_b_valid_hold: assert property (@(posedge aclk) disable iff (!aresetn)
    (bvalid && !bready) |=> bvalid);
  // SPEC: A2.3 p.29: once asserted, ARVALID remains asserted until the handshake.
  ap_ar_valid_hold: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && !arready) |=> arvalid);
  // SPEC: A2.3 p.29: once asserted, RVALID remains asserted until the handshake.
  ap_r_valid_hold: assert property (@(posedge aclk) disable iff (!aresetn)
    (rvalid && !rready) |=> rvalid);

  // ---- Payload stable while VALID && !READY ----------------------------------------------------
  // SPEC: A2.3 p.29: AWID stable until the transfer occurs.
  ap_aw_id_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && !awready) |=> $stable(awid));
  // SPEC: A2.3 p.29: AWADDR stable until the transfer occurs.
  ap_aw_addr_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && !awready) |=> $stable(awaddr));
  // SPEC: A2.3 p.29: AWLEN stable until the transfer occurs.
  ap_aw_len_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && !awready) |=> $stable(awlen));
  // SPEC: A2.3 p.29: AWSIZE stable until the transfer occurs.
  ap_aw_size_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && !awready) |=> $stable(awsize));
  // SPEC: A2.3 p.29: AWBURST stable until the transfer occurs.
  ap_aw_burst_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && !awready) |=> $stable(awburst));
  // SPEC: A2.3 p.29: AWLOCK stable until the transfer occurs.
  ap_aw_lock_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && !awready) |=> $stable(awlock));
  // SPEC: A2.3 p.29: AWCACHE stable until the transfer occurs.
  ap_aw_cache_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && !awready) |=> $stable(awcache));
  // SPEC: A2.3 p.29: AWPROT stable until the transfer occurs.
  ap_aw_prot_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && !awready) |=> $stable(awprot));
  // SPEC: A2.3 p.29: AWQOS stable until the transfer occurs.
  ap_aw_qos_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && !awready) |=> $stable(awqos));
  // SPEC: A2.3 p.29: AWREGION stable until the transfer occurs.
  ap_aw_region_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && !awready) |=> $stable(awregion));
  // SPEC: A2.3 p.29: AWUSER stable until the transfer occurs.
  ap_aw_user_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && !awready) |=> $stable(awuser));

  // SPEC: A2.3 p.29: WDATA stable until the transfer occurs.
  ap_w_data_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (wvalid && !wready) |=> $stable(wdata));
  // SPEC: A2.3 p.29: WSTRB stable until the transfer occurs.
  ap_w_strb_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (wvalid && !wready) |=> $stable(wstrb));
  // SPEC: A2.3 p.29: WLAST stable until the transfer occurs.
  ap_w_last_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (wvalid && !wready) |=> $stable(wlast));
  // SPEC: A2.3 p.29: WUSER stable until the transfer occurs.
  ap_w_user_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (wvalid && !wready) |=> $stable(wuser));

  // SPEC: A2.3 p.29: BID stable until the transfer occurs.
  ap_b_id_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (bvalid && !bready) |=> $stable(bid));
  // SPEC: A2.3 p.29: BRESP stable until the transfer occurs.
  ap_b_resp_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (bvalid && !bready) |=> $stable(bresp));
  // SPEC: A2.3 p.29: BUSER stable until the transfer occurs.
  ap_b_user_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (bvalid && !bready) |=> $stable(buser));

  // SPEC: A2.3 p.29: ARID stable until the transfer occurs.
  ap_ar_id_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && !arready) |=> $stable(arid));
  // SPEC: A2.3 p.29: ARADDR stable until the transfer occurs.
  ap_ar_addr_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && !arready) |=> $stable(araddr));
  // SPEC: A2.3 p.29: ARLEN stable until the transfer occurs.
  ap_ar_len_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && !arready) |=> $stable(arlen));
  // SPEC: A2.3 p.29: ARSIZE stable until the transfer occurs.
  ap_ar_size_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && !arready) |=> $stable(arsize));
  // SPEC: A2.3 p.29: ARBURST stable until the transfer occurs.
  ap_ar_burst_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && !arready) |=> $stable(arburst));
  // SPEC: A2.3 p.29: ARLOCK stable until the transfer occurs.
  ap_ar_lock_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && !arready) |=> $stable(arlock));
  // SPEC: A2.3 p.29: ARCACHE stable until the transfer occurs.
  ap_ar_cache_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && !arready) |=> $stable(arcache));
  // SPEC: A2.3 p.29: ARPROT stable until the transfer occurs.
  ap_ar_prot_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && !arready) |=> $stable(arprot));
  // SPEC: A2.3 p.29: ARQOS stable until the transfer occurs.
  ap_ar_qos_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && !arready) |=> $stable(arqos));
  // SPEC: A2.3 p.29: ARREGION stable until the transfer occurs.
  ap_ar_region_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && !arready) |=> $stable(arregion));
  // SPEC: A2.3 p.29: ARUSER stable until the transfer occurs.
  ap_ar_user_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && !arready) |=> $stable(aruser));

  // SPEC: A2.3 p.29: RID stable until the transfer occurs.
  ap_r_id_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (rvalid && !rready) |=> $stable(rid));
  // SPEC: A2.3 p.29: RDATA stable until the transfer occurs.
  ap_r_data_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (rvalid && !rready) |=> $stable(rdata));
  // SPEC: A2.3 p.29: RRESP stable until the transfer occurs.
  ap_r_resp_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (rvalid && !rready) |=> $stable(rresp));
  // SPEC: A2.3 p.29: RLAST stable until the transfer occurs.
  ap_r_last_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (rvalid && !rready) |=> $stable(rlast));
  // SPEC: A2.3 p.29: RUSER stable until the transfer occurs.
  ap_r_user_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (rvalid && !rready) |=> $stable(ruser));

  // ---- Write request attributes ----------------------------------------------------------------
  // SPEC: A3.1.4 p.46: AWBURST 0b11 is RESERVED.
  ap_aw_burst_not_reserved: assert property (@(posedge aclk) disable iff (!aresetn)
    awvalid |-> awburst != BURST_RSVD);
  // SPEC: A3.1.1 p.43: AWSIZE must not exceed the data width.
  ap_aw_size_le_data_width: assert property (@(posedge aclk) disable iff (!aresetn)
    awvalid |-> sz_bytes(awsize) <= 32'(DB));
  // SPEC: A3.1.2 p.44: a WRAP write has Length 2, 4, 8 or 16.
  ap_aw_wrap_len: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && awburst == BURST_WRAP) |-> awlen inside {8'd1, 8'd3, 8'd7, 8'd15});
  // SPEC: A3.1.4 p.47: a WRAP write start address must be aligned to Size.
  ap_aw_wrap_aligned: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && awburst == BURST_WRAP) |-> (32'(lo12(awaddr)) & (sz_bytes(awsize) - 1)) == 0);
  // SPEC: A3.1.2 p.44: a FIXED write has Length up to 16.
  ap_aw_fixed_len: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && awburst == BURST_FIXED) |-> awlen <= 8'd15);
  // SPEC: A3.1 p.43: a write transaction must not cross a 4KB address boundary.
  ap_aw_no_4k_cross: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && awburst == BURST_INCR) |-> !incr_crosses_4k(lo12(awaddr), awsize, awlen));
  // SPEC: A4.3 p.71: AWCACHE values not listed in Table A4.4 are reserved.
  ap_aw_cache_not_reserved: assert property (@(posedge aclk) disable iff (!aresetn)
    awvalid |-> cache_legal(awcache));
  // SPEC: A6.3.3 p.111: exclusive write Length must not exceed 16 transfers.
  ap_aw_excl_len_max: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && awlock) |-> awlen <= 8'd15);
  // SPEC: A6.3.3 p.111: exclusive write byte count must be a power of 2.
  ap_aw_excl_bytes_pow2: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && awlock) |-> awlen inside {8'd0, 8'd1, 8'd3, 8'd7, 8'd15});
  // SPEC: A6.3.3 p.111: exclusive write transfers at most 128 bytes.
  ap_aw_excl_bytes_max: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && awlock) |-> total_bytes(awsize, awlen) <= 32'd128);
  // SPEC: A6.3.3 p.111: exclusive write address aligned to Size x Length.
  ap_aw_excl_aligned: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && awlock) |-> (32'(lo12(awaddr)) & (total_bytes(awsize, awlen) - 1)) == 0);

  // ---- Read request attributes -----------------------------------------------------------------
  // SPEC: A3.1.4 p.46: ARBURST 0b11 is RESERVED.
  ap_ar_burst_not_reserved: assert property (@(posedge aclk) disable iff (!aresetn)
    arvalid |-> arburst != BURST_RSVD);
  // SPEC: A3.1.1 p.43: ARSIZE must not exceed the data width.
  ap_ar_size_le_data_width: assert property (@(posedge aclk) disable iff (!aresetn)
    arvalid |-> sz_bytes(arsize) <= 32'(DB));
  // SPEC: A3.1.2 p.44: a WRAP read has Length 2, 4, 8 or 16.
  ap_ar_wrap_len: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && arburst == BURST_WRAP) |-> arlen inside {8'd1, 8'd3, 8'd7, 8'd15});
  // SPEC: A3.1.4 p.47: a WRAP read start address must be aligned to Size.
  ap_ar_wrap_aligned: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && arburst == BURST_WRAP) |-> (32'(lo12(araddr)) & (sz_bytes(arsize) - 1)) == 0);
  // SPEC: A3.1.2 p.44: a FIXED read has Length up to 16.
  ap_ar_fixed_len: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && arburst == BURST_FIXED) |-> arlen <= 8'd15);
  // SPEC: A3.1 p.43: a read transaction must not cross a 4KB address boundary.
  ap_ar_no_4k_cross: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && arburst == BURST_INCR) |-> !incr_crosses_4k(lo12(araddr), arsize, arlen));
  // SPEC: A4.3 p.71: ARCACHE values not listed in Table A4.4 are reserved.
  ap_ar_cache_not_reserved: assert property (@(posedge aclk) disable iff (!aresetn)
    arvalid |-> cache_legal(arcache));
  // SPEC: A6.3.3 p.111: exclusive read Length must not exceed 16 transfers.
  ap_ar_excl_len_max: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && arlock) |-> arlen <= 8'd15);
  // SPEC: A6.3.3 p.111: exclusive read byte count must be a power of 2.
  ap_ar_excl_bytes_pow2: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && arlock) |-> arlen inside {8'd0, 8'd1, 8'd3, 8'd7, 8'd15});
  // SPEC: A6.3.3 p.111: exclusive read transfers at most 128 bytes.
  ap_ar_excl_bytes_max: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && arlock) |-> total_bytes(arsize, arlen) <= 32'd128);
  // SPEC: A6.3.3 p.111: exclusive read address aligned to Size x Length.
  ap_ar_excl_aligned: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && arlock) |-> (32'(lo12(araddr)) & (total_bytes(arsize, arlen) - 1)) == 0);

  // ---- Region identifier -----------------------------------------------------------------------
  // SPEC: A4.7.2 p.84: AxREGION must remain constant within any 4KB address space (AW vs last request).
  ap_aw_region_const_4k: assert property (@(posedge aclk) disable iff (!aresetn)
    (aw_hs && rg_v && aw_pg == rg_pg) |-> awregion == rg_val);
  // SPEC: A4.7.2 p.84: AxREGION must remain constant within any 4KB address space (AR vs last request).
  ap_ar_region_const_4k: assert property (@(posedge aclk) disable iff (!aresetn)
    (ar_hs && rg_v && ar_pg == rg_pg) |-> arregion == rg_val);
  // SPEC: A4.7.2 p.84: AxREGION must remain constant within any 4KB address space (AW vs AR, same cycle).
  ap_awar_region_const_4k: assert property (@(posedge aclk) disable iff (!aresetn)
    (aw_hs && ar_hs && aw_pg == ar_pg) |-> awregion == arregion);

  // ---- Write data ------------------------------------------------------------------------------
  // SPEC: A3.2.1 p.53: WLAST must be asserted on the final write transfer of the transaction.
  ap_w_wlast_on_final: assert property (@(posedge aclk) disable iff (!aresetn || wr_ovf)
    (wvalid && w_known && w_beat == {1'b0, w_len}) |-> wlast);
  // SPEC: A3.1.2 p.44: the Manager issues exactly Length write transfers (no early WLAST).
  ap_w_no_early_wlast: assert property (@(posedge aclk) disable iff (!aresetn || wr_ovf)
    (wvalid && w_known && w_beat < {1'b0, w_len}) |-> !wlast);
  // SPEC: A3.1.2 p.44: the Manager issues exactly Length write transfers (no extra beats).
  ap_w_no_beats_beyond_len: assert property (@(posedge aclk) disable iff (!aresetn || wr_ovf)
    (wvalid && w_known) |-> w_beat <= {1'b0, w_len});
  // SPEC: A5.5 p.100: W data leading its request is in request order and matches that AWLEN.
  ap_aw_leading_w_len_match: assert property (@(posedge aclk) disable iff (!aresetn || wr_ovf)
    aw_lead |-> aw_lead_beats == {1'b0, awlen} + 9'd1);
  // SPEC: A3.1.1 p.43: only the Size-wide byte lanes of the current transfer may be strobed.
  ap_w_strb_in_beat_lanes: assert property (@(posedge aclk) disable iff (!aresetn || wr_ovf)
    (wvalid && w_known) |-> (wstrb & ~w_lanes) == '0);
  // SPEC: A3.2.1.1 p.54: outside of the transaction container all write strobes must be LOW.
  ap_w_strb_in_container: assert property (@(posedge aclk) disable iff (!aresetn || wr_ovf)
    (wvalid && w_known && w_bu != BURST_FIXED) |-> (wstrb & ~w_cont_lanes) == '0);

  // ---- Write response --------------------------------------------------------------------------
  // SPEC: A5.5 p.100: BID must match the AWID of an outstanding (already accepted) write request.
  ap_b_id_outstanding: assert property (@(posedge aclk) disable iff (!aresetn || wr_ovf)
    bvalid |-> b_found);
  // SPEC: A2.3.2 p.31: BVALID only after the last write data transfer (WLAST) of that transaction.
  ap_b_after_wlast: assert property (@(posedge aclk) disable iff (!aresetn || wr_ovf)
    (bvalid && b_found) |-> b_data_done);
  // SPEC: A3.3.1 p.62: BRESP EXOKAY is only permitted for an exclusive write.
  ap_b_exokay_only_excl: assert property (@(posedge aclk) disable iff (!aresetn || wr_ovf)
    (bvalid && b_found && bresp == RESP_EXOKAY) |-> b_lock);

  // ---- Read data / response --------------------------------------------------------------------
  // SPEC: A3.2.2 p.55: RVALID only in response to an accepted request whose ARID matches RID.
  ap_r_id_outstanding: assert property (@(posedge aclk) disable iff (!aresetn || rd_ovf)
    rvalid |-> r_found);
  // SPEC: A3.2.2 p.55: RLAST must be asserted on the final read transfer of the transaction.
  ap_r_rlast_on_final: assert property (@(posedge aclk) disable iff (!aresetn || rd_ovf)
    (rvalid && r_final) |-> rlast);
  // SPEC: A3.1.2 p.44: the Subordinate issues exactly Length read transfers (no early RLAST).
  ap_r_no_early_rlast: assert property (@(posedge aclk) disable iff (!aresetn || rd_ovf)
    (rvalid && r_found && !r_final) |-> !rlast);
  // SPEC: A3.3.2 p.63: RRESP EXOKAY is only permitted for an exclusive read.
  ap_r_exokay_only_excl: assert property (@(posedge aclk) disable iff (!aresetn || rd_ovf)
    (rvalid && r_found && rresp == RESP_EXOKAY) |-> r_lock);
  // SPEC: A6.3.4 p.112: an exclusive read must not mix OKAY and EXOKAY responses.
  ap_r_excl_no_okay_exokay_mix: assert property (@(posedge aclk) disable iff (!aresetn || rd_ovf)
    (rvalid && r_found && r_lock) |->
      !((rresp == RESP_OKAY && r_sx) || (rresp == RESP_EXOKAY && r_so)));
  // SPEC: A6.3.4 p.112: a successful exclusive read returns EXOKAY on every read data transfer.
  ap_r_excl_exokay_all_beats: assert property (@(posedge aclk) disable iff (!aresetn || rd_ovf)
    (rvalid && r_found && r_lock && r_bts != '0) |-> ((rresp == RESP_EXOKAY) == r_sx));

  // ---- Exclusive sequence ----------------------------------------------------------------------
  // SPEC: A6.3.2 p.111: an exclusive write must not start until its exclusive read has completed.
  // SPEC-AMBIGUITY: A6.3.2 p.111 - the pairing read is taken as the outstanding exclusive read
  // with the same ID and address; an unrelated same-ID read to another address is not flagged.
  ap_aw_excl_after_read_done: assert property (@(posedge aclk) disable iff (!aresetn || rd_ovf)
    (aw_new && awlock) |-> !ex_rd_pend_aw);

  // =============================================================================================
  // FUNCTIONAL COVERAGE
  // =============================================================================================

  // ---- Handshake orderings (A2.3 Figures A2.2-A2.4) --------------------------------------------
  // SPEC: A2.3 p.29: AW VALID before READY.
  cp_aw_valid_before_ready: cover property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && !awready) ##1 aw_hs);
  // SPEC: A2.3 p.29: AW READY before VALID.
  cp_aw_ready_before_valid: cover property (@(posedge aclk) disable iff (!aresetn)
    (!awvalid && awready) ##1 aw_hs);
  // SPEC: A2.3 p.30: AW VALID with READY in the same cycle.
  cp_aw_valid_with_ready: cover property (@(posedge aclk) disable iff (!aresetn)
    (!awvalid && !awready) ##1 aw_hs);
  // SPEC: A2.3 p.29: AWREADY deasserted before AWVALID is asserted.
  cp_aw_ready_drop: cover property (@(posedge aclk) disable iff (!aresetn)
    (awready && !awvalid) ##1 (!awready && !awvalid));
  // SPEC: A2.3 p.29: W VALID before READY.
  cp_w_valid_before_ready: cover property (@(posedge aclk) disable iff (!aresetn)
    (wvalid && !wready) ##1 w_hs);
  // SPEC: A2.3 p.29: W READY before VALID.
  cp_w_ready_before_valid: cover property (@(posedge aclk) disable iff (!aresetn)
    (!wvalid && wready) ##1 w_hs);
  // SPEC: A2.3 p.30: W VALID with READY in the same cycle.
  cp_w_valid_with_ready: cover property (@(posedge aclk) disable iff (!aresetn)
    (!wvalid && !wready) ##1 w_hs);
  // SPEC: A2.3 p.29: WREADY deasserted before WVALID is asserted.
  cp_w_ready_drop: cover property (@(posedge aclk) disable iff (!aresetn)
    (wready && !wvalid) ##1 (!wready && !wvalid));
  // SPEC: A2.3 p.29: B VALID before READY.
  cp_b_valid_before_ready: cover property (@(posedge aclk) disable iff (!aresetn)
    (bvalid && !bready) ##1 b_hs);
  // SPEC: A2.3.2 p.31: BREADY asserted before BVALID.
  cp_b_ready_before_valid: cover property (@(posedge aclk) disable iff (!aresetn)
    (!bvalid && bready) ##1 b_hs);
  // SPEC: A2.3 p.30: B VALID with READY in the same cycle.
  cp_b_valid_with_ready: cover property (@(posedge aclk) disable iff (!aresetn)
    (!bvalid && !bready) ##1 b_hs);
  // SPEC: A2.3 p.29: BREADY deasserted before BVALID is asserted.
  cp_b_ready_drop: cover property (@(posedge aclk) disable iff (!aresetn)
    (bready && !bvalid) ##1 (!bready && !bvalid));
  // SPEC: A2.3 p.29: AR VALID before READY.
  cp_ar_valid_before_ready: cover property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && !arready) ##1 ar_hs);
  // SPEC: A2.3.2 p.32: ARREADY asserted before ARVALID.
  cp_ar_ready_before_valid: cover property (@(posedge aclk) disable iff (!aresetn)
    (!arvalid && arready) ##1 ar_hs);
  // SPEC: A2.3 p.30: AR VALID with READY in the same cycle.
  cp_ar_valid_with_ready: cover property (@(posedge aclk) disable iff (!aresetn)
    (!arvalid && !arready) ##1 ar_hs);
  // SPEC: A2.3 p.29: ARREADY deasserted before ARVALID is asserted.
  cp_ar_ready_drop: cover property (@(posedge aclk) disable iff (!aresetn)
    (arready && !arvalid) ##1 (!arready && !arvalid));
  // SPEC: A2.3 p.29: R VALID before READY.
  cp_r_valid_before_ready: cover property (@(posedge aclk) disable iff (!aresetn)
    (rvalid && !rready) ##1 r_hs);
  // SPEC: A2.3.2 p.32: RREADY asserted before RVALID.
  cp_r_ready_before_valid: cover property (@(posedge aclk) disable iff (!aresetn)
    (!rvalid && rready) ##1 r_hs);
  // SPEC: A2.3 p.30: R VALID with READY in the same cycle.
  cp_r_valid_with_ready: cover property (@(posedge aclk) disable iff (!aresetn)
    (!rvalid && !rready) ##1 r_hs);
  // SPEC: A2.3 p.29: RREADY deasserted before RVALID is asserted.
  cp_r_ready_drop: cover property (@(posedge aclk) disable iff (!aresetn)
    (rready && !rvalid) ##1 (!rready && !rvalid));
  // SPEC: A2.3 p.29: back-to-back W transfers on consecutive cycles.
  cp_w_back_to_back: cover property (@(posedge aclk) disable iff (!aresetn) w_hs ##1 w_hs ##1 w_hs);
  // SPEC: A2.3 p.29: back-to-back R transfers on consecutive cycles.
  cp_r_back_to_back: cover property (@(posedge aclk) disable iff (!aresetn) r_hs ##1 r_hs ##1 r_hs);

  // ---- Burst type ------------------------------------------------------------------------------
  // SPEC: A3.1.4 p.46: FIXED write burst.
  cp_aw_burst_fixed: cover property (@(posedge aclk) disable iff (!aresetn) aw_hs && awburst == BURST_FIXED);
  // SPEC: A3.1.4 p.46: INCR write burst.
  cp_aw_burst_incr: cover property (@(posedge aclk) disable iff (!aresetn) aw_hs && awburst == BURST_INCR);
  // SPEC: A3.1.4 p.47: WRAP write burst.
  cp_aw_burst_wrap: cover property (@(posedge aclk) disable iff (!aresetn) aw_hs && awburst == BURST_WRAP);
  // SPEC: A3.1.4 p.46: FIXED read burst.
  cp_ar_burst_fixed: cover property (@(posedge aclk) disable iff (!aresetn) ar_hs && arburst == BURST_FIXED);
  // SPEC: A3.1.4 p.46: INCR read burst.
  cp_ar_burst_incr: cover property (@(posedge aclk) disable iff (!aresetn) ar_hs && arburst == BURST_INCR);
  // SPEC: A3.1.4 p.47: WRAP read burst.
  cp_ar_burst_wrap: cover property (@(posedge aclk) disable iff (!aresetn) ar_hs && arburst == BURST_WRAP);

  // ---- Length ----------------------------------------------------------------------------------
  // SPEC: A3.1.2 p.44: single-transfer write.
  cp_aw_len_1: cover property (@(posedge aclk) disable iff (!aresetn) aw_hs && awlen == 8'd0);
  // SPEC: A3.1.2 p.44: 16-transfer write (FIXED/WRAP/exclusive maximum).
  cp_aw_len_16: cover property (@(posedge aclk) disable iff (!aresetn) aw_hs && awlen == 8'd15);
  // SPEC: A3.1.2 p.44: INCR write longer than 16 transfers.
  cp_aw_incr_len_gt16: cover property (@(posedge aclk) disable iff (!aresetn)
    aw_hs && awburst == BURST_INCR && awlen > 8'd15);
  // SPEC: A3.1.2 p.44: maximum 256-transfer write.
  cp_aw_len_256: cover property (@(posedge aclk) disable iff (!aresetn) aw_hs && awlen == 8'd255);
  // SPEC: A3.1.2 p.44: single-transfer read.
  cp_ar_len_1: cover property (@(posedge aclk) disable iff (!aresetn) ar_hs && arlen == 8'd0);
  // SPEC: A3.1.2 p.44: 16-transfer read.
  cp_ar_len_16: cover property (@(posedge aclk) disable iff (!aresetn) ar_hs && arlen == 8'd15);
  // SPEC: A3.1.2 p.44: INCR read longer than 16 transfers.
  cp_ar_incr_len_gt16: cover property (@(posedge aclk) disable iff (!aresetn)
    ar_hs && arburst == BURST_INCR && arlen > 8'd15);
  // SPEC: A3.1.2 p.44: maximum 256-transfer read.
  cp_ar_len_256: cover property (@(posedge aclk) disable iff (!aresetn) ar_hs && arlen == 8'd255);

  for (genvar i = 0; i < 4; i++) begin : g_wrap_len_cov
    // SPEC: A3.1.2 p.44: WRAP write of each legal Length (2, 4, 8, 16).
    cp_aw_wrap_len: cover property (@(posedge aclk) disable iff (!aresetn)
      aw_hs && awburst == BURST_WRAP && awlen == 8'((2 << i) - 1));
    // SPEC: A3.1.2 p.44: WRAP read of each legal Length (2, 4, 8, 16).
    cp_ar_wrap_len: cover property (@(posedge aclk) disable iff (!aresetn)
      ar_hs && arburst == BURST_WRAP && arlen == 8'((2 << i) - 1));
  end

  // ---- Size ------------------------------------------------------------------------------------
  for (genvar s = 0; s <= DB_LOG2; s++) begin : g_size_cov
    // SPEC: A3.1.1 p.43: write of each legal AWSIZE up to the data width.
    cp_aw_size: cover property (@(posedge aclk) disable iff (!aresetn) aw_hs && awsize == 3'(s));
    // SPEC: A3.1.1 p.43: read of each legal ARSIZE up to the data width.
    cp_ar_size: cover property (@(posedge aclk) disable iff (!aresetn) ar_hs && arsize == 3'(s));
  end

  // ---- Address alignment / narrow / boundaries --------------------------------------------------
  // SPEC: A3.2.3 p.55: narrow multi-transfer write (Size below data width).
  cp_aw_narrow: cover property (@(posedge aclk) disable iff (!aresetn)
    aw_hs && sz_bytes(awsize) < 32'(DB) && awlen != 8'd0);
  // SPEC: A3.2.3 p.55: narrow multi-transfer read (Size below data width).
  cp_ar_narrow: cover property (@(posedge aclk) disable iff (!aresetn)
    ar_hs && sz_bytes(arsize) < 32'(DB) && arlen != 8'd0);
  // SPEC: A3.2.5 p.58: unaligned INCR write start address.
  cp_aw_unaligned: cover property (@(posedge aclk) disable iff (!aresetn)
    aw_hs && awburst == BURST_INCR && (32'(lo12(awaddr)) & (sz_bytes(awsize) - 1)) != 0);
  // SPEC: A3.2.5 p.58: unaligned INCR read start address.
  cp_ar_unaligned: cover property (@(posedge aclk) disable iff (!aresetn)
    ar_hs && arburst == BURST_INCR && (32'(lo12(araddr)) & (sz_bytes(arsize) - 1)) != 0);
  // SPEC: A3.1.4 p.47: WRAP write starting above the wrap boundary (address wraps).
  cp_aw_wrap_wraps: cover property (@(posedge aclk) disable iff (!aresetn)
    aw_hs && awburst == BURST_WRAP && (32'(lo12(awaddr)) % total_bytes(awsize, awlen)) != 0);
  // SPEC: A3.1.4 p.47: WRAP read starting above the wrap boundary (address wraps).
  cp_ar_wrap_wraps: cover property (@(posedge aclk) disable iff (!aresetn)
    ar_hs && arburst == BURST_WRAP && (32'(lo12(araddr)) % total_bytes(arsize, arlen)) != 0);
  // SPEC: A3.1 p.43: INCR write ending exactly at a 4KB boundary.
  cp_aw_ends_at_4k: cover property (@(posedge aclk) disable iff (!aresetn)
    aw_hs && awburst == BURST_INCR &&
    ((32'(lo12(awaddr)) & ~(sz_bytes(awsize) - 1)) + total_bytes(awsize, awlen)) == 32'd4096);
  // SPEC: A3.1 p.43: INCR read ending exactly at a 4KB boundary.
  cp_ar_ends_at_4k: cover property (@(posedge aclk) disable iff (!aresetn)
    ar_hs && arburst == BURST_INCR &&
    ((32'(lo12(araddr)) & ~(sz_bytes(arsize) - 1)) + total_bytes(arsize, arlen)) == 32'd4096);

  // ---- Memory types / protection / QoS / region ------------------------------------------------
  for (genvar c = 0; c < 10; c++) begin : g_cache_cov
    // SPEC: A4.3 p.71: write request of each Table A4.4 memory-type encoding.
    cp_aw_cache: cover property (@(posedge aclk) disable iff (!aresetn) aw_hs && awcache == CACHE_TYPES[c]);
    // SPEC: A4.3 p.71: read request of each Table A4.4 memory-type encoding.
    cp_ar_cache: cover property (@(posedge aclk) disable iff (!aresetn) ar_hs && arcache == CACHE_TYPES[c]);
  end
  // SPEC: A4.5.2 p.78: privileged write (AWPROT[0]).
  cp_aw_prot_priv: cover property (@(posedge aclk) disable iff (!aresetn) aw_hs && awprot[0]);
  // SPEC: A4.5.3 p.79: Non-secure write (AWPROT[1]).
  cp_aw_prot_ns: cover property (@(posedge aclk) disable iff (!aresetn) aw_hs && awprot[1]);
  // SPEC: A4.5.2 p.78: instruction write (AWPROT[2]).
  cp_aw_prot_instr: cover property (@(posedge aclk) disable iff (!aresetn) aw_hs && awprot[2]);
  // SPEC: A4.5.2 p.78: privileged read (ARPROT[0]).
  cp_ar_prot_priv: cover property (@(posedge aclk) disable iff (!aresetn) ar_hs && arprot[0]);
  // SPEC: A4.5.3 p.79: Non-secure read (ARPROT[1]).
  cp_ar_prot_ns: cover property (@(posedge aclk) disable iff (!aresetn) ar_hs && arprot[1]);
  // SPEC: A4.5.2 p.78: instruction read (ARPROT[2]).
  cp_ar_prot_instr: cover property (@(posedge aclk) disable iff (!aresetn) ar_hs && arprot[2]);
  // SPEC: A4.8.1 p.86: write with non-default AWQOS.
  cp_aw_qos_nonzero: cover property (@(posedge aclk) disable iff (!aresetn) aw_hs && awqos != 4'd0);
  // SPEC: A4.8.1 p.86: read with non-default ARQOS.
  cp_ar_qos_nonzero: cover property (@(posedge aclk) disable iff (!aresetn) ar_hs && arqos != 4'd0);
  // SPEC: A4.7.2 p.84: write with non-default AWREGION.
  cp_aw_region_nonzero: cover property (@(posedge aclk) disable iff (!aresetn) aw_hs && awregion != 4'd0);
  // SPEC: A4.7.2 p.84: read with non-default ARREGION.
  cp_ar_region_nonzero: cover property (@(posedge aclk) disable iff (!aresetn) ar_hs && arregion != 4'd0);

  // ---- Write strobes / write data ordering -----------------------------------------------------
  // SPEC: A3.2.1.1 p.54: write transfer with all strobes LOW (no data written).
  cp_w_strb_none: cover property (@(posedge aclk) disable iff (!aresetn) w_hs && wstrb == '0);
  // SPEC: A3.2.1.1 p.54: write transfer with all strobes HIGH.
  cp_w_strb_full: cover property (@(posedge aclk) disable iff (!aresetn) w_hs && wstrb == '1);
  // SPEC: A3.2.1.1 p.54: sparse strobes inside the active lanes.
  cp_w_strb_sparse: cover property (@(posedge aclk) disable iff (!aresetn || wr_ovf)
    w_hs && w_known && wstrb != '0 && wstrb != w_lanes);
  // SPEC: A3.2.1.1 p.54: unaligned first transfer with strobes below the start address.
  cp_w_strb_below_start: cover property (@(posedge aclk) disable iff (!aresetn || wr_ovf)
    w_hs && w_known && w_beat == '0 && w_bu == BURST_INCR && (wstrb & w_below) != '0);
  // SPEC: A2.6 p.41: write data appears before its write request.
  cp_w_before_aw: cover property (@(posedge aclk) disable iff (!aresetn) w_hs && !w_known);
  // SPEC: A2.6 p.41: write data in the same cycle as its write request.
  cp_w_with_aw: cover property (@(posedge aclk) disable iff (!aresetn)
    w_hs && aw_hs && w_beat == '0 && aw_cnt == wb_cnt);
  // SPEC: A5.5 p.100: a whole W burst completes before its AW is accepted.
  cp_w_burst_before_aw: cover property (@(posedge aclk) disable iff (!aresetn) aw_lead);

  // ---- Responses -------------------------------------------------------------------------------
  // SPEC: A3.3.1 p.62: BRESP OKAY.
  cp_b_okay: cover property (@(posedge aclk) disable iff (!aresetn) b_hs && bresp == RESP_OKAY);
  // SPEC: A3.3.1 p.62: BRESP SLVERR.
  cp_b_slverr: cover property (@(posedge aclk) disable iff (!aresetn) b_hs && bresp == RESP_SLVERR);
  // SPEC: A3.3.1 p.62: BRESP DECERR.
  cp_b_decerr: cover property (@(posedge aclk) disable iff (!aresetn) b_hs && bresp == RESP_DECERR);
  // SPEC: A3.3.2 p.63: RRESP OKAY.
  cp_r_okay: cover property (@(posedge aclk) disable iff (!aresetn) r_hs && rresp == RESP_OKAY);
  // SPEC: A3.3.2 p.63: RRESP SLVERR.
  cp_r_slverr: cover property (@(posedge aclk) disable iff (!aresetn) r_hs && rresp == RESP_SLVERR);
  // SPEC: A3.3.2 p.63: RRESP DECERR.
  cp_r_decerr: cover property (@(posedge aclk) disable iff (!aresetn) r_hs && rresp == RESP_DECERR);
  // SPEC: A3.3.2 p.63: RRESP differs between transfers of one transaction.
  cp_r_resp_varies: cover property (@(posedge aclk) disable iff (!aresetn)
    r_hs && r_mid_q && rid == r_prev_id && rresp != r_prev_resp);
  // SPEC: A2.3.2 p.31: BVALID in the cycle right after the WLAST transfer.
  cp_b_right_after_wlast: cover property (@(posedge aclk) disable iff (!aresetn)
    (w_hs && wlast) ##1 bvalid);
  // SPEC: A2.3.2 p.32: RVALID in the cycle right after the AR handshake.
  cp_r_right_after_ar: cover property (@(posedge aclk) disable iff (!aresetn) ar_hs ##1 rvalid);

  // ---- Exclusive access ------------------------------------------------------------------------
  // SPEC: A6.3 p.110: exclusive write request.
  cp_aw_exclusive: cover property (@(posedge aclk) disable iff (!aresetn) aw_hs && awlock);
  // SPEC: A6.3 p.110: exclusive read request.
  cp_ar_exclusive: cover property (@(posedge aclk) disable iff (!aresetn) ar_hs && arlock);
  // SPEC: A6.3.4 p.112: exclusive read succeeded (EXOKAY).
  cp_r_excl_exokay: cover property (@(posedge aclk) disable iff (!aresetn || rd_ovf)
    r_hs && r_found && r_lock && rresp == RESP_EXOKAY);
  // SPEC: A6.3.2 p.111: exclusive read to a Subordinate without exclusive support (OKAY).
  cp_r_excl_okay: cover property (@(posedge aclk) disable iff (!aresetn || rd_ovf)
    r_hs && r_found && r_lock && rresp == RESP_OKAY);
  // SPEC: A6.3.4 p.112: exclusive write succeeded (EXOKAY).
  cp_b_excl_exokay: cover property (@(posedge aclk) disable iff (!aresetn || wr_ovf)
    b_hs && b_found && b_lock && bresp == RESP_EXOKAY);
  // SPEC: A6.3.4 p.112: exclusive write failed (OKAY).
  cp_b_excl_okay: cover property (@(posedge aclk) disable iff (!aresetn || wr_ovf)
    b_hs && b_found && b_lock && bresp == RESP_OKAY);
  // SPEC: A6.3.1 p.110: exclusive write whose AWID matches an exclusive read already completed.
  cp_excl_read_then_write: cover property (@(posedge aclk) disable iff (!aresetn)
    (r_hs && r_final && r_lock) ##[1:16] (aw_hs && awlock));

  // ---- Ordering / outstanding / interleaving ---------------------------------------------------
  // SPEC: A5.1 p.90: multiple outstanding write transactions.
  cp_wr_outstanding_4: cover property (@(posedge aclk) disable iff (!aresetn || wr_ovf) wr_out >= 8'd4);
  // SPEC: A5.1 p.90: multiple outstanding read transactions.
  cp_rd_outstanding_4: cover property (@(posedge aclk) disable iff (!aresetn || rd_ovf) rd_out >= 8'd4);
  // SPEC: A5.3 p.93: write issued with the same ID as an outstanding write.
  cp_aw_same_id_outstanding: cover property (@(posedge aclk) disable iff (!aresetn || wr_ovf)
    aw_hs && aw_id_busy);
  // SPEC: A5.3 p.93: read issued with the same ID as an outstanding read.
  cp_ar_same_id_outstanding: cover property (@(posedge aclk) disable iff (!aresetn || rd_ovf)
    ar_hs && ar_id_busy);
  // SPEC: A5.1 p.90: write response returned out of order w.r.t. an older different-ID write.
  cp_b_out_of_order: cover property (@(posedge aclk) disable iff (!aresetn || wr_ovf)
    b_retire && b_seq != wr_old_seq);
  // SPEC: A5.1 p.90: read data started out of order w.r.t. an older different-ID read.
  cp_r_out_of_order: cover property (@(posedge aclk) disable iff (!aresetn || rd_ovf)
    r_hs && r_found && r_bts == '0 && r_seq != rd_old_seq);
  // SPEC: A5.6.1 p.101: read data interleaved between transactions with different IDs.
  cp_r_interleave: cover property (@(posedge aclk) disable iff (!aresetn)
    r_hs && r_mid_q && rid != r_prev_id);
  // SPEC: A2.1.2 p.27: reset asserted while transactions are outstanding.
  cp_reset_with_outstanding: cover property (@(posedge aclk)
    (aresetn && (wr_any || rd_any)) ##1 !aresetn);

endmodule
