###############################################################################
## FMCOMMS2 on MPF300 Splash Kit - timing constraints
##
## Clock plan (requirement: 125 MHz fabric clock):
##   ref_clk_50mhz : 50 MHz board oscillator (ball H7) -> PF_CCC PLL
##   PF_CCC OUT0   : 125 MHz CPU/AXI/adapter domain (constraint supplied by
##                   the generated PF_CCC core's own component SDC)
##   rx_clk_in     : AD9361 DATA_CLK, constrained at the 125 MHz design
##                   ceiling of this system (the SmartHLS adapters are built
##                   for l_clk <= 125 MHz / CLOCK_PERIOD 8)
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

set_clock_groups -asynchronous -group [ get_clocks { rx_clk_in } ]
