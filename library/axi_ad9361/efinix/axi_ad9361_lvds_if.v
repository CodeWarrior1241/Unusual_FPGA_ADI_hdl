// ***************************************************************************
// ***************************************************************************
// Copyright (C) 2014-2026 Analog Devices, Inc. All rights reserved.
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
// Efinix Titanium port of the axi_ad9361_lvds_if (derived from the Microchip
// PolarFire port). The framing, delineation, tx serialization and ensm logic
// are identical to the PolarFire/Xilinx versions; the physical I/O layer is
// GONE from the RTL entirely: on Titanium, LVDS buffers, DDR (x2 half-rate
// SERDES) registers and delay elements live in the configured periphery
// (Interface Designer, scripts/gen_interface.py of the ti375c529 project),
// and this module connects to them through plain core-boundary signals.
//
// PORT REPURPOSING (module name and port list are kept identical to the
// PolarFire variant so the shared axi_ad9361.v needs no changes; the
// physical semantics at each port change as follows):
//
//   rx_clk_in_p    <- l_clk: 61.44 MHz, 0 deg, lvds_pll CLKOUT0 via GBUF.
//                    (The AD9361 DATA_CLK pair enters the periphery on a
//                    GCLK pad and references the PLL via the core clock
//                    tree; the fabric only ever sees the PLL output.)
//   rx_clk_in_n    <- unused, tie 1'b0 (l_clk_90 exists only inside the
//                    periphery: it launches the forwarded-clock TX lane).
//   rx_frame_in_p/n, rx_data_in_p/n[i]
//                  <- per-lane 2-bit deserializer words (RX_DESER=2,
//                    RX_HALF_RATE=1), valid in the l_clk domain:
//                    _n = first captured bit (PolarFire fall sample),
//                    _p = second captured bit (PolarFire rise sample).
//                    If frame alignment fails at bring-up, swapping the
//                    two bits at the system_top wiring is the first knob.
//   tx_clk_out_p/n -> unused at the top level; the forwarded FB_CLK is a
//                    periphery TX lane in CLKOUT mode clocked by l_clk_90
//                    (PLL-guaranteed +90 deg, same eye-centering the
//                    PolarFire PF_CCC OUT1 provided). Note this drops the
//                    dac_clksel polarity option (software default 0 =
//                    normal polarity is the only supported setting).
//   tx_frame_out_p/n, tx_data_out_p/n[i]
//                  -> per-lane 2-bit serializer words (TX_SER=2,
//                    TX_HALF_RATE=1): _n = first transmitted bit,
//                    _p = second transmitted bit (matches the PolarFire
//                    ODDR which put tx_data_0/tx_frame first).
//   enable, txnrx  -> plain registered l_clk-domain outputs (periphery
//                    GPIO output blocks).
//   delay_clk      <- lvds_pll LOCKED (async): synchronized here and
//                    folded into adc_status exactly like the PolarFire
//                    PF_CCC lock, so the power_down/power_up relock
//                    gating contract of the no-os software is preserved.
//                    (No dynamic delay controller exists in the fabric:
//                    delay readback returns zero and delay_locked is tied
//                    high, same approach as the PolarFire/Intel ports.
//                    Runtime eye scanning via the periphery DLY_* ports
//                    is a possible future upgrade.)

`timescale 1ns/100ps

module axi_ad9361_lvds_if #(

  // The FPGA_TECHNOLOGY/IODELAY parameters exist for port compatibility
  // with the Xilinx version; they have no function on Efinix.

  parameter   FPGA_TECHNOLOGY = 0,
  parameter   DAC_IODELAY_ENABLE = 0,
  parameter   IO_DELAY_GROUP = "dev_if_delay_group",
  parameter   IODELAY_CTRL = 1,
  parameter   CLK_DESKEW = 0,
  parameter   USE_SSI_CLK = 1,
  parameter   DELAY_REFCLK_FREQUENCY = 200,
  parameter   RX_NODPA = 0
) (

  // physical interface (receive; see port-repurposing note above)

  input               rx_clk_in_p,
  input               rx_clk_in_n,
  input               rx_frame_in_p,
  input               rx_frame_in_n,
  input   [ 5:0]      rx_data_in_p,
  input   [ 5:0]      rx_data_in_n,

  // physical interface (transmit; see port-repurposing note above)

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
  reg     [ 1:0]      tx_clk_out_r = 'd0;
  reg                 tx_frame_out_r_p = 'd0;
  reg                 tx_frame_out_r_n = 'd0;
  reg     [ 5:0]      tx_data_out_r_p = 'd0;
  reg     [ 5:0]      tx_data_out_r_n = 'd0;
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

  // device clock: on Efinix the DATA_CLK-referenced PLL lives in the
  // periphery; its 0-deg CLKOUT enters the core on rx_clk_in_p.

  assign l_clk = rx_clk_in_p;

  // lvds_pll LOCKED, carried in on the (otherwise unused) delay_clk port.
  // Asynchronous by nature (INTF: LOCKED is async) -- synchronized below.

  assign locked_s = delay_clk;

  // delay interface signals (no dynamic delay control wired on Efinix)

  assign up_adc_drdata = 35'd0;
  assign up_dac_drdata = 50'd0;

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

  // delay_locked means "delay controller ready" to the no-os stack (the
  // delay machinery is stubbed on Efinix) -- kept tied high, NOT gated
  // on the PLL lock, so software delay/tune semantics are unaffected.
  assign delay_locked = 1'b1;

  // locked_s is the lvds_pll lock; it reaches software through adc_status
  // below, and drops while the AD9361 sleeps (DATA_CLK absent ->
  // reference lost).
  always @(posedge l_clk) begin
    rx_locked_m1 <= locked_s;
    rx_locked <= rx_locked_m1;
  end

  // receive data plane: 2-bit deserializer words from the periphery,
  // already synchronous to l_clk (constrained by the interface SDC)

  assign rx_data_1_s = rx_data_in_p;
  assign rx_data_0_s = rx_data_in_n;
  assign rx_frame_s = {rx_frame_in_p, rx_frame_in_n};

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

  // transmit data plane: registered 2-bit serializer words to the
  // periphery (one output register stage, mirroring the PolarFire
  // ad_data_out launch registers). _n is transmitted first, _p second.

  always @(posedge l_clk) begin
    tx_frame_out_r_n <= tx_frame;
    tx_frame_out_r_p <= tx_frame;
    tx_data_out_r_n <= tx_data_0;
    tx_data_out_r_p <= tx_data_1;
    tx_clk_out_r <= tx_clk;
  end

  assign tx_frame_out_p = tx_frame_out_r_p;
  assign tx_frame_out_n = tx_frame_out_r_n;
  assign tx_data_out_p = tx_data_out_r_p;
  assign tx_data_out_n = tx_data_out_r_n;

  // forwarded-clock pattern: unused at the top level (the FB_CLK lane is
  // a periphery CLKOUT-mode TX block on l_clk_90); kept for waveform
  // visibility in simulation and trimmed in synthesis.

  assign tx_clk_out_p = tx_clk_out_r[1];
  assign tx_clk_out_n = tx_clk_out_r[0];

  // ensm outputs: plain registered l_clk-domain signals (periphery GPIO)

  assign enable = enable_int_p;
  assign txnrx = txnrx_int_p;

endmodule
