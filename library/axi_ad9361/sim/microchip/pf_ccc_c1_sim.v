//------------------------------------------------------------------------------
// pf_ccc_c1_sim.v — behavioral stand-in for the Libero-generated PF_CCC_C1
// core that ad_data_clk.v (USE_PLL_90=1, the TX FB_CLK phase-pair change,
// deps/hdl a6df9cdc4) instantiates BY NAME: 0/90-degree l_clk pair derived
// from the AD9361 DATA_CLK reference. The real core's simulation model
// lives in disposable Libero project output (see the mpf300 README's
// "Libero Awkwardness" section, issue 10), so the sim carries this model.
//
// Same model as PF_CCC_C1 in deps/neorv32/setups/
// neorv32_sw_ad9361_dapath_sim_microchip/pf_ccc_sim.v (kept in each
// submodule so both sims stay self-contained):
//   OUT0 follows the reference (0 deg), OUT1 is the reference delayed by a
//   quarter of the measured period (90 deg), lock after 16 reference
//   cycles. The period is re-measured continuously, so the model tracks a
//   stopped/restarted reference clock.
//------------------------------------------------------------------------------

`timescale 1ns / 1ps

module PF_CCC_C1 (
    input  wire PLL_POWERDOWN_N_0,
    input  wire REF_CLK_0,
    output wire OUT0_FABCLK_0,
    output reg  OUT1_FABCLK_0 = 1'b0,
    output reg  PLL_LOCK_0 = 1'b0
);

    // 0-degree output: phase-aligned to the reference
    assign OUT0_FABCLK_0 = REF_CLK_0;

    // measure the reference period
    realtime t_last = 0.0;
    realtime period = 0.0;
    always @(posedge REF_CLK_0) begin
        if (t_last > 0.0)
            period <= $realtime - t_last;
        t_last <= $realtime;
    end

    // 90-degree output: reference delayed a quarter period (transport)
    always @(REF_CLK_0)
        if (period > 0.0)
            OUT1_FABCLK_0 <= #(period / 4.0) REF_CLK_0;

    // lock after 16 reference cycles
    reg [4:0] lock_cnt = 5'd0;
    always @(posedge REF_CLK_0) begin
        if (PLL_POWERDOWN_N_0 && !PLL_LOCK_0 && period > 0.0) begin
            lock_cnt <= lock_cnt + 5'd1;
            if (lock_cnt == 5'd15)
                PLL_LOCK_0 <= 1'b1;
        end
    end

endmodule
