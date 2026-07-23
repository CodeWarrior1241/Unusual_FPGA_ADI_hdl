// ***************************************************************************
// l_clk domain reset synchronizer for the MPF300 FMCOMMS2 design:
// equivalent of the axau15 util_ad9361_lclk_reset proc_sys_reset plus the
// pwr_dn xpm_cdc_single (plan B.4). Produces the reset for the HLS adapter
// datapath and the RX CDC FIFO, held while the system reset is asserted OR
// software power-down is active.
//
// Built from open-logic components (deps/open-logic, VHDL):
//   - olo_base_cc_bits carries pwr_dn from the 125 MHz domain into l_clk
//     (the only project-authored CDC, same as axau15). SyncStages_g=4
//     keeps the 4-stage depth of the hand-rolled synchronizer this
//     replaces.
//   - olo_base_reset_gen filters (system reset | pwr_dn) into an l_clk
//     synchronous reset with an 8-cycle minimum pulse, matching the
//     8-stage shift register it replaces.
//
// The 125 MHz source clock is a new input (clk_125) — olo_base_cc_bits
// registers the crossing signal in its source domain before the
// synchronizer chain, which the hand-rolled 4-flop version did not.
// ***************************************************************************

`timescale 1ns/100ps

module lclk_reset_sync (

  input           l_clk,
  input           clk_125,          // pwr_dn source domain clock
  input           ext_resetn,       // sys_resetn from the 125 MHz domain
  input           pwr_dn,           // 125 MHz domain, synchronized here

  output          lclk_resetn,      // active low
  output          lclk_reset        // active high (SmartHLS adapter)
);

  wire [0:0] pwr_dn_in;
  wire [0:0] pwr_dn_lclk;

  assign pwr_dn_in = pwr_dn;

  olo_base_cc_bits #(
    .Width_g      (1),
    .SyncStages_g (4)
  ) i_pwr_dn_cc (
    .In_Clk   (clk_125),
    .In_Rst   (1'b0),
    .In_Data  (pwr_dn_in),
    .Out_Clk  (l_clk),
    .Out_Rst  (1'b0),
    .Out_Data (pwr_dn_lclk)
  );

  wire rst_src = ~ext_resetn | pwr_dn_lclk[0];   // active high

  olo_base_reset_gen #(
    .RstPulseCycles_g (8)
  ) i_reset_gen (
    .Clk    (l_clk),
    .RstIn  (rst_src),
    .RstOut (lclk_reset)
  );

  assign lclk_resetn = ~lclk_reset;

endmodule
