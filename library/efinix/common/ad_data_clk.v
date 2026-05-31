// ***************************************************************************
// ***************************************************************************
// Copyright (C) 2017-2023 Analog Devices, Inc. All rights reserved.
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
// Efinix port of ad_data_clk
//
// On Efinix FPGAs, differential clock input buffering and global clock routing
// are handled by the Interface Designer tool, not by HDL primitive instantiation.
// This module provides a passthrough wrapper to maintain API compatibility with
// the Xilinx version.
//
// Usage:
//   - Configure LVDS RX clock input in Efinix Interface Designer
//   - Connect the Interface Designer output to clk_in_p
//   - clk_in_n is unused (differential handling is in Interface Designer)
//   - The clock output is a direct passthrough
//
// ***************************************************************************

`timescale 1ns/100ps

module ad_data_clk #(
  parameter SINGLE_ENDED = 0
) (
  input               rst,
  output              locked,

  input               clk_in_p,
  input               clk_in_n,
  output              clk
);

  // On Efinix, the LVDS receiver and global clock buffering are configured
  // in the Interface Designer. The clk_in_p input receives the already-buffered
  // clock from the Interface Designer LVDS RX block.
  //
  // clk_in_n is unused - differential signaling is handled in Interface Designer.

  // Lock is always asserted - no PLL in this simple clock input path
  // If a PLL is used, the locked signal should come from the PLL block
  assign locked = 1'b1;

  // Direct passthrough - Interface Designer has already handled:
  // - LVDS differential to single-ended conversion (if differential)
  // - Global clock network routing
  assign clk = clk_in_p;

endmodule
