// ***************************************************************************
// l_clk domain reset synchronizer for the MPF300 FMCOMMS2 design:
// equivalent of the axau15 util_ad9361_lclk_reset proc_sys_reset plus the
// pwr_dn xpm_cdc_single (plan B.4). Produces the reset for the HLS adapter
// datapath and the RX CDC FIFO, held while the system reset is asserted OR
// software power-down is active.
//
// pwr_dn originates in the 125 MHz domain; it crosses into l_clk through a
// 4-stage synchronizer here (the only project-authored CDC, same as
// axau15).
// ***************************************************************************

`timescale 1ns/100ps

module lclk_reset_sync (

  input           l_clk,
  input           ext_resetn,       // sys_resetn from the 125 MHz domain
  input           pwr_dn,           // 125 MHz domain, synchronized here

  output          lclk_resetn,      // active low
  output          lclk_reset        // active high (SmartHLS adapter)
);

  reg [3:0] pwr_dn_sync = 4'h0;
  reg [7:0] rst_shift = 8'h00;

  always @(posedge l_clk) begin
    pwr_dn_sync <= {pwr_dn_sync[2:0], pwr_dn};
  end

  wire rst_src_n = ext_resetn & ~pwr_dn_sync[3];

  always @(posedge l_clk or negedge rst_src_n) begin
    if (!rst_src_n)
      rst_shift <= 8'h00;
    else
      rst_shift <= {rst_shift[6:0], 1'b1};
  end

  assign lclk_resetn = rst_shift[7];
  assign lclk_reset  = ~rst_shift[7];

endmodule
