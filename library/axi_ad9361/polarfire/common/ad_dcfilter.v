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
// Microchip PolarFire port of ad_dcfilter. The data path (offset add,
// two-stage pipeline, filtered/unfiltered select) is identical to the Xilinx
// version. The DC-offset estimator, implemented there as a DSP48 computing
// ((D - A) * B) + C, is written behaviorally here with the same 3 register
// stages (pre-add, product, accumulate) so Synplify maps it onto a PolarFire
// MACC block with equivalent loop latency.

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

  // internal registers

  reg     [15:0]  dcfilt_coeff_d = 'd0;
  reg     [47:0]  dc_offset = 'd0;
  reg     [47:0]  dc_offset_d = 'd0;
  reg             valid_d = 'd0;
  reg     [15:0]  data_d = 'd0;
  reg             valid_2d = 'd0;
  reg     [15:0]  data_2d = 'd0;
  reg     [15:0]  data_dcfilt = 'd0;
  reg             valid_int = 'd0;
  reg     [15:0]  data_int = 'd0;

  reg     signed [16:0]  dc_diff = 'd0;
  reg     signed [33:0]  dc_prod = 'd0;

  // internal signals

  wire    signed [47:0]  dc_offset_s;

  // data-path disable

  generate
  if (DISABLE == 1) begin
  assign valid_out = valid;
  assign data_out = data;
  end else begin
  assign valid_out = valid_int;
  assign data_out = data_int;
  end
  endgenerate

  always @(posedge clk) begin
    dcfilt_coeff_d <= dcfilt_coeff;
  end

  // removing dc offset

  always @(posedge clk) begin
    dc_offset   <= dc_offset_s;
    dc_offset_d <= dc_offset;
    valid_d <= valid;
    if (valid == 1'b1) begin
      data_d <= data + dcfilt_offset;
    end
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

  // dc-offset estimator, ((D - A) * B) + C

  always @(posedge clk) begin
    dc_diff <= $signed(data_d) - $signed(dc_offset[32:17]);
    dc_prod <= dc_diff * $signed(dcfilt_coeff_d);
  end

  assign dc_offset_s = {{14{dc_prod[33]}}, dc_prod} + $signed(dc_offset_d);

endmodule
