// ***************************************************************************
// ***************************************************************************
// Copyright (C) 2014-2024 Analog Devices, Inc. All rights reserved.
//
// In this HDL repository, there are many different and unique modules, consisting
// of various HDL (Verilog or VHDL) components. The individual modules are
// developed independently, and may be accompanied by separate and unique license
// terms.
//
// The user should read each of these license terms, and understand the
// freedoms and responsibilities that he or she has by using this source/core.
//
// This core is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
// A PARTICULAR PURPOSE.
//
// Redistribution and use of source or resulting binaries, with or without modification
// of this file, are permitted under one of the following two license terms:
//
//   1. The GNU General Public License version 2 as published by the
//      Free Software Foundation, which can be found in the top level directory
//      of this repository (LICENSE_GPL2), and also online at:
//      <https://www.gnu.org/licenses/old-licenses/gpl-2.0.html>
//
// OR
//
//   2. An ADI specific BSD license, which can be found in the top level directory
//      of this repository (LICENSE_ADIBSD), and also on-line at:
//      https://github.com/analogdevicesinc/hdl/blob/main/LICENSE_ADIBSD
//      This will allow to generate bit files and not release the source code,
//      as long as it attaches to an ADI device.
//
// ***************************************************************************
// ***************************************************************************
//
// Efinix port of ad_mul
//
// Signed multiplier with configurable data widths and pipeline delay matching.
//
// The Xilinx version uses MULT_MACRO with 3-cycle latency.
// This Efinix version implements the same functionality using behavioral RTL
// that will be synthesized to Efinix DSP blocks.
//
// Efinix DSP blocks support:
//   - 18x18 signed multiplication (native)
//   - Can cascade for larger widths
//   - Configurable pipeline registers
//
// The synthesis tool will infer DSP blocks from the behavioral multiplication.
// The 3-stage pipeline matches the Xilinx MULT_MACRO latency.
//
// ***************************************************************************

`timescale 1ps/1ps

module ad_mul #(
  parameter   A_DATA_WIDTH = 17,
  parameter   B_DATA_WIDTH = 17,
  parameter   DELAY_DATA_WIDTH = 16
) (

  // data_p = data_a * data_b;
  input                                     clk,
  input   [               A_DATA_WIDTH-1:0] data_a,
  input   [               B_DATA_WIDTH-1:0] data_b,
  output  [A_DATA_WIDTH + B_DATA_WIDTH-1:0] data_p,

  // delay interface
  input       [(DELAY_DATA_WIDTH-1):0]  ddata_in,
  output  reg [(DELAY_DATA_WIDTH-1):0]  ddata_out = 'd0
);

  // -------------------------------------------------------------------------
  // Efinix Implementation Notes:
  // -------------------------------------------------------------------------
  // Efinix DSP blocks have native 18x18 signed multipliers.
  // For the typical 17x17 configuration used in this design, a single DSP
  // block is sufficient.
  //
  // Pipeline stages (3 total, matching Xilinx MULT_MACRO LATENCY=3):
  //   Stage 1: Input registers (A and B)
  //   Stage 2: Multiplier register (M)
  //   Stage 3: Output register (P)
  //
  // The delay data path (ddata) is pipelined to match the multiplier latency.
  // -------------------------------------------------------------------------

  // Pipeline registers for delay data (matches multiplier latency)
  reg [(DELAY_DATA_WIDTH-1):0] p1_ddata = 'd0;
  reg [(DELAY_DATA_WIDTH-1):0] p2_ddata = 'd0;

  // Multiplier pipeline registers
  reg signed [A_DATA_WIDTH-1:0] a_reg = 'd0;
  reg signed [B_DATA_WIDTH-1:0] b_reg = 'd0;
  reg signed [A_DATA_WIDTH + B_DATA_WIDTH-1:0] mult_reg = 'd0;
  reg signed [A_DATA_WIDTH + B_DATA_WIDTH-1:0] p_reg = 'd0;

  // Delay data pipeline (3 stages to match multiplier)
  always @(posedge clk) begin
    p1_ddata  <= ddata_in;
    p2_ddata  <= p1_ddata;
    ddata_out <= p2_ddata;
  end

  // Multiplier with 3-stage pipeline
  // Stage 1: Input registers
  always @(posedge clk) begin
    a_reg <= data_a;
    b_reg <= data_b;
  end

  // Stage 2: Multiplier
  // This multiplication will be inferred to Efinix DSP block
  always @(posedge clk) begin
    mult_reg <= a_reg * b_reg;
  end

  // Stage 3: Output register
  always @(posedge clk) begin
    p_reg <= mult_reg;
  end

  assign data_p = p_reg;

endmodule
