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

  localparam int DATA_BYTES = DATA_W / 8;

  // ============================================================================
  // CLOCK AND RESET ASSERTIONS (A2.1)
  // ============================================================================

  // SPEC: A2.1.2 p.27: VALID signals must be LOW during reset
  VALID_low_during_reset: assert property (@(negedge aresetn) disable iff (aresetn) (
    !awvalid && !wvalid && !arvalid && !rready && !bready
  ));

  // ============================================================================
  // VALID-READY HANDSHAKE (A2.3)
  // ============================================================================

  // SPEC: A2.3 p.28-30: When VALID is asserted, it must remain asserted until handshake occurs
  AWVALID_stable: assert property (@(posedge aclk) disable iff (!aresetn) (
    (awvalid && !awready) |=> awvalid
  ));

  WVALID_stable: assert property (@(posedge aclk) disable iff (!aresetn) (
    (wvalid && !wready) |=> wvalid
  ));

  ARVALID_stable: assert property (@(posedge aclk) disable iff (!aresetn) (
    (arvalid && !arready) |=> arvalid
  ));

  // ============================================================================
  // WRITE TRANSACTION DEPENDENCIES (A2.3.2.1)
  // ============================================================================

  // Track write requests and data
  logic [ID_W-1:0] aw_id_latched;
  logic aw_handshake;
  logic [7:0] w_count;
  logic [7:0] expected_w_count;

  always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      aw_handshake <= 1'b0;
      w_count <= 8'h0;
      expected_w_count <= 8'h0;
    end else begin
      if (awvalid && awready) begin
        aw_handshake <= 1'b1;
        aw_id_latched <= awid;
        expected_w_count <= awlen;
        w_count <= 8'h0;
      end else if (wvalid && wready && aw_handshake) begin
        w_count <= w_count + 1;
        if (w_count == expected_w_count) begin
          aw_handshake <= 1'b0;
        end
      end
    end
  end

  // SPEC: A2.3.2.1 p.31: Subordinate must wait for last write data before asserting BVALID
  BVALID_after_WLAST: assert property (@(posedge aclk) disable iff (!aresetn) (
    (bvalid) |-> $past(wlast && wvalid && wready)
  ));

  // ============================================================================
  // READ TRANSACTION DEPENDENCIES (A2.3.2.2)
  // ============================================================================

  // Track read requests
  logic [ID_W-1:0] ar_id_latched;
  logic ar_handshake;
  logic [7:0] r_count;
  logic [7:0] expected_r_count;

  always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      ar_handshake <= 1'b0;
      r_count <= 8'h0;
      expected_r_count <= 8'h0;
    end else begin
      if (arvalid && arready) begin
        ar_handshake <= 1'b1;
        ar_id_latched <= arid;
        expected_r_count <= arlen;
        r_count <= 8'h0;
      end else if (rvalid && rready && ar_handshake) begin
        r_count <= r_count + 1;
        if (r_count == expected_r_count) begin
          ar_handshake <= 1'b0;
        end
      end
    end
  end

  // SPEC: A2.3.2.2 p.32: Subordinate must assert RLAST when driving final read transfer
  RLAST_on_last: assert property (@(posedge aclk) disable iff (!aresetn) (
    (rvalid && ar_handshake && r_count == expected_r_count) |-> rlast
  ));

  // ============================================================================
  // WRITE DATA CHANNEL (A3.2.1)
  // ============================================================================

  // Track write data transfers
  logic [7:0] w_beat_count;
  logic [7:0] w_expected_beats;
  logic w_tracking;

  always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      w_tracking <= 1'b0;
      w_beat_count <= 8'h0;
      w_expected_beats <= 8'h0;
    end else begin
      if (awvalid && awready) begin
        w_tracking <= 1'b1;
        w_expected_beats <= awlen;
        w_beat_count <= 8'h0;
      end else if (wvalid && wready && w_tracking) begin
        w_beat_count <= w_beat_count + 1;
        if (w_beat_count == w_expected_beats) begin
          w_tracking <= 1'b0;
        end
      end
    end
  end

  // SPEC: A3.2.1 p.53: Manager must assert WLAST with final write transfer
  WLAST_on_final: assert property (@(posedge aclk) disable iff (!aresetn) (
    (wvalid && w_tracking && w_beat_count == w_expected_beats) |-> wlast
  ));

  // ============================================================================
  // TRANSACTION CONSTRAINTS (A3.1)
  // ============================================================================

  // SPEC: A3.1.2 p.44: WRAP burst length must be 2, 4, 8, or 16
  WRAP_write_len: assert property (@(posedge aclk) disable iff (!aresetn) (
    (awvalid && awburst == 2'b10) |->
    (awlen == 8'h01 || awlen == 8'h03 || awlen == 8'h07 || awlen == 8'h0F)
  ));

  WRAP_read_len: assert property (@(posedge aclk) disable iff (!aresetn) (
    (arvalid && arburst == 2'b10) |->
    (arlen == 8'h01 || arlen == 8'h03 || arlen == 8'h07 || arlen == 8'h0F)
  ));

  // SPEC: A3.1.4 p.46: BURST type must not be RESERVED (0b11)
  BURST_not_reserved_write: assert property (@(posedge aclk) disable iff (!aresetn) (
    awvalid |-> (awburst != 2'b11)
  ));

  BURST_not_reserved_read: assert property (@(posedge aclk) disable iff (!aresetn) (
    arvalid |-> (arburst != 2'b11)
  ));

  // SPEC: A3.1.1 p.43: Size must not exceed data width
  AWSIZE_valid: assert property (@(posedge aclk) disable iff (!aresetn) (
    awvalid |-> (awsize <= 3'($clog2(DATA_BYTES)))
  ));

  ARSIZE_valid: assert property (@(posedge aclk) disable iff (!aresetn) (
    arvalid |-> (arsize <= 3'($clog2(DATA_BYTES)))
  ));

  // ============================================================================
  // RESPONSE COUNTERS
  // ============================================================================

  logic [31:0] write_txn_count;
  logic [31:0] write_resp_count;
  logic [31:0] expected_read_beats;
  logic [31:0] actual_read_beats;

  always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      write_txn_count <= 32'h0;
      write_resp_count <= 32'h0;
      expected_read_beats <= 32'h0;
      actual_read_beats <= 32'h0;
    end else begin
      if (awvalid && awready) write_txn_count <= write_txn_count + 1;
      if (bvalid && bready) write_resp_count <= write_resp_count + 1;
      if (arvalid && arready) expected_read_beats <= expected_read_beats + arlen + 1;
      if (rvalid && rready) actual_read_beats <= actual_read_beats + 1;
    end
  end

  // SPEC: A3.3.1 p.61: Each write transaction gets one completion response
  WRITE_resp_ordering: assert property (@(posedge aclk) disable iff (!aresetn) (
    (write_resp_count <= write_txn_count)
  ));

  // SPEC: A3.3.2 p.62: One read response per read data transfer
  READ_resp_ordering: assert property (@(posedge aclk) disable iff (!aresetn) (
    (actual_read_beats <= expected_read_beats)
  ));

  // ============================================================================
  // FUNCTIONAL COVERAGE
  // ============================================================================

  // Write burst types (A3.1.4)
  cvr_write_fixed: cover property (@(posedge aclk) disable iff (!aresetn) (
    awvalid && awburst == 2'b00
  ));

  cvr_write_incr: cover property (@(posedge aclk) disable iff (!aresetn) (
    awvalid && awburst == 2'b01
  ));

  cvr_write_wrap: cover property (@(posedge aclk) disable iff (!aresetn) (
    awvalid && awburst == 2'b10
  ));

  // Read burst types (A3.1.4)
  cvr_read_fixed: cover property (@(posedge aclk) disable iff (!aresetn) (
    arvalid && arburst == 2'b00
  ));

  cvr_read_incr: cover property (@(posedge aclk) disable iff (!aresetn) (
    arvalid && arburst == 2'b01
  ));

  cvr_read_wrap: cover property (@(posedge aclk) disable iff (!aresetn) (
    arvalid && arburst == 2'b10
  ));

  // Write sizes (A3.1.1)
  cvr_write_size_1b: cover property (@(posedge aclk) disable iff (!aresetn) (
    awvalid && awsize == 3'h0
  ));

  cvr_write_size_2b: cover property (@(posedge aclk) disable iff (!aresetn) (
    awvalid && awsize == 3'h1
  ));

  cvr_write_size_4b: cover property (@(posedge aclk) disable iff (!aresetn) (
    awvalid && awsize == 3'h2
  ));

  cvr_write_size_8b: cover property (@(posedge aclk) disable iff (!aresetn) (
    awvalid && awsize == 3'h3
  ));

  // Read sizes (A3.1.1)
  cvr_read_size_1b: cover property (@(posedge aclk) disable iff (!aresetn) (
    arvalid && arsize == 3'h0
  ));

  cvr_read_size_2b: cover property (@(posedge aclk) disable iff (!aresetn) (
    arvalid && arsize == 3'h1
  ));

  cvr_read_size_4b: cover property (@(posedge aclk) disable iff (!aresetn) (
    arvalid && arsize == 3'h2
  ));

  cvr_read_size_8b: cover property (@(posedge aclk) disable iff (!aresetn) (
    arvalid && arsize == 3'h3
  ));

  // Write response types (A3.3.1, Table A3.28)
  cvr_bresp_okay: cover property (@(posedge aclk) disable iff (!aresetn) (
    bvalid && bresp == 2'b00
  ));

  cvr_bresp_exokay: cover property (@(posedge aclk) disable iff (!aresetn) (
    bvalid && bresp == 2'b01
  ));

  cvr_bresp_slverr: cover property (@(posedge aclk) disable iff (!aresetn) (
    bvalid && bresp == 2'b10
  ));

  cvr_bresp_decerr: cover property (@(posedge aclk) disable iff (!aresetn) (
    bvalid && bresp == 2'b11
  ));

  // Read response types (A3.3.2, Table A3.31)
  cvr_rresp_okay: cover property (@(posedge aclk) disable iff (!aresetn) (
    rvalid && rresp == 2'b00
  ));

  cvr_rresp_exokay: cover property (@(posedge aclk) disable iff (!aresetn) (
    rvalid && rresp == 2'b01
  ));

  cvr_rresp_slverr: cover property (@(posedge aclk) disable iff (!aresetn) (
    rvalid && rresp == 2'b10
  ));

  cvr_rresp_decerr: cover property (@(posedge aclk) disable iff (!aresetn) (
    rvalid && rresp == 2'b11
  ));

  // Cache attributes (A4.2)
  cvr_write_cache_0: cover property (@(posedge aclk) disable iff (!aresetn) (
    awvalid && awcache == 4'b0000
  ));

  cvr_write_cache_1: cover property (@(posedge aclk) disable iff (!aresetn) (
    awvalid && awcache == 4'b0001
  ));

  cvr_write_cache_bufferable: cover property (@(posedge aclk) disable iff (!aresetn) (
    awvalid && awcache[0]
  ));

  cvr_write_cache_modifiable: cover property (@(posedge aclk) disable iff (!aresetn) (
    awvalid && awcache[1]
  ));

  cvr_read_cache_0: cover property (@(posedge aclk) disable iff (!aresetn) (
    arvalid && arcache == 4'b0000
  ));

  cvr_read_cache_1: cover property (@(posedge aclk) disable iff (!aresetn) (
    arvalid && arcache == 4'b0001
  ));

  cvr_read_cache_bufferable: cover property (@(posedge aclk) disable iff (!aresetn) (
    arvalid && arcache[0]
  ));

  cvr_read_cache_modifiable: cover property (@(posedge aclk) disable iff (!aresetn) (
    arvalid && arcache[1]
  ));

  // Exclusive accesses (LOCK)
  cvr_exclusive_write: cover property (@(posedge aclk) disable iff (!aresetn) (
    awvalid && awlock
  ));

  cvr_exclusive_read: cover property (@(posedge aclk) disable iff (!aresetn) (
    arvalid && arlock
  ));

  // Protection attributes (A4.5)
  cvr_write_prot_priv: cover property (@(posedge aclk) disable iff (!aresetn) (
    awvalid && awprot[0]
  ));

  cvr_write_prot_nonsec: cover property (@(posedge aclk) disable iff (!aresetn) (
    awvalid && awprot[1]
  ));

  cvr_write_prot_instr: cover property (@(posedge aclk) disable iff (!aresetn) (
    awvalid && awprot[2]
  ));

  cvr_read_prot_priv: cover property (@(posedge aclk) disable iff (!aresetn) (
    arvalid && arprot[0]
  ));

  cvr_read_prot_nonsec: cover property (@(posedge aclk) disable iff (!aresetn) (
    arvalid && arprot[1]
  ));

  cvr_read_prot_instr: cover property (@(posedge aclk) disable iff (!aresetn) (
    arvalid && arprot[2]
  ));

  // QoS (A4.8)
  cvr_write_qos_nonzero: cover property (@(posedge aclk) disable iff (!aresetn) (
    awvalid && awqos != 4'h0
  ));

  cvr_read_qos_nonzero: cover property (@(posedge aclk) disable iff (!aresetn) (
    arvalid && arqos != 4'h0
  ));

  // Handshakes
  cvr_aw_handshake: cover property (@(posedge aclk) disable iff (!aresetn) (
    awvalid && awready
  ));

  cvr_w_handshake: cover property (@(posedge aclk) disable iff (!aresetn) (
    wvalid && wready
  ));

  cvr_b_handshake: cover property (@(posedge aclk) disable iff (!aresetn) (
    bvalid && bready
  ));

  cvr_ar_handshake: cover property (@(posedge aclk) disable iff (!aresetn) (
    arvalid && arready
  ));

  cvr_r_handshake: cover property (@(posedge aclk) disable iff (!aresetn) (
    rvalid && rready
  ));

  // WLAST and RLAST
  cvr_wlast: cover property (@(posedge aclk) disable iff (!aresetn) (
    wvalid && wlast
  ));

  cvr_rlast: cover property (@(posedge aclk) disable iff (!aresetn) (
    rvalid && rlast
  ));

  // Write strobes patterns
  cvr_wstrb_all: cover property (@(posedge aclk) disable iff (!aresetn) (
    wvalid && (wstrb == {DATA_BYTES{1'b1}})
  ));

  cvr_wstrb_partial: cover property (@(posedge aclk) disable iff (!aresetn) (
    wvalid && (wstrb != {DATA_BYTES{1'b1}}) && (wstrb != '0)
  ));

  cvr_wstrb_none: cover property (@(posedge aclk) disable iff (!aresetn) (
    wvalid && (wstrb == '0)
  ));

endmodule
