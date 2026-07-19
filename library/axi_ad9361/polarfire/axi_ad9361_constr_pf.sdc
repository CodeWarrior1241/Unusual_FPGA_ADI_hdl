###############################################################################
## Copyright (C) 2016-2023 Analog Devices, Inc. All rights reserved.
### SPDX short identifier: ADIBSD
###############################################################################
## PolarFire (Libero/Synplify/SmartTime) constraints for axi_ad9361, LVDS mode.
##
## The AD9361 sources DATA_CLK (rx_clk_in) at up to 245.76 MHz in 2R2T LVDS
## DDR mode; the interface clock l_clk is that clock on the global network.
## The ADI up_* infrastructure implements its own multi-stage synchronizers
## for every crossing between the AXI (up_clk) domain and the interface
## domain, and the Xilinx/Intel ports false-path those crossings per
## register. Declaring the two domains asynchronous is the SmartTime
## equivalent and covers the same paths.
##
## rx_clk_in_p / s_axi_aclk are the port names of axi_ad9361; adjust the
## get_ports patterns if the block is wrapped under different top-level pins.

create_clock -name rx_clk_in -period 4.069 [ get_ports { rx_clk_in_p } ]
create_clock -name s_axi_aclk -period 10.000 [ get_ports { s_axi_aclk } ]

set_clock_groups -asynchronous \
  -group [ get_clocks { rx_clk_in } ] \
  -group [ get_clocks { s_axi_aclk } ]
