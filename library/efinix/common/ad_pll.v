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
// Efinix port of ad_mmcm_drp (renamed to ad_pll)
//
// PLL wrapper with DRP-like interface for clock generation.
//
// On Efinix FPGAs, PLLs are configured through Interface Designer, not
// through HDL primitives. This module provides:
//   1. A compatible interface for the ADI HDL framework
//   2. Passthrough for PLL outputs configured in Interface Designer
//   3. Stub DRP interface (dynamic reconfiguration not supported)
//
// INTEGRATION:
// ------------
// Unlike Xilinx where MMCM is instantiated in HDL, Efinix PLLs are created
// in Interface Designer. This module expects external PLL connections:
//
// 1. In Interface Designer, create a PLL with:
//    - Input: Reference clock (frequency per MMCM_CLKIN_PERIOD)
//    - Output 0: mmcm_clk_0 frequency/phase per parameters
//    - Output 1: mmcm_clk_1 frequency/phase per parameters
//    - Output 2: mmcm_clk_2 frequency/phase per parameters
//    - Locked output signal
//
// 2. In your top-level or system integration:
//    - Instantiate the Interface Designer PLL wrapper
//    - Connect PLL outputs to this module's efinix_* ports
//
// 3. This module passes through the clocks and provides DRP stub.
//
// LIMITATIONS:
// ------------
// - DRP (Dynamic Reconfiguration Port) is NOT functional
// - clk2 input and clk_sel are not used (single input only)
// - All PLL parameters are fixed at synthesis time
//
// ***************************************************************************

`timescale 1ns/100ps

module ad_pll #(
  // Parameters for documentation - actual values set in Interface Designer
  parameter   FPGA_TECHNOLOGY = 0,
  parameter   MMCM_CLKIN_PERIOD  = 1.667,
  parameter   MMCM_CLKIN2_PERIOD  = 1.667,
  parameter   MMCM_VCO_DIV  = 6,
  parameter   MMCM_VCO_MUL = 12.000,
  parameter   MMCM_CLK0_DIV = 2.000,
  parameter   MMCM_CLK0_PHASE = 0.000,
  parameter   MMCM_CLK1_DIV = 6,
  parameter   MMCM_CLK1_PHASE = 0.000,
  parameter   MMCM_CLK2_DIV = 2.000,
  parameter   MMCM_CLK2_PHASE = 0.000
) (

  // Clock inputs
  input                   clk,
  input                   clk2,        // Not used on Efinix (single clock input)
  input                   clk_sel,     // Not used on Efinix (no runtime switching)
  input                   mmcm_rst,

  // Clock outputs
  output                  mmcm_clk_0,
  output                  mmcm_clk_1,
  output                  mmcm_clk_2,

  // DRP interface (active but no-op on Efinix)
  input                   up_clk,
  input                   up_rstn,
  input                   up_drp_sel,
  input                   up_drp_wr,
  input       [11:0]      up_drp_addr,
  input       [15:0]      up_drp_wdata,
  output  reg [15:0]      up_drp_rdata,
  output  reg             up_drp_ready,
  output  reg             up_drp_locked,

  // -------------------------------------------------------------------------
  // Efinix-specific ports: Connect to Interface Designer PLL outputs
  // -------------------------------------------------------------------------
  // Configure PLL in Interface Designer with appropriate frequencies,
  // then connect the PLL wrapper outputs to these ports.

  input                   efinix_clk_0,    // PLL output clock 0
  input                   efinix_clk_1,    // PLL output clock 1
  input                   efinix_clk_2,    // PLL output clock 2
  input                   efinix_locked    // PLL locked indicator
);

  // Internal signal for combined lock status
  wire pll_locked_internal;

  // PLL is considered locked when:
  // - Interface Designer PLL reports locked
  // - Reset is not asserted
  assign pll_locked_internal = efinix_locked & ~mmcm_rst;

  // -------------------------------------------------------------------------
  // DRP Interface Stub
  // -------------------------------------------------------------------------
  // Efinix PLLs do not support dynamic reconfiguration. We provide immediate
  // acknowledgment for compatibility with the ADI framework.

  reg up_drp_locked_m1 = 1'b0;

  always @(posedge up_clk) begin
    if (up_rstn == 1'b0) begin
      up_drp_rdata <= 16'd0;
      up_drp_ready <= 1'b0;
      up_drp_locked_m1 <= 1'b0;
      up_drp_locked <= 1'b0;
    end else begin
      // Immediate acknowledge for any DRP access (read returns 0)
      up_drp_ready <= up_drp_sel;
      up_drp_rdata <= 16'd0;

      // Synchronize locked signal
      up_drp_locked_m1 <= pll_locked_internal;
      up_drp_locked <= up_drp_locked_m1;
    end
  end

  // -------------------------------------------------------------------------
  // Clock Output Passthrough
  // -------------------------------------------------------------------------
  assign mmcm_clk_0 = efinix_clk_0;
  assign mmcm_clk_1 = efinix_clk_1;
  assign mmcm_clk_2 = efinix_clk_2;

endmodule
