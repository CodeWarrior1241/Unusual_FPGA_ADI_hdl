// ***************************************************************************
// Reset generator for the Ti375C529 FMCOMMS2 design (renamed from
// mpf300_reset_gen; logic identical) — SystemVerilog mirror of
// open-logic olo_base_reset_gen (the one olo block with no Bedrock-RTL
// equivalent: br_cdc_rst_sync has neither minimum-pulse stretching nor
// power-on assertion). Semantics match the VHDL original exactly:
//
//   * 3-stage async-assert chain, power-up-initialized to all-ones — the
//     Efinity bitstream loads register init values, so reset
//     is guaranteed asserted from configuration until the chains flush
//   * SYNC_STAGES resynchronization stage: the OUTPUT asserts and
//     releases synchronously (olo AsyncResetOutput_g = false)
//   * pulse prolongation to RST_PULSE_CYCLES total cycles
//
// Attributes keep synthesis from restructuring the synchronizer flops
// (Efinity honors syn_preserve / syn_srlstyle, see efinity-synthesis UG).
// See doc/MPF300-Splash-Kit/bedrock_migration_design.md.
// ***************************************************************************

`timescale 1ns/100ps

module efx_reset_gen #(
  parameter integer RST_PULSE_CYCLES = 8,  // minimum output pulse, >= 3
  parameter integer SYNC_STAGES      = 2   // resync depth, 2..4
) (
  input  wire clk,
  input  wire rst_in,   // active high, may assert asynchronously
  output wire rst_out   // active high, synchronous assert + release
);

  // 3-stage async-assert chain (olo RstSyncChain), power-up asserted
  (* syn_preserve = 1, syn_srlstyle = "registers" *)
  reg [2:0] rst_chain = 3'b111;

  always @(posedge clk or posedge rst_in) begin
    if (rst_in)
      rst_chain <= 3'b111;
    else
      rst_chain <= {rst_chain[1:0], 1'b0};
  end

  // resynchronization -> synchronous-asserting internal reset (olo DsSync)
  (* syn_preserve = 1, syn_srlstyle = "registers" *)
  reg [SYNC_STAGES-1:0] ds_sync = {SYNC_STAGES{1'b1}};

  always @(posedge clk)
    ds_sync <= {ds_sync[SYNC_STAGES-2:0], rst_chain[2]};

  wire rst_sync = ds_sync[SYNC_STAGES-1];

  // prolong to RST_PULSE_CYCLES (olo g_prolong; PulseCntMax_c = cycles-4)
  localparam integer PULSE_CNT_MAX = (RST_PULSE_CYCLES > 4) ? RST_PULSE_CYCLES - 4 : 0;

  reg [$clog2(PULSE_CNT_MAX + 1):0] pulse_cnt = '0;
  reg                               rst_pulse = 1'b1;

  always @(posedge clk) begin
    if (rst_sync) begin
      pulse_cnt <= '0;
      rst_pulse <= 1'b1;
    end else if (pulse_cnt == PULSE_CNT_MAX) begin
      rst_pulse <= 1'b0;
    end else begin
      pulse_cnt <= pulse_cnt + 1'b1;
    end
  end

  assign rst_out = (RST_PULSE_CYCLES > 3) ? rst_pulse : rst_sync;

endmodule
