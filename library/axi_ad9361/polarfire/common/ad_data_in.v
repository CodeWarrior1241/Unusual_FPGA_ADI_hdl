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
// Microchip PolarFire port of the Xilinx ad_data_in: differential (or
// single-ended) receive lane, pad buffer -> DDR input capture.
//
// PolarFire has no fabric-instantiable DDR_IN macro (DDR I/O registers live
// in the IOD block, reached through the PF_IOD_GENERIC_RX generated core),
// so the DDR capture is emulated in fabric: a rising-edge and a
// falling-edge register, with the falling sample retimed to the rising
// edge. Both samples are presented on the rising edge (rx_data_p = rising
// sample, rx_data_n = preceding falling sample), matching the Xilinx IDDR
// "SAME_EDGE" mode used by the original module. For full-rate (245.76 MHz)
// operation, replace this capture path with a PF_IOD_GENERIC_RX core.
//
// The dynamic input-delay (IDELAY) interface is accepted but not
// implemented; readback returns zero and delay_locked is tied high,
// following the approach of the Intel port.

`timescale 1ns/100ps

module ad_data_in #(

  parameter   SINGLE_ENDED = 0,
  // The parameters below exist for port compatibility with the Xilinx
  // version; they have no function on PolarFire.
  parameter   FPGA_TECHNOLOGY = 0,
  parameter   DDR_SDR_N = 1,
  parameter   IODELAY_ENABLE = 1,
  parameter   IODELAY_CTRL = 0,
  parameter   IODELAY_GROUP = "dev_if_delay_group",
  parameter   REFCLK_FREQUENCY = 200
) (

  // receive data interface

  input               rx_clk,
  input               rx_data_in_p,
  input               rx_data_in_n,
  output              rx_data_p,
  output              rx_data_n,

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

  wire                rx_data_ibuf_s;

  reg                 rx_data_r = 1'b0;
  reg                 rx_data_f_neg = 1'b0;
  reg                 rx_data_f = 1'b0;

  assign up_drdata = 5'd0;
  assign delay_locked = 1'b1;

  // input buffer

  generate
  if (SINGLE_ENDED == 1) begin
    INBUF i_rx_data_ibuf (
      .PAD (rx_data_in_p),
      .Y (rx_data_ibuf_s));
  end else begin
    INBUF_DIFF i_rx_data_ibuf (
      .PADP (rx_data_in_p),
      .PADN (rx_data_in_n),
      .Y (rx_data_ibuf_s));
  end
  endgenerate

  // ddr input capture, fabric-emulated (see header)

  always @(posedge rx_clk) begin
    rx_data_r <= rx_data_ibuf_s;
    rx_data_f <= rx_data_f_neg;
  end

  always @(negedge rx_clk) begin
    rx_data_f_neg <= rx_data_ibuf_s;
  end

  assign rx_data_p = rx_data_r;
  assign rx_data_n = rx_data_f;

endmodule
