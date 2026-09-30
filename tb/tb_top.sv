// Lab testbench: cocotb AXI manager -> interposer -> verilog-axi axi_ram.
// The checker set under qualification observes the interposer's obs_* bus.

module tb_top #(
  parameter int ID_W       = 8,
  parameter int ADDR_W     = 32,
  parameter int DATA_W     = 32,
  parameter int USER_W     = 1,
  parameter int RAM_ADDR_W = 16
) (
  input logic clk,
  input logic rst
);
  logic aresetn;
  assign aresetn = !rst;

  logic [ID_W-1:0] m_axi_awid;
  logic [ADDR_W-1:0] m_axi_awaddr;
  logic [8-1:0] m_axi_awlen;
  logic [3-1:0] m_axi_awsize;
  logic [2-1:0] m_axi_awburst;
  logic m_axi_awlock;
  logic [4-1:0] m_axi_awcache;
  logic [3-1:0] m_axi_awprot;
  logic [4-1:0] m_axi_awqos;
  logic [4-1:0] m_axi_awregion;
  logic [USER_W-1:0] m_axi_awuser;
  logic m_axi_awvalid;
  logic m_axi_awready;
  logic [DATA_W-1:0] m_axi_wdata;
  logic [DATA_W/8-1:0] m_axi_wstrb;
  logic m_axi_wlast;
  logic [USER_W-1:0] m_axi_wuser;
  logic m_axi_wvalid;
  logic m_axi_wready;
  logic [ID_W-1:0] m_axi_bid;
  logic [2-1:0] m_axi_bresp;
  logic [USER_W-1:0] m_axi_buser;
  logic m_axi_bvalid;
  logic m_axi_bready;
  logic [ID_W-1:0] m_axi_arid;
  logic [ADDR_W-1:0] m_axi_araddr;
  logic [8-1:0] m_axi_arlen;
  logic [3-1:0] m_axi_arsize;
  logic [2-1:0] m_axi_arburst;
  logic m_axi_arlock;
  logic [4-1:0] m_axi_arcache;
  logic [3-1:0] m_axi_arprot;
  logic [4-1:0] m_axi_arqos;
  logic [4-1:0] m_axi_arregion;
  logic [USER_W-1:0] m_axi_aruser;
  logic m_axi_arvalid;
  logic m_axi_arready;
  logic [ID_W-1:0] m_axi_rid;
  logic [DATA_W-1:0] m_axi_rdata;
  logic [2-1:0] m_axi_rresp;
  logic m_axi_rlast;
  logic [USER_W-1:0] m_axi_ruser;
  logic m_axi_rvalid;
  logic m_axi_rready;

  logic [ID_W-1:0] s_axi_awid;
  logic [ADDR_W-1:0] s_axi_awaddr;
  logic [8-1:0] s_axi_awlen;
  logic [3-1:0] s_axi_awsize;
  logic [2-1:0] s_axi_awburst;
  logic s_axi_awlock;
  logic [4-1:0] s_axi_awcache;
  logic [3-1:0] s_axi_awprot;
  logic [4-1:0] s_axi_awqos;
  logic [4-1:0] s_axi_awregion;
  logic [USER_W-1:0] s_axi_awuser;
  logic s_axi_awvalid;
  logic s_axi_awready;
  logic [DATA_W-1:0] s_axi_wdata;
  logic [DATA_W/8-1:0] s_axi_wstrb;
  logic s_axi_wlast;
  logic [USER_W-1:0] s_axi_wuser;
  logic s_axi_wvalid;
  logic s_axi_wready;
  logic [ID_W-1:0] s_axi_bid;
  logic [2-1:0] s_axi_bresp;
  logic [USER_W-1:0] s_axi_buser;
  logic s_axi_bvalid;
  logic s_axi_bready;
  logic [ID_W-1:0] s_axi_arid;
  logic [ADDR_W-1:0] s_axi_araddr;
  logic [8-1:0] s_axi_arlen;
  logic [3-1:0] s_axi_arsize;
  logic [2-1:0] s_axi_arburst;
  logic s_axi_arlock;
  logic [4-1:0] s_axi_arcache;
  logic [3-1:0] s_axi_arprot;
  logic [4-1:0] s_axi_arqos;
  logic [4-1:0] s_axi_arregion;
  logic [USER_W-1:0] s_axi_aruser;
  logic s_axi_arvalid;
  logic s_axi_arready;
  logic [ID_W-1:0] s_axi_rid;
  logic [DATA_W-1:0] s_axi_rdata;
  logic [2-1:0] s_axi_rresp;
  logic s_axi_rlast;
  logic [USER_W-1:0] s_axi_ruser;
  logic s_axi_rvalid;
  logic s_axi_rready;

  logic [ID_W-1:0] obs_awid;
  logic [ADDR_W-1:0] obs_awaddr;
  logic [8-1:0] obs_awlen;
  logic [3-1:0] obs_awsize;
  logic [2-1:0] obs_awburst;
  logic obs_awlock;
  logic [4-1:0] obs_awcache;
  logic [3-1:0] obs_awprot;
  logic [4-1:0] obs_awqos;
  logic [4-1:0] obs_awregion;
  logic [USER_W-1:0] obs_awuser;
  logic obs_awvalid;
  logic obs_awready;
  logic [DATA_W-1:0] obs_wdata;
  logic [DATA_W/8-1:0] obs_wstrb;
  logic obs_wlast;
  logic [USER_W-1:0] obs_wuser;
  logic obs_wvalid;
  logic obs_wready;
  logic [ID_W-1:0] obs_bid;
  logic [2-1:0] obs_bresp;
  logic [USER_W-1:0] obs_buser;
  logic obs_bvalid;
  logic obs_bready;
  logic [ID_W-1:0] obs_arid;
  logic [ADDR_W-1:0] obs_araddr;
  logic [8-1:0] obs_arlen;
  logic [3-1:0] obs_arsize;
  logic [2-1:0] obs_arburst;
  logic obs_arlock;
  logic [4-1:0] obs_arcache;
  logic [3-1:0] obs_arprot;
  logic [4-1:0] obs_arqos;
  logic [4-1:0] obs_arregion;
  logic [USER_W-1:0] obs_aruser;
  logic obs_arvalid;
  logic obs_arready;
  logic [ID_W-1:0] obs_rid;
  logic [DATA_W-1:0] obs_rdata;
  logic [2-1:0] obs_rresp;
  logic obs_rlast;
  logic [USER_W-1:0] obs_ruser;
  logic obs_rvalid;
  logic obs_rready;

  axi_mut_interposer #(.ID_W(ID_W), .ADDR_W(ADDR_W), .DATA_W(DATA_W), .USER_W(USER_W)) u_ip (
    .aclk(clk), .aresetn(aresetn),
    .m_awid(m_axi_awid), .s_awid(s_axi_awid), .obs_awid(obs_awid),
    .m_awaddr(m_axi_awaddr), .s_awaddr(s_axi_awaddr), .obs_awaddr(obs_awaddr),
    .m_awlen(m_axi_awlen), .s_awlen(s_axi_awlen), .obs_awlen(obs_awlen),
    .m_awsize(m_axi_awsize), .s_awsize(s_axi_awsize), .obs_awsize(obs_awsize),
    .m_awburst(m_axi_awburst), .s_awburst(s_axi_awburst), .obs_awburst(obs_awburst),
    .m_awlock(m_axi_awlock), .s_awlock(s_axi_awlock), .obs_awlock(obs_awlock),
    .m_awcache(m_axi_awcache), .s_awcache(s_axi_awcache), .obs_awcache(obs_awcache),
    .m_awprot(m_axi_awprot), .s_awprot(s_axi_awprot), .obs_awprot(obs_awprot),
    .m_awqos(m_axi_awqos), .s_awqos(s_axi_awqos), .obs_awqos(obs_awqos),
    .m_awregion(m_axi_awregion), .s_awregion(s_axi_awregion), .obs_awregion(obs_awregion),
    .m_awuser(m_axi_awuser), .s_awuser(s_axi_awuser), .obs_awuser(obs_awuser),
    .m_awvalid(m_axi_awvalid), .s_awvalid(s_axi_awvalid), .obs_awvalid(obs_awvalid),
    .m_awready(m_axi_awready), .s_awready(s_axi_awready), .obs_awready(obs_awready),
    .m_wdata(m_axi_wdata), .s_wdata(s_axi_wdata), .obs_wdata(obs_wdata),
    .m_wstrb(m_axi_wstrb), .s_wstrb(s_axi_wstrb), .obs_wstrb(obs_wstrb),
    .m_wlast(m_axi_wlast), .s_wlast(s_axi_wlast), .obs_wlast(obs_wlast),
    .m_wuser(m_axi_wuser), .s_wuser(s_axi_wuser), .obs_wuser(obs_wuser),
    .m_wvalid(m_axi_wvalid), .s_wvalid(s_axi_wvalid), .obs_wvalid(obs_wvalid),
    .m_wready(m_axi_wready), .s_wready(s_axi_wready), .obs_wready(obs_wready),
    .m_bid(m_axi_bid), .s_bid(s_axi_bid), .obs_bid(obs_bid),
    .m_bresp(m_axi_bresp), .s_bresp(s_axi_bresp), .obs_bresp(obs_bresp),
    .m_buser(m_axi_buser), .s_buser(s_axi_buser), .obs_buser(obs_buser),
    .m_bvalid(m_axi_bvalid), .s_bvalid(s_axi_bvalid), .obs_bvalid(obs_bvalid),
    .m_bready(m_axi_bready), .s_bready(s_axi_bready), .obs_bready(obs_bready),
    .m_arid(m_axi_arid), .s_arid(s_axi_arid), .obs_arid(obs_arid),
    .m_araddr(m_axi_araddr), .s_araddr(s_axi_araddr), .obs_araddr(obs_araddr),
    .m_arlen(m_axi_arlen), .s_arlen(s_axi_arlen), .obs_arlen(obs_arlen),
    .m_arsize(m_axi_arsize), .s_arsize(s_axi_arsize), .obs_arsize(obs_arsize),
    .m_arburst(m_axi_arburst), .s_arburst(s_axi_arburst), .obs_arburst(obs_arburst),
    .m_arlock(m_axi_arlock), .s_arlock(s_axi_arlock), .obs_arlock(obs_arlock),
    .m_arcache(m_axi_arcache), .s_arcache(s_axi_arcache), .obs_arcache(obs_arcache),
    .m_arprot(m_axi_arprot), .s_arprot(s_axi_arprot), .obs_arprot(obs_arprot),
    .m_arqos(m_axi_arqos), .s_arqos(s_axi_arqos), .obs_arqos(obs_arqos),
    .m_arregion(m_axi_arregion), .s_arregion(s_axi_arregion), .obs_arregion(obs_arregion),
    .m_aruser(m_axi_aruser), .s_aruser(s_axi_aruser), .obs_aruser(obs_aruser),
    .m_arvalid(m_axi_arvalid), .s_arvalid(s_axi_arvalid), .obs_arvalid(obs_arvalid),
    .m_arready(m_axi_arready), .s_arready(s_axi_arready), .obs_arready(obs_arready),
    .m_rid(m_axi_rid), .s_rid(s_axi_rid), .obs_rid(obs_rid),
    .m_rdata(m_axi_rdata), .s_rdata(s_axi_rdata), .obs_rdata(obs_rdata),
    .m_rresp(m_axi_rresp), .s_rresp(s_axi_rresp), .obs_rresp(obs_rresp),
    .m_rlast(m_axi_rlast), .s_rlast(s_axi_rlast), .obs_rlast(obs_rlast),
    .m_ruser(m_axi_ruser), .s_ruser(s_axi_ruser), .obs_ruser(obs_ruser),
    .m_rvalid(m_axi_rvalid), .s_rvalid(s_axi_rvalid), .obs_rvalid(obs_rvalid),
    .m_rready(m_axi_rready), .s_rready(s_axi_rready), .obs_rready(obs_rready)
  );

  // axi_ram has no QOS/REGION/USER; drive its unused responses' USER to zero.
  assign s_axi_buser = '0;
  assign s_axi_ruser = '0;

  axi_ram #(.DATA_WIDTH(DATA_W), .ADDR_WIDTH(RAM_ADDR_W), .ID_WIDTH(ID_W)) u_dut (
    .clk(clk), .rst(rst),
    .s_axi_awid(s_axi_awid),
    .s_axi_awaddr(s_axi_awaddr[RAM_ADDR_W-1:0]),
    .s_axi_awlen(s_axi_awlen),
    .s_axi_awsize(s_axi_awsize),
    .s_axi_awburst(s_axi_awburst),
    .s_axi_awlock(s_axi_awlock),
    .s_axi_awcache(s_axi_awcache),
    .s_axi_awprot(s_axi_awprot),
    .s_axi_awvalid(s_axi_awvalid),
    .s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata),
    .s_axi_wstrb(s_axi_wstrb),
    .s_axi_wlast(s_axi_wlast),
    .s_axi_wvalid(s_axi_wvalid),
    .s_axi_wready(s_axi_wready),
    .s_axi_bid(s_axi_bid),
    .s_axi_bresp(s_axi_bresp),
    .s_axi_bvalid(s_axi_bvalid),
    .s_axi_bready(s_axi_bready),
    .s_axi_arid(s_axi_arid),
    .s_axi_araddr(s_axi_araddr[RAM_ADDR_W-1:0]),
    .s_axi_arlen(s_axi_arlen),
    .s_axi_arsize(s_axi_arsize),
    .s_axi_arburst(s_axi_arburst),
    .s_axi_arlock(s_axi_arlock),
    .s_axi_arcache(s_axi_arcache),
    .s_axi_arprot(s_axi_arprot),
    .s_axi_arvalid(s_axi_arvalid),
    .s_axi_arready(s_axi_arready),
    .s_axi_rid(s_axi_rid),
    .s_axi_rdata(s_axi_rdata),
    .s_axi_rresp(s_axi_rresp),
    .s_axi_rlast(s_axi_rlast),
    .s_axi_rvalid(s_axi_rvalid),
    .s_axi_rready(s_axi_rready)
  );

  axi_checker_set #(.ID_W(ID_W), .ADDR_W(ADDR_W), .DATA_W(DATA_W), .USER_W(USER_W)) u_chk (
    .aclk(clk), .aresetn(aresetn),
    .awid(obs_awid),
    .awaddr(obs_awaddr),
    .awlen(obs_awlen),
    .awsize(obs_awsize),
    .awburst(obs_awburst),
    .awlock(obs_awlock),
    .awcache(obs_awcache),
    .awprot(obs_awprot),
    .awqos(obs_awqos),
    .awregion(obs_awregion),
    .awuser(obs_awuser),
    .awvalid(obs_awvalid),
    .awready(obs_awready),
    .wdata(obs_wdata),
    .wstrb(obs_wstrb),
    .wlast(obs_wlast),
    .wuser(obs_wuser),
    .wvalid(obs_wvalid),
    .wready(obs_wready),
    .bid(obs_bid),
    .bresp(obs_bresp),
    .buser(obs_buser),
    .bvalid(obs_bvalid),
    .bready(obs_bready),
    .arid(obs_arid),
    .araddr(obs_araddr),
    .arlen(obs_arlen),
    .arsize(obs_arsize),
    .arburst(obs_arburst),
    .arlock(obs_arlock),
    .arcache(obs_arcache),
    .arprot(obs_arprot),
    .arqos(obs_arqos),
    .arregion(obs_arregion),
    .aruser(obs_aruser),
    .arvalid(obs_arvalid),
    .arready(obs_arready),
    .rid(obs_rid),
    .rdata(obs_rdata),
    .rresp(obs_rresp),
    .rlast(obs_rlast),
    .ruser(obs_ruser),
    .rvalid(obs_rvalid),
    .rready(obs_rready)
  );
endmodule
