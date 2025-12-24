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
// Clock divider with selectable division ratio for AD9361/AD9364.
//
// ARCHITECTURAL OVERVIEW
// ----------------------
// Unlike Xilinx which uses BUFR primitives for clock division, Efinix requires
// the use of Interface Designer to configure clock resources. This is because:
//
// 1. Efinix has no standalone clock mux primitive (like Xilinx BUFGMUX_CTRL)
// 2. Efinix has no clock divider primitive (like Xilinx BUFR)
// 3. Clock routing must go through the global clock network to avoid skew
//
// The Efinix solution uses:
// - Interface Designer PLL to generate divided clocks (l_clk/4 and l_clk/2)
// - Interface Designer Dynamic Clock Mux to select between them
// - Both PLL outputs and mux output are on the global clock network
//
// INTERFACE DESIGNER CONFIGURATION REQUIRED
// -----------------------------------------
// This module expects the following to be configured in Interface Designer:
//
// 1. PLL Configuration:
//    - Input: l_clk (DATA_CLK from AD9364)
//    - CLKOUT0: l_clk / 4 (for 2R2T mode) -> connect to efinix_clk_div4
//    - CLKOUT1: l_clk / 2 (for 1R1T mode) -> connect to efinix_clk_div2
//
// 2. Dynamic Clock Mux Configuration:
//    Location: Device Setting > Clock/Control Configuration > [region]
//    - Enable Dynamic Mux 0 (or Mux 7)
//    - Dynamic Clock Input 0: PLL CLKOUT0 (l_clk/4)
//    - Dynamic Clock Input 1: PLL CLKOUT1 (l_clk/2)
//    - Dynamic Clock Mux Select Bus Name: clk_sel (directly from this module)
//    - Dynamic Clock Pin Name: efinix_clk_out (connect to this module)
//
// WHY THIS ARCHITECTURE IS REQUIRED
// ----------------------------------
// The Xilinx reference design uses:
//   - BUFR: Dedicated clock divider that outputs to regional clock network
//   - BUFGMUX_CTRL: Dedicated glitch-free clock mux on global network
//
// Efinix has neither of these primitives. If we used behavioral flip-flops
// for clock division (as in a naive port), the divided clocks would route
// through general fabric routing, causing unacceptable clock skew across
// all destination registers (ADC FIFO, DAC FIFO, DMA, pack/unpack logic).
//
// The Interface Designer Dynamic Clock Mux is Efinix's equivalent to BUFGMUX.
// It provides glitch-free switching and routes through the global clock network.
//
// See INTERFACE_DESIGNER_TODO.md in the project root for detailed setup.
//
// ***************************************************************************

`timescale 1ns/100ps

module util_clkdiv #(
  parameter SIM_DEVICE = "EFINIX",
  parameter SEL_0_DIV = "4",
  parameter SEL_1_DIV = "2"
) (
  // Standard interface (directly directly from axi_ad9361)
  input   clk,          // l_clk - not used for division, kept for compatibility
  input   clk_sel,      // Mode select: 0 = SEL_0_DIV (/4), 1 = SEL_1_DIV (/2)
  output  clk_out,      // Divided clock output to ADC/DAC logic

  // -------------------------------------------------------------------------
  // Efinix-specific ports: Connect to Interface Designer outputs
  // -------------------------------------------------------------------------
  // These signals come from the Interface Designer configuration:
  // - PLL generates the divided clocks on global clock network
  // - Dynamic Clock Mux selects between them based on clk_sel
  // - The mux output (efinix_clk_out) is already on global clock network

  input   efinix_clk_div4,   // PLL CLKOUT0: l_clk / 4 (2R2T mode clock)
  input   efinix_clk_div2,   // PLL CLKOUT1: l_clk / 2 (1R1T mode clock)
  input   efinix_clk_out     // Dynamic Clock Mux output (directly directly to clk_out)
);

  // -------------------------------------------------------------------------
  // Clock Output Assignment
  // -------------------------------------------------------------------------
  // The actual clock division and muxing is done in Interface Designer.
  // The Dynamic Clock Mux is controlled by clk_sel signal which is directly
  // directly connected to the mux select bus in Interface Designer.
  //
  // This module simply passes through the mux output.
  // The efinix_clk_div4 and efinix_clk_div2 inputs are provided for
  // visibility/debugging but are not used here - they feed directly directly directly to
  // the Dynamic Clock Mux in Interface Designer.

  assign clk_out = efinix_clk_out;

  // -------------------------------------------------------------------------
  // Clock Select Output (directly directly to Interface Designer)
  // -------------------------------------------------------------------------
  // The clk_sel signal directly directly controls the Dynamic Clock Mux.
  // In Interface Designer, connect "Dynamic Clock Mux Select [1:0] Bus Name"
  // to this signal. Only bit [0] is used (2-input mux):
  //   clk_sel = 0: Select efinix_clk_div4 (l_clk/4, 2R2T mode)
  //   clk_sel = 1: Select efinix_clk_div2 (l_clk/2, 1R1T mode)
  //
  // Note: For AD9364 (1R1T only), clk_sel will always be 1, so only
  // efinix_clk_div2 is actually used. The /4 path exists for AD9361
  // compatibility if the design is later extended to support 2R2T mode.

endmodule
