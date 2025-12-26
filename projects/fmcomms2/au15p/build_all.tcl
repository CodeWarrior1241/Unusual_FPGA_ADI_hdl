###############################################################################
## Copyright (C) 2025 Analog Devices, Inc. All rights reserved.
### SPDX short identifier: ADIBSD
###############################################################################
#
# FMCOMMS2/4 on Avnet AU15P - Top-level build script
#
# Usage: vivado -mode batch -source build_all.tcl
#    or: vivado -mode tcl -source build_all.tcl
#
###############################################################################

# Project configuration
set project_name "fmcomms2_au15p"
set part "xcau15p-ffvb676-2-e"
set project_dir [file dirname [info script]]
set top_level_bd_name "Top"

# Block design component names
set neorv32_cpu "NEORV32_RISC_V"
set axi_ad9361 "AXI_AD9361"
set ecs_clock_300_mhz "ECS_Clock_300MHz"
set cpu_sys_reset "CPU_Reset"
set ad9361_sys_reset "AD9361_Reset"
set neorv32_cpu_input_reset "NEORV32_CPU_Input_Reset_Inv"
set ad9361_derived_reset_inv "AD9361_Derived_Reset_Inv"
set axi_cpu_interconnect "AXI_CPU_Interconnect"
set ad9361_divclk_sel "AD9361_DivClk_Sel"
set ad9361_divclk_sel_concat "AD9361_DivClk_Sel_Concat"
set ad9361_divclk_sel_const "AD9361_DivClk_Sel_Const"
set ad9361_adc_fifo "AD9361_ADC_FIFO"
set ad9361_dac_fifo "AD9361_DAC_FIFO"

###############################################################################
# Board file check and installation instructions
###############################################################################

proc check_board_files {} {
    # Try to get the AU15P board - if it fails, board files are not installed
    set boards [get_board_parts -quiet "*auboard_15p*"]

    if {[llength $boards] == 0} {
        puts ""
        puts "==============================================================================="
        puts "  ERROR: Avnet AU15P board definition files not found in Vivado"
        puts "==============================================================================="
        puts ""
        puts "  The AU15P board files must be installed before building this project."
        puts ""
        puts "  Installation Instructions:"
        puts "  ---------------------------"
        puts ""
        puts "  1. Locate the board files in this repository:"
        puts "       deps/bdf/aub15p/"
        puts ""
        puts "  2. Copy the 'aub15p' folder to the Vivado board_files directory:"
        puts ""
        puts "     WINDOWS (requires admin privileges):"
        puts "       Copy to: <Vivado_Install>/data/boards/board_files/"
        puts "       Example: C:\\Xilinx\\Vivado\\2025.2\\data\\boards\\board_files\\aub15p"
        puts ""
        puts "     WINDOWS (user-specific, no admin required):"
        puts "       Copy to: %APPDATA%\\Xilinx\\Vivado\\board_files\\"
        puts "       Example: C:\\Users\\<username>\\AppData\\Roaming\\Xilinx\\Vivado\\board_files\\aub15p"
        puts ""
        puts "     LINUX (system-wide):"
        puts "       Copy to: <Vivado_Install>/data/boards/board_files/"
        puts "       Example: /opt/Xilinx/Vivado/2025.2/data/boards/board_files/aub15p"
        puts ""
        puts "     LINUX (user-specific, no admin required):"
        puts "       Copy to: ~/.Xilinx/Vivado/board_files/"
        puts "       Example: /home/<username>/.Xilinx/Vivado/board_files/aub15p"
        puts ""
        puts "  3. Restart Vivado and re-run this script."
        puts ""
        puts "==============================================================================="
        puts ""
        return 0
    }

    puts "INFO: AU15P board definition found: $boards"
    return 1
}

###############################################################################
# Main build flow
###############################################################################

puts ""
puts "==============================================================================="
puts "  FMCOMMS2/4 on Avnet AU15P - Build Script"
puts "==============================================================================="
puts ""
puts "  Project: $project_name"
puts "  Part:    $part"
puts "  Dir:     $project_dir"
puts ""

# Create the project targeting the AU15P part
# This will fail gracefully if board files are missing - we just use the part
puts "INFO: Creating project..."

if {[catch {create_project $project_name . -part $part -force} result]} {
    puts "ERROR: Failed to create project: $result"
    exit 1
}

# Check if board files are installed (optional but recommended)
if {[check_board_files]} {
    # Set the board part if available
    set board_part [lindex [get_board_parts -quiet "*auboard_15p*"] 0]
    if {$board_part ne ""} {
        set_property board_part $board_part [current_project]
        puts "INFO: Board part set to: $board_part"
    }
} else {
    puts "WARNING: Continuing without board files (using part only)"
    puts "         Some IP presets may not be available."
}

puts ""
puts "INFO: Project created successfully."
puts ""
puts "==============================================================================="
puts "  Next steps will be added here..."
puts "==============================================================================="
puts ""

# Save off the critical sources names
set synth_sources_name [get_filesets -filter {FILESET_TYPE == "DesignSrcs"}]
set sim_sources_name [get_filesets -filter {FILESET_TYPE == "SimulationSrcs"}]
set impl_sources_name [get_filesets -filter {FILESET_TYPE == "Constrs"}]

# Create the top level block design
create_bd_design $top_level_bd_name
update_compile_order -fileset $synth_sources_name

###############################################################################
# NEORV32 RISC-V Processor
###############################################################################

# Path to NEORV32 sources
set neorv32_home [file normalize "$project_dir/../../../../Softcore_CPU_Simulation"]

# Package NEORV32 as Vivado IP (using existing script)
# Note: neorv32_vivado_ip.tcl creates its own project, packages the IP, then closes it
puts "INFO: Packaging NEORV32 as Vivado IP..."
set neorv32_ip_output_dir "$neorv32_home/rtl/system_integration/neorv32_vivado_ip_work"
source $neorv32_home/rtl/system_integration/neorv32_vivado_ip.tcl

# The neorv32_vivado_ip.tcl script creates/closes its own project for packaging.
# Our project should still be current, but the block design may need reopening.

# Add NEORV32 IP to our project's repository paths
puts "INFO: Adding NEORV32 IP to repository..."
set current_ip_paths [get_property ip_repo_paths [current_project]]
lappend current_ip_paths "$neorv32_ip_output_dir/packaged_ip"
set_property ip_repo_paths $current_ip_paths [current_project]
update_ip_catalog -rebuild

# Reopen the block design
open_bd_design ./$project_name.srcs/$synth_sources_name/bd/$top_level_bd_name/$top_level_bd_name.bd

# Instantiate NEORV32 in block design
puts "INFO: Instantiating NEORV32 in block design..."
create_bd_cell -type ip -vlnv NEORV32:user:neorv32_vivado_ip:1.0 $neorv32_cpu

# Configure NEORV32 for AU15P / FMCOMMS4 application
set_property -dict [list \
    CONFIG.CLOCK_FREQUENCY {100000000} \
    CONFIG.BOOT_MODE_SELECT {0} \
    CONFIG.IMEM_EN {true} \
    CONFIG.IMEM_SIZE {32768} \
    CONFIG.DMEM_EN {true} \
    CONFIG.DMEM_SIZE {16384} \
    CONFIG.RISCV_ISA_C {true} \
    CONFIG.RISCV_ISA_M {true} \
    CONFIG.RISCV_ISA_Zicntr {true} \
    CONFIG.CPU_FAST_MUL_EN {true} \
    CONFIG.CPU_FAST_SHIFT_EN {true} \
    CONFIG.IO_UART0_EN {true} \
    CONFIG.IO_UART0_RX_FIFO {32} \
    CONFIG.IO_UART0_TX_FIFO {32} \
    CONFIG.IO_GPIO_EN {true} \
    CONFIG.IO_GPIO_IN_NUM {8} \
    CONFIG.IO_GPIO_OUT_NUM {8} \
    CONFIG.IO_SPI_EN {true} \
    CONFIG.IO_SPI_FIFO {4} \
    CONFIG.XBUS_EN {true} \
    CONFIG.XBUS_TIMEOUT {255} \
    CONFIG.IO_CLINT_EN {true} \
] [get_bd_cells $neorv32_cpu]

puts "INFO: NEORV32 configured (RV32IMC, 32KB IMEM, 16KB DMEM)"

###############################################################################
# ADI AXI AD9361 IP
###############################################################################

# Path to ADI HDL library
set ad_hdl_dir [file normalize "$project_dir/../../../"]

# Build axi_ad9361 IP if component.xml doesn't exist
set axi_ad9361_dir "$ad_hdl_dir/library/axi_ad9361"
if {![file exists "$axi_ad9361_dir/component.xml"]} {
    puts "INFO: Building axi_ad9361 IP..."
    # Set environment for ADI scripts, this ignores  the current Vivado version check
    set ::env(ADI_IGNORE_VERSION_CHECK) 1

    # Save current directory
    set orig_dir [pwd]
    cd $axi_ad9361_dir

    # Source the IP packaging script
    source axi_ad9361_ip.tcl

    # Return to original directory
    cd $orig_dir

    # Reopen our project (axi_ad9361_ip.tcl creates its own project)
    open_project ./$project_name.xpr

    # Reopen the block design
    open_bd_design ./$project_name.srcs/$synth_sources_name/bd/$top_level_bd_name/$top_level_bd_name.bd
} else {
    puts "INFO: axi_ad9361 IP already built, using existing component.xml"
}

# Add ADI library to IP repository paths
puts "INFO: Adding ADI library to IP repository..."
set current_ip_paths [get_property ip_repo_paths [current_project]]
lappend current_ip_paths "$ad_hdl_dir/library"
set_property ip_repo_paths $current_ip_paths [current_project]
update_ip_catalog -rebuild

# Instantiate axi_ad9361 in block design
puts "INFO: Instantiating axi_ad9361 in block design..."
create_bd_cell -type ip -vlnv analog.com:user:axi_ad9361:1.0 $axi_ad9361

# Configure axi_ad9361 for LVDS mode (FMCOMMS4) - matching KCU105 settings
set_property -dict [list \
    CONFIG.CMOS_OR_LVDS_N {0} \
    CONFIG.ID {0} \
    CONFIG.DAC_DDS_TYPE {1} \
    CONFIG.DAC_DDS_CORDIC_DW {14} \
    CONFIG.ADC_INIT_DELAY {11} \
] [get_bd_cells $axi_ad9361]

puts "INFO: axi_ad9361 configured (LVDS mode, CORDIC DDS, ADC_INIT_DELAY=11)"

# Add the AD9361 FMC I/O external ports
startgroup
    make_bd_pins_external  [get_bd_pins $axi_ad9361/tx_data_out_p]
    make_bd_pins_external  [get_bd_pins $axi_ad9361/tx_data_out_n]
    make_bd_pins_external  [get_bd_pins $axi_ad9361/enable]
    make_bd_pins_external  [get_bd_pins $axi_ad9361/txnrx]
    make_bd_pins_external  [get_bd_pins $axi_ad9361/tx_frame_out_n]
    make_bd_pins_external  [get_bd_pins $axi_ad9361/tx_frame_out_p]
    make_bd_pins_external  [get_bd_pins $axi_ad9361/tx_clk_out_p]
    make_bd_pins_external  [get_bd_pins $axi_ad9361/tx_clk_out_n]
    set_property name enable [get_bd_ports enable_0]
    set_property name txnrx [get_bd_ports txnrx_0]
    set_property name tx_frame_out_n [get_bd_ports tx_frame_out_n_0]
    set_property name tx_frame_out_p [get_bd_ports tx_frame_out_p_0]
    set_property name tx_clk_out_n [get_bd_ports tx_clk_out_n_0]
    set_property name tx_clk_out_p [get_bd_ports tx_clk_out_p_0]
endgroup

# Add board clock input and MMCM
create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 $ecs_clock_300_mhz
set_property -dict [list \
    CONFIG.AUTO_PRIMITIVE {PLL} \
    CONFIG.CLKIN1_JITTER_PS {100.0} \
    CONFIG.CLKOUT1_DRIVES {Buffer} \
    CONFIG.CLKOUT1_JITTER {144.719} \
    CONFIG.CLKOUT1_PHASE_ERROR {114.212} \
    CONFIG.CLKOUT2_DRIVES {Buffer} \
    CONFIG.CLKOUT3_DRIVES {Buffer} \
    CONFIG.CLKOUT4_DRIVES {Buffer} \
    CONFIG.CLKOUT5_DRIVES {Buffer} \
    CONFIG.CLKOUT6_DRIVES {Buffer} \
    CONFIG.CLKOUT7_DRIVES {Buffer} \
    CONFIG.FEEDBACK_SOURCE {FDBK_AUTO} \
    CONFIG.MMCM_BANDWIDTH {OPTIMIZED} \
    CONFIG.MMCM_CLKFBOUT_MULT_F {8} \
    CONFIG.MMCM_CLKIN1_PERIOD {10.000} \
    CONFIG.MMCM_CLKIN2_PERIOD {10.000} \
    CONFIG.MMCM_CLKOUT0_DIVIDE_F {8} \
    CONFIG.MMCM_COMPENSATION {AUTO} \
    CONFIG.MMCM_DIVCLK_DIVIDE {1} \
    CONFIG.OPTIMIZE_CLOCKING_STRUCTURE_EN {true} \
    CONFIG.PRIMITIVE {Auto} \
    CONFIG.PRIM_IN_FREQ {100.000} \
    CONFIG.PRIM_SOURCE {Differential_clock_capable_pin} \
    CONFIG.RESET_BOARD_INTERFACE {system_resetn} \
    CONFIG.RESET_PORT {resetn} \
    CONFIG.RESET_TYPE {ACTIVE_LOW} \
    CONFIG.USE_LOCKED {false} \
  CONFIG.USE_RESET {true} \
] [get_bd_cells $ecs_clock_300_mhz]

# Configure ECS 300MHz input board clock I/O
startgroup
    make_bd_intf_pins_external  [get_bd_intf_pins $ecs_clock_300_mhz/CLK_IN1_D]
    set_property name ecs_clk_in [get_bd_intf_ports CLK_IN1_D_0]
    make_bd_pins_external  [get_bd_pins $ecs_clock_300_mhz/resetn]
    set_property name system_resetn [get_bd_ports resetn_0]
endgroup

# Create reset and clocking
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 $cpu_sys_reset
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 $ad9361_sys_reset

# Create inverter for the NEORV32 active low input reset
create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 $neorv32_cpu_input_reset
set_property -dict [list \
    CONFIG.C_OPERATION {not} \
    CONFIG.C_SIZE {1} \
] [get_bd_cells $neorv32_cpu_input_reset]

# Create the main AXI CPU interconnect
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 $axi_cpu_interconnect
set_property -dict [list \
    CONFIG.NUM_MI {4} \
    CONFIG.NUM_SI {1} \
] [get_bd_cells $axi_cpu_interconnect]

# Create the ADC and DAC FIFOs
create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 $ad9361_derived_reset_inv
set_property -dict [list \
    CONFIG.C_OPERATION {not} \
    CONFIG.C_SIZE {1} \
] [get_bd_cells $ad9361_derived_reset_inv]
create_bd_cell -type ip -vlnv analog.com:user:util_rfifo:1.0 $ad9361_dac_fifo
set_property -dict [list \
    CONFIG.DIN_ADDRESS_WIDTH {4} \
    CONFIG.DIN_DATA_WIDTH {16} \
    CONFIG.DOUT_DATA_WIDTH {16} \
] [get_bd_cells $ad9361_dac_fifo]
create_bd_cell -type ip -vlnv analog.com:user:util_wfifo:1.0 $ad9361_adc_fifo
set_property -dict [list \
    CONFIG.DIN_ADDRESS_WIDTH {4} \
    CONFIG.DIN_DATA_WIDTH {16} \
    CONFIG.DOUT_DATA_WIDTH {16} \
] [get_bd_cells $ad9361_adc_fifo]

# Create AD9361-derived clock handling
create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconcat:1.0 $ad9361_divclk_sel_concat
create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilreduced_logic:1.0 $ad9361_divclk_sel_const
set_property CONFIG.C_SIZE {2} [get_bd_cells $ad9361_divclk_sel_const]
create_bd_cell -type ip -vlnv analog.com:user:util_clkdiv:1.0 $ad9361_divclk_sel
set_property CONFIG.SIM_DEVICE {ULTRASCALE} [get_bd_cells $ad9361_divclk_sel]
connect_bd_net [get_bd_pins $ad9361_divclk_sel_concat/In1] [get_bd_pins $axi_ad9361/dac_r1_mode]
connect_bd_net [get_bd_pins $ad9361_divclk_sel_concat/In0] [get_bd_pins $axi_ad9361/adc_r1_mode]
connect_bd_net [get_bd_pins $ad9361_divclk_sel_concat/dout] [get_bd_pins $ad9361_divclk_sel_const/Op1]
connect_bd_net [get_bd_pins $ad9361_divclk_sel_const/Res] [get_bd_pins $ad9361_divclk_sel/clk_sel]
connect_bd_net [get_bd_pins $ad9361_divclk_sel/clk] [get_bd_pins $axi_ad9361/l_clk]

# Connect critical async resets and clocks for both reset blocks
connect_bd_net [get_bd_ports system_resetn] [get_bd_pins $cpu_sys_reset/ext_reset_in]
connect_bd_net [get_bd_pins $ecs_clock_300_mhz/clk_out1] [get_bd_pins $cpu_sys_reset/slowest_sync_clk]
connect_bd_net [get_bd_pins $cpu_sys_reset/peripheral_aresetn] [get_bd_pins $ad9361_sys_reset/ext_reset_in]
connect_bd_net [get_bd_pins $ad9361_divclk_sel/clk_out] [get_bd_pins $ad9361_sys_reset/slowest_sync_clk]
connect_bd_net [get_bd_pins $ecs_clock_300_mhz/clk_out1] [get_bd_pins $neorv32_cpu/clk]
connect_bd_net [get_bd_pins $cpu_sys_reset/mb_reset] [get_bd_pins $neorv32_cpu_input_reset/Op1]
connect_bd_net [get_bd_pins $neorv32_cpu_input_reset/Res] [get_bd_pins $neorv32_cpu/resetn]
connect_bd_net [get_bd_pins $axi_cpu_interconnect/aclk] [get_bd_pins $ecs_clock_300_mhz/clk_out1]
connect_bd_net [get_bd_pins $axi_cpu_interconnect/aresetn] [get_bd_pins $cpu_sys_reset/peripheral_aresetn]

# Connect CPU and AD9361 external signals
startgroup
    make_bd_pins_external  [get_bd_pins $neorv32_cpu/uart0_txd_o]
    set_property name sys_uart_tx [get_bd_ports uart0_txd_o_0]
    make_bd_pins_external  [get_bd_pins $neorv32_cpu/uart0_rxd_i]
    set_property name sys_uart_rx [get_bd_ports uart0_rxd_i_0]
    make_bd_pins_external  [get_bd_pins AXI_AD9361/rx_clk_in_p]
    set_property name rx_clk_in_p [get_bd_ports rx_clk_in_p_0]
    make_bd_pins_external  [get_bd_pins AXI_AD9361/rx_clk_in_n]
    set_property name rx_clk_in_n [get_bd_ports rx_clk_in_n_0]
    make_bd_pins_external  [get_bd_pins AXI_AD9361/rx_frame_in_p]
    set_property name rx_frame_in_p [get_bd_ports rx_frame_in_p_0]
    make_bd_pins_external  [get_bd_pins AXI_AD9361/rx_frame_in_n]
    set_property name rx_frame_in_n [get_bd_ports rx_frame_in_n_0]
    make_bd_pins_external  [get_bd_pins AXI_AD9361/rx_data_in_p]
    set_property name rx_data_in_p [get_bd_ports rx_data_in_p_0]
    make_bd_pins_external  [get_bd_pins AXI_AD9361/rx_data_in_n]
    set_property name rx_data_in_n [get_bd_ports rx_data_in_n_0]
endgroup

# Connect internal AXI signals
connect_bd_intf_net [get_bd_intf_pins $neorv32_cpu/m_axi] [get_bd_intf_pins $axi_cpu_interconnect/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins $axi_cpu_interconnect/M00_AXI] [get_bd_intf_pins $axi_ad9361/s_axi]

# Connect all the clocks and resets remaining
connect_bd_net [get_bd_pins $axi_ad9361/clk] [get_bd_pins $axi_ad9361/l_clk]
connect_bd_net [get_bd_pins $axi_ad9361/s_axi_aclk] [get_bd_pins $ecs_clock_300_mhz/clk_out1]
connect_bd_net [get_bd_pins $axi_ad9361/s_axi_aresetn] [get_bd_pins $cpu_sys_reset/peripheral_aresetn]
connect_bd_net [get_bd_pins $axi_ad9361/rst] [get_bd_pins $ad9361_derived_reset_inv/Op1]
connect_bd_net [get_bd_pins $ad9361_derived_reset_inv/Res] [get_bd_pins $ad9361_adc_fifo/din_rst]
connect_bd_net [get_bd_pins $ad9361_derived_reset_inv/Res] [get_bd_pins $ad9361_dac_fifo/dout_rst]
connect_bd_net [get_bd_pins $ad9361_adc_fifo/din_clk] [get_bd_pins $axi_ad9361/l_clk]
connect_bd_net [get_bd_pins $ad9361_dac_fifo/dout_clk] [get_bd_pins $axi_ad9361/l_clk]
connect_bd_net [get_bd_pins $ad9361_sys_reset/peripheral_aresetn] [get_bd_pins $ad9361_dac_fifo/din_rstn]
connect_bd_net [get_bd_pins $ad9361_sys_reset/peripheral_aresetn] [get_bd_pins $ad9361_adc_fifo/dout_rstn]
connect_bd_net [get_bd_pins $ad9361_divclk_sel/clk_out] [get_bd_pins $ad9361_adc_fifo/dout_clk]
connect_bd_net [get_bd_pins $ad9361_divclk_sel/clk_out] [get_bd_pins $ad9361_dac_fifo/din_clk]

###############################################################################
# TODO: Add remaining ADI IP blocks and connections
###############################################################################
# - util_tdd_sync (drives AD9361 tdd_sync)
# - util_cpack/util_upack (data packing)
# - axi_dmac (DMA controller ADC)
# - axi_dmac (DMA controller ADC)
# - AXI interconnect (snoop of ADC data)
# - AXI BRAM (storage of snoop ADC data accessible to NEORV32 CPU)
