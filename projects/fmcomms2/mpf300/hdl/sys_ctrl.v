// ***************************************************************************
// System control block for the MPF300 FMCOMMS2 design, 125 MHz domain.
// Combines the roles of the axau15 proc_sys_reset (CPU_Reset), the
// power-down gating logic (pwr_dn_inv / pwr_dn_aresetn_gate) and the GPIO
// xlslice fan-out cells:
//
//   - reset generation: open-logic olo_base_reset_gen (deps/open-logic,
//     VHDL) — synchronizer-filtered reset from PLL lock, PF_INIT_MONITOR
//     device init done, and the board's PF_USER_RESET push-button (active
//     low). RstPulseCycles_g=8 keeps the 8-cycle minimum pulse of the
//     shift-register implementation this replaces; olo asserts synchronously
//     (registers power up in reset via the PolarFire initialization flow,
//     so an async assert path is not needed) and releases synchronously.
//   - pwr_dn = gpio_o[8]: software low-power lever; aresetn_gated =
//     sys_resetn & ~pwr_dn holds axi_ad9361's register domain and the TX
//     CDC FIFO in reset while powered down (axau15 plan B.3)
//   - NEORV32 GPIO output map (per ad9361_no-os software):
//       [0] up_enable  [1] up_txnrx  [2] gpio_resetb  [3] gpio_sync
//       [4] gpio_en_agc  [7:5] gpio_ctl[2:0] (ctl[3] tied 0)  [8] pwr_dn
//   - SPI chip-select: bit 0 of the NEORV32 spi_csn_o bus
// ***************************************************************************

`timescale 1ns/100ps

module sys_ctrl (

  input           clk,              // 125 MHz
  input           pll_lock,
  input           init_done,        // PF_INIT_MONITOR DEVICE_INIT_DONE
  input           ext_resetn,       // PF_USER_RESET push-button, active low

  input   [15:0]  gpio_o,
  input   [ 7:0]  spi_csn_i,

  output          sys_resetn,       // main 125 MHz domain reset, active low
  output          sys_reset,        // same, active high (SmartHLS cores)
  output          aresetn_gated,    // sys_resetn & ~pwr_dn
  output          pwr_dn,

  output          up_enable,
  output          up_txnrx,
  output          gpio_resetb,
  output          gpio_sync,
  output          gpio_en_agc,
  output  [ 3:0]  gpio_ctl,
  output          spi_csn_0
);

  wire rst_src = ~(pll_lock & init_done & ext_resetn);   // active high

  // open-logic reset generator (VHDL entity; generic defaults except the
  // pulse length: RstInPolarity_g='1' so rst_src is taken active-high,
  // SyncStages_g=2)
  olo_base_reset_gen #(
    .RstPulseCycles_g (8)
  ) i_reset_gen (
    .Clk    (clk),
    .RstIn  (rst_src),
    .RstOut (sys_reset)
  );

  assign sys_resetn = ~sys_reset;

  assign pwr_dn = gpio_o[8];
  assign aresetn_gated = sys_resetn & ~pwr_dn;

  assign up_enable   = gpio_o[0];
  assign up_txnrx    = gpio_o[1];
  assign gpio_resetb = gpio_o[2];
  assign gpio_sync   = gpio_o[3];
  assign gpio_en_agc = gpio_o[4];
  assign gpio_ctl    = {1'b0, gpio_o[7:5]};

  assign spi_csn_0 = spi_csn_i[0];

endmodule
