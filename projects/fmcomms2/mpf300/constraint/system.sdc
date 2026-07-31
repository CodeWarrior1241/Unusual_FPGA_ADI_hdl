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
## The chip launches rx_frame/rx_data edge-aligned with DATA_CLK: each bit
## transitions t_DDDV = 0.25..1.25 ns (datasheet LVDS timing) after every
## clock edge, so the bit launched at edge N is valid from N + 1.25 ns to
## (next edge) + 0.25 ns. Capture is fabric-emulated DDR
## (polarfire/common/ad_data_in.v) clocked by l_clk (PF_CCC_C1 OUT0).
## These windows make SmartTime check every sampling point against the eye
## and make the placer balance the per-bit pad->FF routing -- mandatory
## for fabric capture, where unmanaged per-bit skew is nanosecond-class.
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
## tx_frame/tx_data launch from identical fabric DDR structures
## (polarfire/common/ad_data_out.v) on l_clk; the forwarded FB_CLK launches
## from the same structure on PF_CCC_C1's +90 deg OUT1, placing its edges
## a quarter period into the TX data eye (see ad_data_clk.v). The chip
## samples TX data on both FB_CLK edges: t_STX(setup) = 1.0 ns,
## t_HTX(hold) = 0 ns (datasheet LVDS timing). tx_fb_clk models the
## forwarded clock at its pad; the output delays time every data pad
## against it.
###############################################################################

# Fabric-referenced CCC outputs are not derived by SmartTime (same as
# clk_125mhz above) -- declare both explicitly. The +90 deg of OUT1 is
# not modeled (meaningless under the 8 ns ceiling period), so the TX I/O
# checks are advisory; hardware PN BIST / RF EVM verify the interface.
create_generated_clock -name l_clk_pll \
    -source [ get_ports { rx_clk_in_p } ] \
    -multiply_by 1 \
    [ get_pins { *PF_CCC_C1_0/pll_inst_0/OUT0 } ]
create_generated_clock -name tx_fbclk_90 \
    -source [ get_ports { rx_clk_in_p } ] \
    -multiply_by 1 \
    [ get_pins { *PF_CCC_C1_0/pll_inst_0/OUT1 } ]

create_generated_clock -name tx_fb_clk \
    -source [ get_pins { *PF_CCC_C1_0/pll_inst_0/OUT1 } ] \
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

# The l_clk family (CCC pair and the FB_CLK derived from it) is
# asynchronous to the fabric clocks; the ADI up_* synchronizers and the
# CDC FIFOs own every crossing.
set_clock_groups -asynchronous \
    -group [ get_clocks { rx_clk_in l_clk_pll tx_fbclk_90 tx_fb_clk } ]
