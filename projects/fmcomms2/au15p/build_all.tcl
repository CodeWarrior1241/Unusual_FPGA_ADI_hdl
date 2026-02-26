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
# Or with explicit ADI IP path:
#   build_all "C:/Work/Sandbox/QPSK_Triple_Comparison/deps/hdl/library"
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

# Clock divider logic for AD9361 sampling clock
variable util_ad9361_divclk "util_ad9361_divclk"
variable util_ad9361_divclk_sel "util_ad9361_divclk_sel"
variable util_ad9361_divclk_sel_concat "util_ad9361_divclk_sel_concat"
variable util_ad9361_divclk_reset "util_ad9361_divclk_reset"

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

proc build_all {{adi_ip_dir ""}} {
    # Import global variables
    global project_name part project_dir top_level_bd_name
    global neorv32_cpu ecs_clock_300_mhz cpu_sys_reset neorv32_cpu_input_reset axi_cpu_interconnect
    global axi_bram_controller qpsk_snapshot_bram
    global axi_ad9361 axi_ad9361_adapter
    global util_ad9361_divclk util_ad9361_divclk_sel util_ad9361_divclk_sel_concat util_ad9361_divclk_reset

    # Default ADI IP directory: relative to this script (deps/hdl/library)
    if {$adi_ip_dir eq ""} {
        set adi_ip_dir [file normalize "$project_dir/../../../library"]
    } else {
        set adi_ip_dir [file normalize $adi_ip_dir]
    }

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
    # Install NEORV32 Software Image (ad9361_loopback)
    ###########################################################################
    # Copy the pre-built ad9361_loopback application image into rtl/core/
    # so that IP packaging picks up the correct program.

    set sw_app_dir  "$neorv32_home/sw/ad9361_loopback"
    set prebuilt    "$sw_app_dir/neorv32_application_image.vhd"
    set app_image   "$neorv32_home/rtl/core/neorv32_application_image.vhd"

    if {[file exists $prebuilt]} {
        puts "INFO: Installing pre-built ad9361_loopback image..."
        file copy -force $prebuilt $app_image
        puts "INFO: $prebuilt -> $app_image"
    } else {
        puts ""
        puts "ERROR: Pre-built ad9361_loopback application image not found:"
        puts "         $prebuilt"
        puts ""
        puts "  To build it, run the following from a terminal with RISC-V GCC in PATH:"
        puts "    cd $sw_app_dir"
        puts "    make clean_all image"
        puts ""
        puts "  This will produce neorv32_application_image.vhd in the sw/ad9361_loopback/ directory."
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

    # Add NEORV32 IP, ADI IP, and HLS IP to our project's repository paths
    puts "INFO: Adding NEORV32 IP, ADI IP, and HLS IP to repository..."
    set current_ip_paths [get_property ip_repo_paths [current_project]]
    lappend current_ip_paths "$neorv32_ip_output_dir/packaged_ip"
    lappend current_ip_paths $adi_ip_dir
    lappend current_ip_paths $hls_ip_dir
    set_property ip_repo_paths $current_ip_paths [current_project]
    update_ip_catalog -rebuild

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
        make_bd_pins_external [get_bd_pins $neorv32_cpu/spi_csn_o]
        set_property name spi_csn_0 [get_bd_ports spi_csn_o_0]
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
    create_bd_port -dir I -from 5 -to 0 rx_data_in_p
    create_bd_port -dir I -from 5 -to 0 rx_data_in_n

    # TX ports
    create_bd_port -dir O tx_clk_out_p
    create_bd_port -dir O tx_clk_out_n
    create_bd_port -dir O tx_frame_out_p
    create_bd_port -dir O tx_frame_out_n
    create_bd_port -dir O -from 5 -to 0 tx_data_out_p
    create_bd_port -dir O -from 5 -to 0 tx_data_out_n

    # Control ports (directly from axi_ad9361)
    create_bd_port -dir O enable
    create_bd_port -dir O txnrx

    # Connect AD9361 LVDS ports
    connect_bd_net [get_bd_ports rx_clk_in_p] [get_bd_pins $axi_ad9361/rx_clk_in_p]
    connect_bd_net [get_bd_ports rx_clk_in_n] [get_bd_pins $axi_ad9361/rx_clk_in_n]
    connect_bd_net [get_bd_ports rx_frame_in_p] [get_bd_pins $axi_ad9361/rx_frame_in_p]
    connect_bd_net [get_bd_ports rx_frame_in_n] [get_bd_pins $axi_ad9361/rx_frame_in_n]
    connect_bd_net [get_bd_ports rx_data_in_p] [get_bd_pins $axi_ad9361/rx_data_in_p]
    connect_bd_net [get_bd_ports rx_data_in_n] [get_bd_pins $axi_ad9361/rx_data_in_n]
    connect_bd_net [get_bd_ports tx_clk_out_p] [get_bd_pins $axi_ad9361/tx_clk_out_p]
    connect_bd_net [get_bd_ports tx_clk_out_n] [get_bd_pins $axi_ad9361/tx_clk_out_n]
    connect_bd_net [get_bd_ports tx_frame_out_p] [get_bd_pins $axi_ad9361/tx_frame_out_p]
    connect_bd_net [get_bd_ports tx_frame_out_n] [get_bd_pins $axi_ad9361/tx_frame_out_n]
    connect_bd_net [get_bd_ports tx_data_out_p] [get_bd_pins $axi_ad9361/tx_data_out_p]
    connect_bd_net [get_bd_ports tx_data_out_n] [get_bd_pins $axi_ad9361/tx_data_out_n]
    connect_bd_net [get_bd_ports enable] [get_bd_pins $axi_ad9361/enable]
    connect_bd_net [get_bd_ports txnrx] [get_bd_pins $axi_ad9361/txnrx]

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
    # Clock Divider Logic for AD9361 Sampling Clock
    # Interface runs at 4x in 2r2t mode, and 2x in 1r1t mode
    ###########################################################################

    puts "INFO: Creating AD9361 clock divider logic..."

    # Mode selection concatenation
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 $util_ad9361_divclk_sel_concat
    set_property CONFIG.NUM_PORTS {2} [get_bd_cells $util_ad9361_divclk_sel_concat]
    connect_bd_net [get_bd_pins $axi_ad9361/adc_r1_mode] [get_bd_pins $util_ad9361_divclk_sel_concat/In0]
    connect_bd_net [get_bd_pins $axi_ad9361/dac_r1_mode] [get_bd_pins $util_ad9361_divclk_sel_concat/In1]

    # Reduced logic for clock selection
    create_bd_cell -type ip -vlnv xilinx.com:ip:util_reduced_logic:2.0 $util_ad9361_divclk_sel
    set_property CONFIG.C_SIZE {2} [get_bd_cells $util_ad9361_divclk_sel]
    connect_bd_net [get_bd_pins $util_ad9361_divclk_sel_concat/dout] [get_bd_pins $util_ad9361_divclk_sel/Op1]

    # Clock divider (ADI IP)
    create_bd_cell -type ip -vlnv analog.com:user:util_clkdiv:1.0 $util_ad9361_divclk
    set_property CONFIG.SIM_DEVICE {ULTRASCALE} [get_bd_cells $util_ad9361_divclk]
    connect_bd_net [get_bd_pins $util_ad9361_divclk_sel/Res] [get_bd_pins $util_ad9361_divclk/clk_sel]
    connect_bd_net [get_bd_pins $axi_ad9361/l_clk] [get_bd_pins $util_ad9361_divclk/clk]

    # Reset synchronizer for divided clock domain
    create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 $util_ad9361_divclk_reset
    connect_bd_net [get_bd_pins $cpu_sys_reset/peripheral_aresetn] [get_bd_pins $util_ad9361_divclk_reset/ext_reset_in]
    connect_bd_net [get_bd_pins $util_ad9361_divclk/clk_out] [get_bd_pins $util_ad9361_divclk_reset/slowest_sync_clk]

    ###########################################################################
    # AXI AD9361 Adapter (HLS IP)
    # Replaces: util_ad9361_adc_fifo, util_ad9361_adc_pack,
    #           axi_ad9361_dac_fifo, util_ad9361_dac_upack
    # Provides: Internal TX/RX BRAMs, loopback capability, AXI-Lite control
    ###########################################################################

    puts "INFO: Instantiating AXI AD9361 Adapter..."

    # Create the HLS adapter IP
    create_bd_cell -type ip -vlnv user:hls:axi_ad9361_adapter:3.0 $axi_ad9361_adapter

    # Connect adapter clock and reset (uses AXI clock domain)
    connect_bd_net [get_bd_pins $ecs_clock_300_mhz/clk_out1] [get_bd_pins $axi_ad9361_adapter/ap_clk]
    connect_bd_net [get_bd_pins $cpu_sys_reset/peripheral_aresetn] [get_bd_pins $axi_ad9361_adapter/ap_rst_n]

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

    # Connect axi_ad9361_adapter AXI-Lite control interface
    connect_bd_intf_net [get_bd_intf_pins $axi_ad9361_adapter/s_axi_ctrl] [get_bd_intf_pins $axi_cpu_interconnect/M02_AXI]

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

    # axi_ad9361_adapter at 0x44A10000 (16KB range)
    assign_bd_address -target_address_space /$neorv32_cpu/m_axi [get_bd_addr_segs $axi_ad9361_adapter/s_axi_ctrl/Reg] -force
    set_property offset 0x44A10000 [get_bd_addr_segs {NEORV32_RISC_V/m_axi/SEG_axi_ad9361_adapter_Reg}]
    set_property range 16K [get_bd_addr_segs {NEORV32_RISC_V/m_axi/SEG_axi_ad9361_adapter_Reg}]

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
puts "    or:  build_all \"<path_to_adi_ip_library>\""
puts ""
puts "  Example:"
puts "    build_all"
puts "    build_all \"C:/Work/Sandbox/QPSK_Triple_Comparison/deps/hdl/library\""
puts ""
