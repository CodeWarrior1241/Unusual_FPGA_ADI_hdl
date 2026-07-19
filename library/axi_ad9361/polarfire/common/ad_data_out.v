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
// Microchip PolarFire port of the Xilinx ad_data_out: DDR output registers
// -> differential (or single-ended / pseudo-differential) pad buffer.
//
// PolarFire has no fabric-instantiable DDR_OUT macro (DDR I/O registers
// live in the IOD block, reached through the PF_IOD_GENERIC_TX generated
// core), so the DDR output is emulated in fabric: both bits are registered
// on the rising edge, the low-phase bit is retimed to the falling edge, and
// the clock muxes between them — the fabric equivalent of the Xilinx ODDR
// "SAME_EDGE" mode. The original module maps D1 = tx_data_n and
// D2 = tx_data_p, so tx_data_n is the first-out (clock-high) bit; that
// ordering is preserved here. For full-rate operation, replace this output
// path with a PF_IOD_GENERIC_TX core.
//
// The dynamic output-delay (ODELAY) interface is accepted but not
// implemented; readback returns zero and delay_locked is tied high.

`timescale 1ns/100ps

module ad_data_out #(

  parameter   SINGLE_ENDED = 0,
  parameter   PSEUDO_DIFF = 0,
  // The parameters below exist for port compatibility with the Xilinx
  // version; they have no function on PolarFire.
  parameter   FPGA_TECHNOLOGY = 0,
  parameter   IODELAY_ENABLE = 0,
  parameter   IODELAY_CTRL = 0,
  parameter   IODELAY_GROUP = "dev_if_delay_group",
  parameter   REFCLK_FREQUENCY = 200
) (

  // transmit data interface

  input               tx_clk,
  input               tx_data_p,
  input               tx_data_n,
  output              tx_data_out_p,
  output              tx_data_out_n,

  // delay-data interface (unused on PolarFire)

  input               up_clk,
  input               up_dld,
  input       [ 4:0]  up_dwdata,
  output      [ 4:0]  up_drdata,

  // delay-control interface (unused on PolarFire)

  input               delay_clk,
  input               delay_rst,
  output              delay_locked
);

  wire                tx_data_oddr_s;

  reg                 tx_data_r = 1'b0;
  reg                 tx_data_f_hold = 1'b0;
  reg                 tx_data_f = 1'b0;

  assign up_drdata = 5'd0;
  assign delay_locked = 1'b1;

  // ddr output registers, fabric-emulated (see header)

  always @(posedge tx_clk) begin
    tx_data_r <= tx_data_n;
    tx_data_f_hold <= tx_data_p;
  end

  always @(negedge tx_clk) begin
    tx_data_f <= tx_data_f_hold;
  end

  assign tx_data_oddr_s = (tx_clk == 1'b1) ? tx_data_r : tx_data_f;

  // output buffer

  generate
  if (SINGLE_ENDED == 1) begin
    assign tx_data_out_n = 1'b0;
    OUTBUF i_tx_data_obuf (
      .D (tx_data_oddr_s),
      .PAD (tx_data_out_p));
  end else if (PSEUDO_DIFF == 1) begin
    // two single-ended pads driven with complementary data
    wire tx_data_oddr_inv_s;
    assign tx_data_oddr_inv_s = (tx_clk == 1'b1) ? ~tx_data_r : ~tx_data_f;
    OUTBUF i_tx_data_obuf_p (
      .D (tx_data_oddr_s),
      .PAD (tx_data_out_p));
    OUTBUF i_tx_data_obuf_n (
      .D (tx_data_oddr_inv_s),
      .PAD (tx_data_out_n));
  end else begin
    OUTBUF_DIFF i_tx_data_obuf (
      .D (tx_data_oddr_s),
      .PADP (tx_data_out_p),
      .PADN (tx_data_out_n));
  end
  endgenerate

endmodule
