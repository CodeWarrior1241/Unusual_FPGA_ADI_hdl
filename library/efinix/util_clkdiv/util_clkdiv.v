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
// Efinix port of util_clkdiv
//
// Clock divider with selectable division ratio.
//
// The Xilinx version uses BUFR primitives for clock division. BUFR is a
// regional clock buffer with built-in integer division (not a PLL).
//
// On Efinix FPGAs, we implement equivalent functionality using:
//   - Toggle flip-flops for clock division
//   - Behavioral clock mux for selection
//
// The Efinity synthesis tool will:
//   - Place divider FFs close to the clock network
//   - Infer global/regional clock buffers as needed
//   - Map the clock mux to available clock mux resources
//
// INPUT CLOCK:
// ------------
// For AD9361/AD9364 designs, the input clock (clk) is l_clk from the
// axi_ad9361 core, which is derived from the AD9364's DATA_CLK output.
// Frequency range depends on sample rate and mode:
//   - 1R1T mode: 2x sample rate (up to ~122.88 MHz at max rate)
//   - 2R2T mode: 4x sample rate (up to ~245.76 MHz at max rate)
//
// The divider outputs:
//   - SEL_0_DIV = "4": l_clk / 4 (sample rate in 2R2T mode)
//   - SEL_1_DIV = "2": l_clk / 2 (sample rate in 1R1T mode)
//
// ***************************************************************************

`timescale 1ns/100ps

module util_clkdiv #(
  parameter SIM_DEVICE = "EFINIX",
  parameter SEL_0_DIV = "4",
  parameter SEL_1_DIV = "2"
) (
  input   clk,
  input   clk_sel,
  output  clk_out
);

  // -------------------------------------------------------------------------
  // Clock Division Implementation
  // -------------------------------------------------------------------------
  // Convert string parameters to integer division values
  localparam integer DIV_0 = (SEL_0_DIV == "1") ? 1 :
                              (SEL_0_DIV == "2") ? 2 :
                              (SEL_0_DIV == "4") ? 4 :
                              (SEL_0_DIV == "8") ? 8 : 4;

  localparam integer DIV_1 = (SEL_1_DIV == "1") ? 1 :
                              (SEL_1_DIV == "2") ? 2 :
                              (SEL_1_DIV == "4") ? 4 :
                              (SEL_1_DIV == "8") ? 8 : 2;

  // Divided clock signals
  wire clk_div_sel_0;
  wire clk_div_sel_1;

  // -------------------------------------------------------------------------
  // Clock Divider 0 (SEL_0_DIV, typically /4)
  // -------------------------------------------------------------------------
  generate
    if (DIV_0 == 1) begin : gen_div0_bypass
      assign clk_div_sel_0 = clk;
    end
    else if (DIV_0 == 2) begin : gen_div0_by2
      // Divide by 2: toggle on every rising edge
      reg div0_clk_r = 1'b0;
      always @(posedge clk) begin
        div0_clk_r <= ~div0_clk_r;
      end
      assign clk_div_sel_0 = div0_clk_r;
    end
    else if (DIV_0 == 4) begin : gen_div0_by4
      // Divide by 4: two cascaded /2 stages
      reg [1:0] div0_cnt = 2'b00;
      always @(posedge clk) begin
        div0_cnt <= div0_cnt + 1'b1;
      end
      assign clk_div_sel_0 = div0_cnt[1];
    end
    else if (DIV_0 == 8) begin : gen_div0_by8
      // Divide by 8: three cascaded /2 stages
      reg [2:0] div0_cnt = 3'b000;
      always @(posedge clk) begin
        div0_cnt <= div0_cnt + 1'b1;
      end
      assign clk_div_sel_0 = div0_cnt[2];
    end
  endgenerate

  // -------------------------------------------------------------------------
  // Clock Divider 1 (SEL_1_DIV, typically /2)
  // -------------------------------------------------------------------------
  generate
    if (DIV_1 == 1) begin : gen_div1_bypass
      assign clk_div_sel_1 = clk;
    end
    else if (DIV_1 == 2) begin : gen_div1_by2
      reg div1_clk_r = 1'b0;
      always @(posedge clk) begin
        div1_clk_r <= ~div1_clk_r;
      end
      assign clk_div_sel_1 = div1_clk_r;
    end
    else if (DIV_1 == 4) begin : gen_div1_by4
      reg [1:0] div1_cnt = 2'b00;
      always @(posedge clk) begin
        div1_cnt <= div1_cnt + 1'b1;
      end
      assign clk_div_sel_1 = div1_cnt[1];
    end
    else if (DIV_1 == 8) begin : gen_div1_by8
      reg [2:0] div1_cnt = 3'b000;
      always @(posedge clk) begin
        div1_cnt <= div1_cnt + 1'b1;
      end
      assign clk_div_sel_1 = div1_cnt[2];
    end
  endgenerate

  // -------------------------------------------------------------------------
  // Clock Mux with Synchronization
  // -------------------------------------------------------------------------
  // Synchronize the select signal to prevent glitches during switching.
  // The synchronization is done in the source clock domain (clk).
  //
  // Note: This is a behavioral mux. The Efinity synthesis tool will map
  // this to dedicated clock mux resources in the Efinix clock network.
  // For glitch-free operation, ensure clk_sel changes only when both
  // divided clocks are stable.

  reg clk_sel_sync1 = 1'b0;
  reg clk_sel_sync2 = 1'b0;

  always @(posedge clk) begin
    clk_sel_sync1 <= clk_sel;
    clk_sel_sync2 <= clk_sel_sync1;
  end

  // Clock output mux
  // clk_sel = 0: Use SEL_0_DIV divided clock (typically /4 for 2R2T)
  // clk_sel = 1: Use SEL_1_DIV divided clock (typically /2 for 1R1T)
  assign clk_out = clk_sel_sync2 ? clk_div_sel_1 : clk_div_sel_0;

endmodule
