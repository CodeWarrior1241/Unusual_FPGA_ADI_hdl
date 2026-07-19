// ***************************************************************************
// 32 KB AXI4 single-beat RAM for the MPF300 FMCOMMS2 design: the QPSK
// snapshot BRAM, equivalent of the axau15 axi_bram_ctrl + blk_mem_gen pair.
// Mapped at 0xC000_0000 by axi_1to3_decoder. Synplify infers PolarFire
// LSRAM (8192 x 32, byte-enable writes).
//
// Single-beat only: the only master is the NEORV32 xbus2axi4 bridge with no
// caches, which never bursts. Read latency 2 (registered RAM output +
// registered RVALID), matching the axau15 BRAM controller setting.
// ***************************************************************************

`timescale 1ns/100ps

module axi_bram_32k (

  input           aclk,
  input           aresetn,

  input   [31:0]  awaddr,
  input           awvalid,
  output reg      awready,
  input   [31:0]  wdata,
  input   [ 3:0]  wstrb,
  input           wvalid,
  output reg      wready,
  output  [ 1:0]  bresp,
  output reg      bvalid,
  input           bready,

  input   [31:0]  araddr,
  input           arvalid,
  output reg      arready,
  output  [31:0]  rdata,
  output  [ 1:0]  rresp,
  output reg      rvalid,
  input           rready
);

  reg  [31:0] mem [0:8191];

  reg  [12:0] waddr_r = 13'd0;
  reg         w_pend = 1'b0;
  reg  [31:0] rdata_r = 32'd0;
  reg  [31:0] rdata_out = 32'd0;
  reg         r_stage = 1'b0;

  assign bresp = 2'b00;
  assign rresp = 2'b00;
  assign rdata = rdata_out;

  // write: capture address, then data (they may arrive in any order the
  // bridge produces; single outstanding transaction)

  always @(posedge aclk) begin
    if (!aresetn) begin
      awready <= 1'b0;
      wready  <= 1'b0;
      bvalid  <= 1'b0;
      w_pend  <= 1'b0;
    end else begin
      awready <= 1'b0;
      wready  <= 1'b0;

      if (awvalid && !awready && !w_pend && !bvalid) begin
        waddr_r <= awaddr[14:2];
        awready <= 1'b1;
        w_pend  <= 1'b1;
      end

      if (w_pend && wvalid && !wready) begin
        if (wstrb[0]) mem[waddr_r][ 7: 0] <= wdata[ 7: 0];
        if (wstrb[1]) mem[waddr_r][15: 8] <= wdata[15: 8];
        if (wstrb[2]) mem[waddr_r][23:16] <= wdata[23:16];
        if (wstrb[3]) mem[waddr_r][31:24] <= wdata[31:24];
        wready <= 1'b1;
        w_pend <= 1'b0;
        bvalid <= 1'b1;
      end

      if (bvalid && bready)
        bvalid <= 1'b0;
    end
  end

  // read: 2-cycle latency

  always @(posedge aclk) begin
    if (!aresetn) begin
      arready <= 1'b0;
      rvalid  <= 1'b0;
      r_stage <= 1'b0;
    end else begin
      arready <= 1'b0;

      if (arvalid && !arready && !r_stage && !rvalid) begin
        rdata_r <= mem[araddr[14:2]];
        arready <= 1'b1;
        r_stage <= 1'b1;
      end

      if (r_stage) begin
        rdata_out <= rdata_r;
        rvalid    <= 1'b1;
        r_stage   <= 1'b0;
      end

      if (rvalid && rready)
        rvalid <= 1'b0;
    end
  end

endmodule
