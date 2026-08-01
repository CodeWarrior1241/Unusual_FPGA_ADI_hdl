// ***************************************************************************
// l_clk domain reset synchronizer for the MPF300 FMCOMMS2 design:
// equivalent of the axau15 util_ad9361_lclk_reset proc_sys_reset plus the
// pwr_dn xpm_cdc_single (plan B.4). Produces the reset for the HLS adapter
// datapath and the RX CDC FIFO, held while the system reset is asserted OR
// software power-down is active.
//
// Built from Bedrock-RTL (deps/bedrock-rtl, SystemVerilog) plus the
// project-local reset generator (both replacing open-logic VHDL — see
// doc/MPF300-Splash-Kit/bedrock_migration_design.md):
//   - br_cdc_bit_toggle carries pwr_dn from the 125 MHz domain into l_clk
//     (the only project-authored CDC, same as axau15). NumStages=4 keeps
//     the 4-stage depth of the hand-rolled synchronizer this replaces;
//     AddSourceFlop=1 keeps the source-domain register olo_base_cc_bits
//     added over the original hand-rolled 4-flop version.
//   - mpf300_reset_gen filters (system reset | pwr_dn) into an l_clk
//     synchronous reset with an 8-cycle minimum pulse, mirroring
//     olo_base_reset_gen exactly.
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

  wire pwr_dn_lclk;

  br_cdc_bit_toggle #(
    .NumStages     (4),
    .AddSourceFlop (1)
  ) i_pwr_dn_cc (
    .src_clk (clk_125),
    .src_rst (1'b0),
    .src_bit (pwr_dn),
    .dst_clk (l_clk),
    .dst_rst (1'b0),
    .dst_bit (pwr_dn_lclk)
  );

  wire rst_src = ~ext_resetn | pwr_dn_lclk;      // active high

  mpf300_reset_gen #(
    .RST_PULSE_CYCLES (8)
  ) i_reset_gen (
    .clk     (l_clk),
    .rst_in  (rst_src),
    .rst_out (lclk_reset)
  );

  assign lclk_resetn = ~lclk_reset;

endmodule
