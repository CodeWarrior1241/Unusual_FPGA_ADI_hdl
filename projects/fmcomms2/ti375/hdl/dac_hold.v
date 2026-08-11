// ***************************************************************************
// DAC data holding registers for the Ti375C529 FMCOMMS2 design, l_clk domain.
//
// The SmartHLS axi_ad9361_adapter exposes its DAC sample outputs as
// write_data/write_en pairs (SmartHLS reference-argument convention); the
// ADI axi_ad9361 core expects level-held dac_data buses sampled on
// dac_valid. This block latches each channel on its write_en pulse, which
// is exactly what the Vitis HLS adapter's ap_none output registers did
// implicitly on the axau15 design.
// ***************************************************************************

`timescale 1ns/100ps

module dac_hold (

  input           clk,              // l_clk

  input           dac_data_i0_write_en,
  input   [15:0]  dac_data_i0_write_data,
  input           dac_data_q0_write_en,
  input   [15:0]  dac_data_q0_write_data,
  input           dac_data_i1_write_en,
  input   [15:0]  dac_data_i1_write_data,
  input           dac_data_q1_write_en,
  input   [15:0]  dac_data_q1_write_data,
  input           dac_dunf_write_en,
  input           dac_dunf_write_data,

  output reg [15:0] dac_data_i0 = 16'd0,
  output reg [15:0] dac_data_q0 = 16'd0,
  output reg [15:0] dac_data_i1 = 16'd0,
  output reg [15:0] dac_data_q1 = 16'd0,
  output reg        dac_dunf = 1'b0
);

  always @(posedge clk) begin
    if (dac_data_i0_write_en) dac_data_i0 <= dac_data_i0_write_data;
    if (dac_data_q0_write_en) dac_data_q0 <= dac_data_q0_write_data;
    if (dac_data_i1_write_en) dac_data_i1 <= dac_data_i1_write_data;
    if (dac_data_q1_write_en) dac_data_q1 <= dac_data_q1_write_data;
    if (dac_dunf_write_en)    dac_dunf    <= dac_dunf_write_data;
  end

endmodule
