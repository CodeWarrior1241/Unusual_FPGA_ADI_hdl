###############################################################################
## Copyright (C) 2025 Analog Devices, Inc. All rights reserved.
### SPDX short identifier: ADIBSD
###############################################################################
#
# FMCOMMS2/4 on Alinx AXAU15 - Top-level build script
#
# Forked from projects/fmcomms2/au15p/build_all.tcl with the bank-86 LVDS
# workaround removed: every FMC LA pin lands in BANK64 or BANK65 on AXAU15
# (both HP, 1.8V VCCO), so all 6 RX and 6 TX pairs are native differential
# LVDS — no pseudo-differential plumbing, no xlslice/xlconcat splits.
#
# Usage (from Vivado TCL console):
#   cd {path/to/deps/hdl/projects/fmcomms2/axau15}
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

variable project_name "fmcomms2_axau15"
variable part "xcau15p-ffvb676-2-i"
variable project_dir [file normalize [file dirname [info script]]]
variable top_level_bd_name "Top"

###############################################################################
# IP version resolution
###############################################################################
#
# create_bd_cell needs a fully-versioned VLNV, but Xilinx bumps IP major.minor
# versions between Vivado releases, and re-exported user IP (NEORV32, ADI, HLS)
# can move too. Resolve the version against the IP catalog at build time:
# prefer the version this script was validated with, otherwise fall back to the
# newest version in the catalog with a warning. This keeps the script working
# across Vivado releases (e.g. 2025.2 -> 2026.1) without editing every
# create_bd_cell call.
#
proc resolve_ip_vlnv {vlnv_base {validated_version ""}} {
    # Exact match on the validated version, if the catalog still ships it
    if {$validated_version ne ""} {
        set exact [get_ipdefs -quiet "${vlnv_base}:${validated_version}"]
        if {[llength $exact] > 0} {
            return [lindex $exact 0]
        }
    }

    # Fall back to the newest version present in the catalog
    set defs [get_ipdefs -quiet "${vlnv_base}:*"]
    if {[llength $defs] == 0} {
        error "resolve_ip_vlnv: no IP matching '${vlnv_base}:*' in the IP\
 catalog. Check that the required IP repositories are set up and the catalog\
 is up to date."
    }
    set best ""
    set best_version ""
    foreach def $defs {
        set version [lindex [split $def ":"] 3]
        if {$best eq "" || [package vcompare $version $best_version] > 0} {
            set best $def
            set best_version $version
        }
    }
    if {$validated_version ne ""} {
        puts "WARNING: ${vlnv_base}:${validated_version} not found in the IP\
 catalog; using $best instead."
    }
    return $best
}

###############################################################################
# Block design component names
###############################################################################

# NEORV32 CPU and infrastructure
variable neorv32_cpu "NEORV32_RISC_V"
variable sitime_300_mhz "SiTime_300MHz"
variable cpu_sys_reset "CPU_Reset"
variable neorv32_cpu_input_reset "NEORV32_CPU_Input_Reset_Inv"
variable axi_cpu_interconnect "AXI_CPU_Interconnect"

# BRAM for IQ snapshot data
variable axi_bram_controller "AXI_BRAM_Controller"
variable qpsk_snapshot_bram "QPSK_Snapshot_BRAM"

# AD9361 core and datapath
variable axi_ad9361 "axi_ad9361"
variable axi_ad9361_adapter "axi_ad9361_adapter"

# AXI-Lite to Streaming adapter bridge (150 MHz domain)
variable axi_streaming_adapter "axi_streaming_adapter"

# AXI-Stream CDC FIFOs (150 MHz <-> l_clk)
variable ad9361_cdc_tx_streaming_fifo "ad9361_cdc_tx_streaming_fifo"
variable ad9361_cdc_rx_streaming_fifo "ad9361_cdc_rx_streaming_fifo"

# Reset synchronizer for AD9361 l_clk domain
variable util_ad9361_lclk_reset "util_ad9361_lclk_reset"

###############################################################################
# Board file check
###############################################################################
#
# Alinx does not currently ship Vivado board definition files for AXAU15.
# Build proceeds with the raw part name; all pinning and clocking comes from
# system_constr.xdc.
###############################################################################

proc check_board_files {} {
    set boards [get_board_parts -quiet "*axau15*"]
    if {[llength $boards] == 0} {
        puts "INFO: No AXAU15 board definition installed in Vivado (expected)."
        puts "      Build will proceed with part name only."
        return 0
    }
    puts "INFO: AXAU15 board definition found: $boards"
    return 1
}

###############################################################################
# Main build procedure
###############################################################################

proc build_all {} {
    # Import global variables
    global project_name part project_dir top_level_bd_name
    global neorv32_cpu sitime_300_mhz cpu_sys_reset neorv32_cpu_input_reset axi_cpu_interconnect
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
        puts "    Windows: set ADI_IP_LOCATION=C:\\path\\to\\QPSK_Triple_Comparison\\deps\\hdl\\library"
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
    puts "  FMCOMMS2/4 on Alinx AXAU15 - Build Script"
    puts "==============================================================================="
    puts ""
    puts "  Project: $project_name"
    puts "  Part:    $part"
    puts "  Dir:     $project_dir"
    puts ""

    # Create the project targeting the AXAU15 part (XCAU15P-2FFVB676I, same
    # silicon as AU15P, industrial-grade temperature).
    puts "INFO: Creating project..."

    if {[catch {create_project $project_name $project_dir -part $part -force} result]} {
        puts "ERROR: Failed to create project: $result"
        return -1
    }

    # No Vivado board file for AXAU15 — proceed with raw part only.
    check_board_files

    puts ""
    puts "INFO: Project created successfully."
    puts ""

    # AXAU15 does NOT define AU15P_BANK86_WORKAROUND — the shared
    # axi_ad9361_lvds_if.v keeps the stock ADI 6-pair LVDS generate loops
    # (no PSEUDO_DIFF, no SINGLE_ENDED). It DOES define AXAU15_BANK65_IDELAYCTRLS
    # so axi_ad9361_lvds_if.v adds 4 per-nibble IDELAYCTRLs for the scattered
    # BANK65 rx_data lanes (rx_frame's single IDELAYCTRL does not serve them;
    # see system_constr.xdc). Without it the lanes capture 0x000 / dig_tune fails.
    set_property verilog_define {AXAU15_BANK65_IDELAYCTRLS=1} [current_fileset]
    set_property verilog_define {AXAU15_BANK65_IDELAYCTRLS=1} [current_fileset -simset]
    puts "INFO: Set verilog_define AXAU15_BANK65_IDELAYCTRLS=1 on synth + sim filesets"

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

    # Path to NEORV32 sources (deps/neorv32 relative to axau15)
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
    # Navigate up 5 levels: axau15 -> fmcomms2 -> projects -> hdl -> deps -> project root
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
    open_bd_design $project_dir/$project_name.srcs/$synth_sources_name/bd/$top_level_bd_name/$top_level_bd_name.bd

    # Instantiate NEORV32 in block design
    puts "INFO: Instantiating NEORV32 in block design..."
    create_bd_cell -type ip -vlnv [resolve_ip_vlnv NEORV32:user:neorv32_vivado_ip 1.0] $neorv32_cpu

    # Configure NEORV32 for AXAU15 / FMCOMMS2 application
    set_property -dict [list \
        CONFIG.CLOCK_FREQUENCY {150000000} \
        CONFIG.BOOT_MODE_SELECT {2} \
        CONFIG.IMEM_EN {true} \
        CONFIG.IMEM_SIZE {131072} \
        CONFIG.DMEM_EN {true} \
        CONFIG.DMEM_SIZE {32768} \
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
        CONFIG.IO_GPIO_OUT_NUM {16} \
        CONFIG.IO_SPI_EN {true} \
        CONFIG.IO_SPI_FIFO {4} \
        CONFIG.XBUS_EN {true} \
        CONFIG.XBUS_TIMEOUT {255} \
        CONFIG.IO_CLINT_EN {true} \
    ] [get_bd_cells $neorv32_cpu]

    puts "INFO: NEORV32 configured (RV32IMC, 128KB IMEM, 16KB DMEM)"

    # Add board clock input and MMCM.
    # AXAU15: 200 MHz LVDS sysclk on T24/U24 (BANK65 MRCC), generated from
    # SiTime SiT9121AI on the core board. MMCM produces clk_out1=150 MHz
    # (AXI domain) and clk_out2=300 MHz (axi_ad9361 IODELAY refclk).
    # Block-design cell renamed from AU15P's "ECS_Clock_300MHz" to
    # "SiTime_300MHz" reflecting the 200 MHz SiTime SiT9121AI input.
    create_bd_cell -type ip -vlnv [resolve_ip_vlnv xilinx.com:ip:clk_wiz 6.0] $sitime_300_mhz
    set_property -dict [list \
        CONFIG.AUTO_PRIMITIVE {PLL} \
        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {150.000} \
        CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {300.000} \
        CONFIG.CLKOUT2_USED {true} \
        CONFIG.CLKOUT2_DRIVES {BUFGCE} \
        CONFIG.CLKOUT3_DRIVES {Buffer} \
        CONFIG.CLKOUT4_DRIVES {Buffer} \
        CONFIG.CLKOUT5_DRIVES {Buffer} \
        CONFIG.CLKOUT6_DRIVES {Buffer} \
        CONFIG.CLKOUT7_DRIVES {Buffer} \
        CONFIG.FEEDBACK_SOURCE {FDBK_AUTO} \
        CONFIG.NUM_OUT_CLKS {2} \
        CONFIG.OPTIMIZE_CLOCKING_STRUCTURE_EN {true} \
        CONFIG.PRIMITIVE {Auto} \
        CONFIG.PRIM_SOURCE {Differential_clock_capable_pin} \
        CONFIG.RESET_BOARD_INTERFACE {Custom} \
        CONFIG.RESET_PORT {resetn} \
        CONFIG.RESET_TYPE {ACTIVE_LOW} \
        CONFIG.USE_LOCKED {true} \
        CONFIG.USE_RESET {true} \
    ] [get_bd_cells $sitime_300_mhz]

    # Configure 200 MHz LVDS sysclk input.
    # Note: MMCM resetn is tied internally to 1'b1 instead of being exported
    # to a push-button. Per UG572, the MMCM does not need an explicit reset
    # to function — it starts locking as soon as the input clock is valid.
    # AU15P's PB3 was wired to system_resetn but was never used in practice;
    # AXAU15 drops the pin entirely. Power-cycle remains the recovery path.
    startgroup
        make_bd_intf_pins_external  [get_bd_intf_pins $sitime_300_mhz/CLK_IN1_D]
        set_property name sys_clk_in [get_bd_intf_ports CLK_IN1_D_0]
        set_property CONFIG.FREQ_HZ 200000000 [get_bd_intf_ports /sys_clk_in]
        set_property -dict [list \
            CONFIG.CLKIN1_JITTER_PS {50.0} \
            CONFIG.MMCM_CLKIN1_PERIOD {5.000} \
            CONFIG.PRIM_IN_FREQ {200.000} \
        ] [get_bd_cells $sitime_300_mhz]
    endgroup

    # Tie MMCM resetn high internally (no external system_resetn port).
    create_bd_cell -type ip -vlnv [resolve_ip_vlnv xilinx.com:ip:xlconstant 1.1] system_resetn_tieoff
    set_property -dict [list CONFIG.CONST_VAL {1} CONFIG.CONST_WIDTH {1}] [get_bd_cells system_resetn_tieoff]
    connect_bd_net [get_bd_pins system_resetn_tieoff/dout] [get_bd_pins $sitime_300_mhz/resetn]

    # Create reset and clocking
    create_bd_cell -type ip -vlnv [resolve_ip_vlnv xilinx.com:ip:proc_sys_reset 5.0] $cpu_sys_reset

    # Create inverter for the NEORV32 active low input reset
    create_bd_cell -type ip -vlnv [resolve_ip_vlnv xilinx.com:ip:util_vector_logic 2.0] $neorv32_cpu_input_reset
    set_property -dict [list \
        CONFIG.C_OPERATION {not} \
        CONFIG.C_SIZE {1} \
    ] [get_bd_cells $neorv32_cpu_input_reset]

    ###########################################################################
    # Power-Down Control (Tier 1) -- pwr_dn = gpio_o[8]
    #
    # Software-activated low-power lever (1 = powered down). Derived nets:
    #   pwr_dn_inv (NOT)          -> SiTime_300MHz/clk_out2_ce : stop 300 MHz
    #                                IODELAY refclk via BUFGCE (B.2)
    #   pwr_dn_aresetn_gate (AND) -> axi_ad9361 s_axi_aresetn + TX CDC FIFO
    #                                s_axis_aresetn : reset-hold (B.3 ::3a/3b)
    #   xpm_cdc_single (below, B.4) -> util_ad9361_lclk_reset/aux_reset_in
    # Created here (after NEORV32 + CPU_Reset) so the later reset re-points
    # and the clk_out2_ce net can reference these cells.
    # See plans/prepare-the-plan-to-shiny-taco.md, Part B.
    ###########################################################################

    # pwr_dn: slice bit 8 out of the now-16-bit gpio_o bus.
    create_bd_cell -type ip -vlnv [resolve_ip_vlnv xilinx.com:ip:xlslice 1.0] gpio_pwr_dn_slice
    set_property -dict [list CONFIG.DIN_WIDTH {16} CONFIG.DIN_FROM {8} CONFIG.DIN_TO {8}] [get_bd_cells gpio_pwr_dn_slice]
    connect_bd_net [get_bd_pins $neorv32_cpu/gpio_o] [get_bd_pins gpio_pwr_dn_slice/Din]

    # pwr_dn_n = NOT pwr_dn (clock-enable / active-low-reset sense)
    create_bd_cell -type ip -vlnv [resolve_ip_vlnv xilinx.com:ip:util_vector_logic 2.0] pwr_dn_inv
    set_property -dict [list CONFIG.C_OPERATION {not} CONFIG.C_SIZE {1}] [get_bd_cells pwr_dn_inv]
    connect_bd_net [get_bd_pins gpio_pwr_dn_slice/Dout] [get_bd_pins pwr_dn_inv/Op1]

    # aresetn_gated = peripheral_aresetn AND pwr_dn_n (active-low, 150 MHz domain)
    create_bd_cell -type ip -vlnv [resolve_ip_vlnv xilinx.com:ip:util_vector_logic 2.0] pwr_dn_aresetn_gate
    set_property -dict [list CONFIG.C_OPERATION {and} CONFIG.C_SIZE {1}] [get_bd_cells pwr_dn_aresetn_gate]
    connect_bd_net [get_bd_pins $cpu_sys_reset/peripheral_aresetn] [get_bd_pins pwr_dn_aresetn_gate/Op1]
    connect_bd_net [get_bd_pins pwr_dn_inv/Res] [get_bd_pins pwr_dn_aresetn_gate/Op2]

    # B.2 net: gate the 300 MHz IODELAY refclk. CLKOUT2_DRIVES={BUFGCE} (set in
    # the clk_wiz config above) exposes clk_out2_ce; CE = pwr_dn_n (run when up).
    connect_bd_net [get_bd_pins pwr_dn_inv/Res] [get_bd_pins $sitime_300_mhz/clk_out2_ce]

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
        create_bd_cell -type ip -vlnv [resolve_ip_vlnv xilinx.com:ip:xlslice 1.0] spi_csn_slice
        set_property -dict [list CONFIG.DIN_WIDTH {8} CONFIG.DIN_FROM {0} CONFIG.DIN_TO {0}] [get_bd_cells spi_csn_slice]
        connect_bd_net [get_bd_pins $neorv32_cpu/spi_csn_o] [get_bd_pins spi_csn_slice/Din]
        create_bd_port -dir O spi_csn_0
        connect_bd_net [get_bd_pins spi_csn_slice/Dout] [get_bd_ports spi_csn_0]
    endgroup

    # Create the main AXI CPU interconnect
    # NUM_MI = 3: BRAM controller, axi_ad9361, axi_ad9361_adapter
    create_bd_cell -type ip -vlnv [resolve_ip_vlnv xilinx.com:ip:smartconnect 1.0] $axi_cpu_interconnect
    set_property -dict [list \
        CONFIG.NUM_MI {3} \
        CONFIG.NUM_SI {1} \
    ] [get_bd_cells $axi_cpu_interconnect]

    ###########################################################################
    # QPSK Snapshot BRAM
    ###########################################################################

    # Create the AXI BRAM controller and the BRAM block itself
    create_bd_cell -type ip -vlnv [resolve_ip_vlnv xilinx.com:ip:axi_bram_ctrl 4.1] $axi_bram_controller
    set_property CONFIG.SINGLE_PORT_BRAM {1} [get_bd_cells $axi_bram_controller]
    set_property CONFIG.READ_LATENCY {2} [get_bd_cells $axi_bram_controller]
    set_property CONFIG.PROTOCOL {AXI4} [get_bd_cells $axi_bram_controller]
    create_bd_cell -type ip -vlnv [resolve_ip_vlnv xilinx.com:ip:blk_mem_gen 8.4] $qpsk_snapshot_bram
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
    create_bd_cell -type ip -vlnv [resolve_ip_vlnv analog.com:user:axi_ad9361 1.0] $axi_ad9361
    set_property -dict [list \
        CONFIG.CMOS_OR_LVDS_N {0} \
        CONFIG.ID {0} \
        CONFIG.FPGA_TECHNOLOGY {3} \
        CONFIG.DAC_DDS_TYPE {1} \
        CONFIG.DAC_DDS_CORDIC_DW {14} \
        CONFIG.ADC_INIT_DELAY {11} \
        CONFIG.DELAY_REFCLK_FREQUENCY {300} \
        CONFIG.TDD_DISABLE {1} \
    ] [get_bd_cells $axi_ad9361]

    # Create external ports for AD9361 LVDS interface (AXAU15: all HP bank,
    # all native differential — no bank-86 single-ended workarounds).
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

    # ─── Direct connections — all LVDS, no slicing needed ───
    connect_bd_net [get_bd_ports rx_clk_in_p]   [get_bd_pins $axi_ad9361/rx_clk_in_p]
    connect_bd_net [get_bd_ports rx_clk_in_n]   [get_bd_pins $axi_ad9361/rx_clk_in_n]
    connect_bd_net [get_bd_ports rx_frame_in_p] [get_bd_pins $axi_ad9361/rx_frame_in_p]
    connect_bd_net [get_bd_ports rx_frame_in_n] [get_bd_pins $axi_ad9361/rx_frame_in_n]
    connect_bd_net [get_bd_ports rx_data_in_p]  [get_bd_pins $axi_ad9361/rx_data_in_p]
    connect_bd_net [get_bd_ports rx_data_in_n]  [get_bd_pins $axi_ad9361/rx_data_in_n]
    connect_bd_net [get_bd_ports tx_clk_out_p]   [get_bd_pins $axi_ad9361/tx_clk_out_p]
    connect_bd_net [get_bd_ports tx_clk_out_n]   [get_bd_pins $axi_ad9361/tx_clk_out_n]
    connect_bd_net [get_bd_ports tx_frame_out_p] [get_bd_pins $axi_ad9361/tx_frame_out_p]
    connect_bd_net [get_bd_ports tx_frame_out_n] [get_bd_pins $axi_ad9361/tx_frame_out_n]
    connect_bd_net [get_bd_ports tx_data_out_p]  [get_bd_pins $axi_ad9361/tx_data_out_p]
    connect_bd_net [get_bd_ports tx_data_out_n]  [get_bd_pins $axi_ad9361/tx_data_out_n]
    connect_bd_net [get_bd_ports enable]        [get_bd_pins $axi_ad9361/enable]
    connect_bd_net [get_bd_ports txnrx]         [get_bd_pins $axi_ad9361/txnrx]

    # Tie off tdd_sync (TDD not used — running FDD mode)
    create_bd_cell -type ip -vlnv [resolve_ip_vlnv xilinx.com:ip:xlconstant 1.1] tdd_sync_const
    set_property -dict [list CONFIG.CONST_VAL {0} CONFIG.CONST_WIDTH {1}] [get_bd_cells tdd_sync_const]
    connect_bd_net [get_bd_pins tdd_sync_const/dout] [get_bd_pins $axi_ad9361/tdd_sync]

    # Connect delay_clk for IODELAY calibration (300 MHz from clk_out2)
    connect_bd_net [get_bd_pins $axi_ad9361/delay_clk] [get_bd_pins $sitime_300_mhz/clk_out2]

    # Connect l_clk to itself (AD9361 uses recovered clock internally)
    connect_bd_net [get_bd_pins $axi_ad9361/l_clk] [get_bd_pins $axi_ad9361/clk]

    # Connect AXI clock and reset
    connect_bd_net [get_bd_pins $sitime_300_mhz/clk_out1] [get_bd_pins $axi_ad9361/s_axi_aclk]
    # B.3 ::3a: hold axi_ad9361's up/register (150 MHz) domain in reset during
    # power-down. Releasing aresetn_gated on wake re-pulses the IP-internal
    # delay_rst (UG571 IDELAYCTRL-after-REFCLK-interruption reset). Was driven
    # directly by $cpu_sys_reset/peripheral_aresetn.
    connect_bd_net [get_bd_pins pwr_dn_aresetn_gate/Res] [get_bd_pins $axi_ad9361/s_axi_aresetn]

    # Connect up_enable and up_txnrx from NEORV32 GPIO
    # GPIO[0] = up_enable, GPIO[1] = up_txnrx
    create_bd_cell -type ip -vlnv [resolve_ip_vlnv xilinx.com:ip:xlslice 1.0] gpio_up_enable_slice
    set_property -dict [list CONFIG.DIN_WIDTH {16} CONFIG.DIN_FROM {0} CONFIG.DIN_TO {0}] [get_bd_cells gpio_up_enable_slice]
    create_bd_cell -type ip -vlnv [resolve_ip_vlnv xilinx.com:ip:xlslice 1.0] gpio_up_txnrx_slice
    set_property -dict [list CONFIG.DIN_WIDTH {16} CONFIG.DIN_FROM {1} CONFIG.DIN_TO {1}] [get_bd_cells gpio_up_txnrx_slice]

    connect_bd_net [get_bd_pins $neorv32_cpu/gpio_o] [get_bd_pins gpio_up_enable_slice/Din]
    connect_bd_net [get_bd_pins $neorv32_cpu/gpio_o] [get_bd_pins gpio_up_txnrx_slice/Din]
    connect_bd_net [get_bd_pins gpio_up_enable_slice/Dout] [get_bd_pins $axi_ad9361/up_enable]
    connect_bd_net [get_bd_pins gpio_up_txnrx_slice/Dout] [get_bd_pins $axi_ad9361/up_txnrx]

    # Additional GPIO slices for AD9361 control signals
    # GPIO[2] = gpio_resetb (AD9361 hard reset)
    create_bd_cell -type ip -vlnv [resolve_ip_vlnv xilinx.com:ip:xlslice 1.0] gpio_resetb_slice
    set_property -dict [list CONFIG.DIN_WIDTH {16} CONFIG.DIN_FROM {2} CONFIG.DIN_TO {2}] [get_bd_cells gpio_resetb_slice]
    connect_bd_net [get_bd_pins $neorv32_cpu/gpio_o] [get_bd_pins gpio_resetb_slice/Din]
    create_bd_port -dir O gpio_resetb
    connect_bd_net [get_bd_pins gpio_resetb_slice/Dout] [get_bd_ports gpio_resetb]

    # GPIO[3] = gpio_sync (multi-chip sync)
    create_bd_cell -type ip -vlnv [resolve_ip_vlnv xilinx.com:ip:xlslice 1.0] gpio_sync_slice
    set_property -dict [list CONFIG.DIN_WIDTH {16} CONFIG.DIN_FROM {3} CONFIG.DIN_TO {3}] [get_bd_cells gpio_sync_slice]
    connect_bd_net [get_bd_pins $neorv32_cpu/gpio_o] [get_bd_pins gpio_sync_slice/Din]
    create_bd_port -dir O gpio_sync
    connect_bd_net [get_bd_pins gpio_sync_slice/Dout] [get_bd_ports gpio_sync]

    # GPIO[4] = gpio_en_agc (AGC enable)
    create_bd_cell -type ip -vlnv [resolve_ip_vlnv xilinx.com:ip:xlslice 1.0] gpio_en_agc_slice
    set_property -dict [list CONFIG.DIN_WIDTH {16} CONFIG.DIN_FROM {4} CONFIG.DIN_TO {4}] [get_bd_cells gpio_en_agc_slice]
    connect_bd_net [get_bd_pins $neorv32_cpu/gpio_o] [get_bd_pins gpio_en_agc_slice/Din]
    create_bd_port -dir O gpio_en_agc
    connect_bd_net [get_bd_pins gpio_en_agc_slice/Dout] [get_bd_ports gpio_en_agc]

    # GPIO[7:5] = gpio_ctl[3:0] (control signals, padded with constant 0 for bit 3)
    create_bd_cell -type ip -vlnv [resolve_ip_vlnv xilinx.com:ip:xlslice 1.0] gpio_ctl_slice
    set_property -dict [list CONFIG.DIN_WIDTH {16} CONFIG.DIN_FROM {7} CONFIG.DIN_TO {5} CONFIG.DOUT_WIDTH {3}] [get_bd_cells gpio_ctl_slice]
    connect_bd_net [get_bd_pins $neorv32_cpu/gpio_o] [get_bd_pins gpio_ctl_slice/Din]
    create_bd_port -dir O -from 3 -to 0 gpio_ctl
    # Concatenate the 3-bit slice with a constant 0 for gpio_ctl[3]
    create_bd_cell -type ip -vlnv [resolve_ip_vlnv xilinx.com:ip:xlconcat 2.1] gpio_ctl_concat
    set_property CONFIG.NUM_PORTS {2} [get_bd_cells gpio_ctl_concat]
    connect_bd_net [get_bd_pins gpio_ctl_slice/Dout] [get_bd_pins gpio_ctl_concat/In0]
    create_bd_cell -type ip -vlnv [resolve_ip_vlnv xilinx.com:ip:xlconstant 1.1] gpio_ctl_pad_const
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
    create_bd_cell -type ip -vlnv [resolve_ip_vlnv xilinx.com:ip:proc_sys_reset 5.0] $util_ad9361_lclk_reset
    connect_bd_net [get_bd_pins $cpu_sys_reset/peripheral_aresetn] [get_bd_pins $util_ad9361_lclk_reset/ext_reset_in]
    connect_bd_net [get_bd_pins $axi_ad9361/l_clk] [get_bd_pins $util_ad9361_lclk_reset/slowest_sync_clk]

    # B.4 ::4: hold the l_clk-domain reset (HLS adapter ap_rst_n + RX CDC FIFO
    # s_axis_aresetn, both already driven by this proc_sys_reset) during
    # power-down. pwr_dn lives in the clk_out1 (150 MHz) domain; aux_reset_in is
    # sampled in the l_clk domain -- the ONLY new project-authored CDC. Carry it
    # through a self-constrained xpm_cdc_single so the top-level XDC is untouched
    # and no new inter-clock timed endpoints appear (see plan B.4).
    set_property -dict [list CONFIG.C_AUX_RESET_HIGH {1}] [get_bd_cells $util_ad9361_lclk_reset]
    create_bd_cell -type ip -vlnv [resolve_ip_vlnv xilinx.com:ip:xpm_cdc_gen 1.0] pwr_dn_lclk_sync
    set_property -dict [list \
        CONFIG.CDC_TYPE {xpm_cdc_single} \
        CONFIG.WIDTH {1} \
        CONFIG.DEST_SYNC_FF {4} \
        CONFIG.SRC_INPUT_REG {false} \
    ] [get_bd_cells pwr_dn_lclk_sync]
    connect_bd_net [get_bd_pins gpio_pwr_dn_slice/Dout] [get_bd_pins pwr_dn_lclk_sync/src_in]
    # src_clk: the source (gpio_o flop) is in the clk_out1 (150 MHz) domain.
    # xpm_cdc_single keeps a src_clk pin even with SRC_INPUT_REG=false; BD
    # validation requires it driven by a real clock.
    connect_bd_net [get_bd_pins $sitime_300_mhz/clk_out1] [get_bd_pins pwr_dn_lclk_sync/src_clk]
    connect_bd_net [get_bd_pins $axi_ad9361/l_clk]      [get_bd_pins pwr_dn_lclk_sync/dest_clk]
    connect_bd_net [get_bd_pins pwr_dn_lclk_sync/dest_out] [get_bd_pins $util_ad9361_lclk_reset/aux_reset_in]

    ###########################################################################
    # AXI AD9361 Adapter (HLS IP)
    # Replaces: util_ad9361_adc_fifo, util_ad9361_adc_pack,
    #           axi_ad9361_dac_fifo, util_ad9361_dac_upack
    # Provides: Internal TX/RX BRAMs, loopback capability, AXI-Lite control
    ###########################################################################

    puts "INFO: Instantiating AXI AD9361 Adapter..."

    # Create the HLS adapter IP (v5.0: AXI-Stream + ap_none, single clock domain)
    create_bd_cell -type ip -vlnv [resolve_ip_vlnv user:hls:axi_ad9361_adapter 5.0] $axi_ad9361_adapter

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
    create_bd_cell -type ip -vlnv [resolve_ip_vlnv xilinx.com:ip:xlconstant 1.1] adc_dovf_const
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
    # control/status interfaces.  Runs in the 150 MHz AXI clock domain.
    ###########################################################################

    puts "INFO: Instantiating AXI-Lite to Streaming Adapter..."

    create_bd_cell -type ip -vlnv [resolve_ip_vlnv user:hls:axi_lite_to_streaming_adapter 1.0] $axi_streaming_adapter

    # Connect adapter clock and reset (150 MHz AXI domain)
    connect_bd_net [get_bd_pins $sitime_300_mhz/clk_out1] [get_bd_pins $axi_streaming_adapter/ap_clk]
    connect_bd_net [get_bd_pins $cpu_sys_reset/peripheral_aresetn] [get_bd_pins $axi_streaming_adapter/ap_rst_n]

    ###########################################################################
    # AXI-Stream CDC FIFOs (150 MHz <-> l_clk)
    ###########################################################################

    puts "INFO: Instantiating AXI-Stream CDC FIFOs..."

    # TX CDC FIFO: axi_streaming_adapter (150 MHz) -> ad9361_adapter (l_clk)
    create_bd_cell -type ip -vlnv [resolve_ip_vlnv xilinx.com:ip:axis_data_fifo 2.0] $ad9361_cdc_tx_streaming_fifo
    set_property -dict [list CONFIG.HAS_TLAST.VALUE_SRC USER] [get_bd_cells $ad9361_cdc_tx_streaming_fifo]
    set_property -dict [list \
        CONFIG.FIFO_DEPTH {256} \
        CONFIG.HAS_TLAST {1} \
        CONFIG.IS_ACLK_ASYNC {1} \
    ] [get_bd_cells $ad9361_cdc_tx_streaming_fifo]

    # TX FIFO clocks and resets
    connect_bd_net [get_bd_pins $sitime_300_mhz/clk_out1]             [get_bd_pins $ad9361_cdc_tx_streaming_fifo/s_axis_aclk]
    # B.3 ::3b: hold the TX CDC FIFO (its only reset port; write/150 side, the
    # IP synchronizes it to the l_clk read side) during power-down so it flushes
    # empty. Was driven directly by $cpu_sys_reset/peripheral_aresetn.
    connect_bd_net [get_bd_pins pwr_dn_aresetn_gate/Res] [get_bd_pins $ad9361_cdc_tx_streaming_fifo/s_axis_aresetn]
    connect_bd_net [get_bd_pins $axi_ad9361/l_clk]                       [get_bd_pins $ad9361_cdc_tx_streaming_fifo/m_axis_aclk]

    # TX FIFO data path: streaming adapter -> FIFO -> ad9361_adapter
    connect_bd_intf_net [get_bd_intf_pins $axi_streaming_adapter/tx_stream]      [get_bd_intf_pins $ad9361_cdc_tx_streaming_fifo/S_AXIS]
    connect_bd_intf_net [get_bd_intf_pins $ad9361_cdc_tx_streaming_fifo/M_AXIS]  [get_bd_intf_pins $axi_ad9361_adapter/tx_stream]

    # RX CDC FIFO: ad9361_adapter (l_clk) -> axi_streaming_adapter (150 MHz)
    # ap_clk (150 MHz) is intentionally faster than l_clk (max 125 MHz) so the
    # RX FIFO drains faster than the AD9361 fills it — prevents overflow.
    create_bd_cell -type ip -vlnv [resolve_ip_vlnv xilinx.com:ip:axis_data_fifo 2.0] $ad9361_cdc_rx_streaming_fifo
    set_property -dict [list CONFIG.HAS_TLAST.VALUE_SRC USER] [get_bd_cells $ad9361_cdc_rx_streaming_fifo]
    set_property -dict [list \
        CONFIG.FIFO_DEPTH {256} \
        CONFIG.HAS_TLAST {1} \
        CONFIG.IS_ACLK_ASYNC {1} \
    ] [get_bd_cells $ad9361_cdc_rx_streaming_fifo]

    # RX FIFO clocks and resets
    connect_bd_net [get_bd_pins $axi_ad9361/l_clk]                          [get_bd_pins $ad9361_cdc_rx_streaming_fifo/s_axis_aclk]
    connect_bd_net [get_bd_pins $util_ad9361_lclk_reset/peripheral_aresetn] [get_bd_pins $ad9361_cdc_rx_streaming_fifo/s_axis_aresetn]
    connect_bd_net [get_bd_pins $sitime_300_mhz/clk_out1]               [get_bd_pins $ad9361_cdc_rx_streaming_fifo/m_axis_aclk]

    # RX FIFO data path: ad9361_adapter -> FIFO -> streaming adapter
    connect_bd_intf_net [get_bd_intf_pins $axi_ad9361_adapter/rx_stream]          [get_bd_intf_pins $ad9361_cdc_rx_streaming_fifo/S_AXIS]
    connect_bd_intf_net [get_bd_intf_pins $ad9361_cdc_rx_streaming_fifo/M_AXIS]   [get_bd_intf_pins $axi_streaming_adapter/rx_stream]

    ###########################################################################
    # AXI and Reset Connections
    ###########################################################################

    puts "INFO: Connecting clocks, resets, and AXI interfaces..."

    # Connect critical async resets and clocks.
    # proc_sys_reset/ext_reset_in is the async external reset input. Default
    # polarity is active-low (C_EXT_RESET_HIGH=0 unset), so '1 = not asserted.
    # Share the same constant-1 net used for the MMCM resetn tie-off; both
    # are async, both want permanent deassert. Reset of the AXI subsystem on
    # startup is then driven entirely by dcm_locked going high after MMCM
    # acquires lock (per PG164 — ext_reset_in being permanently deasserted
    # is a valid mode when locked-gated startup is sufficient).
    connect_bd_net [get_bd_pins system_resetn_tieoff/dout] [get_bd_pins $cpu_sys_reset/ext_reset_in]
    connect_bd_net [get_bd_pins $sitime_300_mhz/clk_out1] [get_bd_pins $cpu_sys_reset/slowest_sync_clk]
    connect_bd_net [get_bd_pins $sitime_300_mhz/locked] [get_bd_pins $cpu_sys_reset/dcm_locked]
    connect_bd_net [get_bd_pins $sitime_300_mhz/clk_out1] [get_bd_pins $neorv32_cpu/clk]
    connect_bd_net [get_bd_pins $cpu_sys_reset/mb_reset] [get_bd_pins $neorv32_cpu_input_reset/Op1]
    connect_bd_net [get_bd_pins $neorv32_cpu_input_reset/Res] [get_bd_pins $neorv32_cpu/resetn]
    connect_bd_net [get_bd_pins $axi_cpu_interconnect/aclk] [get_bd_pins $sitime_300_mhz/clk_out1]
    connect_bd_net [get_bd_pins $axi_cpu_interconnect/aresetn] [get_bd_pins $cpu_sys_reset/peripheral_aresetn]
    connect_bd_net [get_bd_pins $axi_bram_controller/s_axi_aresetn] [get_bd_pins $cpu_sys_reset/peripheral_aresetn]
    connect_bd_net [get_bd_pins $axi_bram_controller/s_axi_aclk] [get_bd_pins $sitime_300_mhz/clk_out1]

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
    set_property target_language Verilog [current_project]
    make_wrapper -files [get_files $project_dir/$project_name.srcs/$synth_sources_name/bd/$top_level_bd_name/$top_level_bd_name.bd] -top
    add_files -norecurse $project_dir/$project_name.gen/$synth_sources_name/bd/$top_level_bd_name/hdl/${top_level_bd_name}_wrapper.v
    add_files -fileset constrs_1 -norecurse $project_dir/system_constr.xdc
    save_bd_design

    # Generate output products for all IP
    update_compile_order -fileset sources_1
    set bd_file "$project_dir/$project_name.srcs/$synth_sources_name/bd/$top_level_bd_name/$top_level_bd_name.bd"
    generate_target all [get_files $bd_file]

    # ─── Propagate AXAU15_BANK65_IDELAYCTRLS to OOC synth runs ────────────────
    # The verilog_define on [current_fileset] only reaches top-level user-RTL
    # synthesis. axi_ad9361 is synthesized OOC in its own per-IP synth_run whose
    # fileset does NOT inherit the parent verilog_defines. Inject the macro into
    # every IP synth run; without this the AXAU15_BANK65_IDELAYCTRLS block stays
    # excluded and the 4 extra IDELAYCTRLs never reach the netlist.
    set ip_synth_runs [get_runs -filter {IS_SYNTHESIS && NAME != "synth_1"}]
    foreach run $ip_synth_runs {
        set existing [get_property STEPS.SYNTH_DESIGN.ARGS.MORE_OPTIONS $run]
        set new "$existing -verilog_define AXAU15_BANK65_IDELAYCTRLS=1"
        set_property STEPS.SYNTH_DESIGN.ARGS.MORE_OPTIONS $new $run
        puts "INFO: Injected -verilog_define AXAU15_BANK65_IDELAYCTRLS=1 into $run"
    }

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
