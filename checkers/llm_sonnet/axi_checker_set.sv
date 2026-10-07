// AXI4 protocol checker + functional coverage model.
// Source: AMBA AXI Protocol Specification IHI 0022 Issue L, Part A chapters A1-A6.
// Passive: samples on ACLK rising edge, ARESETn active-low.
// ASSUMPTION: at most WT outstanding writes / RT outstanding reads are tracked; if the
//   tracker overflows, the table-dependent checks are switched off (sticky) rather than
//   raising a false failure.
// ASSUMPTION: all AXI4 signals of port_list.sv are present; AxCACHE reserved encodings
//   are taken from Table A4.4 (values not listed are reserved and must not be driven).
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

  // ------------------------------------------------------------------
  // Constants
  // ------------------------------------------------------------------
  localparam int DB    = DATA_W/8;            // data bytes
  localparam int MAXSZ = $clog2(DB);          // largest legal AxSIZE
  localparam int WT    = 64;                  // write tracker depth (power of 2)
  localparam int WI    = $clog2(WT);
  localparam int RT    = 64;                  // read tracker depth
  localparam int PN    = 8;                   // region/page table depth
  localparam int PI    = $clog2(PN);
  localparam int XR_IDW = (ID_W > 8) ? 8 : ID_W;   // exclusive-monitor index width
  localparam int XRN   = 1 << XR_IDW;
  localparam int AX    = ADDR_W + 16;         // extended address width for arithmetic

  localparam logic [1:0] BURST_FIXED = 2'b00, BURST_INCR = 2'b01, BURST_WRAP = 2'b10;
  localparam logic [1:0] RESP_OKAY = 2'b00, RESP_EXOKAY = 2'b01, RESP_SLVERR = 2'b10, RESP_DECERR = 2'b11;

  // ------------------------------------------------------------------
  // Functions
  // ------------------------------------------------------------------
  // True when a transaction crosses a 4KB boundary (INCR arithmetic of A3.1.6)
  function automatic logic f_cross4k(input logic [ADDR_W-1:0] a, input logic [2:0] sz, input logic [7:0] ln);
    logic [AX-1:0] ae, sb, al, last;
    ae = {16'b0, a};
    sb = {{(AX-1){1'b0}}, 1'b1} << sz;
    al = ae & ~(sb - 1'b1);
    last = al + ({{(AX-8){1'b0}}, ln} << sz) + (sb - 1'b1);
    f_cross4k = ((last >> 12) != (ae >> 12));
  endfunction

  // Low 12 bits of the last byte address of an INCR transaction
  function automatic logic [11:0] f_last_off(input logic [ADDR_W-1:0] a, input logic [2:0] sz, input logic [7:0] ln);
    logic [AX-1:0] ae, sb, al, last;
    ae = {16'b0, a};
    sb = {{(AX-1){1'b0}}, 1'b1} << sz;
    al = ae & ~(sb - 1'b1);
    last = al + ({{(AX-8){1'b0}}, ln} << sz) + (sb - 1'b1);
    f_last_off = last[11:0];
  endfunction

  // Byte lanes that a given transfer (beat n, 0 based) is permitted to use (A3.1.6)
  function automatic logic [DB-1:0] f_lane_mask(input logic [ADDR_W-1:0] a, input logic [2:0] sz,
                                                input logic [1:0] bt, input logic [7:0] ln,
                                                input logic [15:0] n);
    logic [AX-1:0] ae, sb, al, cont, wbnd, raw, an, aln, dbm;
    logic [DB-1:0] m;
    int lo, hi;
    ae   = {16'b0, a};
    sb   = {{(AX-1){1'b0}}, 1'b1} << sz;
    al   = ae & ~(sb - 1'b1);
    cont = sb * ({{(AX-8){1'b0}}, ln} + 1'b1);
    wbnd = ae & ~(cont - 1'b1);
    raw  = al + ({{(AX-16){1'b0}}, n} * sb);
    dbm  = DB - 1;
    if (n == 16'd0)                                    an = ae;
    else if (bt == BURST_FIXED)                        an = ae;
    else if (bt == BURST_WRAP && raw >= wbnd + cont)   an = raw - cont;
    else                                               an = raw;
    aln = an & ~(sb - 1'b1);
    lo  = int'(an & dbm);
    hi  = int'(aln & dbm) + int'(sb) - 1;
    m   = '0;
    if (sz > 3'(MAXSZ)) begin
      m = '1;
    end else begin
      for (int i = 0; i < DB; i++) if (i >= lo && i <= hi) m[i] = 1'b1;
    end
    f_lane_mask = m;
  endfunction

  // Table A4.4: AxCACHE values that are not reserved (same set for AR and AW)
  function automatic logic f_cache_ok(input logic [3:0] c);
    f_cache_ok = c[1] | ~(c[3] | c[2]);
  endfunction

  // ------------------------------------------------------------------
  // Handshake and reset helpers
  // ------------------------------------------------------------------
  logic rst_q = 1'b0;
  always_ff @(posedge aclk) rst_q <= aresetn;

  wire aw_hs = awvalid && awready;
  wire w_hs  = wvalid  && wready;
  wire b_hs  = bvalid  && bready;
  wire ar_hs = arvalid && arready;
  wire r_hs  = rvalid  && rready;

  wire w_end = w_hs && wlast;

  // ------------------------------------------------------------------
  // Write tracker
  // ------------------------------------------------------------------
  logic [31:0]        aw_cnt;      // AW handshakes accepted
  logic [31:0]        wb_cnt;      // W bursts completed (WLAST handshakes)
  logic [15:0]        wbeat;       // W beats accepted in the current burst
  logic               wt_ovf;

  logic               wt_v     [WT];
  logic [31:0]        wt_seq   [WT];
  logic [ID_W-1:0]    wt_id    [WT];
  logic [ADDR_W-1:0]  wt_addr  [WT];
  logic [7:0]         wt_len   [WT];
  logic [2:0]         wt_size  [WT];
  logic [1:0]         wt_burst [WT];
  logic               wt_lock  [WT];
  logic               wt_wdone [WT];
  logic               wdone_early [WT];
  logic [15:0]        wearly_beats [WT];

  wire [WI-1:0] aw_idx = aw_cnt[WI-1:0];
  wire [WI-1:0] widx   = wb_cnt[WI-1:0];

  wire w_known_reg = wt_v[widx] && (wt_seq[widx] == wb_cnt);
  wire w_known_new = aw_hs && (aw_cnt == wb_cnt);
  wire w_known     = w_known_reg || w_known_new;

  wire [ADDR_W-1:0] w_addr  = w_known_reg ? wt_addr[widx]  : awaddr;
  wire [7:0]        w_len   = w_known_reg ? wt_len[widx]   : awlen;
  wire [2:0]        w_size  = w_known_reg ? wt_size[widx]  : awsize;
  wire [1:0]        w_burst = w_known_reg ? wt_burst[widx] : awburst;

  wire [15:0] w_len16    = {8'b0, w_len};
  wire        w_is_final = (wbeat == w_len16);
  wire [DB-1:0] w_lmask  = f_lane_mask(w_addr, w_size, w_burst, w_len, wbeat);

  // AW arriving after some or all of its write data (data before address is legal, A2.6)
  wire aw_early_hit = wdone_early[aw_idx];
  wire aw_wfirst_bad = aw_hs && (
        (aw_early_hit && (wearly_beats[aw_idx] != ({8'b0, awlen} + 16'd1))) ||
        (!aw_early_hit && (aw_cnt == wb_cnt) && (wbeat > {8'b0, awlen})));

  // B channel: oldest outstanding write carrying BID
  logic              b_found, b_ooo;
  logic [WI-1:0]     b_idx;
  logic [31:0]       b_age;
  always_comb begin
    b_found = 1'b0; b_idx = '0; b_age = '0; b_ooo = 1'b0;
    for (int i = 0; i < WT; i++) begin
      if (wt_v[i] && wt_id[i] == bid) begin
        if (!b_found || ((aw_cnt - wt_seq[i]) > b_age)) begin
          b_found = 1'b1; b_idx = WI'(i); b_age = aw_cnt - wt_seq[i];
        end
      end
    end
    for (int i = 0; i < WT; i++)
      if (b_found && wt_v[i] && ((aw_cnt - wt_seq[i]) > b_age)) b_ooo = 1'b1;
  end
  wire b_complete = b_found && wt_wdone[b_idx];
  wire b_lock     = b_found && wt_lock[b_idx];

  logic xr_seen [XRN];

  int unsigned wr_outst;
  logic        aw_same_id;
  always_comb begin
    wr_outst = 0; aw_same_id = 1'b0;
    for (int i = 0; i < WT; i++) begin
      if (wt_v[i]) wr_outst++;
      if (wt_v[i] && wt_id[i] == awid) aw_same_id = 1'b1;
    end
  end

  always_ff @(posedge aclk) begin
    if (!aresetn) begin
      aw_cnt <= '0; wb_cnt <= '0; wbeat <= '0; wt_ovf <= 1'b0;
      for (int i = 0; i < WT; i++) begin
        wt_v[i] <= 1'b0; wt_seq[i] <= '0; wt_id[i] <= '0; wt_addr[i] <= '0; wt_len[i] <= '0;
        wt_size[i] <= '0; wt_burst[i] <= '0; wt_lock[i] <= 1'b0; wt_wdone[i] <= 1'b0;
        wdone_early[i] <= 1'b0; wearly_beats[i] <= '0;
      end
      for (int i = 0; i < XRN; i++) xr_seen[i] <= 1'b0;
    end else begin
      if (b_hs && b_found) wt_v[b_idx] <= 1'b0;
      if (aw_hs) begin
        if (wt_v[aw_idx] && !(b_hs && b_found && b_idx == aw_idx)) wt_ovf <= 1'b1;
        wt_v[aw_idx]     <= 1'b1;
        wt_seq[aw_idx]   <= aw_cnt;
        wt_id[aw_idx]    <= awid;
        wt_addr[aw_idx]  <= awaddr;
        wt_len[aw_idx]   <= awlen;
        wt_size[aw_idx]  <= awsize;
        wt_burst[aw_idx] <= awburst;
        wt_lock[aw_idx]  <= awlock;
        wt_wdone[aw_idx] <= aw_early_hit || (w_end && aw_cnt == wb_cnt);
        wdone_early[aw_idx] <= 1'b0;
        aw_cnt <= aw_cnt + 32'd1;
      end
      if (w_hs) begin
        if (w_end) begin
          wbeat  <= '0;
          wb_cnt <= wb_cnt + 32'd1;
          if (w_known_reg) wt_wdone[widx] <= 1'b1;
          else if (!w_known_new) begin
            wdone_early[widx]   <= 1'b1;
            wearly_beats[widx]  <= wbeat + 16'd1;
          end
        end else if (wbeat != 16'hFFFF) wbeat <= wbeat + 16'd1;
      end
      if (ar_hs && arlock) xr_seen[arid[XR_IDW-1:0]] <= 1'b1;
    end
  end

  // ------------------------------------------------------------------
  // Read tracker
  // ------------------------------------------------------------------
  logic [31:0]        ar_cnt;
  logic               rt_ovf;
  logic               rt_v     [RT];
  logic [31:0]        rt_seq   [RT];
  logic [ID_W-1:0]    rt_id    [RT];
  logic [7:0]         rt_len   [RT];
  logic               rt_lock  [RT];
  logic [15:0]        rt_beat  [RT];
  logic               rt_ok    [RT];
  logic               rt_exok  [RT];

  logic              r_found, r_ooo;
  logic [$clog2(RT)-1:0] r_idx;
  logic [31:0]       r_age;
  logic              r_free_found;
  logic [$clog2(RT)-1:0] r_free_idx;
  int unsigned       rd_outst;
  logic              ar_same_id;
  always_comb begin
    r_found = 1'b0; r_idx = '0; r_age = '0; r_ooo = 1'b0;
    r_free_found = 1'b0; r_free_idx = '0; rd_outst = 0; ar_same_id = 1'b0;
    for (int i = 0; i < RT; i++) begin
      if (rt_v[i] && rt_id[i] == rid) begin
        if (!r_found || ((ar_cnt - rt_seq[i]) > r_age)) begin
          r_found = 1'b1; r_idx = ($clog2(RT))'(i); r_age = ar_cnt - rt_seq[i];
        end
      end
      if (!rt_v[i] && !r_free_found) begin r_free_found = 1'b1; r_free_idx = ($clog2(RT))'(i); end
      if (rt_v[i]) rd_outst++;
      if (rt_v[i] && rt_id[i] == arid) ar_same_id = 1'b1;
    end
    for (int i = 0; i < RT; i++)
      if (r_found && rt_v[i] && ((ar_cnt - rt_seq[i]) > r_age)) r_ooo = 1'b1;
  end
  wire [15:0] r_len16 = {8'b0, rt_len[r_idx]};
  wire        r_last_now = (rt_beat[r_idx] == r_len16);
  wire        r_lock  = r_found && rt_lock[r_idx];
  wire        r_mix   = r_found && rt_lock[r_idx] &&
                        ((rresp == RESP_OKAY   && rt_exok[r_idx]) ||
                         (rresp == RESP_EXOKAY && rt_ok[r_idx]));

  logic       r_prev_open;
  logic [ID_W-1:0] r_prev_id;

  always_ff @(posedge aclk) begin
    if (!aresetn) begin
      ar_cnt <= '0; rt_ovf <= 1'b0; r_prev_open <= 1'b0; r_prev_id <= '0;
      for (int i = 0; i < RT; i++) begin
        rt_v[i] <= 1'b0; rt_seq[i] <= '0; rt_id[i] <= '0; rt_len[i] <= '0; rt_lock[i] <= 1'b0;
        rt_beat[i] <= '0; rt_ok[i] <= 1'b0; rt_exok[i] <= 1'b0;
      end
    end else begin
      if (r_hs && r_found) begin
        rt_beat[r_idx] <= (rt_beat[r_idx] == 16'hFFFF) ? rt_beat[r_idx] : rt_beat[r_idx] + 16'd1;
        if (rresp == RESP_OKAY)   rt_ok[r_idx]   <= 1'b1;
        if (rresp == RESP_EXOKAY) rt_exok[r_idx] <= 1'b1;
        if (rlast || r_last_now) rt_v[r_idx] <= 1'b0;
      end
      if (r_hs) begin r_prev_open <= !rlast; r_prev_id <= rid; end
      if (ar_hs) begin
        if (!r_free_found) rt_ovf <= 1'b1;
        else begin
          rt_v[r_free_idx]    <= 1'b1;
          rt_seq[r_free_idx]  <= ar_cnt;
          rt_id[r_free_idx]   <= arid;
          rt_len[r_free_idx]  <= arlen;
          rt_lock[r_free_idx] <= arlock;
          rt_beat[r_free_idx] <= '0;
          rt_ok[r_free_idx]   <= 1'b0;
          rt_exok[r_free_idx] <= 1'b0;
        end
        ar_cnt <= ar_cnt + 32'd1;
      end
    end
  end

  // ------------------------------------------------------------------
  // AxREGION-per-4KB-page table (A4.7.2)
  // ------------------------------------------------------------------
  wire [AX-1:0] awaddr_x = {16'b0, awaddr};
  wire [AX-1:0] araddr_x = {16'b0, araddr};
  wire [ADDR_W-1:0] aw_page = awaddr_x[ADDR_W+11:12];
  wire [ADDR_W-1:0] ar_page = araddr_x[ADDR_W+11:12];
  logic              pg_v  [PN];
  logic [ADDR_W-1:0] pg_pg [PN];
  logic [3:0]        pg_rg [PN];
  logic [PI-1:0]     pg_rr;
  logic              aw_reg_conf, ar_reg_conf, aw_pg_hit, ar_pg_hit;
  logic [PI-1:0]     aw_pg_idx, ar_pg_idx;
  always_comb begin
    aw_reg_conf = 1'b0; ar_reg_conf = 1'b0; aw_pg_hit = 1'b0; ar_pg_hit = 1'b0;
    aw_pg_idx = '0; ar_pg_idx = '0;
    for (int i = 0; i < PN; i++) begin
      if (pg_v[i] && pg_pg[i] == aw_page) begin
        aw_pg_hit = 1'b1; aw_pg_idx = PI'(i);
        if (pg_rg[i] != awregion) aw_reg_conf = 1'b1;
      end
      if (pg_v[i] && pg_pg[i] == ar_page) begin
        ar_pg_hit = 1'b1; ar_pg_idx = PI'(i);
        if (pg_rg[i] != arregion) ar_reg_conf = 1'b1;
      end
    end
    if (arvalid && awvalid && ar_page == aw_page && arregion != awregion) aw_reg_conf = 1'b1;
  end
  wire [PI-1:0] pg_rr_ar = pg_rr + PI'(aw_hs && !aw_pg_hit);
  always_ff @(posedge aclk) begin
    if (!aresetn) begin
      pg_rr <= '0;
      for (int i = 0; i < PN; i++) begin pg_v[i] <= 1'b0; pg_pg[i] <= '0; pg_rg[i] <= '0; end
    end else begin
      if (aw_hs) begin
        if (aw_pg_hit) pg_rg[aw_pg_idx] <= awregion;
        else begin pg_v[pg_rr] <= 1'b1; pg_pg[pg_rr] <= aw_page; pg_rg[pg_rr] <= awregion; end
      end
      if (ar_hs) begin
        if (ar_pg_hit) pg_rg[ar_pg_idx] <= arregion;
        else begin pg_v[pg_rr_ar] <= 1'b1; pg_pg[pg_rr_ar] <= ar_page; pg_rg[pg_rr_ar] <= arregion; end
      end
      pg_rr <= pg_rr_ar + PI'(ar_hs && !ar_pg_hit);
    end
  end

  wire wr_ovf_dis = wt_ovf;
  wire rd_ovf_dis = rt_ovf;

  // ==================================================================
  // ASSERTIONS
  // ==================================================================

  // ---- Reset (A2.1.2 p.27, A2.3 p.29) ----
  // SPEC: A2.3 p.29: AWVALID must be LOW during reset
  a_rst_awvalid_low: assert property (@(posedge aclk)
    !aresetn |-> !awvalid);

  // SPEC: A2.3 p.29: WVALID must be LOW during reset
  a_rst_wvalid_low: assert property (@(posedge aclk)
    !aresetn |-> !wvalid);

  // SPEC: A2.3 p.29: BVALID must be LOW during reset
  a_rst_bvalid_low: assert property (@(posedge aclk)
    !aresetn |-> !bvalid);

  // SPEC: A2.3 p.29: ARVALID must be LOW during reset
  a_rst_arvalid_low: assert property (@(posedge aclk)
    !aresetn |-> !arvalid);

  // SPEC: A2.3 p.29: RVALID must be LOW during reset
  a_rst_rvalid_low: assert property (@(posedge aclk)
    !aresetn |-> !rvalid);

  // SPEC: A2.1.2 p.27: AWVALID stays LOW until the ACLK edge after ARESETn goes HIGH
  a_rst_awvalid_exit: assert property (@(posedge aclk)
    (aresetn && !rst_q) |-> !awvalid);

  // SPEC: A2.1.2 p.27: WVALID stays LOW until the ACLK edge after ARESETn goes HIGH
  a_rst_wvalid_exit: assert property (@(posedge aclk)
    (aresetn && !rst_q) |-> !wvalid);

  // SPEC: A2.1.2 p.27: BVALID stays LOW until the ACLK edge after ARESETn goes HIGH
  a_rst_bvalid_exit: assert property (@(posedge aclk)
    (aresetn && !rst_q) |-> !bvalid);

  // SPEC: A2.1.2 p.27: ARVALID stays LOW until the ACLK edge after ARESETn goes HIGH
  a_rst_arvalid_exit: assert property (@(posedge aclk)
    (aresetn && !rst_q) |-> !arvalid);

  // SPEC: A2.1.2 p.27: RVALID stays LOW until the ACLK edge after ARESETn goes HIGH
  a_rst_rvalid_exit: assert property (@(posedge aclk)
    (aresetn && !rst_q) |-> !rvalid);

  // ---- Valid/Ready handshake (A2.3 p.29) ----
  // SPEC: A2.3 p.29: once AWVALID is asserted it must stay asserted until the handshake
  a_hs_awvalid_hold: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && !awready) |=> awvalid);

  // SPEC: A2.3 p.29: once WVALID is asserted it must stay asserted until the handshake
  a_hs_wvalid_hold: assert property (@(posedge aclk) disable iff (!aresetn)
    (wvalid && !wready) |=> wvalid);

  // SPEC: A2.3 p.29: once BVALID is asserted it must stay asserted until the handshake
  a_hs_bvalid_hold: assert property (@(posedge aclk) disable iff (!aresetn)
    (bvalid && !bready) |=> bvalid);

  // SPEC: A2.3 p.29: once ARVALID is asserted it must stay asserted until the handshake
  a_hs_arvalid_hold: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && !arready) |=> arvalid);

  // SPEC: A2.3 p.29: once RVALID is asserted it must stay asserted until the handshake
  a_hs_rvalid_hold: assert property (@(posedge aclk) disable iff (!aresetn)
    (rvalid && !rready) |=> rvalid);

  // SPEC: A2.3 p.29: AW information must stay stable while AWVALID is high and not yet accepted
  a_hs_aw_payload_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && !awready) |=> (!awvalid || ($stable(awid) && $stable(awaddr) && $stable(awlen) && $stable(awsize) && $stable(awburst) && $stable(awlock) && $stable(awcache) && $stable(awprot) && $stable(awqos) && $stable(awregion) && $stable(awuser))));

  // SPEC: A2.3 p.29: W information must stay stable while WVALID is high and not yet accepted
  a_hs_w_payload_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (wvalid && !wready) |=> (!wvalid || ($stable(wdata) && $stable(wstrb) && $stable(wlast) && $stable(wuser))));

  // SPEC: A2.3 p.29: B information must stay stable while BVALID is high and not yet accepted
  a_hs_b_payload_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (bvalid && !bready) |=> (!bvalid || ($stable(bid) && $stable(bresp) && $stable(buser))));

  // SPEC: A2.3 p.29: AR information must stay stable while ARVALID is high and not yet accepted
  a_hs_ar_payload_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && !arready) |=> (!arvalid || ($stable(arid) && $stable(araddr) && $stable(arlen) && $stable(arsize) && $stable(arburst) && $stable(arlock) && $stable(arcache) && $stable(arprot) && $stable(arqos) && $stable(arregion) && $stable(aruser))));

  // SPEC: A2.3 p.29: R information must stay stable while RVALID is high and not yet accepted
  a_hs_r_payload_stable: assert property (@(posedge aclk) disable iff (!aresetn)
    (rvalid && !rready) |=> (!rvalid || ($stable(rid) && $stable(rdata) && $stable(rresp) && $stable(rlast) && $stable(ruser))));

  // ---- Request attribute rules, AW and AR (A3.1, A4.2, A6.3.3) ----
  wire [15:0] aw_bytes = ({8'b0, awlen} + 16'd1) << awsize;
  wire [ADDR_W-1:0] aw_szmask = ({{(ADDR_W-1){1'b0}}, 1'b1} << awsize) - 1'b1;
  wire aw_wrap_unal = |(awaddr & aw_szmask);
  wire aw_excl_unal = |(awaddr_x[15:0] & (aw_bytes - 16'd1));
  wire aw_bytes_pow2 = ((aw_bytes & (aw_bytes - 16'd1)) == 16'd0);

  // SPEC: A3.1.1 p.43: AWSIZE must not exceed the data width of the interface
  a_aw_size_le_data_width: assert property (@(posedge aclk) disable iff (!aresetn)
    awvalid |-> (awsize <= 3'(MAXSZ)));

  // SPEC: A3.1.4 p.46: AWBURST 0b11 is reserved
  a_aw_burst_not_reserved: assert property (@(posedge aclk) disable iff (!aresetn)
    awvalid |-> (awburst != 2'b11));

  // SPEC: A3.1.4 p.47: WRAP burst Length must be 2, 4, 8 or 16
  a_aw_wrap_len: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && awburst == BURST_WRAP) |-> (awlen == 8'd1 || awlen == 8'd3 || awlen == 8'd7 || awlen == 8'd15));

  // SPEC: A3.1.4 p.47: WRAP burst start address must be aligned to the transfer size
  a_aw_wrap_aligned: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && awburst == BURST_WRAP) |-> !aw_wrap_unal);

  // SPEC: A3.1.2 p.44 / A3.1.4 p.47: FIXED burst Length is at most 16 transfers
  a_aw_fixed_len: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && awburst == BURST_FIXED) |-> (awlen <= 8'd15));

  // SPEC: A3.1 p.43: a transaction must not cross a 4KB address boundary
  a_aw_no_4kb_cross: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && awburst != 2'b11) |-> !f_cross4k(awaddr, awsize, awlen));

  // SPEC: A6.3.3 p.111: exclusive access Length must not exceed 16 transfers
  a_aw_excl_len: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && awlock) |-> (awlen <= 8'd15));

  // SPEC: A6.3.3 p.111: exclusive access total bytes must be a power of 2 and at most 128
  a_aw_excl_bytes: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && awlock) |-> (aw_bytes_pow2 && aw_bytes <= 16'd128));

  // SPEC: A6.3.3 p.111: exclusive access address must be aligned to the total transaction bytes
  a_aw_excl_aligned: assert property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && awlock && aw_bytes_pow2) |-> !aw_excl_unal);

  // SPEC: A4.3 p.71 Table A4.4: AWCACHE encodings not in the table are reserved
  a_aw_cache_not_reserved: assert property (@(posedge aclk) disable iff (!aresetn)
    awvalid |-> f_cache_ok(awcache));

  wire [15:0] ar_bytes = ({8'b0, arlen} + 16'd1) << arsize;
  wire [ADDR_W-1:0] ar_szmask = ({{(ADDR_W-1){1'b0}}, 1'b1} << arsize) - 1'b1;
  wire ar_wrap_unal = |(araddr & ar_szmask);
  wire ar_excl_unal = |(araddr_x[15:0] & (ar_bytes - 16'd1));
  wire ar_bytes_pow2 = ((ar_bytes & (ar_bytes - 16'd1)) == 16'd0);

  // SPEC: A3.1.1 p.43: ARSIZE must not exceed the data width of the interface
  a_ar_size_le_data_width: assert property (@(posedge aclk) disable iff (!aresetn)
    arvalid |-> (arsize <= 3'(MAXSZ)));

  // SPEC: A3.1.4 p.46: ARBURST 0b11 is reserved
  a_ar_burst_not_reserved: assert property (@(posedge aclk) disable iff (!aresetn)
    arvalid |-> (arburst != 2'b11));

  // SPEC: A3.1.4 p.47: WRAP burst Length must be 2, 4, 8 or 16
  a_ar_wrap_len: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && arburst == BURST_WRAP) |-> (arlen == 8'd1 || arlen == 8'd3 || arlen == 8'd7 || arlen == 8'd15));

  // SPEC: A3.1.4 p.47: WRAP burst start address must be aligned to the transfer size
  a_ar_wrap_aligned: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && arburst == BURST_WRAP) |-> !ar_wrap_unal);

  // SPEC: A3.1.2 p.44 / A3.1.4 p.47: FIXED burst Length is at most 16 transfers
  a_ar_fixed_len: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && arburst == BURST_FIXED) |-> (arlen <= 8'd15));

  // SPEC: A3.1 p.43: a transaction must not cross a 4KB address boundary
  a_ar_no_4kb_cross: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && arburst != 2'b11) |-> !f_cross4k(araddr, arsize, arlen));

  // SPEC: A6.3.3 p.111: exclusive access Length must not exceed 16 transfers
  a_ar_excl_len: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && arlock) |-> (arlen <= 8'd15));

  // SPEC: A6.3.3 p.111: exclusive access total bytes must be a power of 2 and at most 128
  a_ar_excl_bytes: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && arlock) |-> (ar_bytes_pow2 && ar_bytes <= 16'd128));

  // SPEC: A6.3.3 p.111: exclusive access address must be aligned to the total transaction bytes
  a_ar_excl_aligned: assert property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && arlock && ar_bytes_pow2) |-> !ar_excl_unal);

  // SPEC: A4.3 p.71 Table A4.4: ARCACHE encodings not in the table are reserved
  a_ar_cache_not_reserved: assert property (@(posedge aclk) disable iff (!aresetn)
    arvalid |-> f_cache_ok(arcache));

  // SPEC: A4.7.2 p.84: AxREGION must remain constant within a 4KB address space (AW)
  a_awregion_const_in_4kb: assert property (@(posedge aclk) disable iff (!aresetn)
    awvalid |-> !aw_reg_conf);

  // SPEC: A4.7.2 p.84: AxREGION must remain constant within a 4KB address space (AR)
  a_arregion_const_in_4kb: assert property (@(posedge aclk) disable iff (!aresetn)
    arvalid |-> !ar_reg_conf);

  // ---- Write data channel (A2.3.2.1 p.31, A3.1.2 p.44, A3.2.1 p.53-54, A5.5 p.100) ----
  // SPEC: A3.2.1 p.53: WLAST must be asserted on the final write transfer (AWLEN+1 beats)
  a_w_last_on_final_beat: assert property (@(posedge aclk) disable iff (!aresetn || wr_ovf_dis)
    (wvalid && w_known && w_is_final) |-> wlast);

  // SPEC: A3.1.2 p.44: a Manager must issue exactly AWLEN+1 write transfers; WLAST only on the last
  a_w_no_early_last: assert property (@(posedge aclk) disable iff (!aresetn || wr_ovf_dis)
    (wvalid && w_known && !w_is_final) |-> !wlast);

  // SPEC: A3.1.2 p.44: write data issued before its AW must still contain exactly AWLEN+1 beats
  a_w_first_len_match: assert property (@(posedge aclk) disable iff (!aresetn || wr_ovf_dis)
    !aw_wfirst_bad);

  // SPEC: A3.2.1.1 p.54 / A3.1.1 p.43: WSTRB must be LOW for byte lanes outside the active lanes of the transfer
  a_w_strb_within_lanes: assert property (@(posedge aclk) disable iff (!aresetn || wr_ovf_dis)
    (wvalid && w_known) |-> ((wstrb & ~w_lmask) == '0));

  // ---- Write response channel (A2.3.2.1 p.31, A3.3.1 p.61, A5.5 p.100, A6.3 p.112) ----
  // SPEC: A5.5 p.100: BID must match the AWID of an outstanding write; BVALID only after AW accepted (A2.3.2.1 p.31)
  a_b_id_matches_outstanding_aw: assert property (@(posedge aclk) disable iff (!aresetn || wr_ovf_dis)
    bvalid |-> b_found);

  // SPEC: A2.3.2.1 p.31 / A2.6 p.41 / A5.3.4 p.95: BVALID only after AW and last W accepted, and per-ID responses in request order
  a_b_after_last_w_and_in_order: assert property (@(posedge aclk) disable iff (!aresetn || wr_ovf_dis)
    (bvalid && b_found) |-> b_complete);

  // SPEC: A3.3.1 p.62: EXOKAY on BRESP is only permitted for an exclusive write
  a_b_exokay_only_exclusive: assert property (@(posedge aclk) disable iff (!aresetn || wr_ovf_dis)
    (bvalid && bresp == RESP_EXOKAY && b_found) |-> b_lock);

  // SPEC: A6.3.4 p.112: EXOKAY write requires an earlier exclusive read with the same ID
  a_b_exokay_needs_excl_read: assert property (@(posedge aclk) disable iff (!aresetn)
    (bvalid && bresp == RESP_EXOKAY) |-> xr_seen[bid[XR_IDW-1:0]]);

  // ---- Read data channel (A2.3.2.2 p.32, A3.2.2 p.55, A3.3.2 p.63, A5.6 p.101, A6.3.4 p.112) ----
  // SPEC: A5.6 p.101: RID must match the ARID of an outstanding read; RVALID only after AR accepted (A2.3.2.2 p.32)
  a_r_id_matches_outstanding_ar: assert property (@(posedge aclk) disable iff (!aresetn || rd_ovf_dis)
    rvalid |-> r_found);

  // SPEC: A3.2.2 p.55: RLAST must be asserted on the final read transfer (ARLEN+1 beats)
  a_r_last_on_final_beat: assert property (@(posedge aclk) disable iff (!aresetn || rd_ovf_dis)
    (rvalid && r_found && r_last_now) |-> rlast);

  // SPEC: A3.1.2 p.44: a Subordinate must issue exactly ARLEN+1 read transfers; RLAST only on the last
  a_r_no_early_last: assert property (@(posedge aclk) disable iff (!aresetn || rd_ovf_dis)
    (rvalid && r_found && !r_last_now) |-> !rlast);

  // SPEC: A3.3.2 p.63: EXOKAY on RRESP is only permitted for an exclusive read
  a_r_exokay_only_exclusive: assert property (@(posedge aclk) disable iff (!aresetn || rd_ovf_dis)
    (rvalid && rresp == RESP_EXOKAY && r_found) |-> r_lock);

  // SPEC: A6.3.4 p.112: an exclusive read must not mix OKAY and EXOKAY responses
  a_r_excl_no_okay_exokay_mix: assert property (@(posedge aclk) disable iff (!aresetn || rd_ovf_dis)
    (rvalid && r_found) |-> !r_mix);

  // ==================================================================
  // FUNCTIONAL COVERAGE
  // ==================================================================

  // ---- Channel activity and flow control (A2.3 p.29-30) ----
  // SPEC: A2.3 p.29: a transfer occurs when VALID and READY are both high on AW
  c_aw_handshake: cover property (@(posedge aclk) disable iff (!aresetn)
    awvalid && awready);

  // SPEC: A2.3 p.29 Fig A2.2: VALID asserted before READY (backpressure) on AW
  c_aw_valid_before_ready: cover property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && !awready) ##1 (awvalid && awready));

  // SPEC: A2.3 p.29 Fig A2.3: READY high before VALID on AW
  c_aw_ready_before_valid: cover property (@(posedge aclk) disable iff (!aresetn)
    (awready && !awvalid) ##1 (awvalid && awready));

  // SPEC: A2.3 p.30 Fig A2.4: VALID and READY asserted together on AW
  c_aw_same_cycle: cover property (@(posedge aclk) disable iff (!aresetn)
    $rose(awvalid) && awready);

  // SPEC: A2.3 p.29: consecutive-cycle transfers on AW
  c_aw_back_to_back: cover property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && awready) ##1 (awvalid && awready));

  // SPEC: A2.3 p.29: VALID held for 3+ cycles before READY on AW
  c_aw_long_stall: cover property (@(posedge aclk) disable iff (!aresetn)
    (awvalid && !awready) ##1 (awvalid && !awready) ##1 (awvalid && !awready) ##1 (awvalid && awready));

  // SPEC: A2.3 p.29: a transfer occurs when VALID and READY are both high on W
  c_w_handshake: cover property (@(posedge aclk) disable iff (!aresetn)
    wvalid && wready);

  // SPEC: A2.3 p.29 Fig A2.2: VALID asserted before READY (backpressure) on W
  c_w_valid_before_ready: cover property (@(posedge aclk) disable iff (!aresetn)
    (wvalid && !wready) ##1 (wvalid && wready));

  // SPEC: A2.3 p.29 Fig A2.3: READY high before VALID on W
  c_w_ready_before_valid: cover property (@(posedge aclk) disable iff (!aresetn)
    (wready && !wvalid) ##1 (wvalid && wready));

  // SPEC: A2.3 p.30 Fig A2.4: VALID and READY asserted together on W
  c_w_same_cycle: cover property (@(posedge aclk) disable iff (!aresetn)
    $rose(wvalid) && wready);

  // SPEC: A2.3 p.29: consecutive-cycle transfers on W
  c_w_back_to_back: cover property (@(posedge aclk) disable iff (!aresetn)
    (wvalid && wready) ##1 (wvalid && wready));

  // SPEC: A2.3 p.29: VALID held for 3+ cycles before READY on W
  c_w_long_stall: cover property (@(posedge aclk) disable iff (!aresetn)
    (wvalid && !wready) ##1 (wvalid && !wready) ##1 (wvalid && !wready) ##1 (wvalid && wready));

  // SPEC: A2.3 p.29: a transfer occurs when VALID and READY are both high on B
  c_b_handshake: cover property (@(posedge aclk) disable iff (!aresetn)
    bvalid && bready);

  // SPEC: A2.3 p.29 Fig A2.2: VALID asserted before READY (backpressure) on B
  c_b_valid_before_ready: cover property (@(posedge aclk) disable iff (!aresetn)
    (bvalid && !bready) ##1 (bvalid && bready));

  // SPEC: A2.3 p.29 Fig A2.3: READY high before VALID on B
  c_b_ready_before_valid: cover property (@(posedge aclk) disable iff (!aresetn)
    (bready && !bvalid) ##1 (bvalid && bready));

  // SPEC: A2.3 p.30 Fig A2.4: VALID and READY asserted together on B
  c_b_same_cycle: cover property (@(posedge aclk) disable iff (!aresetn)
    $rose(bvalid) && bready);

  // SPEC: A2.3 p.29: consecutive-cycle transfers on B
  c_b_back_to_back: cover property (@(posedge aclk) disable iff (!aresetn)
    (bvalid && bready) ##1 (bvalid && bready));

  // SPEC: A2.3 p.29: VALID held for 3+ cycles before READY on B
  c_b_long_stall: cover property (@(posedge aclk) disable iff (!aresetn)
    (bvalid && !bready) ##1 (bvalid && !bready) ##1 (bvalid && !bready) ##1 (bvalid && bready));

  // SPEC: A2.3 p.29: a transfer occurs when VALID and READY are both high on AR
  c_ar_handshake: cover property (@(posedge aclk) disable iff (!aresetn)
    arvalid && arready);

  // SPEC: A2.3 p.29 Fig A2.2: VALID asserted before READY (backpressure) on AR
  c_ar_valid_before_ready: cover property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && !arready) ##1 (arvalid && arready));

  // SPEC: A2.3 p.29 Fig A2.3: READY high before VALID on AR
  c_ar_ready_before_valid: cover property (@(posedge aclk) disable iff (!aresetn)
    (arready && !arvalid) ##1 (arvalid && arready));

  // SPEC: A2.3 p.30 Fig A2.4: VALID and READY asserted together on AR
  c_ar_same_cycle: cover property (@(posedge aclk) disable iff (!aresetn)
    $rose(arvalid) && arready);

  // SPEC: A2.3 p.29: consecutive-cycle transfers on AR
  c_ar_back_to_back: cover property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && arready) ##1 (arvalid && arready));

  // SPEC: A2.3 p.29: VALID held for 3+ cycles before READY on AR
  c_ar_long_stall: cover property (@(posedge aclk) disable iff (!aresetn)
    (arvalid && !arready) ##1 (arvalid && !arready) ##1 (arvalid && !arready) ##1 (arvalid && arready));

  // SPEC: A2.3 p.29: a transfer occurs when VALID and READY are both high on R
  c_r_handshake: cover property (@(posedge aclk) disable iff (!aresetn)
    rvalid && rready);

  // SPEC: A2.3 p.29 Fig A2.2: VALID asserted before READY (backpressure) on R
  c_r_valid_before_ready: cover property (@(posedge aclk) disable iff (!aresetn)
    (rvalid && !rready) ##1 (rvalid && rready));

  // SPEC: A2.3 p.29 Fig A2.3: READY high before VALID on R
  c_r_ready_before_valid: cover property (@(posedge aclk) disable iff (!aresetn)
    (rready && !rvalid) ##1 (rvalid && rready));

  // SPEC: A2.3 p.30 Fig A2.4: VALID and READY asserted together on R
  c_r_same_cycle: cover property (@(posedge aclk) disable iff (!aresetn)
    $rose(rvalid) && rready);

  // SPEC: A2.3 p.29: consecutive-cycle transfers on R
  c_r_back_to_back: cover property (@(posedge aclk) disable iff (!aresetn)
    (rvalid && rready) ##1 (rvalid && rready));

  // SPEC: A2.3 p.29: VALID held for 3+ cycles before READY on R
  c_r_long_stall: cover property (@(posedge aclk) disable iff (!aresetn)
    (rvalid && !rready) ##1 (rvalid && !rready) ##1 (rvalid && !rready) ##1 (rvalid && rready));

  // ---- Request attributes, AW and AR (A3.1, A4.2, A4.5, A4.7, A4.8) ----
  // SPEC: A3.1.4 p.46: FIXED burst on AW
  c_aw_burst_fixed: cover property (@(posedge aclk) disable iff (!aresetn)
    awvalid && awready && awburst == BURST_FIXED);

  // SPEC: A3.1.4 p.46: INCR burst on AW
  c_aw_burst_incr: cover property (@(posedge aclk) disable iff (!aresetn)
    awvalid && awready && awburst == BURST_INCR);

  // SPEC: A3.1.4 p.47: WRAP burst on AW
  c_aw_burst_wrap: cover property (@(posedge aclk) disable iff (!aresetn)
    awvalid && awready && awburst == BURST_WRAP);

  // SPEC: A3.1.2 p.44: single-beat transaction on AW
  c_aw_len_1beat: cover property (@(posedge aclk) disable iff (!aresetn)
    awvalid && awready && awlen == 8'd0);

  // SPEC: A3.1.2 p.44: 2 to 16 beat transaction on AW
  c_aw_len_2to16: cover property (@(posedge aclk) disable iff (!aresetn)
    awvalid && awready && awlen >= 8'd1 && awlen <= 8'd15);

  // SPEC: A3.1.2 p.44: 16 beat transaction on AW
  c_aw_len_16: cover property (@(posedge aclk) disable iff (!aresetn)
    awvalid && awready && awlen == 8'd15);

  // SPEC: A3.1.2 p.44: 17 to 255 beat INCR transaction on AW
  c_aw_len_17to255: cover property (@(posedge aclk) disable iff (!aresetn)
    awvalid && awready && awburst == BURST_INCR && awlen > 8'd15 && awlen < 8'd255);

  // SPEC: A3.1.2 p.44: 256 beat INCR transaction on AW
  c_aw_len_256: cover property (@(posedge aclk) disable iff (!aresetn)
    awvalid && awready && awburst == BURST_INCR && awlen == 8'd255);

  // SPEC: A3.1.4 p.47: WRAP burst of 2 beats on AW
  c_aw_wrap_len2: cover property (@(posedge aclk) disable iff (!aresetn)
    awvalid && awready && awburst == BURST_WRAP && awlen == 8'd1);

  // SPEC: A3.1.4 p.47: WRAP burst of 4 beats on AW
  c_aw_wrap_len4: cover property (@(posedge aclk) disable iff (!aresetn)
    awvalid && awready && awburst == BURST_WRAP && awlen == 8'd3);

  // SPEC: A3.1.4 p.47: WRAP burst of 8 beats on AW
  c_aw_wrap_len8: cover property (@(posedge aclk) disable iff (!aresetn)
    awvalid && awready && awburst == BURST_WRAP && awlen == 8'd7);

  // SPEC: A3.1.4 p.47: WRAP burst of 16 beats on AW
  c_aw_wrap_len16: cover property (@(posedge aclk) disable iff (!aresetn)
    awvalid && awready && awburst == BURST_WRAP && awlen == 8'd15);

  // SPEC: A3.1.4 p.47: WRAP burst whose start is above the wrap boundary (address wraps) on AW
  c_aw_wrap_nonzero_offset: cover property (@(posedge aclk) disable iff (!aresetn)
    awvalid && awready && awburst == BURST_WRAP && (awaddr & ((({{(ADDR_W-1){1'b0}}, 1'b1} << awsize) * ({{(ADDR_W-8){1'b0}}, awlen} + 1'b1)) - 1'b1)) != '0);

  // SPEC: A3.2.3 p.55: narrow transfer (size below data width) on AW
  c_aw_narrow: cover property (@(posedge aclk) disable iff (!aresetn)
    awvalid && awready && (awsize < 3'(MAXSZ)));

  // SPEC: A3.1.1 p.43: full data-width transfer on AW
  c_aw_full_width: cover property (@(posedge aclk) disable iff (!aresetn)
    awvalid && awready && (awsize == 3'(MAXSZ)));

  // SPEC: A3.2.5 p.58: INCR start address not aligned to size on AW
  c_aw_unaligned_start: cover property (@(posedge aclk) disable iff (!aresetn)
    awvalid && awready && awburst == BURST_INCR && |(awaddr & aw_szmask));

  // SPEC: A3.1 p.43: INCR transaction whose last byte is the last byte of a 4KB page on AW
  c_aw_ends_at_4kb_top: cover property (@(posedge aclk) disable iff (!aresetn)
    awvalid && awready && awburst == BURST_INCR && f_last_off(awaddr, awsize, awlen) == 12'hFFF);

  // SPEC: A6.3 p.110: exclusive access request on AW
  c_aw_excl: cover property (@(posedge aclk) disable iff (!aresetn)
    awvalid && awready && awlock);

  // SPEC: A6.3.3 p.111: multi-beat exclusive access on AW
  c_aw_excl_multi_beat: cover property (@(posedge aclk) disable iff (!aresetn)
    awvalid && awready && awlock && awlen != 8'd0);

  // SPEC: A6.3 p.110: non-exclusive request on AW
  c_aw_normal_lock0: cover property (@(posedge aclk) disable iff (!aresetn)
    awvalid && awready && !awlock);

  // SPEC: A4.7.1 p.84: non-zero AWREGION
  c_aw_region_nonzero: cover property (@(posedge aclk) disable iff (!aresetn)
    awvalid && awready && awregion != 4'd0);

  // SPEC: A4.8.1 p.86: non-zero AWQOS
  c_aw_qos_nonzero: cover property (@(posedge aclk) disable iff (!aresetn)
    awvalid && awready && awqos != 4'd0);

  // SPEC: A3.1 p.43: non-zero AWUSER
  c_aw_user_nonzero: cover property (@(posedge aclk) disable iff (!aresetn)
    awvalid && awready && |awuser);

  // SPEC: A5.1.1 p.90: non-zero AWID
  c_aw_id_nonzero: cover property (@(posedge aclk) disable iff (!aresetn)
    awvalid && awready && |awid);

  // SPEC: A5.3 p.93: new AW request with an ID that already has a transaction outstanding
  c_aw_same_id_outstanding: cover property (@(posedge aclk) disable iff (!aresetn)
    awvalid && awready && aw_same_id);

  for (genvar s = 0; s <= MAXSZ; s++) begin : g_aw_size
    // SPEC: A3.1.1 p.43 Table A3.2: every legal AWSIZE encoding used
    c_aw_size: cover property (@(posedge aclk) disable iff (!aresetn)
      awvalid && awready && awsize == 3'(s));
  end

  for (genvar c = 0; c < 16; c++) begin : g_aw_cache
    if (c[1] || !(c[3] || c[2])) begin : g_legal
      // SPEC: A4.3 p.71 Table A4.4: each non-reserved AWCACHE memory type
      c_aw_cache: cover property (@(posedge aclk) disable iff (!aresetn)
        awvalid && awready && awcache == 4'(c));
    end
  end

  for (genvar q = 0; q < 8; q++) begin : g_aw_prot
    // SPEC: A4.5.1 p.77: each AWPROT value
    c_aw_prot: cover property (@(posedge aclk) disable iff (!aresetn)
      awvalid && awready && awprot == 3'(q));
  end

  // SPEC: A3.1.4 p.46: FIXED burst on AR
  c_ar_burst_fixed: cover property (@(posedge aclk) disable iff (!aresetn)
    arvalid && arready && arburst == BURST_FIXED);

  // SPEC: A3.1.4 p.46: INCR burst on AR
  c_ar_burst_incr: cover property (@(posedge aclk) disable iff (!aresetn)
    arvalid && arready && arburst == BURST_INCR);

  // SPEC: A3.1.4 p.47: WRAP burst on AR
  c_ar_burst_wrap: cover property (@(posedge aclk) disable iff (!aresetn)
    arvalid && arready && arburst == BURST_WRAP);

  // SPEC: A3.1.2 p.44: single-beat transaction on AR
  c_ar_len_1beat: cover property (@(posedge aclk) disable iff (!aresetn)
    arvalid && arready && arlen == 8'd0);

  // SPEC: A3.1.2 p.44: 2 to 16 beat transaction on AR
  c_ar_len_2to16: cover property (@(posedge aclk) disable iff (!aresetn)
    arvalid && arready && arlen >= 8'd1 && arlen <= 8'd15);

  // SPEC: A3.1.2 p.44: 16 beat transaction on AR
  c_ar_len_16: cover property (@(posedge aclk) disable iff (!aresetn)
    arvalid && arready && arlen == 8'd15);

  // SPEC: A3.1.2 p.44: 17 to 255 beat INCR transaction on AR
  c_ar_len_17to255: cover property (@(posedge aclk) disable iff (!aresetn)
    arvalid && arready && arburst == BURST_INCR && arlen > 8'd15 && arlen < 8'd255);

  // SPEC: A3.1.2 p.44: 256 beat INCR transaction on AR
  c_ar_len_256: cover property (@(posedge aclk) disable iff (!aresetn)
    arvalid && arready && arburst == BURST_INCR && arlen == 8'd255);

  // SPEC: A3.1.4 p.47: WRAP burst of 2 beats on AR
  c_ar_wrap_len2: cover property (@(posedge aclk) disable iff (!aresetn)
    arvalid && arready && arburst == BURST_WRAP && arlen == 8'd1);

  // SPEC: A3.1.4 p.47: WRAP burst of 4 beats on AR
  c_ar_wrap_len4: cover property (@(posedge aclk) disable iff (!aresetn)
    arvalid && arready && arburst == BURST_WRAP && arlen == 8'd3);

  // SPEC: A3.1.4 p.47: WRAP burst of 8 beats on AR
  c_ar_wrap_len8: cover property (@(posedge aclk) disable iff (!aresetn)
    arvalid && arready && arburst == BURST_WRAP && arlen == 8'd7);

  // SPEC: A3.1.4 p.47: WRAP burst of 16 beats on AR
  c_ar_wrap_len16: cover property (@(posedge aclk) disable iff (!aresetn)
    arvalid && arready && arburst == BURST_WRAP && arlen == 8'd15);

  // SPEC: A3.1.4 p.47: WRAP burst whose start is above the wrap boundary (address wraps) on AR
  c_ar_wrap_nonzero_offset: cover property (@(posedge aclk) disable iff (!aresetn)
    arvalid && arready && arburst == BURST_WRAP && (araddr & ((({{(ADDR_W-1){1'b0}}, 1'b1} << arsize) * ({{(ADDR_W-8){1'b0}}, arlen} + 1'b1)) - 1'b1)) != '0);

  // SPEC: A3.2.3 p.55: narrow transfer (size below data width) on AR
  c_ar_narrow: cover property (@(posedge aclk) disable iff (!aresetn)
    arvalid && arready && (arsize < 3'(MAXSZ)));

  // SPEC: A3.1.1 p.43: full data-width transfer on AR
  c_ar_full_width: cover property (@(posedge aclk) disable iff (!aresetn)
    arvalid && arready && (arsize == 3'(MAXSZ)));

  // SPEC: A3.2.5 p.58: INCR start address not aligned to size on AR
  c_ar_unaligned_start: cover property (@(posedge aclk) disable iff (!aresetn)
    arvalid && arready && arburst == BURST_INCR && |(araddr & ar_szmask));

  // SPEC: A3.1 p.43: INCR transaction whose last byte is the last byte of a 4KB page on AR
  c_ar_ends_at_4kb_top: cover property (@(posedge aclk) disable iff (!aresetn)
    arvalid && arready && arburst == BURST_INCR && f_last_off(araddr, arsize, arlen) == 12'hFFF);

  // SPEC: A6.3 p.110: exclusive access request on AR
  c_ar_excl: cover property (@(posedge aclk) disable iff (!aresetn)
    arvalid && arready && arlock);

  // SPEC: A6.3.3 p.111: multi-beat exclusive access on AR
  c_ar_excl_multi_beat: cover property (@(posedge aclk) disable iff (!aresetn)
    arvalid && arready && arlock && arlen != 8'd0);

  // SPEC: A6.3 p.110: non-exclusive request on AR
  c_ar_normal_lock0: cover property (@(posedge aclk) disable iff (!aresetn)
    arvalid && arready && !arlock);

  // SPEC: A4.7.1 p.84: non-zero ARREGION
  c_ar_region_nonzero: cover property (@(posedge aclk) disable iff (!aresetn)
    arvalid && arready && arregion != 4'd0);

  // SPEC: A4.8.1 p.86: non-zero ARQOS
  c_ar_qos_nonzero: cover property (@(posedge aclk) disable iff (!aresetn)
    arvalid && arready && arqos != 4'd0);

  // SPEC: A3.1 p.43: non-zero ARUSER
  c_ar_user_nonzero: cover property (@(posedge aclk) disable iff (!aresetn)
    arvalid && arready && |aruser);

  // SPEC: A5.1.1 p.90: non-zero ARID
  c_ar_id_nonzero: cover property (@(posedge aclk) disable iff (!aresetn)
    arvalid && arready && |arid);

  // SPEC: A5.3 p.93: new AR request with an ID that already has a transaction outstanding
  c_ar_same_id_outstanding: cover property (@(posedge aclk) disable iff (!aresetn)
    arvalid && arready && ar_same_id);

  for (genvar s = 0; s <= MAXSZ; s++) begin : g_ar_size
    // SPEC: A3.1.1 p.43 Table A3.2: every legal ARSIZE encoding used
    c_ar_size: cover property (@(posedge aclk) disable iff (!aresetn)
      arvalid && arready && arsize == 3'(s));
  end

  for (genvar c = 0; c < 16; c++) begin : g_ar_cache
    if (c[1] || !(c[3] || c[2])) begin : g_legal
      // SPEC: A4.3 p.71 Table A4.4: each non-reserved ARCACHE memory type
      c_ar_cache: cover property (@(posedge aclk) disable iff (!aresetn)
        arvalid && arready && arcache == 4'(c));
    end
  end

  for (genvar q = 0; q < 8; q++) begin : g_ar_prot
    // SPEC: A4.5.1 p.77: each ARPROT value
    c_ar_prot: cover property (@(posedge aclk) disable iff (!aresetn)
      arvalid && arready && arprot == 3'(q));
  end

  // ---- Write data (A3.2.1 p.53-54, A2.6 p.41) ----
  // SPEC: A3.2.1 p.53: WLAST beat accepted
  c_w_beat_last: cover property (@(posedge aclk) disable iff (!aresetn)
    w_hs && wlast);

  // SPEC: A3.2.1 p.53: non-last write beat accepted
  c_w_beat_nonlast: cover property (@(posedge aclk) disable iff (!aresetn)
    w_hs && !wlast);

  // SPEC: A3.2.1.1 p.54: all write strobes asserted
  c_w_strb_all_ones: cover property (@(posedge aclk) disable iff (!aresetn)
    w_hs && (&wstrb));

  // SPEC: A3.2.1.1 p.54: partial write strobes
  c_w_strb_partial: cover property (@(posedge aclk) disable iff (!aresetn)
    w_hs && (|wstrb) && !(&wstrb));

  // SPEC: A3.2.1.1 p.54: all write strobes LOW (no data written)
  c_w_strb_all_zero: cover property (@(posedge aclk) disable iff (!aresetn)
    w_hs && (wstrb == '0));

  // SPEC: A3.1.2 p.44: multi-beat write data burst completes
  c_w_multibeat_burst: cover property (@(posedge aclk) disable iff (!aresetn)
    (w_hs && !wlast) ##[1:$] w_end);

  // SPEC: A2.6 p.41: write data accepted before its write request
  c_w_before_aw: cover property (@(posedge aclk) disable iff (!aresetn)
    w_hs && !w_known);

  // SPEC: A2.6 p.41: write data in the same cycle as its write request
  c_w_same_cycle_as_aw: cover property (@(posedge aclk) disable iff (!aresetn)
    w_hs && w_known_new);

  // SPEC: A2.6 p.41: write data accepted after its write request
  c_w_after_aw: cover property (@(posedge aclk) disable iff (!aresetn)
    w_hs && w_known_reg);

  // SPEC: A3.2.1 p.53: non-zero WUSER
  c_w_user_nonzero: cover property (@(posedge aclk) disable iff (!aresetn)
    w_hs && |wuser);

  // ---- Responses (A3.3 p.61-63, A6.3 p.110-112) ----
  // SPEC: A3.3.1 p.62 Table A3.28: BRESP OKAY
  c_b_resp_okay: cover property (@(posedge aclk) disable iff (!aresetn)
    b_hs && bresp == RESP_OKAY);

  // SPEC: A3.3.2 p.63 Table A3.31: RRESP OKAY
  c_r_resp_okay: cover property (@(posedge aclk) disable iff (!aresetn)
    r_hs && rresp == RESP_OKAY);

  // SPEC: A3.3.1 p.62 Table A3.28: BRESP EXOKAY
  c_b_resp_exokay: cover property (@(posedge aclk) disable iff (!aresetn)
    b_hs && bresp == RESP_EXOKAY);

  // SPEC: A3.3.2 p.63 Table A3.31: RRESP EXOKAY
  c_r_resp_exokay: cover property (@(posedge aclk) disable iff (!aresetn)
    r_hs && rresp == RESP_EXOKAY);

  // SPEC: A3.3.1 p.62 Table A3.28: BRESP SLVERR
  c_b_resp_slverr: cover property (@(posedge aclk) disable iff (!aresetn)
    b_hs && bresp == RESP_SLVERR);

  // SPEC: A3.3.2 p.63 Table A3.31: RRESP SLVERR
  c_r_resp_slverr: cover property (@(posedge aclk) disable iff (!aresetn)
    r_hs && rresp == RESP_SLVERR);

  // SPEC: A3.3.1 p.62 Table A3.28: BRESP DECERR
  c_b_resp_decerr: cover property (@(posedge aclk) disable iff (!aresetn)
    b_hs && bresp == RESP_DECERR);

  // SPEC: A3.3.2 p.63 Table A3.31: RRESP DECERR
  c_r_resp_decerr: cover property (@(posedge aclk) disable iff (!aresetn)
    r_hs && rresp == RESP_DECERR);

  // SPEC: A6.3.4 p.112: exclusive write completes with EXOKAY
  c_b_excl_success: cover property (@(posedge aclk) disable iff (!aresetn)
    b_hs && b_found && b_lock && bresp == RESP_EXOKAY);

  // SPEC: A6.3.4 p.112: exclusive write fails with OKAY
  c_b_excl_fail: cover property (@(posedge aclk) disable iff (!aresetn)
    b_hs && b_found && b_lock && bresp == RESP_OKAY);

  // SPEC: A6.3.2 p.111: exclusive read succeeds with EXOKAY
  c_r_excl_success: cover property (@(posedge aclk) disable iff (!aresetn)
    r_hs && r_found && r_lock && rresp == RESP_EXOKAY);

  // SPEC: A6.3.2 p.111: exclusive read answered OKAY
  c_r_excl_unsupported: cover property (@(posedge aclk) disable iff (!aresetn)
    r_hs && r_found && r_lock && rresp == RESP_OKAY);

  // SPEC: A3.3.2 p.63: RRESP differs between beats of one transaction
  c_r_resp_mixed_in_burst: cover property (@(posedge aclk) disable iff (!aresetn)
    r_hs && r_found && !rt_ok[r_idx] && rt_beat[r_idx] != 16'd0 && rresp == RESP_OKAY);

  // SPEC: A3.2.2 p.55: RLAST beat accepted
  c_r_last_beat: cover property (@(posedge aclk) disable iff (!aresetn)
    r_hs && rlast);

  // SPEC: A3.2.2 p.55: non-zero RUSER
  c_r_user_nonzero: cover property (@(posedge aclk) disable iff (!aresetn)
    r_hs && |ruser);

  // SPEC: A3.3.1 p.61: non-zero BUSER
  c_b_user_nonzero: cover property (@(posedge aclk) disable iff (!aresetn)
    b_hs && |buser);

  // ---- Ordering and concurrency (A5.1 p.90, A5.3 p.93-95, A5.6 p.101) ----
  // SPEC: A5.1 p.90: two or more writes outstanding
  c_multi_outstanding_writes: cover property (@(posedge aclk) disable iff (!aresetn)
    wr_outst >= 2);

  // SPEC: A5.1 p.90: two or more reads outstanding
  c_multi_outstanding_reads: cover property (@(posedge aclk) disable iff (!aresetn)
    rd_outst >= 2);

  // SPEC: A5.1 p.90: eight or more reads outstanding
  c_many_outstanding_reads: cover property (@(posedge aclk) disable iff (!aresetn)
    rd_outst >= 8);

  // SPEC: A5.1 p.90: eight or more writes outstanding
  c_many_outstanding_writes: cover property (@(posedge aclk) disable iff (!aresetn)
    wr_outst >= 8);

  // SPEC: A5.6 p.101: read data of different IDs interleaved (previous burst not finished)
  c_read_data_interleave: cover property (@(posedge aclk) disable iff (!aresetn)
    r_hs && r_prev_open && rid != r_prev_id);

  // SPEC: A5.1 p.90: read completes out of order across different IDs
  c_read_ooo_completion: cover property (@(posedge aclk) disable iff (!aresetn)
    r_hs && rlast && r_ooo);

  // SPEC: A5.1 p.90: write response returned out of order across different IDs
  c_write_ooo_response: cover property (@(posedge aclk) disable iff (!aresetn)
    b_hs && b_ooo);

  // SPEC: A2.2 p.28: read and write transfers in the same cycle
  c_read_and_write_concurrent: cover property (@(posedge aclk) disable iff (!aresetn)
    r_hs && w_hs);

  // SPEC: A2.3.2.1 p.31: BVALID in the cycle after the last write data handshake
  c_b_immediately_after_last_w: cover property (@(posedge aclk) disable iff (!aresetn)
    w_end ##1 bvalid);

  // SPEC: A2.3.2.2 p.32: RVALID in the cycle after the read request handshake
  c_r_immediately_after_ar: cover property (@(posedge aclk) disable iff (!aresetn)
    ar_hs ##1 rvalid);

  // SPEC: A5.3 p.93: same-ID write outstanding at a new AW
  c_aw_same_id_outstanding_write: cover property (@(posedge aclk) disable iff (!aresetn)
    aw_hs && aw_same_id);

  // SPEC: A6.3.1 p.110: exclusive read completed then exclusive write on the same ID
  c_excl_read_then_write: cover property (@(posedge aclk) disable iff (!aresetn)
    (r_hs && rlast && r_lock) ##[1:$] (aw_hs && awlock));

  // ---- Reset (A2.1.2 p.27) ----
  // SPEC: A2.1.2 p.27: reset asserted while transfers are outstanding
  c_reset_mid_traffic: cover property (@(posedge aclk) disable iff (1'b0)
    !aresetn && rst_q && (wr_outst != 0 || rd_outst != 0));

  // SPEC: A2.1.2 p.27: exit from reset
  c_reset_exit: cover property (@(posedge aclk) disable iff (1'b0)
    aresetn && !rst_q);

endmodule
