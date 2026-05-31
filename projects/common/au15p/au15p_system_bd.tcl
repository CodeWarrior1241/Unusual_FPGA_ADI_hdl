###############################################################################
## Copyright (C) 2014-2025 Analog Devices, Inc. All rights reserved.
### SPDX short identifier: ADIBSD
###############################################################################
#
# AU15P Board Support - Minimal design for NEORV32 + FMCOMMS4
#
# This design does NOT use:
# - MicroBlaze (NEORV32 RISC-V softcore used instead)
# - DDR4/MIG (no external memory controller needed)
# - Zynq PS (pure FPGA design)
#
# The NEORV32 processor is instantiated separately in the project.
# This file provides minimal board infrastructure for clocking and I/O.
#
###############################################################################

# create board design
# interface ports

# System clock input (differential)
create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 sys_clk

# System reset
create_bd_port -dir I -type rst sys_rst

# UART
create_bd_port -dir I uart_sin
create_bd_port -dir O uart_sout

# SPI (directly directly connected to AD9364)
create_bd_port -dir O -from 7 -to 0 spi_csn_o
create_bd_port -dir I -from 7 -to 0 spi_csn_i
create_bd_port -dir I spi_clk_i
create_bd_port -dir O spi_clk_o
create_bd_port -dir I spi_sdo_i
create_bd_port -dir O spi_sdo_o
create_bd_port -dir I spi_sdi_i

# GPIO
create_bd_port -dir I -from 31 -to 0 gpio0_i
create_bd_port -dir O -from 31 -to 0 gpio0_o
create_bd_port -dir O -from 31 -to 0 gpio0_t
create_bd_port -dir I -from 31 -to 0 gpio1_i
create_bd_port -dir O -from 31 -to 0 gpio1_o
create_bd_port -dir O -from 31 -to 0 gpio1_t

# io settings
# TODO: Update clock frequency for AU15P board oscillator

set_property -dict [list CONFIG.POLARITY {ACTIVE_HIGH}] [get_bd_ports sys_rst]
set_property -dict [list CONFIG.FREQ_HZ {100000000}] [get_bd_intf_ports sys_clk]

# instance: system clocking
# Generate 100 MHz system clock and 200 MHz IDELAY reference clock from board oscillator

ad_ip_instance clk_wiz sys_clk_wiz
ad_ip_parameter sys_clk_wiz CONFIG.PRIMITIVE MMCM
ad_ip_parameter sys_clk_wiz CONFIG.PRIM_SOURCE Differential_clock_capable_pin
ad_ip_parameter sys_clk_wiz CONFIG.PRIM_IN_FREQ 100.000
ad_ip_parameter sys_clk_wiz CONFIG.CLKOUT1_REQUESTED_OUT_FREQ 100.000
ad_ip_parameter sys_clk_wiz CONFIG.CLKOUT2_USED true
ad_ip_parameter sys_clk_wiz CONFIG.CLKOUT2_REQUESTED_OUT_FREQ 200.000
ad_ip_parameter sys_clk_wiz CONFIG.USE_LOCKED true
ad_ip_parameter sys_clk_wiz CONFIG.USE_RESET true
ad_ip_parameter sys_clk_wiz CONFIG.RESET_TYPE ACTIVE_HIGH

# instance: system reset generators

ad_ip_instance proc_sys_reset sys_rstgen
ad_ip_parameter sys_rstgen CONFIG.C_EXT_RST_WIDTH 1

ad_ip_instance proc_sys_reset sys_200m_rstgen
ad_ip_parameter sys_200m_rstgen CONFIG.C_EXT_RST_WIDTH 1

# Clock connections

ad_connect  sys_clk sys_clk_wiz/CLK_IN1_D
ad_connect  sys_rst sys_clk_wiz/reset

ad_connect  sys_cpu_clk sys_clk_wiz/clk_out1
ad_connect  sys_200m_clk sys_clk_wiz/clk_out2

ad_connect  sys_clk_wiz/locked sys_rstgen/dcm_locked
ad_connect  sys_clk_wiz/locked sys_200m_rstgen/dcm_locked

ad_connect  sys_cpu_clk sys_rstgen/slowest_sync_clk
ad_connect  sys_200m_clk sys_200m_rstgen/slowest_sync_clk

ad_connect  sys_rst sys_rstgen/ext_reset_in
ad_connect  sys_rst sys_200m_rstgen/ext_reset_in

ad_connect  sys_cpu_reset sys_rstgen/peripheral_reset
ad_connect  sys_cpu_resetn sys_rstgen/peripheral_aresetn
ad_connect  sys_200m_reset sys_200m_rstgen/peripheral_reset
ad_connect  sys_200m_resetn sys_200m_rstgen/peripheral_aresetn

# generic system clocks pointers

set sys_cpu_clk           [get_bd_nets sys_cpu_clk]
set sys_dma_clk           [get_bd_nets sys_cpu_clk]
set sys_iodelay_clk       [get_bd_nets sys_200m_clk]

set sys_cpu_reset         [get_bd_nets sys_cpu_reset]
set sys_cpu_resetn        [get_bd_nets sys_cpu_resetn]
set sys_dma_reset         [get_bd_nets sys_cpu_reset]
set sys_dma_resetn        [get_bd_nets sys_cpu_resetn]
set sys_iodelay_reset     [get_bd_nets sys_200m_reset]
set sys_iodelay_resetn    [get_bd_nets sys_200m_resetn]

# AXI infrastructure for peripherals (directly directly connected to NEORV32 via bridge)
# Note: NEORV32 Wishbone-to-AXI bridge instantiated in system_top.v

ad_ip_instance axi_quad_spi axi_spi
ad_ip_parameter axi_spi CONFIG.C_USE_STARTUP 0
ad_ip_parameter axi_spi CONFIG.C_NUM_SS_BITS 8
ad_ip_parameter axi_spi CONFIG.C_SCK_RATIO 8

ad_ip_instance axi_gpio axi_gpio
ad_ip_parameter axi_gpio CONFIG.C_IS_DUAL 1
ad_ip_parameter axi_gpio CONFIG.C_GPIO_WIDTH 32
ad_ip_parameter axi_gpio CONFIG.C_GPIO2_WIDTH 32
ad_ip_parameter axi_gpio CONFIG.C_INTERRUPT_PRESENT 1

# system id

ad_ip_instance axi_sysid axi_sysid_0
ad_ip_instance sysid_rom rom_sys_0

ad_connect  axi_sysid_0/rom_addr   	rom_sys_0/rom_addr
ad_connect  axi_sysid_0/sys_rom_data   	rom_sys_0/rom_data
ad_connect  sys_cpu_clk                 rom_sys_0/clk

# SPI connections

ad_connect  spi_csn_i axi_spi/ss_i
ad_connect  spi_csn_o axi_spi/ss_o
ad_connect  spi_clk_i axi_spi/sck_i
ad_connect  spi_clk_o axi_spi/sck_o
ad_connect  spi_sdo_i axi_spi/io0_i
ad_connect  spi_sdo_o axi_spi/io0_o
ad_connect  spi_sdi_i axi_spi/io1_i
ad_connect  sys_cpu_clk axi_spi/ext_spi_clk

# GPIO connections

ad_connect  gpio0_i axi_gpio/gpio_io_i
ad_connect  gpio0_o axi_gpio/gpio_io_o
ad_connect  gpio0_t axi_gpio/gpio_io_t
ad_connect  gpio1_i axi_gpio/gpio2_io_i
ad_connect  gpio1_o axi_gpio/gpio2_io_o
ad_connect  gpio1_t axi_gpio/gpio2_io_t

# interconnect - processor
# Note: These will be connected to NEORV32 AXI master

ad_cpu_interconnect 0x45000000 axi_sysid_0
ad_cpu_interconnect 0x40000000 axi_gpio
ad_cpu_interconnect 0x44A70000 axi_spi
