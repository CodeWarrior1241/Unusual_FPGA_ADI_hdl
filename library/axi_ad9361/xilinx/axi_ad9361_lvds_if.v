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

`timescale 1ns/100ps

module axi_ad9361_lvds_if #(

  parameter   FPGA_TECHNOLOGY = 0,
  parameter   DAC_IODELAY_ENABLE = 0,
  parameter   IO_DELAY_GROUP = "dev_if_delay_group",
  parameter   IODELAY_CTRL = 1,
  parameter   CLK_DESKEW = 0,
  parameter   USE_SSI_CLK = 1,
  parameter   DELAY_REFCLK_FREQUENCY = 200,
  parameter   RX_NODPA = 0
) (

  // physical interface (receive)

  input               rx_clk_in_p,
  input               rx_clk_in_n,
  input               rx_frame_in_p,
  input               rx_frame_in_n,
  input   [ 5:0]      rx_data_in_p,
  input   [ 5:0]      rx_data_in_n,

  // physical interface (transmit)

  output              tx_clk_out_p,
  output              tx_clk_out_n,
  output              tx_frame_out_p,
  output              tx_frame_out_n,
  output  [ 5:0]      tx_data_out_p,
  output  [ 5:0]      tx_data_out_n,

  // ensm control

  output              enable,
  output              txnrx,

  // clock (common to both receive and transmit)

  input               rst,
  input               clk,
  output              l_clk,

  // receive data path interface

  output              adc_valid,
  output  [47:0]      adc_data,
  output              adc_status,
  input               adc_r1_mode,
  input               adc_ddr_edgesel,

  // transmit data path interface

  input               dac_valid,
  input   [47:0]      dac_data,
  input               dac_clksel,
  input               dac_r1_mode,

  // tdd interface

  input               tdd_enable,
  input               tdd_txnrx,
  input               tdd_mode,

  // delay interface

  input               mmcm_rst,
  input               up_clk,
  input               up_rstn,
  input               up_enable,
  input               up_txnrx,
  input   [ 6:0]      up_adc_dld,
  input   [34:0]      up_adc_dwdata,
  output  [34:0]      up_adc_drdata,
  input   [ 9:0]      up_dac_dld,
  input   [49:0]      up_dac_dwdata,
  output  [49:0]      up_dac_drdata,
  input               delay_clk,
  input               delay_rst,
  output              delay_locked,

  // drp interface

  input               up_drp_sel,
  input               up_drp_wr,
  input   [11:0]      up_drp_addr,
  input   [31:0]      up_drp_wdata,
  output  [31:0]      up_drp_rdata,
  output              up_drp_ready,
  output              up_drp_locked
);

  // internal registers

  reg                 rx_r1_mode = 'd0;
  reg                 rx_locked_m1 = 'd0;
  reg                 rx_locked = 'd0;
  reg     [ 1:0]      rx_frame = 'd0;
  reg     [ 5:0]      rx_data_1 = 'd0;
  reg     [ 5:0]      rx_data_0 = 'd0;
  reg                 adc_valid_p = 'd0;
  reg     [47:0]      adc_data_p = 'd0;
  reg                 adc_status_p = 'd0;
  reg                 adc_valid_int = 'd0;
  reg     [47:0]      adc_data_int = 'd0;
  reg                 adc_status_int = 'd0;
  reg     [ 1:0]      tx_data_sel = 'd0;
  reg     [47:0]      tx_data = 'd0;
  reg     [ 1:0]      tx_clk_p = 'd0;
  reg                 tx_frame_p = 'd0;
  reg     [ 5:0]      tx_data_0_p = 'd0;
  reg     [ 5:0]      tx_data_1_p = 'd0;
  reg     [ 1:0]      tx_clk = 'd0;
  reg                 tx_frame = 'd0;
  reg     [ 5:0]      tx_data_0 = 'd0;
  reg     [ 5:0]      tx_data_1 = 'd0;
  reg                 up_enable_int = 'd0;
  reg                 up_txnrx_int = 'd0;
  reg                 enable_up_m1 = 'd0;
  reg                 txnrx_up_m1 = 'd0;
  reg                 enable_up = 'd0;
  reg                 txnrx_up = 'd0;
  reg                 enable_int = 'd0;
  reg                 txnrx_int = 'd0;
  reg                 enable_int_p = 'd0;
  reg                 txnrx_int_p = 'd0;

  // internal signals

  wire    [ 5:0]      rx_data_1_s;
  wire    [ 5:0]      rx_data_0_s;
  wire    [ 1:0]      rx_frame_s;
  wire                locked_s;
  wire                rx_error;

  // drp interface signals

  assign up_drp_rdata = 32'd0;
  assign up_drp_ready = 1'd0;
  assign up_drp_locked = 1'd1;

  // r1mode

  generate if (CLK_DESKEW) begin

    reg adc_r1_mode_n = 'd0;

    always @(negedge clk) begin
      adc_r1_mode_n <= adc_r1_mode;
    end

    always @(posedge l_clk) begin
      rx_r1_mode <= adc_r1_mode_n;
    end

  end else begin /* CLK_DESKEW == 0 */

    always @(posedge l_clk) begin
      rx_r1_mode <= adc_r1_mode;
    end

  end
  endgenerate

  // adc-status

  assign delay_locked = locked_s;

  always @(posedge l_clk) begin
    rx_locked_m1 <= locked_s;
    rx_locked <= rx_locked_m1;
  end

  // intel-equivalence

  always @(posedge l_clk) begin
    rx_frame <= rx_frame_s;
    rx_data_1 <= rx_data_1_s;
    rx_data_0 <= rx_data_0_s;
  end

  // frame check
  assign rx_error = ^rx_frame;

  // delineation

  always @(posedge l_clk) begin
      case ({rx_r1_mode, rx_frame_s, rx_frame})
        5'b01111: begin
          adc_valid_p <= 1'b0;
          adc_data_p[23:12] <= {rx_data_1, rx_data_1_s};
          adc_data_p[11: 0] <= {rx_data_0, rx_data_0_s};
        end
        5'b00000: begin
          adc_valid_p <= 1'b1;
          adc_data_p[47:36] <= {rx_data_1, rx_data_1_s};
          adc_data_p[35:24] <= {rx_data_0, rx_data_0_s};
        end
        5'b10011: begin
          adc_valid_p <= 1'b1;
          adc_data_p[47:24] <= 24'd0;
          adc_data_p[23:12] <= {rx_data_1, rx_data_1_s};
          adc_data_p[11: 0] <= {rx_data_0, rx_data_0_s};
        end
        default: begin
          adc_valid_p <= 1'b0;
        end
      endcase
  end

  // adc-status

  always @(posedge l_clk) begin
    adc_status_p <= ~rx_error & rx_locked;
  end

  // transfer to common clock

  generate if (CLK_DESKEW) begin

    reg         adc_valid_n = 'd0;
    reg [47:0]  adc_data_n = 'd0;
    reg         adc_status_n = 'd0;

    always @(negedge l_clk) begin
      adc_valid_n <= adc_valid_p;
      adc_data_n <= adc_data_p;
      adc_status_n <= adc_status_p;
    end

    always @(posedge clk) begin
      adc_valid_int <= adc_valid_n;
      adc_data_int <= adc_data_n;
      adc_status_int <= adc_status_n;
    end

    assign adc_valid = adc_valid_int;
    assign adc_data = adc_data_int;
    assign adc_status = adc_status_int;

  end else begin /* CLK_DESKEW == 0 */

    always @(posedge clk) begin
      adc_valid_int <= adc_valid_p;
      adc_data_int <= adc_data_p;
      adc_status_int <= adc_status_p;
    end

    assign adc_valid = adc_valid_int;
    assign adc_data = adc_data_int;
    assign adc_status = adc_status_int;

  end
  endgenerate

  // dac-tx interface

  always @(posedge clk) begin
    if (dac_valid == 1'b1) begin
      tx_data_sel <= 2'b00;
    end else begin
      tx_data_sel <= tx_data_sel + 1'b1;
    end
    if (dac_valid == 1'b1) begin
      tx_data <= dac_data;
    end
  end

  always @(posedge clk) begin
    tx_clk_p <= {~dac_clksel, dac_clksel};
  end

  always @(posedge clk) begin
    case ({dac_r1_mode, tx_data_sel})
      3'b000: begin
        tx_frame_p <= 1'b1;
        tx_data_0_p <= tx_data[11:6];
        tx_data_1_p <= tx_data[23:18];
      end
      3'b001: begin
        tx_frame_p <= 1'b1;
        tx_data_0_p <= tx_data[5:0];
        tx_data_1_p <= tx_data[17:12];
      end
      3'b010: begin
        tx_frame_p <= 1'b0;
        tx_data_0_p <= tx_data[35:30];
        tx_data_1_p <= tx_data[47:42];
      end
      3'b011: begin
        tx_frame_p <= 1'b0;
        tx_data_0_p <= tx_data[29:24];
        tx_data_1_p <= tx_data[41:36];
      end
      3'b100: begin
        tx_frame_p <= 1'b1;
        tx_data_0_p <= tx_data[11:6];
        tx_data_1_p <= tx_data[23:18];
      end
      3'b101: begin
        tx_frame_p <= 1'b0;
        tx_data_0_p <= tx_data[5:0];
        tx_data_1_p <= tx_data[17:12];
      end
      default: begin
        tx_frame_p <= 1'b0;
        tx_data_0_p <= 6'd0;
        tx_data_1_p <= 6'd0;
      end
    endcase
  end

  // transfer to local clock

  generate if (CLK_DESKEW) begin

    reg [ 1:0]  tx_clk_n = 'd0;
    reg         tx_frame_n = 'd0;
    reg [ 5:0]  tx_data_0_n = 'd0;
    reg [ 5:0]  tx_data_1_n = 'd0;

    always @(negedge clk) begin
      tx_clk_n <= tx_clk_p;
      tx_frame_n <= tx_frame_p;
      tx_data_0_n <= tx_data_0_p;
      tx_data_1_n <= tx_data_1_p;
    end

    always @(posedge l_clk) begin
      tx_clk <= tx_clk_n;
      tx_frame <= tx_frame_n;
      tx_data_0 <= tx_data_0_n;
      tx_data_1 <= tx_data_1_n;
    end

  end else begin /* CLK_DESKEW == 0 */

    always @(posedge l_clk) begin
      tx_clk <= tx_clk_p;
      tx_frame <= tx_frame_p;
      tx_data_0 <= tx_data_0_p;
      tx_data_1 <= tx_data_1_p;
    end

  end
  endgenerate

  // tdd/ensm control

  always @(posedge up_clk) begin
    up_enable_int <= up_enable;
    up_txnrx_int <= up_txnrx;
  end

  always @(posedge clk or posedge rst) begin
    if (rst == 1'b1) begin
      enable_up_m1 <= 1'b0;
      txnrx_up_m1 <= 1'b0;
      enable_up <= 1'b0;
      txnrx_up <= 1'b0;
    end else begin
      enable_up_m1 <= up_enable_int;
      txnrx_up_m1 <= up_txnrx_int;
      enable_up <= enable_up_m1;
      txnrx_up <= txnrx_up_m1;
    end
  end

  always @(posedge clk) begin
    if (tdd_mode == 1'b1) begin
      enable_int <= tdd_enable;
      txnrx_int <= tdd_txnrx;
    end else begin
      enable_int <= enable_up;
      txnrx_int <= txnrx_up;
    end
  end

  generate if (CLK_DESKEW) begin

    reg enable_int_n = 'd0;
    reg txnrx_int_n = 'd0;

    always @(negedge clk) begin
      enable_int_n <= enable_int;
      txnrx_int_n <= txnrx_int;
    end

    always @(posedge l_clk) begin
      enable_int_p <= enable_int_n;
      txnrx_int_p <= txnrx_int_n;
    end

  end else begin /* CLK_DESKEW == 0 */

    always @(posedge l_clk) begin
      enable_int_p <= enable_int;
      txnrx_int_p <= txnrx_int;
    end

  end
  endgenerate

  // receive data interface, ibuf -> idelay -> iddr

  genvar i;

`ifdef AU15P_BANK86_WORKAROUND
  // ====================================================================
  // AU15P bank 86 (HD I/O) workaround — rx_data[5] is single-ended.
  // ====================================================================
  // rx data bits [4:0] — differential (HP bank 66)
  generate
  for (i = 0; i < 5; i = i + 1) begin: g_rx_data
  ad_data_in #(
    .FPGA_TECHNOLOGY (FPGA_TECHNOLOGY),
    .IODELAY_CTRL (0),
    .IODELAY_GROUP (IO_DELAY_GROUP),
    .REFCLK_FREQUENCY (DELAY_REFCLK_FREQUENCY)
  ) i_rx_data (
    .rx_clk (l_clk),
    .rx_data_in_p (rx_data_in_p[i]),
    .rx_data_in_n (rx_data_in_n[i]),
    .rx_data_p (rx_data_1_s[i]),
    .rx_data_n (rx_data_0_s[i]),
    .up_clk (up_clk),
    .up_dld (up_adc_dld[i]),
    .up_dwdata (up_adc_dwdata[((i*5)+4):(i*5)]),
    .up_drdata (up_adc_drdata[((i*5)+4):(i*5)]),
    .delay_clk (delay_clk),
    .delay_rst (delay_rst),
    .delay_locked ());
  end
  endgenerate

  // rx data bit [5] — single-ended (AU15P HD bank 86, no LVDS support)
  // IODELAY disabled: HD banks cannot host IDELAYE3 primitives.
  ad_data_in #(
    .SINGLE_ENDED (1),
    .FPGA_TECHNOLOGY (FPGA_TECHNOLOGY),
    .IODELAY_ENABLE (0),
    .IODELAY_CTRL (0),
    .IODELAY_GROUP (IO_DELAY_GROUP),
    .REFCLK_FREQUENCY (DELAY_REFCLK_FREQUENCY)
  ) i_rx_data_5 (
    .rx_clk (l_clk),
    .rx_data_in_p (rx_data_in_p[5]),
    .rx_data_in_n (rx_data_in_n[5]),
    .rx_data_p (rx_data_1_s[5]),
    .rx_data_n (rx_data_0_s[5]),
    .up_clk (up_clk),
    .up_dld (up_adc_dld[5]),
    .up_dwdata (up_adc_dwdata[29:25]),
    .up_drdata (up_adc_drdata[29:25]),
    .delay_clk (delay_clk),
    .delay_rst (delay_rst),
    .delay_locked ());
`else
  // Stock ADI: 6 LVDS RX pairs, all differential.
  generate
  for (i = 0; i < 6; i = i + 1) begin: g_rx_data
  ad_data_in #(
    .FPGA_TECHNOLOGY (FPGA_TECHNOLOGY),
    .IODELAY_CTRL (0),
    .IODELAY_GROUP (IO_DELAY_GROUP),
    .REFCLK_FREQUENCY (DELAY_REFCLK_FREQUENCY)
  ) i_rx_data (
    .rx_clk (l_clk),
    .rx_data_in_p (rx_data_in_p[i]),
    .rx_data_in_n (rx_data_in_n[i]),
    .rx_data_p (rx_data_1_s[i]),
    .rx_data_n (rx_data_0_s[i]),
    .up_clk (up_clk),
    .up_dld (up_adc_dld[i]),
    .up_dwdata (up_adc_dwdata[((i*5)+4):(i*5)]),
    .up_drdata (up_adc_drdata[((i*5)+4):(i*5)]),
    .delay_clk (delay_clk),
    .delay_rst (delay_rst),
    .delay_locked ());
  end
  endgenerate
`endif

  // receive frame interface, ibuf -> idelay -> iddr

  ad_data_in #(
    .FPGA_TECHNOLOGY (FPGA_TECHNOLOGY),
    .IODELAY_CTRL (IODELAY_CTRL),
    .IODELAY_GROUP (IO_DELAY_GROUP),
    .REFCLK_FREQUENCY (DELAY_REFCLK_FREQUENCY)
  ) i_rx_frame (
    .rx_clk (l_clk),
    .rx_data_in_p (rx_frame_in_p),
    .rx_data_in_n (rx_frame_in_n),
    .rx_data_p (rx_frame_s[1]),
    .rx_data_n (rx_frame_s[0]),
    .up_clk (up_clk),
    .up_dld (up_adc_dld[6]),
    .up_dwdata (up_adc_dwdata[34:30]),
    .up_drdata (up_adc_drdata[34:30]),
    .delay_clk (delay_clk),
    .delay_rst (delay_rst),
    .delay_locked (locked_s));

`ifdef AU15P_BANK86_WORKAROUND
  //--------------------------------------------------------------------------
  // AU15P additional IDELAYCTRLs — one per nibble containing an IDELAYE3.
  //
  // The ad_data_in module's IODELAY_CTRL=1 path inside the rx_frame instance
  // above instantiates ONE IDELAYCTRL. Per Xilinx UG571, one IDELAYCTRL is
  // required per I/O bank (and on UltraScale+ HRIO, per nibble) containing
  // IDELAY primitives, with matching IODELAY_GROUP. Vivado's IODELAY_GROUP
  // auto-replication does NOT engage in this design (netlist inspection:
  // only the single rx_frame IDELAYCTRL exists, placed in clock region X0Y0
  // far from the IDELAYE3s in clock region X0Y2). The IDELAY taps in
  // unserved nibbles are uncalibrated, so dig_tune's tap sweeps produce no
  // effective change in delay — the LVDS RX data lanes cannot be aligned
  // to the chip's data eye.
  //
  // The 6 LVDS RX IDELAYE3 cells (rx_data[0..4] + rx_frame) place into 5
  // distinct nibbles of bank 66 (clock region X0Y2). Match each with its
  // own IDELAYCTRL via explicit instantiation + XDC LOC.
  //
  //   rx_data[1] @ Y106 -> byte 8 lower nibble (BITSLICE_CONTROL_X0Y16)
  //   rx_data[2] @ Y108 -> byte 8 lower nibble (shares X0Y16)
  //   rx_data[3] @ Y110 -> byte 8 upper nibble (BITSLICE_CONTROL_X0Y17)
  //   rx_frame   @ Y127 -> byte 9 upper nibble (BITSLICE_CONTROL_X0Y19)
  //                        (served by rx_frame's own i_delay_ctrl above,
  //                         LOC-constrained in system_constr.xdc)
  //   rx_data[0] @ Y138 -> byte 10 upper nibble (BITSLICE_CONTROL_X0Y21)
  //   rx_data[4] @ Y151 -> byte 11 upper nibble (BITSLICE_CONTROL_X0Y23)
  //
  // BISC unavailability: each IDELAYCTRL placement causes BISC to run on its
  // nibble at boot, making BITSLICE_0 (lower nibble) or BITSLICE_6 (upper
  // nibble) of that byte unavailable until BISC RDY asserts (~1 ms after
  // bitstream load — well before the AD9361 chip is brought out of reset).
  // Affected ports get UNAVAILABLE_DURING_CALIBRATION in system_constr.xdc.
  //
  // SIM_DEVICE="ULTRASCALE" matches ad_data_in.v's IODELAY_CTRL_SIM_DEVICE
  // localparam (which maps both ULTRASCALE and ULTRASCALE_PLUS to "ULTRASCALE").
  // The IDELAYCTRL primitive's SIM_DEVICE parameter only accepts "7SERIES",
  // "ULTRASCALE", or "VERSAL" — there is no "ULTRASCALE_PLUS" value for this
  // primitive; both UltraScale and UltraScale+ silicon use the "ULTRASCALE"
  // string here. (This differs from IDELAYE3's SIM_DEVICE, which DOES have a
  // distinct "ULTRASCALE_PLUS" value.) Setting it to "ULTRASCALE_PLUS" causes
  // DRC ADEF-911 — Vivado silently falls back to "ULTRASCALE" anyway.
  //
  // NOTE: AXAU15 (HP banks 64/65) also needs per-nibble IDELAYCTRLs because
  // the UltraScale+ HRIO rule applies regardless of HP vs HD. The AXAU15
  // pin layout maps to different BITSLICE_CONTROL sites, so AXAU15 ships
  // its own ifdef block below.
  //--------------------------------------------------------------------------

  (* IODELAY_GROUP = IO_DELAY_GROUP *)
  IDELAYCTRL #(.SIM_DEVICE ("ULTRASCALE")) i_delay_ctrl_byte8_lo (
    .RST    (delay_rst),
    .REFCLK (delay_clk),
    .RDY    ());

  (* IODELAY_GROUP = IO_DELAY_GROUP *)
  IDELAYCTRL #(.SIM_DEVICE ("ULTRASCALE")) i_delay_ctrl_byte8_hi (
    .RST    (delay_rst),
    .REFCLK (delay_clk),
    .RDY    ());

  (* IODELAY_GROUP = IO_DELAY_GROUP *)
  IDELAYCTRL #(.SIM_DEVICE ("ULTRASCALE")) i_delay_ctrl_byte10_hi (
    .RST    (delay_rst),
    .REFCLK (delay_clk),
    .RDY    ());

  (* IODELAY_GROUP = IO_DELAY_GROUP *)
  IDELAYCTRL #(.SIM_DEVICE ("ULTRASCALE")) i_delay_ctrl_byte11_hi (
    .RST    (delay_rst),
    .REFCLK (delay_clk),
    .RDY    ());
`endif  // AU15P_BANK86_WORKAROUND

`ifdef AXAU15_BANK65_IDELAYCTRLS
  //--------------------------------------------------------------------------
  // AXAU15 per-nibble IDELAYCTRLs.
  //
  // The 6 RX data IDELAYE3 cells scatter across 4 BANK65 nibbles that are NOT
  // served by rx_frame's own IDELAYCTRL (byte5 upper, X0Y11). Without an
  // IDELAYCTRL per nibble those BITSLICEs never reach BISC RDY and the lanes
  // capture a constant 0x000 (dig_tune all-fail). Nibbles from place_design
  // (BITSLICE_RX_TX Y / 13 = byte; offset 0-5 lower, 6-12 upper):
  //   rx_data[0]   Y82       -> byte6 lower (X0Y12)
  //   rx_data[2,3] Y88,Y86   -> byte6 upper (X0Y13)
  //   rx_data[5]   Y93       -> byte7 lower (X0Y14)
  //   rx_data[1,4] Y101,Y97  -> byte7 upper (X0Y15)
  // LOC constraints live in axau15/system_constr.xdc. SIM_DEVICE="ULTRASCALE"
  // (not "ULTRASCALE_PLUS" — DRC ADEF-911; see the AU15P block above).
  //--------------------------------------------------------------------------

  (* IODELAY_GROUP = IO_DELAY_GROUP *)
  IDELAYCTRL #(.SIM_DEVICE ("ULTRASCALE")) i_delay_ctrl_byte6_lo (
    .RST    (delay_rst),
    .REFCLK (delay_clk),
    .RDY    ());

  (* IODELAY_GROUP = IO_DELAY_GROUP *)
  IDELAYCTRL #(.SIM_DEVICE ("ULTRASCALE")) i_delay_ctrl_byte6_hi (
    .RST    (delay_rst),
    .REFCLK (delay_clk),
    .RDY    ());

  (* IODELAY_GROUP = IO_DELAY_GROUP *)
  IDELAYCTRL #(.SIM_DEVICE ("ULTRASCALE")) i_delay_ctrl_byte7_lo (
    .RST    (delay_rst),
    .REFCLK (delay_clk),
    .RDY    ());

  (* IODELAY_GROUP = IO_DELAY_GROUP *)
  IDELAYCTRL #(.SIM_DEVICE ("ULTRASCALE")) i_delay_ctrl_byte7_hi (
    .RST    (delay_rst),
    .REFCLK (delay_clk),
    .RDY    ());
`endif  // AXAU15_BANK65_IDELAYCTRLS

  // transmit data interface, oddr -> obuf

`ifdef AU15P_BANK86_WORKAROUND
  // tx data bit [0] — pseudo-differential (AU15P HD bank 86, no LVDS support)
  ad_data_out #(
    .PSEUDO_DIFF (1),
    .FPGA_TECHNOLOGY (FPGA_TECHNOLOGY),
    .IODELAY_ENABLE (DAC_IODELAY_ENABLE),
    .IODELAY_CTRL (0),
    .IODELAY_GROUP (IO_DELAY_GROUP),
    .REFCLK_FREQUENCY (DELAY_REFCLK_FREQUENCY)
  ) i_tx_data_0 (
    .tx_clk (l_clk),
    .tx_data_p (tx_data_1[0]),
    .tx_data_n (tx_data_0[0]),
    .tx_data_out_p (tx_data_out_p[0]),
    .tx_data_out_n (tx_data_out_n[0]),
    .up_clk (up_clk),
    .up_dld (up_dac_dld[0]),
    .up_dwdata (up_dac_dwdata[4:0]),
    .up_drdata (up_dac_drdata[4:0]),
    .delay_clk (delay_clk),
    .delay_rst (delay_rst),
    .delay_locked ());

  // tx data bits [5:1] — differential (HP bank)
  generate
  for (i = 1; i < 6; i = i + 1) begin: g_tx_data
  ad_data_out #(
    .FPGA_TECHNOLOGY (FPGA_TECHNOLOGY),
    .IODELAY_ENABLE (DAC_IODELAY_ENABLE),
    .IODELAY_CTRL (0),
    .IODELAY_GROUP (IO_DELAY_GROUP),
    .REFCLK_FREQUENCY (DELAY_REFCLK_FREQUENCY)
  ) i_tx_data (
    .tx_clk (l_clk),
    .tx_data_p (tx_data_1[i]),
    .tx_data_n (tx_data_0[i]),
    .tx_data_out_p (tx_data_out_p[i]),
    .tx_data_out_n (tx_data_out_n[i]),
    .up_clk (up_clk),
    .up_dld (up_dac_dld[i]),
    .up_dwdata (up_dac_dwdata[((i*5)+4):(i*5)]),
    .up_drdata (up_dac_drdata[((i*5)+4):(i*5)]),
    .delay_clk (delay_clk),
    .delay_rst (delay_rst),
    .delay_locked ());
  end
  endgenerate
`else
  // Stock ADI: 6 LVDS TX pairs, all differential.
  generate
  for (i = 0; i < 6; i = i + 1) begin: g_tx_data
  ad_data_out #(
    .FPGA_TECHNOLOGY (FPGA_TECHNOLOGY),
    .IODELAY_ENABLE (DAC_IODELAY_ENABLE),
    .IODELAY_CTRL (0),
    .IODELAY_GROUP (IO_DELAY_GROUP),
    .REFCLK_FREQUENCY (DELAY_REFCLK_FREQUENCY)
  ) i_tx_data (
    .tx_clk (l_clk),
    .tx_data_p (tx_data_1[i]),
    .tx_data_n (tx_data_0[i]),
    .tx_data_out_p (tx_data_out_p[i]),
    .tx_data_out_n (tx_data_out_n[i]),
    .up_clk (up_clk),
    .up_dld (up_dac_dld[i]),
    .up_dwdata (up_dac_dwdata[((i*5)+4):(i*5)]),
    .up_drdata (up_dac_drdata[((i*5)+4):(i*5)]),
    .delay_clk (delay_clk),
    .delay_rst (delay_rst),
    .delay_locked ());
  end
  endgenerate
`endif

  // transmit frame interface, oddr -> obuf

  ad_data_out #(
    .FPGA_TECHNOLOGY (FPGA_TECHNOLOGY),
    .IODELAY_ENABLE (DAC_IODELAY_ENABLE),
    .IODELAY_CTRL (0),
    .IODELAY_GROUP (IO_DELAY_GROUP),
    .REFCLK_FREQUENCY (DELAY_REFCLK_FREQUENCY)
  ) i_tx_frame (
    .tx_clk (l_clk),
    .tx_data_p (tx_frame),
    .tx_data_n (tx_frame),
    .tx_data_out_p (tx_frame_out_p),
    .tx_data_out_n (tx_frame_out_n),
    .up_clk (up_clk),
    .up_dld (up_dac_dld[6]),
    .up_dwdata (up_dac_dwdata[34:30]),
    .up_drdata (up_dac_drdata[34:30]),
    .delay_clk (delay_clk),
    .delay_rst (delay_rst),
    .delay_locked ());

  // transmit clock interface, oddr -> obuf
  // AU15P: pseudo-differential (HD bank 86, no LVDS support).
  // Stock: differential LVDS.

  ad_data_out #(
`ifdef AU15P_BANK86_WORKAROUND
    .PSEUDO_DIFF (1),
`endif
    .FPGA_TECHNOLOGY (FPGA_TECHNOLOGY),
    .IODELAY_ENABLE (DAC_IODELAY_ENABLE),
    .IODELAY_CTRL (0),
    .IODELAY_GROUP (IO_DELAY_GROUP),
    .REFCLK_FREQUENCY (DELAY_REFCLK_FREQUENCY)
  ) i_tx_clk (
    .tx_clk (l_clk),
    .tx_data_p (tx_clk[1]),
    .tx_data_n (tx_clk[0]),
    .tx_data_out_p (tx_clk_out_p),
    .tx_data_out_n (tx_clk_out_n),
    .up_clk (up_clk),
    .up_dld (up_dac_dld[7]),
    .up_dwdata (up_dac_dwdata[39:35]),
    .up_drdata (up_dac_drdata[39:35]),
    .delay_clk (delay_clk),
    .delay_rst (delay_rst),
    .delay_locked ());

  // enable, oddr -> obuf

  ad_data_out #(
    .SINGLE_ENDED (1),
    .FPGA_TECHNOLOGY (FPGA_TECHNOLOGY),
    .IODELAY_ENABLE (DAC_IODELAY_ENABLE),
    .IODELAY_CTRL (0),
    .IODELAY_GROUP (IO_DELAY_GROUP),
    .REFCLK_FREQUENCY (DELAY_REFCLK_FREQUENCY)
  ) i_enable (
    .tx_clk (l_clk),
    .tx_data_p (enable_int_p),
    .tx_data_n (enable_int_p),
    .tx_data_out_p (enable),
    .tx_data_out_n (),
    .up_clk (up_clk),
    .up_dld (up_dac_dld[8]),
    .up_dwdata (up_dac_dwdata[44:40]),
    .up_drdata (up_dac_drdata[44:40]),
    .delay_clk (delay_clk),
    .delay_rst (delay_rst),
    .delay_locked ());

  // txnrx, oddr -> obuf

  ad_data_out #(
    .SINGLE_ENDED (1),
    .FPGA_TECHNOLOGY (FPGA_TECHNOLOGY),
    .IODELAY_ENABLE (DAC_IODELAY_ENABLE),
    .IODELAY_CTRL (0),
    .IODELAY_GROUP (IO_DELAY_GROUP),
    .REFCLK_FREQUENCY (DELAY_REFCLK_FREQUENCY)
  ) i_txnrx (
    .tx_clk (l_clk),
    .tx_data_p (txnrx_int_p),
    .tx_data_n (txnrx_int_p),
    .tx_data_out_p (txnrx),
    .tx_data_out_n (),
    .up_clk (up_clk),
    .up_dld (up_dac_dld[9]),
    .up_dwdata (up_dac_dwdata[49:45]),
    .up_drdata (up_dac_drdata[49:45]),
    .delay_clk (delay_clk),
    .delay_rst (delay_rst),
    .delay_locked ());

  // device clock interface (receive clock)
  generate if (USE_SSI_CLK == 1) begin
  ad_data_clk i_clk (
    .rst (1'd0),
    .locked (),
    .clk_in_p (rx_clk_in_p),
    .clk_in_n (rx_clk_in_n),
    .clk (l_clk));
  end else begin
    assign l_clk = clk;
  end
  endgenerate

endmodule
