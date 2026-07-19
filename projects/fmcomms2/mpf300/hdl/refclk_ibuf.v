// ***************************************************************************
// Board reference clock input buffer: INBUF -> CLKINT onto the global
// network, feeding the PF_CCC reference as a fabric-routed clock.
//
// Routing the reference through the fabric (instead of the pad's dedicated
// CCC connection) frees the placer to put the PLL in any corner: the
// Splash Kit's 50 MHz oscillator sits on H7 (CCC_SW_CLKIN_W_2), whose
// dedicated routing only reaches the SW CCC, and Libero (PDCPF-13) refuses
// the pin constraint when the PLL lands elsewhere. PolarFire placement
// rules allow up to two fabric-driven PLL reference clocks per corner
// (PRPF-011); at a 50 MHz reference the added jitter is negligible.
// ***************************************************************************

`timescale 1ns/100ps

module refclk_ibuf (
  input   pad,
  output  clk
);

  wire clk_ibuf_s;

  INBUF i_ibuf (
    .PAD (pad),
    .Y (clk_ibuf_s));

  // CLKINT_PRESERVE, not CLKINT: Synplify optimizes a plain CLKINT out of
  // the reference path, reconnecting pad -> PLL directly and reinstating
  // the dedicated-routing placement rule this buffer exists to avoid.
  CLKINT_PRESERVE i_gbuf (
    .A (clk_ibuf_s),
    .Y (clk));

endmodule
