###############################################################################
## Copyright (C) 2014-2025 Analog Devices, Inc. All rights reserved.
### SPDX short identifier: ADIBSD
###############################################################################
#
# AU15P Board Constraints - Placeholder
#
# TODO: Update all pin assignments with actual AU15P package pins
# These are placeholder values based on typical UltraScale+ pinouts.
# Refer to Avnet AU15P schematic and user guide for correct pins.
#
###############################################################################

# System Reset
# TODO: Update with AU15P reset button pin
set_property -dict  {PACKAGE_PIN  TBD   IOSTANDARD  LVCMOS18} [get_ports sys_rst]

# System Clock (differential)
# TODO: Update with AU15P oscillator pins
set_property -dict  {PACKAGE_PIN  TBD} [get_ports sys_clk_p]
set_property -dict  {PACKAGE_PIN  TBD} [get_ports sys_clk_n]

# UART
# TODO: Update with AU15P UART pins (typically directly connected to FTDI or similar)
set_property -dict  {PACKAGE_PIN  TBD   IOSTANDARD  LVCMOS18} [get_ports uart_sout]
set_property -dict  {PACKAGE_PIN  TBD   IOSTANDARD  LVCMOS18} [get_ports uart_sin]

# GPIO - LEDs
# TODO: Update with AU15P LED pins
set_property -dict  {PACKAGE_PIN  TBD   IOSTANDARD  LVCMOS18} [get_ports gpio_bd[0]]
set_property -dict  {PACKAGE_PIN  TBD   IOSTANDARD  LVCMOS18} [get_ports gpio_bd[1]]
set_property -dict  {PACKAGE_PIN  TBD   IOSTANDARD  LVCMOS18} [get_ports gpio_bd[2]]
set_property -dict  {PACKAGE_PIN  TBD   IOSTANDARD  LVCMOS18} [get_ports gpio_bd[3]]

# GPIO - Switches/Buttons
# TODO: Update with AU15P switch/button pins
set_property -dict  {PACKAGE_PIN  TBD   IOSTANDARD  LVCMOS18} [get_ports gpio_bd[4]]
set_property -dict  {PACKAGE_PIN  TBD   IOSTANDARD  LVCMOS18} [get_ports gpio_bd[5]]
set_property -dict  {PACKAGE_PIN  TBD   IOSTANDARD  LVCMOS18} [get_ports gpio_bd[6]]
set_property -dict  {PACKAGE_PIN  TBD   IOSTANDARD  LVCMOS18} [get_ports gpio_bd[7]]

# Configuration Bank Voltage
# TODO: Verify AU15P configuration voltage (typically 1.8V for UltraScale+)
set_property CFGBVS GND [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]

# Create SPI clock constraint
create_generated_clock -name spi_clk  \
  -source [get_pins i_system_wrapper/system_i/axi_spi/ext_spi_clk] \
  -divide_by 2 [get_pins i_system_wrapper/system_i/axi_spi/sck_o]
