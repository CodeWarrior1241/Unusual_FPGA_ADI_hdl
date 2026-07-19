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
// The single AXI master is the NEORV32 xbus2axi4 bridge, which issues one
// outstanding single-beat transaction at a time (no caches are enabled), so
// the router carries no transaction queues: one select register per
// direction, held from address handshake to response handshake.
// Non-decoded addresses are accepted and answered with DECERR.
//
// M1 is an AXI4-Lite endpoint: len/size/burst are dropped and RLAST is
// generated here. M0/M2 receive the full AXI4 signals.
// ***************************************************************************

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

  localparam [1:0] SEL_BRAM   = 2'd0;
  localparam [1:0] SEL_AD9361 = 2'd1;
  localparam [1:0] SEL_ADPT   = 2'd2;
  localparam [1:0] SEL_NONE   = 2'd3;

  function [1:0] decode;
    input [31:0] addr;
    begin
      if (addr[31:15] == {16'hC000, 1'b0})        // 0xC0000000/32K
        decode = SEL_BRAM;
      else if (addr[31:16] == 16'h44A0)           // 0x44A00000/64K
        decode = SEL_AD9361;
      else if (addr[31:14] == {16'h44A1, 2'b00})  // 0x44A10000/16K
        decode = SEL_ADPT;
      else
        decode = SEL_NONE;
    end
  endfunction

  // -------------------------------------------------------------------------
  // write path
  // -------------------------------------------------------------------------

  reg  [1:0]  wsel = SEL_NONE;
  reg         wbusy = 1'b0;
  reg         decerr_bvalid = 1'b0;

  wire [1:0]  wsel_c = decode(s_awaddr);
  wire [1:0]  wsel_eff = wbusy ? wsel : wsel_c;

  wire        aw_hs = s_awvalid & s_awready;
  wire        b_hs  = s_bvalid & s_bready;

  always @(posedge aclk) begin
    if (!aresetn) begin
      wbusy <= 1'b0;
      wsel  <= SEL_NONE;
    end else if (aw_hs && !wbusy) begin
      wbusy <= 1'b1;
      wsel  <= wsel_c;
    end else if (b_hs) begin
      wbusy <= 1'b0;
    end
  end

  // DECERR write responder: accept AW/W, then answer DECERR
  reg decerr_w_seen = 1'b0;
  always @(posedge aclk) begin
    if (!aresetn) begin
      decerr_w_seen <= 1'b0;
      decerr_bvalid <= 1'b0;
    end else begin
      if (wbusy && wsel == SEL_NONE && s_wvalid && s_wlast)
        decerr_w_seen <= 1'b1;
      if (decerr_w_seen && !decerr_bvalid)
        decerr_bvalid <= 1'b1;
      if (b_hs && wsel == SEL_NONE) begin
        decerr_bvalid <= 1'b0;
        decerr_w_seen <= 1'b0;
      end
    end
  end

  assign m0_awaddr  = s_awaddr;
  assign m0_awvalid = s_awvalid & ~wbusy & (wsel_c == SEL_BRAM);
  assign m1_awaddr  = s_awaddr[15:0];
  assign m1_awprot  = s_awprot;
  assign m1_awvalid = s_awvalid & ~wbusy & (wsel_c == SEL_AD9361);
  assign m2_awaddr  = s_awaddr;
  assign m2_awlen   = s_awlen;
  assign m2_awsize  = s_awsize;
  assign m2_awburst = s_awburst;
  assign m2_awvalid = s_awvalid & ~wbusy & (wsel_c == SEL_ADPT);

  assign s_awready = ~wbusy & ((wsel_c == SEL_BRAM)   ? m0_awready :
                               (wsel_c == SEL_AD9361) ? m1_awready :
                               (wsel_c == SEL_ADPT)   ? m2_awready : 1'b1);

  assign m0_wdata  = s_wdata;
  assign m0_wstrb  = s_wstrb;
  assign m0_wvalid = s_wvalid & wbusy & (wsel == SEL_BRAM);
  assign m1_wdata  = s_wdata;
  assign m1_wstrb  = s_wstrb;
  assign m1_wvalid = s_wvalid & wbusy & (wsel == SEL_AD9361);
  assign m2_wdata  = s_wdata;
  assign m2_wstrb  = s_wstrb;
  assign m2_wlast  = s_wlast;
  assign m2_wvalid = s_wvalid & wbusy & (wsel == SEL_ADPT);

  assign s_wready = wbusy & ((wsel == SEL_BRAM)   ? m0_wready :
                             (wsel == SEL_AD9361) ? m1_wready :
                             (wsel == SEL_ADPT)   ? m2_wready :
                             ~decerr_w_seen);

  assign s_bresp = (wsel == SEL_BRAM)   ? m0_bresp :
                   (wsel == SEL_AD9361) ? m1_bresp :
                   (wsel == SEL_ADPT)   ? m2_bresp : 2'b11;

  assign s_bvalid = (wsel == SEL_BRAM)   ? m0_bvalid :
                    (wsel == SEL_AD9361) ? m1_bvalid :
                    (wsel == SEL_ADPT)   ? m2_bvalid : decerr_bvalid;

  assign m0_bready = s_bready & (wsel == SEL_BRAM);
  assign m1_bready = s_bready & (wsel == SEL_AD9361);
  assign m2_bready = s_bready & (wsel == SEL_ADPT);

  // -------------------------------------------------------------------------
  // read path
  // -------------------------------------------------------------------------

  reg  [1:0]  rsel = SEL_NONE;
  reg         rbusy = 1'b0;
  reg         decerr_rvalid = 1'b0;

  wire [1:0]  rsel_c = decode(s_araddr);

  wire        ar_hs = s_arvalid & s_arready;
  wire        r_hs  = s_rvalid & s_rready & s_rlast;

  always @(posedge aclk) begin
    if (!aresetn) begin
      rbusy <= 1'b0;
      rsel  <= SEL_NONE;
    end else if (ar_hs && !rbusy) begin
      rbusy <= 1'b1;
      rsel  <= rsel_c;
    end else if (r_hs) begin
      rbusy <= 1'b0;
    end
  end

  always @(posedge aclk) begin
    if (!aresetn)
      decerr_rvalid <= 1'b0;
    else if (rbusy && rsel == SEL_NONE && !decerr_rvalid)
      decerr_rvalid <= 1'b1;
    else if (r_hs && rsel == SEL_NONE)
      decerr_rvalid <= 1'b0;
  end

  assign m0_araddr  = s_araddr;
  assign m0_arvalid = s_arvalid & ~rbusy & (rsel_c == SEL_BRAM);
  assign m1_araddr  = s_araddr[15:0];
  assign m1_arprot  = s_arprot;
  assign m1_arvalid = s_arvalid & ~rbusy & (rsel_c == SEL_AD9361);
  assign m2_araddr  = s_araddr;
  assign m2_arlen   = s_arlen;
  assign m2_arsize  = s_arsize;
  assign m2_arburst = s_arburst;
  assign m2_arvalid = s_arvalid & ~rbusy & (rsel_c == SEL_ADPT);

  assign s_arready = ~rbusy & ((rsel_c == SEL_BRAM)   ? m0_arready :
                               (rsel_c == SEL_AD9361) ? m1_arready :
                               (rsel_c == SEL_ADPT)   ? m2_arready : 1'b1);

  assign s_rdata = (rsel == SEL_BRAM)   ? m0_rdata :
                   (rsel == SEL_AD9361) ? m1_rdata :
                   (rsel == SEL_ADPT)   ? m2_rdata : 32'hDEC0DEED;

  assign s_rresp = (rsel == SEL_BRAM)   ? m0_rresp :
                   (rsel == SEL_AD9361) ? m1_rresp :
                   (rsel == SEL_ADPT)   ? m2_rresp : 2'b11;

  // BRAM and axi_ad9361 are single-beat / AXI4-Lite: RLAST generated here
  assign s_rlast = (rsel == SEL_ADPT) ? m2_rlast : 1'b1;

  assign s_rvalid = (rsel == SEL_BRAM)   ? m0_rvalid :
                    (rsel == SEL_AD9361) ? m1_rvalid :
                    (rsel == SEL_ADPT)   ? m2_rvalid : decerr_rvalid;

  assign m0_rready = s_rready & (rsel == SEL_BRAM);
  assign m1_rready = s_rready & (rsel == SEL_AD9361);
  assign m2_rready = s_rready & (rsel == SEL_ADPT);

endmodule
