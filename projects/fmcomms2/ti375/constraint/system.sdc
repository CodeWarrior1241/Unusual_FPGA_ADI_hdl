###############################################################################
## FMCOMMS2 on Ti375C529 Dev Kit - timing constraints
##
## Efinity constrains at the CORE-PERIPHERY BOUNDARY, not at package pins
## (efinity-timing-closure UG): the clocks below are the periphery PLL
## outputs as they enter the core, named by their Interface Designer pin
## names (scripts/gen_interface.py). All names lowercase (VHDL entities
## are lowercased by synthesis).
##
## Clock plan:
##   clk_125mhz  sys_pll CLKOUT0 (25 MHz OSC1 -> x5), CPU/AXI/adapter domain
##   l_clk       lvds_pll CLKOUT0, 61.44 MHz 0 deg (AD9361 DATA_CLK via
##               GCLK CLK7 -> PLL BR0 core-tree reference)
##   l_clk_90    lvds_pll CLKOUT1 (+90 deg) exists only in the periphery
##               (FB_CLK TX lane launch clock) - no core loads, so it is
##               not declared here; the interface-generated
##               outflow/ti375c529.pt.sdc carries its waveform.
##
## Unlike the MPF300/axau15 ports there are NO per-pin set_input_delay/
## set_output_delay constraints for the LVDS lanes: capture and launch
## happen inside the characterized periphery SERDES blocks, whose margins
## are owned by the interface timing report (outflow/*.pt_timing.rpt) and
## the per-lane static delay settings.
##
## The ADI up_* infrastructure synchronizes every crossing between the
## 125 MHz domain and l_clk, and the Bedrock CDC FIFOs handle the
## streaming path, so the two groups are declared asynchronous (same
## intent as the axau15 per-register false-path XDCs and the mpf300
## clock groups).
###############################################################################

create_clock -name clk_125mhz -period 8.000  [get_ports {clk_125mhz}]
create_clock -name l_clk      -period 16.276 [get_ports {l_clk}]

# AD9361 DATA_CLK as it enters the core clock tree (feeds only the
# lvds_pll reference in the periphery; constrained for completeness in
# case any core load appears)
create_clock -name rx_clk     -period 16.276 [get_ports {rx_clk}]

set_clock_groups -asynchronous \
    -group {clk_125mhz} \
    -group {l_clk rx_clk}
