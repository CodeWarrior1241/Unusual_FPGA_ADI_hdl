// ***************************************************************************
// ***************************************************************************
// Copyright (C) 2014-2023 Analog Devices, Inc. All rights reserved.
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
// Efinix port of ad_dcfilter
//
// DC filter implementing: y(n) = c*x(n) + (1-c)*y(n-1)
//
// The Xilinx version uses DSP48E1 primitives with the operation ((D-A)*B)+C.
// This Efinix version implements the same algorithm using behavioral RTL
// that will be synthesized to Efinix DSP blocks.
//
// Efinix DSP blocks support:
//   - 18x18 signed multiplication
//   - 54-bit accumulator
//   - Pre-adder
//   - Pipelining
//
// The synthesis tool will infer DSP blocks from the behavioral description.
// For optimal DSP inference, the code follows multiplication and accumulation
// patterns that map well to Efinix DSP architecture.
//
// ***************************************************************************

`timescale 1ps/1ps

module ad_dcfilter #(
  // data path disable
  parameter   DISABLE = 0
) (

  // data interface
  input           clk,
  input           valid,
  input   [15:0]  data,
  output          valid_out,
  output  [15:0]  data_out,

  // control interface
  input           dcfilt_enb,
  input   [15:0]  dcfilt_coeff,
  input   [15:0]  dcfilt_offset
);

  // -------------------------------------------------------------------------
  // Efinix Implementation Notes:
  // -------------------------------------------------------------------------
  // The DC filter computes: y(n) = c*x(n) + (1-c)*y(n-1)
  // Which can be rewritten as: y(n) = y(n-1) + c*(x(n) - y(n-1))
  //
  // This is implemented as:
  //   1. diff = data_in - dc_estimate
  //   2. correction = diff * coefficient
  //   3. dc_estimate_new = dc_estimate + correction
  //   4. output = data_in - dc_estimate
  //
  // The Xilinx DSP48E1 computes ((D-A)*B)+C in one cycle with pipelining.
  // On Efinix, we use behavioral RTL that will infer DSP blocks.
  //
  // Pipeline stages (matching Xilinx latency):
  //   Stage 1: Register inputs, compute data + offset
  //   Stage 2: Register intermediate, compute difference
  //   Stage 3: Multiply difference by coefficient
  //   Stage 4: Accumulate result
  //   Stage 5: Output
  // -------------------------------------------------------------------------

  // data-path disable
  generate
  if (DISABLE == 1) begin : gen_disabled
    assign valid_out = valid;
    assign data_out = data;
  end else begin : gen_enabled

    // Internal registers
    reg [15:0]  dcfilt_coeff_d = 'd0;
    reg [47:0]  dc_offset = 'd0;
    reg [47:0]  dc_offset_d = 'd0;
    reg         valid_d = 'd0;
    reg [15:0]  data_d = 'd0;
    reg         valid_2d = 'd0;
    reg [15:0]  data_2d = 'd0;
    reg [15:0]  data_dcfilt = 'd0;
    reg         valid_int = 'd0;
    reg [15:0]  data_int = 'd0;

    // DSP computation signals
    reg signed [24:0]  dsp_d_reg = 'd0;      // D input (data + offset, sign-extended)
    reg signed [29:0]  dsp_a_reg = 'd0;      // A input (dc_offset feedback)
    reg signed [17:0]  dsp_b_reg = 'd0;      // B input (coefficient)
    reg signed [47:0]  dsp_c_reg = 'd0;      // C input (dc_offset for accumulation)
    reg signed [24:0]  dsp_diff = 'd0;       // D - A (pre-adder result)
    reg signed [42:0]  dsp_mult = 'd0;       // (D - A) * B
    reg signed [47:0]  dsp_result = 'd0;     // ((D - A) * B) + C

    // Register coefficient to remove timing warnings
    always @(posedge clk) begin
      dcfilt_coeff_d <= dcfilt_coeff;
    end

    // Pipeline stage 1: Register inputs
    always @(posedge clk) begin
      valid_d <= valid;
      if (valid == 1'b1) begin
        data_d <= data + dcfilt_offset;
      end
    end

    // DSP input registration (maps to DSP input registers)
    always @(posedge clk) begin
      // D input: data + offset, sign-extended to 25 bits
      dsp_d_reg <= {{9{data_d[15]}}, data_d};
      // A input: current DC estimate (from accumulator), sign-extended
      dsp_a_reg <= {{14{dsp_result[32]}}, dsp_result[32:17]};
      // B input: filter coefficient, sign-extended to 18 bits
      dsp_b_reg <= {{2{dcfilt_coeff_d[15]}}, dcfilt_coeff_d};
      // C input: previous DC offset for accumulation
      dsp_c_reg <= dc_offset_d;
    end

    // DSP pre-adder: D - A
    always @(posedge clk) begin
      dsp_diff <= dsp_d_reg - dsp_a_reg[24:0];
    end

    // DSP multiplier: (D - A) * B
    // This should infer to Efinix DSP multiplier
    always @(posedge clk) begin
      dsp_mult <= dsp_diff * dsp_b_reg;
    end

    // DSP post-adder/accumulator: ((D - A) * B) + C
    always @(posedge clk) begin
      dsp_result <= {{5{dsp_mult[42]}}, dsp_mult} + dsp_c_reg;
    end

    // DC offset tracking
    always @(posedge clk) begin
      dc_offset   <= dsp_result;
      dc_offset_d <= dc_offset;
    end

    // Output pipeline
    always @(posedge clk) begin
      valid_2d <= valid_d;
      data_2d  <= data_d;
      data_dcfilt <= data_d - dc_offset[32:17];

      if (dcfilt_enb == 1'b1) begin
        valid_int <= valid_2d;
        data_int  <= data_dcfilt;
      end else begin
        valid_int <= valid_2d;
        data_int  <= data_2d;
      end
    end

    assign valid_out = valid_int;
    assign data_out = data_int;

  end
  endgenerate

endmodule
