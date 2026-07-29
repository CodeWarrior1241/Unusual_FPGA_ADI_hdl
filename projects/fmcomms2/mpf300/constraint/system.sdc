###############################################################################
## FMCOMMS2 on MPF300 Splash Kit - timing constraints
##
## Clock plan (requirement: 125 MHz fabric clock):
##   ref_clk_50mhz : 50 MHz board oscillator (ball H7) -> PF_CCC PLL
##   PF_CCC OUT0   : 125 MHz CPU/AXI/adapter domain (constraint supplied by
##                   the generated PF_CCC core's own component SDC)
##   rx_clk_in     : AD9361 DATA_CLK, constrained at 8 ns like the axau15
##                   XDC (125 MHz ceiling; the actual rate in this design's
##                   fixed 1R1T 30.72 MSPS profile is 61.44 MHz, period
##                   16.276 ns). NOTE: the DDR I/O eye analysis below is
##                   therefore ~2x pessimistic -- negative I/O slack up to
##                   ~4 ns may be an artifact of the ceiling period, not a
##                   real eye violation; re-check any failure against the
##                   real 16.276 ns period before acting on it.
##
## The ADI up_* infrastructure synchronizes every crossing between the AXI
## domain and l_clk, and the CDC FIFOs handle the streaming path, so the
## l_clk group is declared asynchronous to all other clocks (the same intent
## as the per-register false-path XDCs on axau15).
###############################################################################

create_clock -name ref_clk_50mhz -period 20.000 [ get_ports { ref_clk_50mhz } ]
create_clock -name rx_clk_in -period 8.000 [ get_ports { rx_clk_in_p } ]

# 125 MHz CPU/AXI/adapter domain on the PF_CCC output. Declared explicitly:
# with the reference entering through the fabric (refclk_ibuf), SmartTime
# does not derive the PLL output clock on its own and the whole NEORV32/AXI
# domain would otherwise go unconstrained.
create_generated_clock -name clk_125mhz \
    -multiply_by 5 -divide_by 2 \
    -source [ get_ports { ref_clk_50mhz } ] \
    [ get_pins { clk_gen/PF_CCC_C0_0/pll_inst_0/OUT0 } ]

###############################################################################
## AD9361 LVDS RX: source-synchronous DDR input capture (chip -> FPGA)
##
## The chip launches rx_frame and rx_data edge-aligned with DATA_CLK: each
## bit transitions t_DDDV after every DATA_CLK edge. AD9361 datasheet LVDS
## timing (VERIFY against the datasheet revision in use):
##   t_DDDV(min) = 0.25 ns   t_DDDV(max) = 1.25 ns
## So the valid window for the bit launched at edge N runs from
## (N + 1.25 ns) to (next edge + 0.25 ns). The PolarFire capture is
## fabric-emulated DDR (polarfire/common/ad_data_in.v): posedge and negedge
## fabric FFs clocked by l_clk (= DATA_CLK after INBUF + CLKINT, i.e. the
## global-network insertion delay sets the effective sampling point). These
## constraints make SmartTime analyze exactly that geometry and force the
## placer to balance the per-bit pad->FF routing -- both were previously
## unconstrained, and the interface corrupted data (the PN monitors never
## locked under chip PRBS: hold_bist + get_valid_rate = 100% oos re-set).
###############################################################################

set rx_ddr_in_ports [ get_ports { rx_data_in_p[*] rx_data_in_n[*] \
                                  rx_frame_in_p rx_frame_in_n } ]

# bit launched on the DATA_CLK rising edge
set_input_delay -clock rx_clk_in -max 1.250 $rx_ddr_in_ports
set_input_delay -clock rx_clk_in -min 0.250 $rx_ddr_in_ports
# bit launched on the DATA_CLK falling edge
set_input_delay -clock rx_clk_in -clock_fall -max 1.250 -add_delay $rx_ddr_in_ports
set_input_delay -clock rx_clk_in -clock_fall -min 0.250 -add_delay $rx_ddr_in_ports

###############################################################################
## AD9361 LVDS TX: source-synchronous DDR output (FPGA -> chip)
##
## The FPGA forwards FB_CLK (tx_clk_out) and launches tx_frame/tx_data from
## identical fabric-emulated DDR output structures (polarfire/common/
## ad_data_out.v), all driven by l_clk. The chip re-samples TX data on both
## FB_CLK edges and needs (AD9361 datasheet LVDS timing, VERIFY):
##   t_STX(setup, min) = 1.0 ns   t_HTX(hold, min) = 0 ns
## tx_fb_clk models the forwarded clock at its pad; the output delays make
## SmartTime time every data pad against the forwarded-clock pad and force
## the placer to balance the 8 output structures. If SmartTime cannot trace
## the generated clock through the DDR output mux it warns that tx_fb_clk
## has no driving path -- check the post-P&R timing report; fall back to
## set_max_delay/set_min_delay port-to-port matching if so.
###############################################################################

create_generated_clock -name tx_fb_clk \
    -source [ get_ports { rx_clk_in_p } ] \
    -multiply_by 1 \
    [ get_ports { tx_clk_out_p } ]

set tx_ddr_out_ports [ get_ports { tx_data_out_p[*] tx_data_out_n[*] \
                                   tx_frame_out_p tx_frame_out_n } ]

# chip samples on the FB_CLK rising edge
set_output_delay -clock tx_fb_clk -max 1.000 $tx_ddr_out_ports
set_output_delay -clock tx_fb_clk -min 0.000 $tx_ddr_out_ports
# chip samples on the FB_CLK falling edge
set_output_delay -clock tx_fb_clk -clock_fall -max 1.000 -add_delay $tx_ddr_out_ports
set_output_delay -clock tx_fb_clk -clock_fall -min 0.000 -add_delay $tx_ddr_out_ports

# ---------------------------------------------------------------------------
# FB_CLK quarter-period shift (TX eye centering).
#
# All TX outputs (clock included) launch from identical fabric DDR muxes
# switching on every l_clk edge, so with a matched clock path FB_CLK edges
# land exactly on the data transition instants and the chip samples at the
# eye edge -- dac_clksel only swaps which bit pairs with which edge, it
# cannot move the sampling point (verified on hardware: clksel_on had no
# effect; loopback EVM stayed ~27% with RX proven bit-perfect by PN BIST).
#
# Force the rx_clk_in -> tx_clk_out pad path to be ~4.1 ns (quarter of the
# 16.276 ns DATA_CLK period, half a UI) longer than the ~4.8 ns natural
# data-pad paths: the placer/router adds the detour on the clock net only,
# FB_CLK edges move to mid-eye, and the set_output_delay checks above then
# verify the resulting setup/hold against the chip's t_STX/t_HTX.
# Multi-corner spread of a routing detour is roughly +/-1 ns here; the
# 8.6-9.6 window keeps >= 2.5 ns of eye margin at both corners at the
# real 61.44 MHz rate.
# ---------------------------------------------------------------------------

set_min_delay 8.600 -from [ get_ports { rx_clk_in_p } ] \
    -to [ get_ports { tx_clk_out_p tx_clk_out_n } ]
set_max_delay 9.600 -from [ get_ports { rx_clk_in_p } ] \
    -to [ get_ports { tx_clk_out_p tx_clk_out_n } ]

# l_clk domain (and the FB_CLK derived from it) is asynchronous to the
# fabric clocks; the ADI up_* synchronizers and the CDC FIFOs own every
# crossing.
set_clock_groups -asynchronous -group [ get_clocks { rx_clk_in tx_fb_clk } ]
