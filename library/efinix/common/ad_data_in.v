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
// Efinix port of ad_data_in
//
// On Efinix FPGAs, the following functions are handled by the Interface Designer
// tool rather than HDL primitive instantiation:
//   - LVDS differential input buffering (equivalent to Xilinx IBUFDS)
//   - DDR input capture (DDIO blocks, equivalent to Xilinx IDDR)
//
// IMPORTANT: Efinix FPGAs do NOT have programmable input delay (IDELAY)
// equivalent. The IODELAY_ENABLE parameter is accepted for API compatibility
// but has no effect. Timing adjustments must be handled through:
//   - Careful PCB trace length matching
//   - Software/firmware calibration at runtime
//   - Timing constraints in the Efinity toolchain
//
// Usage:
//   - Configure LVDS RX with DDIO input in Efinix Interface Designer
//   - Connect Interface Designer outputs to rx_data_in_p (DDR data from DDIO)
//   - For DDR mode: rx_data_in_p carries the DDIO output {Q1, Q0} or similar
//   - rx_data_in_n is unused (differential handling is in Interface Designer)
//
// Interface Designer Configuration:
//   - Create GPIO (LVDS RX) block for each data line
//   - Enable DDR (DDIO) input mode
//   - Connect rx_clk to the DDIO clock input
//   - The DDIO outputs (typically named xxx_HI and xxx_LO) map to rx_data_p/n
//
// ***************************************************************************

`timescale 1ns/100ps

module ad_data_in #(
  // Parameters maintained for API compatibility with Xilinx version
  parameter   SINGLE_ENDED = 0,
  parameter   FPGA_TECHNOLOGY = 0,
  parameter   DDR_SDR_N = 1,
  parameter   IDDR_CLK_EDGE = "SAME_EDGE",
  // IDELAY parameters - NOT SUPPORTED on Efinix, kept for compatibility
  parameter   IDELAY_TYPE = "VAR_LOAD",
  parameter   DELAY_FORMAT = "COUNT",
  parameter   US_DELAY_TYPE = "VAR_LOAD",
  parameter   IODELAY_ENABLE = 1,
  parameter   IODELAY_CTRL = 0,
  parameter   IODELAY_GROUP = "dev_if_delay_group",
  parameter   REFCLK_FREQUENCY = 200
) (

  // data interface
  input               rx_clk,
  input               rx_data_in_p,
  input               rx_data_in_n,
  output              rx_data_p,
  output              rx_data_n,

  // delay-data interface (active but no-op on Efinix - no IDELAY)
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
  // 1. LVDS Input Buffer:
  //    - Configure in Interface Designer as LVDS RX GPIO
  //    - The differential-to-single-ended conversion happens in the I/O tile
  //    - rx_data_in_p receives the already-converted single-ended signal
  //    - rx_data_in_n is unused (tied off internally)
  //
  // 2. DDR Input (DDIO):
  //    - Configure in Interface Designer with DDR input mode enabled
  //    - The DDIO block captures data on both clock edges
  //    - Interface Designer generates two output signals (HI/LO)
  //    - These should be connected to this module appropriately
  //
  // 3. Input Delay (IDELAY):
  //    - NOT AVAILABLE on Efinix FPGAs
  //    - The delay interface signals are present but non-functional
  //    - up_drdata always returns 0 (no delay taps)
  //    - delay_locked is always asserted
  //    - Calibration must be done via software or external means
  //
  // -------------------------------------------------------------------------

  // Delay interface - no IDELAY on Efinix, always report locked with 0 delay
  assign delay_locked = 1'b1;
  assign up_drdata = 5'd0;

  // -------------------------------------------------------------------------
  // DDR vs SDR Mode
  // -------------------------------------------------------------------------
  // For DDR mode on Efinix:
  //   The Interface Designer DDIO block provides two outputs per input pin,
  //   capturing data on rising and falling edges. These outputs need to be
  //   properly connected based on your Interface Designer configuration.
  //
  //   Option A: If Interface Designer provides separate HI/LO signals,
  //             connect them directly to rx_data_p and rx_data_n externally
  //             and instantiate this module in SDR mode.
  //
  //   Option B: If you want to handle DDR internally (shown below),
  //             the rx_data_in_p should come from the Interface Designer
  //             DDIO output, and we register it here.
  //
  // For this implementation, we assume the Interface Designer DDIO block
  // is used, and this module receives the already-captured DDR data.
  // -------------------------------------------------------------------------

  generate
    if (DDR_SDR_N == 1'b1) begin : gen_ddr_mode
      // DDR mode
      // On Efinix, the DDIO capture is done in the Interface Designer.
      // The signals arriving at this module are already captured.
      //
      // If Interface Designer is configured to output two separate signals
      // (e.g., data_hi and data_lo), those should be connected to rx_data_in_p
      // and rx_data_in_n respectively at the top level.
      //
      // For now, we provide a registered passthrough that can be adapted
      // based on the actual Interface Designer configuration.

      reg rx_data_p_reg;
      reg rx_data_n_reg;

      always @(posedge rx_clk) begin
        // Rising edge data (typically the "HI" output from DDIO)
        rx_data_p_reg <= rx_data_in_p;
        // Falling edge data (typically the "LO" output from DDIO)
        // On Efinix, this would come from Interface Designer as a separate signal
        // Here we use rx_data_in_n as a placeholder for the second DDIO output
        rx_data_n_reg <= rx_data_in_n;
      end

      assign rx_data_p = rx_data_p_reg;
      assign rx_data_n = rx_data_n_reg;

    end else begin : gen_sdr_mode
      // SDR mode - simple passthrough
      // rx_data_in_p comes from Interface Designer LVDS RX or GPIO input
      reg rx_data_p_reg;

      always @(posedge rx_clk) begin
        rx_data_p_reg <= rx_data_in_p;
      end

      assign rx_data_p = rx_data_p_reg;
      assign rx_data_n = 1'b0;
    end
  endgenerate

endmodule
