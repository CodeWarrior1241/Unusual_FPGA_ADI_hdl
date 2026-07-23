// ***************************************************************************
// AXI4 single-beat 1-to-3 address decoder / router for the MPF300 FMCOMMS2
// design. Fills the role of the Vivado SmartConnect (NUM_SI=1, NUM_MI=3) in
// the axau15 block design, with the same address map (which the ad9361_no-os
// software in deps/neorv32/sw/ad9361_no-os expects):
//
//   M0  0xC000_0000 .. 0xC000_7FFF   QPSK snapshot BRAM      (32 KB)
//   M1  0x44A0_0000 .. 0x44A0_FFFF   axi_ad9361 (AXI4-Lite)  (64 KB)
//   M2  0x44A1_0000 .. 0x44A1_3FFF   axi_lite_to_streaming_adapter (16 KB)
//
// The routing fabric is the PULP platform axi_lite_xbar (deps/axi,
// v0.39.10: addr_decode + axi_lite_demux + axi_lite_mux + DECERR error
// slave), configured 1 slave x 3 masters. The single AXI master is the
// NEORV32 xbus2axi4 bridge, which issues one outstanding single-beat
// transaction at a time (no caches are enabled), so the whole fabric is run
// as AXI4-Lite: this wrapper drops the AXI4 burst signals on the slave side
// (len/size/burst/last -- always single-beat) and reconstructs them on the
// master ports that want them. Non-decoded addresses get DECERR from the
// xbar's internal error slave.
//
// Port adaptation per master:
//   M1 is a true AXI4-Lite endpoint with a 16-bit address.
//   M0 (BRAM) takes the lite subset (no prot).
//   M2 (SmartHLS streaming adapter) takes the AXI4 subset the generated
//      core exposes: len/size/burst are tied to single-beat values, WLAST
//      is tied high and RLAST is consumed here (single-beat reads).
// ***************************************************************************

`include "axi/typedef.svh"

`timescale 1ns/100ps

module axi_1to3_decoder (

  input           aclk,
  input           aresetn,

  // slave port (from CPU bridge)

  input   [31:0]  s_awaddr,
  input   [ 7:0]  s_awlen,
  input   [ 2:0]  s_awsize,
  input   [ 1:0]  s_awburst,
  input   [ 2:0]  s_awprot,
  input           s_awvalid,
  output          s_awready,
  input   [31:0]  s_wdata,
  input   [ 3:0]  s_wstrb,
  input           s_wlast,
  input           s_wvalid,
  output          s_wready,
  output  [ 1:0]  s_bresp,
  output          s_bvalid,
  input           s_bready,
  input   [31:0]  s_araddr,
  input   [ 7:0]  s_arlen,
  input   [ 2:0]  s_arsize,
  input   [ 1:0]  s_arburst,
  input   [ 2:0]  s_arprot,
  input           s_arvalid,
  output          s_arready,
  output  [31:0]  s_rdata,
  output  [ 1:0]  s_rresp,
  output          s_rlast,
  output          s_rvalid,
  input           s_rready,

  // master port 0: BRAM (AXI4, single-beat)

  output  [31:0]  m0_awaddr,
  output          m0_awvalid,
  input           m0_awready,
  output  [31:0]  m0_wdata,
  output  [ 3:0]  m0_wstrb,
  output          m0_wvalid,
  input           m0_wready,
  input   [ 1:0]  m0_bresp,
  input           m0_bvalid,
  output          m0_bready,
  output  [31:0]  m0_araddr,
  output          m0_arvalid,
  input           m0_arready,
  input   [31:0]  m0_rdata,
  input   [ 1:0]  m0_rresp,
  input           m0_rvalid,
  output          m0_rready,

  // master port 1: axi_ad9361 (AXI4-Lite, 16-bit address)

  output  [15:0]  m1_awaddr,
  output  [ 2:0]  m1_awprot,
  output          m1_awvalid,
  input           m1_awready,
  output  [31:0]  m1_wdata,
  output  [ 3:0]  m1_wstrb,
  output          m1_wvalid,
  input           m1_wready,
  input   [ 1:0]  m1_bresp,
  input           m1_bvalid,
  output          m1_bready,
  output  [15:0]  m1_araddr,
  output  [ 2:0]  m1_arprot,
  output          m1_arvalid,
  input           m1_arready,
  input   [31:0]  m1_rdata,
  input   [ 1:0]  m1_rresp,
  input           m1_rvalid,
  output          m1_rready,

  // master port 2: streaming adapter (SmartHLS AXI4 subset)

  output  [31:0]  m2_awaddr,
  output  [ 7:0]  m2_awlen,
  output  [ 2:0]  m2_awsize,
  output  [ 1:0]  m2_awburst,
  output          m2_awvalid,
  input           m2_awready,
  output  [31:0]  m2_wdata,
  output  [ 3:0]  m2_wstrb,
  output          m2_wlast,
  output          m2_wvalid,
  input           m2_wready,
  input   [ 1:0]  m2_bresp,
  input           m2_bvalid,
  output          m2_bready,
  output  [31:0]  m2_araddr,
  output  [ 7:0]  m2_arlen,
  output  [ 2:0]  m2_arsize,
  output  [ 1:0]  m2_arburst,
  output          m2_arvalid,
  input           m2_arready,
  input   [31:0]  m2_rdata,
  input   [ 1:0]  m2_rresp,
  input           m2_rlast,
  input           m2_rvalid,
  output          m2_rready
);

  // -------------------------------------------------------------------------
  // PULP AXI4-Lite types and crossbar configuration
  // -------------------------------------------------------------------------

  localparam int unsigned IdxBram   = 0;
  localparam int unsigned IdxAd9361 = 1;
  localparam int unsigned IdxAdpt   = 2;

  typedef logic [31:0] addr_t;
  typedef logic [31:0] data_t;
  typedef logic [ 3:0] strb_t;

  `AXI_LITE_TYPEDEF_ALL(axi_lite, addr_t, data_t, strb_t)

  localparam axi_pkg::xbar_cfg_t XbarCfg = '{
    NoSlvPorts:         32'd1,
    NoMstPorts:         32'd3,
    MaxMstTrans:        32'd1,   // NEORV32 bridge: one outstanding transaction
    MaxSlvTrans:        32'd1,
    FallThrough:        1'b0,
    // CUT_ALL_PORTS (spill registers on every channel), not NO_LATENCY: the
    // SmartHLS streaming adapter's r_valid depends combinationally on
    // r_ready, which closes a combinational loop through the demux's
    // fall-through R routing. The spill registers sever every combinational
    // path through the crossbar; the added cycles are irrelevant for a
    // polling CPU.
    LatencyMode:        axi_pkg::CUT_ALL_PORTS,
    PipelineStages:     32'd0,
    AxiIdWidthSlvPorts: 32'd0,   // AXI4-Lite: no IDs
    AxiIdUsedSlvPorts:  32'd0,
    UniqueIds:          1'b0,
    AxiAddrWidth:       32'd32,
    AxiDataWidth:       32'd32,
    NoAddrRules:        32'd3
  };

  localparam axi_pkg::xbar_rule_32_t [2:0] AddrMap = '{
    '{idx: IdxAdpt,   start_addr: 32'h44A1_0000, end_addr: 32'h44A1_4000},
    '{idx: IdxAd9361, start_addr: 32'h44A0_0000, end_addr: 32'h44A1_0000},
    '{idx: IdxBram,   start_addr: 32'hC000_0000, end_addr: 32'hC000_8000}
  };

  axi_lite_req_t          slv_req;
  axi_lite_resp_t         slv_resp;
  axi_lite_req_t  [2:0]   mst_req;
  axi_lite_resp_t [2:0]   mst_resp;

  // -------------------------------------------------------------------------
  // slave port: AXI4 single-beat -> AXI4-Lite
  // (len/size/burst carry no information for a single-beat master and are
  //  dropped; WLAST is dropped, RLAST is regenerated below)
  // -------------------------------------------------------------------------

  assign slv_req.aw.addr  = s_awaddr;
  assign slv_req.aw.prot  = s_awprot;
  assign slv_req.aw_valid = s_awvalid;
  assign s_awready        = slv_resp.aw_ready;

  assign slv_req.w.data   = s_wdata;
  assign slv_req.w.strb   = s_wstrb;
  assign slv_req.w_valid  = s_wvalid;
  assign s_wready         = slv_resp.w_ready;

  assign s_bresp          = slv_resp.b.resp;
  assign s_bvalid         = slv_resp.b_valid;
  assign slv_req.b_ready  = s_bready;

  assign slv_req.ar.addr  = s_araddr;
  assign slv_req.ar.prot  = s_arprot;
  assign slv_req.ar_valid = s_arvalid;
  assign s_arready        = slv_resp.ar_ready;

  assign s_rdata          = slv_resp.r.data;
  assign s_rresp          = slv_resp.r.resp;
  assign s_rlast          = 1'b1;            // single-beat: every beat is last
  assign s_rvalid         = slv_resp.r_valid;
  assign slv_req.r_ready  = s_rready;

  // -------------------------------------------------------------------------
  // crossbar
  // -------------------------------------------------------------------------

  axi_lite_xbar #(
    .Cfg        (XbarCfg),
    .aw_chan_t  (axi_lite_aw_chan_t),
    .w_chan_t   (axi_lite_w_chan_t),
    .b_chan_t   (axi_lite_b_chan_t),
    .ar_chan_t  (axi_lite_ar_chan_t),
    .r_chan_t   (axi_lite_r_chan_t),
    .axi_req_t  (axi_lite_req_t),
    .axi_resp_t (axi_lite_resp_t),
    .rule_t     (axi_pkg::xbar_rule_32_t)
  ) i_xbar (
    .clk_i                 (aclk),
    .rst_ni                (aresetn),
    .test_i                (1'b0),
    .slv_ports_req_i       (slv_req),
    .slv_ports_resp_o      (slv_resp),
    .mst_ports_req_o       (mst_req),
    .mst_ports_resp_i      (mst_resp),
    .addr_map_i            (AddrMap),
    .en_default_mst_port_i (1'b0),
    .default_mst_port_i    ('0)
  );

  // -------------------------------------------------------------------------
  // master port 0: BRAM (lite subset, no prot)
  // -------------------------------------------------------------------------

  assign m0_awaddr                 = mst_req[IdxBram].aw.addr;
  assign m0_awvalid                = mst_req[IdxBram].aw_valid;
  assign mst_resp[IdxBram].aw_ready = m0_awready;

  assign m0_wdata                  = mst_req[IdxBram].w.data;
  assign m0_wstrb                  = mst_req[IdxBram].w.strb;
  assign m0_wvalid                 = mst_req[IdxBram].w_valid;
  assign mst_resp[IdxBram].w_ready = m0_wready;

  assign mst_resp[IdxBram].b.resp  = m0_bresp;
  assign mst_resp[IdxBram].b_valid = m0_bvalid;
  assign m0_bready                 = mst_req[IdxBram].b_ready;

  assign m0_araddr                 = mst_req[IdxBram].ar.addr;
  assign m0_arvalid                = mst_req[IdxBram].ar_valid;
  assign mst_resp[IdxBram].ar_ready = m0_arready;

  assign mst_resp[IdxBram].r.data  = m0_rdata;
  assign mst_resp[IdxBram].r.resp  = m0_rresp;
  assign mst_resp[IdxBram].r_valid = m0_rvalid;
  assign m0_rready                 = mst_req[IdxBram].r_ready;

  // -------------------------------------------------------------------------
  // master port 1: axi_ad9361 (AXI4-Lite, 16-bit address)
  // -------------------------------------------------------------------------

  assign m1_awaddr                   = mst_req[IdxAd9361].aw.addr[15:0];
  assign m1_awprot                   = mst_req[IdxAd9361].aw.prot;
  assign m1_awvalid                  = mst_req[IdxAd9361].aw_valid;
  assign mst_resp[IdxAd9361].aw_ready = m1_awready;

  assign m1_wdata                    = mst_req[IdxAd9361].w.data;
  assign m1_wstrb                    = mst_req[IdxAd9361].w.strb;
  assign m1_wvalid                   = mst_req[IdxAd9361].w_valid;
  assign mst_resp[IdxAd9361].w_ready = m1_wready;

  assign mst_resp[IdxAd9361].b.resp  = m1_bresp;
  assign mst_resp[IdxAd9361].b_valid = m1_bvalid;
  assign m1_bready                   = mst_req[IdxAd9361].b_ready;

  assign m1_araddr                   = mst_req[IdxAd9361].ar.addr[15:0];
  assign m1_arprot                   = mst_req[IdxAd9361].ar.prot;
  assign m1_arvalid                  = mst_req[IdxAd9361].ar_valid;
  assign mst_resp[IdxAd9361].ar_ready = m1_arready;

  assign mst_resp[IdxAd9361].r.data  = m1_rdata;
  assign mst_resp[IdxAd9361].r.resp  = m1_rresp;
  assign mst_resp[IdxAd9361].r_valid = m1_rvalid;
  assign m1_rready                   = mst_req[IdxAd9361].r_ready;

  // -------------------------------------------------------------------------
  // master port 2: streaming adapter (AXI4 subset, single-beat reconstruction)
  // -------------------------------------------------------------------------

  // The SmartHLS bridge decodes its FULL axi_aw_addr/axi_ar_addr (addr>>2,
  // no masking — see axi_lite_to_streaming_adapter.cpp), so it must be
  // given window offsets, not absolute addresses: present the low 14 bits
  // zero-extended (the Vitis IP's s_axi_ctrl port was 14 bits wide and got
  // this masking for free from the port width).
  assign m2_awaddr                 = {18'b0, mst_req[IdxAdpt].aw.addr[13:0]};
  assign m2_awlen                  = 8'd0;      // single-beat
  assign m2_awsize                 = 3'd2;      // 4 bytes
  assign m2_awburst                = 2'b01;     // INCR
  assign m2_awvalid                = mst_req[IdxAdpt].aw_valid;
  assign mst_resp[IdxAdpt].aw_ready = m2_awready;

  assign m2_wdata                  = mst_req[IdxAdpt].w.data;
  assign m2_wstrb                  = mst_req[IdxAdpt].w.strb;
  assign m2_wlast                  = 1'b1;      // single-beat
  assign m2_wvalid                 = mst_req[IdxAdpt].w_valid;
  assign mst_resp[IdxAdpt].w_ready = m2_wready;

  assign mst_resp[IdxAdpt].b.resp  = m2_bresp;
  assign mst_resp[IdxAdpt].b_valid = m2_bvalid;
  assign m2_bready                 = mst_req[IdxAdpt].b_ready;

  assign m2_araddr                 = {18'b0, mst_req[IdxAdpt].ar.addr[13:0]};
  assign m2_arlen                  = 8'd0;
  assign m2_arsize                 = 3'd2;
  assign m2_arburst                = 2'b01;
  assign m2_arvalid                = mst_req[IdxAdpt].ar_valid;
  assign mst_resp[IdxAdpt].ar_ready = m2_arready;

  assign mst_resp[IdxAdpt].r.data  = m2_rdata;
  assign mst_resp[IdxAdpt].r.resp  = m2_rresp;
  assign mst_resp[IdxAdpt].r_valid = m2_rvalid;
  assign m2_rready                 = mst_req[IdxAdpt].r_ready;
  // m2_rlast is consumed here: reads are single-beat, RLAST regenerated at
  // the slave port

  wire unused_m2_rlast = m2_rlast;

endmodule
