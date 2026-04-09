###############################################################################
## Copyright (C) 2025 Analog Devices, Inc. All rights reserved.
### SPDX short identifier: ADIBSD
###############################################################################
#
# FMCOMMS2/4 on Avnet AU15P - Top-level build script
#
# Based on the validated neorv32_sw_ad9361_datapath_sim/build_all.tcl design,
# adapted for synthesis targeting the AU15P board with FMCOMMS2/4 FMC card.
#
# Usage (from Vivado TCL console):
#   cd {C:/Work/Sandbox/QPSK_Triple_Comparison/deps/hdl/projects/fmcomms2/au15p}
#   source build_all.tcl
#   build_all
#
# Environment Variables (required):
#   ADI_IP_LOCATION - Path to ADI IP library root (e.g., deps/hdl/library)
#                     Set in ~/.bashrc:
#                       export ADI_IP_LOCATION=/path/to/deps/hdl/library
#
###############################################################################

###############################################################################
# Project configuration (global variables)
###############################################################################

variable project_name "fmcomms2_au15p"
variable part "xcau15p-ffvb676-2-e"
variable project_dir [file dirname [info script]]
variable top_level_bd_name "Top"

###############################################################################
# Block design component names
###############################################################################

# NEORV32 CPU and infrastructure
variable neorv32_cpu "NEORV32_RISC_V"
variable ecs_clock_300_mhz "ECS_Clock_300MHz"
variable cpu_sys_reset "CPU_Reset"
variable neorv32_cpu_input_reset "NEORV32_CPU_Input_Reset_Inv"
variable axi_cpu_interconnect "AXI_CPU_Interconnect"

# BRAM for IQ snapshot data
variable axi_bram_controller "AXI_BRAM_Controller"
variable qpsk_snapshot_bram "QPSK_Snapshot_BRAM"

# AD9361 core and datapath
variable axi_ad9361 "axi_ad9361"
variable axi_ad9361_adapter "axi_ad9361_adapter"

# AXI-Lite to Streaming adapter bridge (100 MHz domain)
variable axi_streaming_adapter "axi_streaming_adapter"

# AXI-Stream CDC FIFOs (100 MHz <-> l_clk)
variable ad9361_cdc_tx_streaming_fifo "ad9361_cdc_tx_streaming_fifo"
variable ad9361_cdc_rx_streaming_fifo "ad9361_cdc_rx_streaming_fifo"

# Reset synchronizer for AD9361 l_clk domain
variable util_ad9361_lclk_reset "util_ad9361_lclk_reset"

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
# Main build procedure
###############################################################################

proc build_all {} {
    # Import global variables
    global project_name part project_dir top_level_bd_name
    global neorv32_cpu ecs_clock_300_mhz cpu_sys_reset neorv32_cpu_input_reset axi_cpu_interconnect
    global axi_bram_controller qpsk_snapshot_bram
    global axi_ad9361 axi_ad9361_adapter
    global axi_streaming_adapter
    global ad9361_cdc_tx_streaming_fifo ad9361_cdc_rx_streaming_fifo
    global util_ad9361_lclk_reset

    # Read ADI IP directory from environment variable
    if {![info exists ::env(ADI_IP_LOCATION)]} {
        puts ""
        puts "==============================================================================="
        puts "  ERROR: ADI_IP_LOCATION environment variable not set"
        puts "==============================================================================="
        puts ""
        puts "  Set it to point to the ADI HDL IP library root:"
        puts ""
        puts "    Windows: set ADI_IP_LOCATION=C:\\Work\\QPSK_Triple_Comparison\\deps\\hdl\\library"
        puts "    Linux:   export ADI_IP_LOCATION=/path/to/deps/hdl/library"
        puts ""
        puts "  The ADI library IPs must be built first:"
        puts ""
        puts "    cd deps/hdl/projects/fmcomms2/kcu105"
        puts "    make"
        puts ""
        puts "==============================================================================="
        return -1
    }
    set adi_ip_dir [file normalize $::env(ADI_IP_LOCATION)]
    if {![file exists $adi_ip_dir]} {
        puts "ERROR: ADI IP directory does not exist: $adi_ip_dir"
        return -1
    }
    puts "INFO: Using ADI IP directory: $adi_ip_dir"

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
    puts "INFO: Creating project..."

    if {[catch {create_project $project_name . -part $part -force} result]} {
        puts "ERROR: Failed to create project: $result"
        return -1
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

    # Save off the critical sources names
    set synth_sources_name [get_filesets -filter {FILESET_TYPE == "DesignSrcs"}]
    set sim_sources_name [get_filesets -filter {FILESET_TYPE == "SimulationSrcs"}]
    set impl_sources_name [get_filesets -filter {FILESET_TYPE == "Constrs"}]

    # Create the top level block design
    create_bd_design $top_level_bd_name
    update_compile_order -fileset $synth_sources_name

    ###########################################################################
    # NEORV32 RISC-V Processor
    ###########################################################################

    # Path to NEORV32 sources (deps/neorv32 relative to au15p)
    set neorv32_home [file normalize "$project_dir/../../../../neorv32"]

    ###########################################################################
    # Install NEORV32 Software Image (ad9361_no-os)
    ###########################################################################
    # Copy the pre-built ad9361_no-os application image into rtl/core/
    # so that IP packaging picks up the correct program.

    set sw_app_dir  "$neorv32_home/sw/ad9361_no-os"
    set prebuilt    "$sw_app_dir/neorv32_imem_image.vhd"
    set app_image   "$neorv32_home/rtl/core/neorv32_imem_image.vhd"

    if {[file exists $prebuilt]} {
        puts "INFO: Installing pre-built ad9361_no-os image..."
        file copy -force $prebuilt $app_image
        puts "INFO: $prebuilt -> $app_image"
    } else {
        puts ""
        puts "ERROR: Pre-built ad9361_no-os application image not found:"
        puts "         $prebuilt"
        puts ""
        puts "  To build it, run the following from a terminal with RISC-V GCC in PATH:"
        puts "    cd $sw_app_dir"
        puts "    make clean_all image"
        puts ""
        puts "  This will produce neorv32_imem_image.vhd in the sw/ad9361_no-os/ directory."
        puts "  Then re-run build_all."
        return -1
    }

    if {![file exists $app_image]} {
        puts "ERROR: Application image not found after copy: $app_image"
        return -1
    }

    # Package NEORV32 as Vivado IP (using existing script)
    puts "INFO: Packaging NEORV32 as Vivado IP..."
    set neorv32_ip_output_dir "$neorv32_home/rtl/system_integration/neorv32_vivado_ip_work"
    source $neorv32_home/rtl/system_integration/neorv32_vivado_ip.tcl

    ###########################################################################
    # AXI AD9361 Adapter HLS IP
    ###########################################################################

    # Use pre-built HLS IP from the project-level src directory
    # Navigate up 5 levels: au15p -> fmcomms2 -> projects -> hdl -> deps -> project root
    set hls_ip_dir [file normalize "$project_dir/../../../../../src/axiad9361_adapter/axiad9361_adapter/hls/impl/ip"]

    if {![file exists $hls_ip_dir]} {
        puts "ERROR: HLS IP directory not found: $hls_ip_dir"
        puts "       Please build the HLS IP first using Vitis HLS."
        return -1
    }
    puts "INFO: Using pre-built HLS IP from: $hls_ip_dir"

    set hls_streaming_adapter_ip_dir [file normalize "$project_dir/../../../../../src/axi_lite_to_streaming_adapter/axi_lite_to_streaming_adapter/hls/impl/ip"]

    if {![file exists $hls_streaming_adapter_ip_dir]} {
        puts "ERROR: HLS IP directory not found: $hls_streaming_adapter_ip_dir"
        puts "       Please build the AXI-Lite to Streaming Adapter HLS IP first using Vitis HLS."
        return -1
    }
    puts "INFO: Using pre-built AXI-Lite to Streaming Adapter HLS IP from: $hls_streaming_adapter_ip_dir"

    # Add NEORV32 IP, ADI IP, and HLS IP to our project's repository paths
    puts "INFO: Adding NEORV32 IP, ADI IP, and HLS IP to repository..."
    set current_ip_paths [get_property ip_repo_paths [current_project]]
    lappend current_ip_paths "$neorv32_ip_output_dir/packaged_ip"
    lappend current_ip_paths $adi_ip_dir
    lappend current_ip_paths $hls_ip_dir
    lappend current_ip_paths $hls_streaming_adapter_ip_dir
    set_property ip_repo_paths $current_ip_paths [current_project]
    update_ip_catalog -rebuild

    puts "INFO: IP repo paths:"
    foreach p [get_property ip_repo_paths [current_project]] {
        puts "  $p"
    }

    # Reopen the block design
    open_bd_design ./$project_name.srcs/$synth_sources_name/bd/$top_level_bd_name/$top_level_bd_name.bd

    # Instantiate NEORV32 in block design
    puts "INFO: Instantiating NEORV32 in block design..."
    create_bd_cell -type ip -vlnv NEORV32:user:neorv32_vivado_ip:1.0 $neorv32_cpu

    # Configure NEORV32 for AU15P / FMCOMMS2 application
    set_property -dict [list \
        CONFIG.CLOCK_FREQUENCY {100000000} \
        CONFIG.BOOT_MODE_SELECT {0} \
        CONFIG.IMEM_EN {true} \
        CONFIG.IMEM_SIZE {131072} \
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

    puts "INFO: NEORV32 configured (RV32IMC, 128KB IMEM, 16KB DMEM)"

    # Add board clock input and MMCM
    create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 $ecs_clock_300_mhz
    set_property -dict [list \
        CONFIG.AUTO_PRIMITIVE {PLL} \
        CONFIG.CLKOUT1_JITTER {101.573} \
        CONFIG.CLKOUT1_PHASE_ERROR {84.323} \
        CONFIG.CLKOUT2_JITTER {81.816} \
        CONFIG.CLKOUT2_PHASE_ERROR {84.323} \
        CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {300.000} \
        CONFIG.CLKOUT2_USED {true} \
        CONFIG.CLKOUT2_DRIVES {Buffer} \
        CONFIG.CLKOUT3_DRIVES {Buffer} \
        CONFIG.CLKOUT4_DRIVES {Buffer} \
        CONFIG.CLKOUT5_DRIVES {Buffer} \
        CONFIG.CLKOUT6_DRIVES {Buffer} \
        CONFIG.CLKOUT7_DRIVES {Buffer} \
        CONFIG.FEEDBACK_SOURCE {FDBK_AUTO} \
        CONFIG.MMCM_BANDWIDTH {OPTIMIZED} \
        CONFIG.MMCM_CLKFBOUT_MULT_F {3} \
        CONFIG.MMCM_CLKIN1_PERIOD {10.000} \
        CONFIG.MMCM_CLKIN2_PERIOD {10.000} \
        CONFIG.MMCM_CLKOUT0_DIVIDE_F {9} \
        CONFIG.MMCM_CLKOUT1_DIVIDE {3} \
        CONFIG.NUM_OUT_CLKS {2} \
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
        set_property CONFIG.FREQ_HZ 300000000 [get_bd_intf_ports /ecs_clk_in]
        make_bd_pins_external  [get_bd_pins $ecs_clock_300_mhz/resetn]
        set_property name system_resetn [get_bd_ports resetn_0]
        set_property -dict [list \
            CONFIG.CLKIN1_JITTER_PS {33.330000000000005} \
            CONFIG.CLKOUT1_JITTER {143.207} \
            CONFIG.MMCM_CLKIN1_PERIOD {3.333} \
            CONFIG.MMCM_CLKIN2_PERIOD {10.0} \
            CONFIG.MMCM_DIVCLK_DIVIDE {3} \
            CONFIG.PRIM_IN_FREQ {300.000} \
        ] [get_bd_cells $ecs_clock_300_mhz]
    endgroup

    # Create reset and clocking
    create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 $cpu_sys_reset

    # Create inverter for the NEORV32 active low input reset
    create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 $neorv32_cpu_input_reset
    set_property -dict [list \
        CONFIG.C_OPERATION {not} \
        CONFIG.C_SIZE {1} \
    ] [get_bd_cells $neorv32_cpu_input_reset]

    # Create the external UART signals
    startgroup
        make_bd_pins_external  [get_bd_pins $neorv32_cpu/uart0_rxd_i]
        set_property name sys_uart_rx [get_bd_ports uart0_rxd_i_0]
        make_bd_pins_external  [get_bd_pins $neorv32_cpu/uart0_txd_o]
        set_property name sys_uart_tx [get_bd_ports uart0_txd_o_0]
    endgroup

    # Create the external SPI signals for AD9361
    startgroup
        make_bd_pins_external [get_bd_pins $neorv32_cpu/spi_clk_o]
        set_property name spi_clk [get_bd_ports spi_clk_o_0]
        make_bd_pins_external [get_bd_pins $neorv32_cpu/spi_dat_o]
        set_property name spi_mosi [get_bd_ports spi_dat_o_0]
        make_bd_pins_external [get_bd_pins $neorv32_cpu/spi_dat_i]
        set_property name spi_miso [get_bd_ports spi_dat_i_0]
        # spi_csn_o is an 8-bit bus — extract bit 0 via xlslice for the single AD9361 CS
        create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 spi_csn_slice
        set_property -dict [list CONFIG.DIN_WIDTH {8} CONFIG.DIN_FROM {0} CONFIG.DIN_TO {0}] [get_bd_cells spi_csn_slice]
        connect_bd_net [get_bd_pins $neorv32_cpu/spi_csn_o] [get_bd_pins spi_csn_slice/Din]
        create_bd_port -dir O spi_csn_0
        connect_bd_net [get_bd_pins spi_csn_slice/Dout] [get_bd_ports spi_csn_0]
    endgroup

    # Create the main AXI CPU interconnect
    # NUM_MI = 3: BRAM controller, axi_ad9361, axi_ad9361_adapter
    create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 $axi_cpu_interconnect
    set_property -dict [list \
        CONFIG.NUM_MI {3} \
        CONFIG.NUM_SI {1} \
    ] [get_bd_cells $axi_cpu_interconnect]

    ###########################################################################
    # QPSK Snapshot BRAM
    ###########################################################################

    # Create the AXI BRAM controller and the BRAM block itself
    create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 $axi_bram_controller
    set_property CONFIG.SINGLE_PORT_BRAM {1} [get_bd_cells $axi_bram_controller]
    set_property CONFIG.READ_LATENCY {2} [get_bd_cells $axi_bram_controller]
    set_property CONFIG.PROTOCOL {AXI4} [get_bd_cells $axi_bram_controller]
    create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 $qpsk_snapshot_bram
    set_property -dict [list CONFIG.Enable_32bit_Address.VALUE_SRC PROPAGATED] [get_bd_cells $qpsk_snapshot_bram]

    # Configure BRAM (no COE initialization for synthesis)
    set_property -dict [list \
        CONFIG.use_bram_block {Stand_Alone} \
        CONFIG.Enable_32bit_Address {true} \
        CONFIG.Enable_A {Always_Enabled} \
        CONFIG.EN_SAFETY_CKT {false} \
        CONFIG.Register_PortA_Output_of_Memory_Core {false} \
        CONFIG.Register_PortA_Output_of_Memory_Primitives {true} \
        CONFIG.Use_RSTA_Pin {false} \
        CONFIG.Fill_Remaining_Memory_Locations {true} \
        CONFIG.Remaining_Memory_Locations {FF} \
    ] [get_bd_cells $qpsk_snapshot_bram]

    ###########################################################################
    # AD9361 Core
    ###########################################################################

    puts "INFO: Instantiating AD9361 core and datapath..."

    # Create AD9361 core
    create_bd_cell -type ip -vlnv analog.com:user:axi_ad9361:1.0 $axi_ad9361
    set_property -dict [list \
        CONFIG.CMOS_OR_LVDS_N {0} \
        CONFIG.ID {0} \
        CONFIG.DAC_DDS_TYPE {1} \
        CONFIG.DAC_DDS_CORDIC_DW {14} \
        CONFIG.ADC_INIT_DELAY {11} \
    ] [get_bd_cells $axi_ad9361]

    # Create external ports for AD9361 LVDS interface
    # RX ports
    create_bd_port -dir I rx_clk_in_p
    create_bd_port -dir I rx_clk_in_n
    create_bd_port -dir I rx_frame_in_p
    create_bd_port -dir I rx_frame_in_n
    # RX data ports — bits [4:0] are HP bank (differential _p/_n naming OK)
    # bit [5] is HD bank 86 — renamed to avoid Vivado differential inference
    create_bd_port -dir I -from 4 -to 0 rx_data_in_p
    create_bd_port -dir I -from 4 -to 0 rx_data_in_n
    create_bd_port -dir I rx_data_5_se        ;# rx_data_in_p[5] on HD bank 86 (IBUF only)
    create_bd_port -dir I rx_data_5_se_unused  ;# rx_data_in_n[5] on HD bank 86 (unconnected)

    # TX ports — HP bank (differential _p/_n naming OK)
    create_bd_port -dir O tx_frame_out_p
    create_bd_port -dir O tx_frame_out_n
    create_bd_port -dir O -from 4 -to 0 tx_data_out_p
    create_bd_port -dir O -from 4 -to 0 tx_data_out_n

    # TX ports — HD bank 86 (pseudo-differential LVCMOS18)
    # Renamed to avoid Vivado _p/_n differential pair inference.
    # PSEUDO_DIFF=1 in axi_ad9361_lvds_if.v drives N as inverted P.
    create_bd_port -dir O tx_clk_se_true
    create_bd_port -dir O tx_clk_se_comp
    create_bd_port -dir O tx_d0_se_true
    create_bd_port -dir O tx_d0_se_comp

    # Control ports (directly from axi_ad9361)
    create_bd_port -dir O enable
    create_bd_port -dir O txnrx

    # ─── RX data: concat 5-bit bus + 1-bit scalar into 6-bit IP pin ───
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 rx_data_p_concat
    set_property -dict [list CONFIG.NUM_PORTS {2} CONFIG.IN0_WIDTH {5} CONFIG.IN1_WIDTH {1}] [get_bd_cells rx_data_p_concat]
    connect_bd_net [get_bd_ports rx_data_in_p]  [get_bd_pins rx_data_p_concat/In0]
    connect_bd_net [get_bd_ports rx_data_5_se]  [get_bd_pins rx_data_p_concat/In1]
    connect_bd_net [get_bd_pins rx_data_p_concat/dout] [get_bd_pins $axi_ad9361/rx_data_in_p]

    create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 rx_data_n_concat
    set_property -dict [list CONFIG.NUM_PORTS {2} CONFIG.IN0_WIDTH {5} CONFIG.IN1_WIDTH {1}] [get_bd_cells rx_data_n_concat]
    connect_bd_net [get_bd_ports rx_data_in_n]       [get_bd_pins rx_data_n_concat/In0]
    connect_bd_net [get_bd_ports rx_data_5_se_unused] [get_bd_pins rx_data_n_concat/In1]
    connect_bd_net [get_bd_pins rx_data_n_concat/dout] [get_bd_pins $axi_ad9361/rx_data_in_n]

    # ─── TX data: slice 6-bit IP pin into 5-bit bus + 1-bit scalar ───
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 tx_data_p_hp_slice
    set_property -dict [list CONFIG.DIN_WIDTH {6} CONFIG.DIN_FROM {5} CONFIG.DIN_TO {1}] [get_bd_cells tx_data_p_hp_slice]
    connect_bd_net [get_bd_pins $axi_ad9361/tx_data_out_p] [get_bd_pins tx_data_p_hp_slice/Din]
    connect_bd_net [get_bd_pins tx_data_p_hp_slice/Dout]   [get_bd_ports tx_data_out_p]

    create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 tx_data_n_hp_slice
    set_property -dict [list CONFIG.DIN_WIDTH {6} CONFIG.DIN_FROM {5} CONFIG.DIN_TO {1}] [get_bd_cells tx_data_n_hp_slice]
    connect_bd_net [get_bd_pins $axi_ad9361/tx_data_out_n] [get_bd_pins tx_data_n_hp_slice/Din]
    connect_bd_net [get_bd_pins tx_data_n_hp_slice/Dout]   [get_bd_ports tx_data_out_n]

    create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 tx_data_p_hd_slice
    set_property -dict [list CONFIG.DIN_WIDTH {6} CONFIG.DIN_FROM {0} CONFIG.DIN_TO {0}] [get_bd_cells tx_data_p_hd_slice]
    connect_bd_net [get_bd_pins $axi_ad9361/tx_data_out_p] [get_bd_pins tx_data_p_hd_slice/Din]
    connect_bd_net [get_bd_pins tx_data_p_hd_slice/Dout]   [get_bd_ports tx_d0_se_true]

    create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 tx_data_n_hd_slice
    set_property -dict [list CONFIG.DIN_WIDTH {6} CONFIG.DIN_FROM {0} CONFIG.DIN_TO {0}] [get_bd_cells tx_data_n_hd_slice]
    connect_bd_net [get_bd_pins $axi_ad9361/tx_data_out_n] [get_bd_pins tx_data_n_hd_slice/Din]
    connect_bd_net [get_bd_pins tx_data_n_hd_slice/Dout]   [get_bd_ports tx_d0_se_comp]

    # ─── Direct connections (unchanged) ───
    connect_bd_net [get_bd_ports rx_clk_in_p] [get_bd_pins $axi_ad9361/rx_clk_in_p]
    connect_bd_net [get_bd_ports rx_clk_in_n] [get_bd_pins $axi_ad9361/rx_clk_in_n]
    connect_bd_net [get_bd_ports rx_frame_in_p] [get_bd_pins $axi_ad9361/rx_frame_in_p]
    connect_bd_net [get_bd_ports rx_frame_in_n] [get_bd_pins $axi_ad9361/rx_frame_in_n]
    connect_bd_net [get_bd_ports tx_clk_se_true] [get_bd_pins $axi_ad9361/tx_clk_out_p]
    connect_bd_net [get_bd_ports tx_clk_se_comp] [get_bd_pins $axi_ad9361/tx_clk_out_n]
    connect_bd_net [get_bd_ports tx_frame_out_p] [get_bd_pins $axi_ad9361/tx_frame_out_p]
    connect_bd_net [get_bd_ports tx_frame_out_n] [get_bd_pins $axi_ad9361/tx_frame_out_n]
    connect_bd_net [get_bd_ports enable] [get_bd_pins $axi_ad9361/enable]
    connect_bd_net [get_bd_ports txnrx] [get_bd_pins $axi_ad9361/txnrx]

    # Tie off tdd_sync (TDD not used — running FDD mode)
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 tdd_sync_const
    set_property -dict [list CONFIG.CONST_VAL {0} CONFIG.CONST_WIDTH {1}] [get_bd_cells tdd_sync_const]
    connect_bd_net [get_bd_pins tdd_sync_const/dout] [get_bd_pins $axi_ad9361/tdd_sync]

    # Connect delay_clk for IODELAY calibration (300 MHz from clk_out2)
    connect_bd_net [get_bd_pins $axi_ad9361/delay_clk] [get_bd_pins $ecs_clock_300_mhz/clk_out2]

    # Connect l_clk to itself (AD9361 uses recovered clock internally)
    connect_bd_net [get_bd_pins $axi_ad9361/l_clk] [get_bd_pins $axi_ad9361/clk]

    # Connect AXI clock and reset
    connect_bd_net [get_bd_pins $ecs_clock_300_mhz/clk_out1] [get_bd_pins $axi_ad9361/s_axi_aclk]
    connect_bd_net [get_bd_pins $cpu_sys_reset/peripheral_aresetn] [get_bd_pins $axi_ad9361/s_axi_aresetn]

    # Connect up_enable and up_txnrx from NEORV32 GPIO
    # GPIO[0] = up_enable, GPIO[1] = up_txnrx
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 gpio_up_enable_slice
    set_property -dict [list CONFIG.DIN_WIDTH {8} CONFIG.DIN_FROM {0} CONFIG.DIN_TO {0}] [get_bd_cells gpio_up_enable_slice]
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 gpio_up_txnrx_slice
    set_property -dict [list CONFIG.DIN_WIDTH {8} CONFIG.DIN_FROM {1} CONFIG.DIN_TO {1}] [get_bd_cells gpio_up_txnrx_slice]

    connect_bd_net [get_bd_pins $neorv32_cpu/gpio_o] [get_bd_pins gpio_up_enable_slice/Din]
    connect_bd_net [get_bd_pins $neorv32_cpu/gpio_o] [get_bd_pins gpio_up_txnrx_slice/Din]
    connect_bd_net [get_bd_pins gpio_up_enable_slice/Dout] [get_bd_pins $axi_ad9361/up_enable]
    connect_bd_net [get_bd_pins gpio_up_txnrx_slice/Dout] [get_bd_pins $axi_ad9361/up_txnrx]

    # Additional GPIO slices for AD9361 control signals
    # GPIO[2] = gpio_resetb (AD9361 hard reset)
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 gpio_resetb_slice
    set_property -dict [list CONFIG.DIN_WIDTH {8} CONFIG.DIN_FROM {2} CONFIG.DIN_TO {2}] [get_bd_cells gpio_resetb_slice]
    connect_bd_net [get_bd_pins $neorv32_cpu/gpio_o] [get_bd_pins gpio_resetb_slice/Din]
    create_bd_port -dir O gpio_resetb
    connect_bd_net [get_bd_pins gpio_resetb_slice/Dout] [get_bd_ports gpio_resetb]

    # GPIO[3] = gpio_sync (multi-chip sync)
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 gpio_sync_slice
    set_property -dict [list CONFIG.DIN_WIDTH {8} CONFIG.DIN_FROM {3} CONFIG.DIN_TO {3}] [get_bd_cells gpio_sync_slice]
    connect_bd_net [get_bd_pins $neorv32_cpu/gpio_o] [get_bd_pins gpio_sync_slice/Din]
    create_bd_port -dir O gpio_sync
    connect_bd_net [get_bd_pins gpio_sync_slice/Dout] [get_bd_ports gpio_sync]

    # GPIO[4] = gpio_en_agc (AGC enable)
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 gpio_en_agc_slice
    set_property -dict [list CONFIG.DIN_WIDTH {8} CONFIG.DIN_FROM {4} CONFIG.DIN_TO {4}] [get_bd_cells gpio_en_agc_slice]
    connect_bd_net [get_bd_pins $neorv32_cpu/gpio_o] [get_bd_pins gpio_en_agc_slice/Din]
    create_bd_port -dir O gpio_en_agc
    connect_bd_net [get_bd_pins gpio_en_agc_slice/Dout] [get_bd_ports gpio_en_agc]

    # GPIO[7:5] = gpio_ctl[3:0] (control signals, padded with constant 0 for bit 3)
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 gpio_ctl_slice
    set_property -dict [list CONFIG.DIN_WIDTH {8} CONFIG.DIN_FROM {7} CONFIG.DIN_TO {5} CONFIG.DOUT_WIDTH {3}] [get_bd_cells gpio_ctl_slice]
    connect_bd_net [get_bd_pins $neorv32_cpu/gpio_o] [get_bd_pins gpio_ctl_slice/Din]
    create_bd_port -dir O -from 3 -to 0 gpio_ctl
    # Concatenate the 3-bit slice with a constant 0 for gpio_ctl[3]
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 gpio_ctl_concat
    set_property CONFIG.NUM_PORTS {2} [get_bd_cells gpio_ctl_concat]
    connect_bd_net [get_bd_pins gpio_ctl_slice/Dout] [get_bd_pins gpio_ctl_concat/In0]
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 gpio_ctl_pad_const
    set_property -dict [list CONFIG.CONST_VAL {0} CONFIG.CONST_WIDTH {1}] [get_bd_cells gpio_ctl_pad_const]
    connect_bd_net [get_bd_pins gpio_ctl_pad_const/dout] [get_bd_pins gpio_ctl_concat/In1]
    connect_bd_net [get_bd_pins gpio_ctl_concat/dout] [get_bd_ports gpio_ctl]

    # GPIO inputs: gpio_status[7:0] directly to NEORV32 gpio_i
    create_bd_port -dir I -from 7 -to 0 gpio_status
    connect_bd_net [get_bd_ports gpio_status] [get_bd_pins $neorv32_cpu/gpio_i]

    ###########################################################################
    # Reset Synchronizer for AD9361 l_clk Domain
    ###########################################################################

    puts "INFO: Creating l_clk domain reset synchronizer..."

    # Reset synchronizer for l_clk domain (used by HLS adapter datapath)
    create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 $util_ad9361_lclk_reset
    connect_bd_net [get_bd_pins $cpu_sys_reset/peripheral_aresetn] [get_bd_pins $util_ad9361_lclk_reset/ext_reset_in]
    connect_bd_net [get_bd_pins $axi_ad9361/l_clk] [get_bd_pins $util_ad9361_lclk_reset/slowest_sync_clk]

    ###########################################################################
    # AXI AD9361 Adapter (HLS IP)
    # Replaces: util_ad9361_adc_fifo, util_ad9361_adc_pack,
    #           axi_ad9361_dac_fifo, util_ad9361_dac_upack
    # Provides: Internal TX/RX BRAMs, loopback capability, AXI-Lite control
    ###########################################################################

    puts "INFO: Instantiating AXI AD9361 Adapter..."

    # Create the HLS adapter IP (v5.0: AXI-Stream + ap_none, single clock domain)
    create_bd_cell -type ip -vlnv user:hls:axi_ad9361_adapter:5.0 $axi_ad9361_adapter

    # Connect adapter clock and reset (l_clk domain)
    connect_bd_net [get_bd_pins $axi_ad9361/l_clk] [get_bd_pins $axi_ad9361_adapter/ap_clk]
    connect_bd_net [get_bd_pins $util_ad9361_lclk_reset/peripheral_aresetn] [get_bd_pins $axi_ad9361_adapter/ap_rst_n]

    # Connect ADC data from axi_ad9361 to adapter
    # Channel 0 I/Q
    connect_bd_net [get_bd_pins $axi_ad9361/adc_data_i0] [get_bd_pins $axi_ad9361_adapter/adc_data_i0]
    connect_bd_net [get_bd_pins $axi_ad9361/adc_data_q0] [get_bd_pins $axi_ad9361_adapter/adc_data_q0]
    connect_bd_net [get_bd_pins $axi_ad9361/adc_enable_i0] [get_bd_pins $axi_ad9361_adapter/adc_enable_i0]
    connect_bd_net [get_bd_pins $axi_ad9361/adc_enable_q0] [get_bd_pins $axi_ad9361_adapter/adc_enable_q0]
    connect_bd_net [get_bd_pins $axi_ad9361/adc_valid_i0] [get_bd_pins $axi_ad9361_adapter/adc_valid_i0]
    connect_bd_net [get_bd_pins $axi_ad9361/adc_valid_q0] [get_bd_pins $axi_ad9361_adapter/adc_valid_q0]

    # Channel 1 I/Q
    connect_bd_net [get_bd_pins $axi_ad9361/adc_data_i1] [get_bd_pins $axi_ad9361_adapter/adc_data_i1]
    connect_bd_net [get_bd_pins $axi_ad9361/adc_data_q1] [get_bd_pins $axi_ad9361_adapter/adc_data_q1]
    connect_bd_net [get_bd_pins $axi_ad9361/adc_enable_i1] [get_bd_pins $axi_ad9361_adapter/adc_enable_i1]
    connect_bd_net [get_bd_pins $axi_ad9361/adc_enable_q1] [get_bd_pins $axi_ad9361_adapter/adc_enable_q1]
    connect_bd_net [get_bd_pins $axi_ad9361/adc_valid_i1] [get_bd_pins $axi_ad9361_adapter/adc_valid_i1]
    connect_bd_net [get_bd_pins $axi_ad9361/adc_valid_q1] [get_bd_pins $axi_ad9361_adapter/adc_valid_q1]

    # ADC overflow handling
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 adc_dovf_const
    set_property -dict [list CONFIG.CONST_VAL {0} CONFIG.CONST_WIDTH {1}] [get_bd_cells adc_dovf_const]
    connect_bd_net [get_bd_pins adc_dovf_const/dout] [get_bd_pins $axi_ad9361/adc_dovf]
    connect_bd_net [get_bd_pins adc_dovf_const/dout] [get_bd_pins $axi_ad9361_adapter/adc_dovf]

    # Connect DAC data from adapter to axi_ad9361
    # Channel 0 I/Q
    connect_bd_net [get_bd_pins $axi_ad9361_adapter/dac_data_i0] [get_bd_pins $axi_ad9361/dac_data_i0]
    connect_bd_net [get_bd_pins $axi_ad9361_adapter/dac_data_q0] [get_bd_pins $axi_ad9361/dac_data_q0]

    # Channel 1 I/Q
    connect_bd_net [get_bd_pins $axi_ad9361_adapter/dac_data_i1] [get_bd_pins $axi_ad9361/dac_data_i1]
    connect_bd_net [get_bd_pins $axi_ad9361_adapter/dac_data_q1] [get_bd_pins $axi_ad9361/dac_data_q1]

    # Connect DAC control signals from axi_ad9361 to adapter
    # Channel 0 I/Q
    connect_bd_net [get_bd_pins $axi_ad9361/dac_valid_i0] [get_bd_pins $axi_ad9361_adapter/dac_valid_i0]
    connect_bd_net [get_bd_pins $axi_ad9361/dac_valid_q0] [get_bd_pins $axi_ad9361_adapter/dac_valid_q0]
    connect_bd_net [get_bd_pins $axi_ad9361/dac_enable_i0] [get_bd_pins $axi_ad9361_adapter/dac_enable_i0]
    connect_bd_net [get_bd_pins $axi_ad9361/dac_enable_q0] [get_bd_pins $axi_ad9361_adapter/dac_enable_q0]

    # Channel 1 I/Q
    connect_bd_net [get_bd_pins $axi_ad9361/dac_valid_i1] [get_bd_pins $axi_ad9361_adapter/dac_valid_i1]
    connect_bd_net [get_bd_pins $axi_ad9361/dac_valid_q1] [get_bd_pins $axi_ad9361_adapter/dac_valid_q1]
    connect_bd_net [get_bd_pins $axi_ad9361/dac_enable_i1] [get_bd_pins $axi_ad9361_adapter/dac_enable_i1]
    connect_bd_net [get_bd_pins $axi_ad9361/dac_enable_q1] [get_bd_pins $axi_ad9361_adapter/dac_enable_q1]

    # Connect DAC underflow from adapter to axi_ad9361
    connect_bd_net [get_bd_pins $axi_ad9361_adapter/dac_dunf] [get_bd_pins $axi_ad9361/dac_dunf]

    ###########################################################################
    # AXI-Lite to Streaming Adapter (HLS IP)
    # Bridges CPU AXI-Lite to the AD9361 adapter's AXI-Stream and ap_none
    # control/status interfaces.  Runs in the 100 MHz AXI clock domain.
    ###########################################################################

    puts "INFO: Instantiating AXI-Lite to Streaming Adapter..."

    create_bd_cell -type ip -vlnv user:hls:axi_lite_to_streaming_adapter:1.0 $axi_streaming_adapter

    # Connect adapter clock and reset (100 MHz AXI domain)
    connect_bd_net [get_bd_pins $ecs_clock_300_mhz/clk_out1] [get_bd_pins $axi_streaming_adapter/ap_clk]
    connect_bd_net [get_bd_pins $cpu_sys_reset/peripheral_aresetn] [get_bd_pins $axi_streaming_adapter/ap_rst_n]

    ###########################################################################
    # AXI-Stream CDC FIFOs (100 MHz <-> l_clk)
    ###########################################################################

    puts "INFO: Instantiating AXI-Stream CDC FIFOs..."

    # TX CDC FIFO: axi_streaming_adapter (100 MHz) -> ad9361_adapter (l_clk)
    create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo:2.0 $ad9361_cdc_tx_streaming_fifo
    set_property -dict [list CONFIG.HAS_TLAST.VALUE_SRC USER] [get_bd_cells $ad9361_cdc_tx_streaming_fifo]
    set_property -dict [list \
        CONFIG.FIFO_DEPTH {256} \
        CONFIG.HAS_TLAST {1} \
        CONFIG.IS_ACLK_ASYNC {1} \
    ] [get_bd_cells $ad9361_cdc_tx_streaming_fifo]

    # TX FIFO clocks and resets
    connect_bd_net [get_bd_pins $ecs_clock_300_mhz/clk_out1]             [get_bd_pins $ad9361_cdc_tx_streaming_fifo/s_axis_aclk]
    connect_bd_net [get_bd_pins $cpu_sys_reset/peripheral_aresetn]        [get_bd_pins $ad9361_cdc_tx_streaming_fifo/s_axis_aresetn]
    connect_bd_net [get_bd_pins $axi_ad9361/l_clk]                       [get_bd_pins $ad9361_cdc_tx_streaming_fifo/m_axis_aclk]

    # TX FIFO data path: streaming adapter -> FIFO -> ad9361_adapter
    connect_bd_intf_net [get_bd_intf_pins $axi_streaming_adapter/tx_stream]      [get_bd_intf_pins $ad9361_cdc_tx_streaming_fifo/S_AXIS]
    connect_bd_intf_net [get_bd_intf_pins $ad9361_cdc_tx_streaming_fifo/M_AXIS]  [get_bd_intf_pins $axi_ad9361_adapter/tx_stream]

    # RX CDC FIFO: ad9361_adapter (l_clk) -> axi_streaming_adapter (100 MHz)
    create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo:2.0 $ad9361_cdc_rx_streaming_fifo
    set_property -dict [list CONFIG.HAS_TLAST.VALUE_SRC USER] [get_bd_cells $ad9361_cdc_rx_streaming_fifo]
    set_property -dict [list \
        CONFIG.FIFO_DEPTH {256} \
        CONFIG.HAS_TLAST {1} \
        CONFIG.IS_ACLK_ASYNC {1} \
    ] [get_bd_cells $ad9361_cdc_rx_streaming_fifo]

    # RX FIFO clocks and resets
    connect_bd_net [get_bd_pins $axi_ad9361/l_clk]                          [get_bd_pins $ad9361_cdc_rx_streaming_fifo/s_axis_aclk]
    connect_bd_net [get_bd_pins $util_ad9361_lclk_reset/peripheral_aresetn] [get_bd_pins $ad9361_cdc_rx_streaming_fifo/s_axis_aresetn]
    connect_bd_net [get_bd_pins $ecs_clock_300_mhz/clk_out1]               [get_bd_pins $ad9361_cdc_rx_streaming_fifo/m_axis_aclk]

    # RX FIFO data path: ad9361_adapter -> FIFO -> streaming adapter
    connect_bd_intf_net [get_bd_intf_pins $axi_ad9361_adapter/rx_stream]          [get_bd_intf_pins $ad9361_cdc_rx_streaming_fifo/S_AXIS]
    connect_bd_intf_net [get_bd_intf_pins $ad9361_cdc_rx_streaming_fifo/M_AXIS]   [get_bd_intf_pins $axi_streaming_adapter/rx_stream]

    ###########################################################################
    # AXI and Reset Connections
    ###########################################################################

    puts "INFO: Connecting clocks, resets, and AXI interfaces..."

    # Connect critical async resets and clocks
    connect_bd_net [get_bd_ports system_resetn] [get_bd_pins $cpu_sys_reset/ext_reset_in]
    connect_bd_net [get_bd_pins $ecs_clock_300_mhz/clk_out1] [get_bd_pins $cpu_sys_reset/slowest_sync_clk]
    connect_bd_net [get_bd_pins $ecs_clock_300_mhz/clk_out1] [get_bd_pins $neorv32_cpu/clk]
    connect_bd_net [get_bd_pins $cpu_sys_reset/mb_reset] [get_bd_pins $neorv32_cpu_input_reset/Op1]
    connect_bd_net [get_bd_pins $neorv32_cpu_input_reset/Res] [get_bd_pins $neorv32_cpu/resetn]
    connect_bd_net [get_bd_pins $axi_cpu_interconnect/aclk] [get_bd_pins $ecs_clock_300_mhz/clk_out1]
    connect_bd_net [get_bd_pins $axi_cpu_interconnect/aresetn] [get_bd_pins $cpu_sys_reset/peripheral_aresetn]
    connect_bd_net [get_bd_pins $axi_bram_controller/s_axi_aresetn] [get_bd_pins $cpu_sys_reset/peripheral_aresetn]
    connect_bd_net [get_bd_pins $axi_bram_controller/s_axi_aclk] [get_bd_pins $ecs_clock_300_mhz/clk_out1]

    # Connect internal AXI signals and BRAM memory signals
    connect_bd_intf_net [get_bd_intf_pins $neorv32_cpu/m_axi] [get_bd_intf_pins $axi_cpu_interconnect/S00_AXI]
    connect_bd_intf_net [get_bd_intf_pins $axi_bram_controller/S_AXI] [get_bd_intf_pins $axi_cpu_interconnect/M00_AXI]
    connect_bd_intf_net [get_bd_intf_pins $axi_bram_controller/BRAM_PORTA] [get_bd_intf_pins $qpsk_snapshot_bram/BRAM_PORTA]

    # Connect axi_ad9361 AXI interface
    connect_bd_intf_net [get_bd_intf_pins $axi_ad9361/s_axi] [get_bd_intf_pins $axi_cpu_interconnect/M01_AXI]

    # Connect axi_streaming_adapter AXI-Lite control interface
    connect_bd_intf_net [get_bd_intf_pins $axi_streaming_adapter/s_axi_ctrl] [get_bd_intf_pins $axi_cpu_interconnect/M02_AXI]

    ###########################################################################
    # Address Assignment
    ###########################################################################

    puts "INFO: Assigning addresses..."

    # BRAM at 0xC0000000 (32KB range)
    assign_bd_address -target_address_space /$neorv32_cpu/m_axi [get_bd_addr_segs $axi_bram_controller/S_AXI/Mem0] -force
    set_property offset 0xC0000000 [get_bd_addr_segs {NEORV32_RISC_V/m_axi/SEG_AXI_BRAM_Controller_Mem0}]
    set_property range 32K [get_bd_addr_segs {NEORV32_RISC_V/m_axi/SEG_AXI_BRAM_Controller_Mem0}]

    # axi_ad9361 at 0x44A00000 (64KB range)
    assign_bd_address -target_address_space /$neorv32_cpu/m_axi [get_bd_addr_segs $axi_ad9361/s_axi/axi_lite] -force
    set_property offset 0x44A00000 [get_bd_addr_segs {NEORV32_RISC_V/m_axi/SEG_axi_ad9361_axi_lite}]
    set_property range 64K [get_bd_addr_segs {NEORV32_RISC_V/m_axi/SEG_axi_ad9361_axi_lite}]

    # axi_streaming_adapter at 0x44A10000 (16KB range)
    assign_bd_address -target_address_space /$neorv32_cpu/m_axi [get_bd_addr_segs $axi_streaming_adapter/s_axi_ctrl/Reg] -force
    set_property offset 0x44A10000 [get_bd_addr_segs {NEORV32_RISC_V/m_axi/SEG_axi_streaming_adapter_Reg}]
    set_property range 16K [get_bd_addr_segs {NEORV32_RISC_V/m_axi/SEG_axi_streaming_adapter_Reg}]

    ###########################################################################
    # Save and Generate
    ###########################################################################

    validate_bd_design
    save_bd_design
    set_property target_language VHDL [current_project]
    make_wrapper -files [get_files $project_dir/$project_name.srcs/$synth_sources_name/bd/$top_level_bd_name/$top_level_bd_name.bd] -top
    add_files -norecurse $project_dir/$project_name.gen/$synth_sources_name/bd/$top_level_bd_name/hdl/${top_level_bd_name}_wrapper.vhd
    add_files -fileset constrs_1 -norecurse $project_dir/system_constr.xdc
    save_bd_design

    # Generate output products for all IP
    update_compile_order -fileset sources_1
    set bd_file "$project_dir/$project_name.srcs/$synth_sources_name/bd/$top_level_bd_name/$top_level_bd_name.bd"
    generate_target all [get_files $bd_file]

    puts ""
    puts "==============================================================================="
    puts "  Build complete!"
    puts "==============================================================================="
    puts ""
    puts "  Project saved to: $project_dir/$project_name.xpr"
    puts "  Open in Vivado GUI to continue working manually."
    puts ""

    return 0
}
# End of build_all procedure

puts ""
puts "==============================================================================="
puts "  build_all.tcl loaded successfully"
puts "==============================================================================="
puts ""
puts "  Usage: build_all"
puts ""
puts "  Requires ADI_IP_LOCATION environment variable to be set:"
puts "    export ADI_IP_LOCATION=/path/to/deps/hdl/library"
puts ""
