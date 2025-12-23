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
// Efinix port of ad_data_out
//
// On Efinix FPGAs, the following functions are handled by the Interface Designer
// tool rather than HDL primitive instantiation:
//   - LVDS differential output buffering (equivalent to Xilinx OBUFDS)
//   - DDR output generation (DDIO blocks, equivalent to Xilinx ODDR)
//
// IMPORTANT: Efinix FPGAs do NOT have programmable output delay (ODELAY)
// equivalent. The IODELAY_ENABLE parameter is accepted for API compatibility
// but has no effect. Timing adjustments must be handled through:
//   - Careful PCB trace length matching
//   - Timing constraints in the Efinity toolchain
//
// Usage:
//   - Configure LVDS TX with DDIO output in Efinix Interface Designer
//   - tx_data_out_p connects to the Interface Designer DDIO input
//   - tx_data_out_n is unused (differential handling is in Interface Designer)
//   - The Interface Designer DDIO block needs HI/LO inputs for DDR data
//
// Interface Designer Configuration:
//   - Create GPIO (LVDS TX) block for each data line
//   - Enable DDR (DDIO) output mode
//   - Connect tx_clk to the DDIO clock input
//   - Connect tx_data_p to DDIO HI input
//   - Connect tx_data_n to DDIO LO input
//
// ***************************************************************************

`timescale 1ns/100ps

module ad_data_out #(
  // Parameters maintained for API compatibility with Xilinx version
  parameter   FPGA_TECHNOLOGY = 0,
  parameter   SINGLE_ENDED = 0,
  parameter   IDDR_CLK_EDGE = "SAME_EDGE",
  // ODELAY parameters - NOT SUPPORTED on Efinix, kept for compatibility
  parameter   ODELAY_TYPE = "VAR_LOAD",
  parameter   DELAY_FORMAT = "COUNT",
  parameter   US_DELAY_TYPE = "VAR_LOAD",
  parameter   IODELAY_ENABLE = 0,
  parameter   IODELAY_CTRL = 0,
  parameter   IODELAY_GROUP = "dev_if_delay_group",
  parameter   REFCLK_FREQUENCY = 200
) (

  // data interface
  input               tx_clk,
  input               tx_data_p,
  input               tx_data_n,
  output              tx_data_out_p,
  output              tx_data_out_n,

  // delay-data interface (active but no-op on Efinix - no ODELAY)
  input               up_clk,
  input               up_dld,
  input       [ 4:0]  up_dwdata,
  output      [ 4:0]  up_drdata,

  // delay-cntrl interface
  input               delay_clk,
  input               delay_rst,
  output              delay_locked
);

  // -------------------------------------------------------------------------
  // Efinix Implementation Notes:
  // -------------------------------------------------------------------------
  // On Efinix FPGAs, the physical I/O primitives are configured through
  // the Interface Designer tool, not through HDL instantiation:
  //
  // 1. LVDS Output Buffer:
  //    - Configure in Interface Designer as LVDS TX GPIO
  //    - The single-ended-to-differential conversion happens in the I/O tile
  //    - tx_data_out_p connects to the Interface Designer DDIO/GPIO input
  //    - tx_data_out_n is unused (grounded internally)
  //
  // 2. DDR Output (DDIO):
  //    - Configure in Interface Designer with DDR output mode enabled
  //    - The DDIO block generates output data on both clock edges
  //    - Interface Designer expects two input signals (HI/LO)
  //    - These should be connected from this module appropriately
  //
  // 3. Output Delay (ODELAY):
  //    - NOT AVAILABLE on Efinix FPGAs
  //    - The delay interface signals are present but non-functional
  //    - up_drdata always returns 0 (no delay taps)
  //    - delay_locked is always asserted
  //
  // -------------------------------------------------------------------------

  // Delay interface - no ODELAY on Efinix, always report locked with 0 delay
  assign delay_locked = 1'b1;
  assign up_drdata = 5'd0;

  // -------------------------------------------------------------------------
  // DDR Output Implementation
  // -------------------------------------------------------------------------
  // On Efinix, the Interface Designer DDIO block requires:
  //   - A clock input (tx_clk)
  //   - A HI data input (data to output on rising edge)
  //   - A LO data input (data to output on falling edge)
  //
  // The Xilinx ODDR has D1 output on rising edge, D2 on falling edge.
  // Note: In the Xilinx version, D1=tx_data_n and D2=tx_data_p (swapped).
  //
  // For Efinix, we register the data and provide it to the Interface Designer
  // DDIO block through tx_data_out_p (HI) and tx_data_out_n (LO).
  //
  // Since Interface Designer handles the actual DDR conversion, this module
  // provides registered outputs that can be connected to DDIO inputs.
  // -------------------------------------------------------------------------

  reg tx_data_p_reg;
  reg tx_data_n_reg;

  always @(posedge tx_clk) begin
    // Register the input data for clean timing
    // tx_data_p goes to HI (rising edge output)
    // tx_data_n goes to LO (falling edge output)
    // Note: Follow the Xilinx ODDR convention where D1->Q on rising, D2->Q on falling
    tx_data_p_reg <= tx_data_p;
    tx_data_n_reg <= tx_data_n;
  end

  // Connect to Interface Designer DDIO block inputs
  // tx_data_out_p -> DDIO HI input (or direct GPIO if SDR mode used in Interface Designer)
  // tx_data_out_n -> DDIO LO input (unused if SINGLE_ENDED or SDR mode)
  assign tx_data_out_p = tx_data_p_reg;
  assign tx_data_out_n = tx_data_n_reg;

endmodule
