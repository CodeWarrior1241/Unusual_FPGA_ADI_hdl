#==============================================================================
# run_sim.tcl
#
# Vivado XSim simulation script for axi_ad9361 testbench
#
# Usage (from Vivado TCL console):
#   cd {C:/Work/Sandbox/QPSK_Triple_Comparison/deps/hdl/library/axi_ad9361/sim/xilinx}
#   source run_sim.tcl
#
# Or from command line:
#   vivado -mode batch -source run_sim.tcl
#
# This script:
# - Compiles all axi_ad9361 and common library sources
# - Compiles the testbench
# - Launches XSim simulation
# - Adds key signals to waveform viewer
#==============================================================================

# Get the directory where this script is located
set script_dir [file dirname [info script]]
set script_dir [file normalize $script_dir]

# Define paths relative to script location
# Script is at: deps/hdl/library/axi_ad9361/sim/xilinx/run_sim.tcl
# Go up 2 levels to get to axi_ad9361 dir: sim/xilinx -> axi_ad9361
set axi_ad9361_dir [file normalize "$script_dir/../.."]
# Go up 3 levels to get to library dir: sim/xilinx -> library
set hdl_library_dir [file normalize "$script_dir/../../.."]
set common_dir "$hdl_library_dir/common"
set sim_dir "$script_dir"

puts ""
puts "=============================================="
puts "  axi_ad9361 XSim Simulation Script"
puts "=============================================="
puts ""
puts "Script directory:     $script_dir"
puts "HDL library dir:      $hdl_library_dir"
puts "axi_ad9361 dir:       $axi_ad9361_dir"
puts "Common library dir:   $common_dir"
puts ""

# Verify directories exist
if {![file exists $axi_ad9361_dir]} {
    error "ERROR: axi_ad9361 directory not found: $axi_ad9361_dir"
}
if {![file exists $common_dir]} {
    error "ERROR: Common library directory not found: $common_dir"
}

#==============================================================================
# Create simulation project (in-memory, no files written to disk)
#==============================================================================

puts "Creating simulation project..."

# Close any existing project
catch {close_project}

# Create a simulation-only project in memory
# Use a temp directory for project files
set proj_dir "$sim_dir/xsim_proj"
file mkdir $proj_dir

create_project -force xsim_axi_ad9361 $proj_dir -part xcau15p-ffvb676-2-e
set_property target_language Verilog [current_project]
set_property simulator_language Verilog [current_project]

#==============================================================================
# Add Common Library Source Files
#==============================================================================

puts "Adding common library sources..."

# Core utility modules
set common_sources [list \
    "$common_dir/ad_rst.v" \
    "$common_dir/ad_pngen.v" \
    "$common_dir/ad_pnmon.v" \
    "$common_dir/ad_datafmt.v" \
    "$common_dir/ad_iqcor.v" \
    "$common_dir/ad_dds.v" \
    "$common_dir/ad_dds_1.v" \
    "$common_dir/ad_dds_2.v" \
    "$common_dir/ad_dds_sine.v" \
    "$common_dir/ad_dds_sine_cordic.v" \
    "$common_dir/ad_dds_cordic_pipe.v" \
    "$common_dir/ad_addsub.v" \
    "$common_dir/ad_b2g.v" \
    "$common_dir/ad_g2b.v" \
    "$common_dir/ad_mem.v" \
    "$common_dir/ad_mem_asym.v" \
    "$common_dir/ad_mux.v" \
    "$common_dir/ad_mux_core.v" \
    "$common_dir/ad_pack.v" \
    "$common_dir/ad_perfect_shuffle.v" \
    "$common_dir/ad_tdd_control.v" \
    "$common_dir/ad_edge_detect.v" \
    "$common_dir/ad_pps_receiver.v" \
    "$common_dir/ad_iobuf.v" \
    "$common_dir/up_axi.v" \
    "$common_dir/up_xfer_cntrl.v" \
    "$common_dir/up_xfer_status.v" \
    "$common_dir/up_clock_mon.v" \
    "$common_dir/up_delay_cntrl.v" \
    "$common_dir/up_adc_common.v" \
    "$common_dir/up_adc_channel.v" \
    "$common_dir/up_dac_common.v" \
    "$common_dir/up_dac_channel.v" \
    "$common_dir/up_tdd_cntrl.v" \
    "$common_dir/util_pulse_gen.v" \
]

foreach src $common_sources {
    if {[file exists $src]} {
        add_files -norecurse $src
    } else {
        puts "WARNING: Common source not found: $src"
    }
}

#==============================================================================
# Add Xilinx-specific Common Library Files
#==============================================================================

puts "Adding Xilinx-specific common library sources..."

set xilinx_common_dir "$hdl_library_dir/xilinx/common"

set xilinx_common_sources [list \
    "$xilinx_common_dir/ad_data_clk.v" \
    "$xilinx_common_dir/ad_data_in.v" \
    "$xilinx_common_dir/ad_data_out.v" \
    "$xilinx_common_dir/ad_dcfilter.v" \
    "$xilinx_common_dir/ad_mul.v" \
    "$xilinx_common_dir/ad_serdes_clk.v" \
    "$xilinx_common_dir/ad_serdes_in.v" \
    "$xilinx_common_dir/ad_serdes_out.v" \
]

foreach src $xilinx_common_sources {
    if {[file exists $src]} {
        add_files -norecurse $src
    } else {
        puts "WARNING: Xilinx common source not found: $src"
    }
}

#==============================================================================
# Add axi_ad9361 Source Files
#==============================================================================

puts "Adding axi_ad9361 sources..."

# Main axi_ad9361 modules
set axi_ad9361_sources [list \
    "$axi_ad9361_dir/axi_ad9361.v" \
    "$axi_ad9361_dir/axi_ad9361_rx.v" \
    "$axi_ad9361_dir/axi_ad9361_rx_channel.v" \
    "$axi_ad9361_dir/axi_ad9361_rx_pnmon.v" \
    "$axi_ad9361_dir/axi_ad9361_tx.v" \
    "$axi_ad9361_dir/axi_ad9361_tx_channel.v" \
    "$axi_ad9361_dir/axi_ad9361_tdd.v" \
    "$axi_ad9361_dir/axi_ad9361_tdd_if.v" \
]

# Xilinx-specific interface modules
set xilinx_sources [list \
    "$axi_ad9361_dir/xilinx/axi_ad9361_lvds_if.v" \
    "$axi_ad9361_dir/xilinx/axi_ad9361_cmos_if.v" \
]

foreach src $axi_ad9361_sources {
    if {[file exists $src]} {
        add_files -norecurse $src
    } else {
        puts "WARNING: axi_ad9361 source not found: $src"
    }
}

foreach src $xilinx_sources {
    if {[file exists $src]} {
        add_files -norecurse $src
    } else {
        puts "WARNING: Xilinx source not found: $src"
    }
}

#==============================================================================
# Add Testbench
#==============================================================================

puts "Adding testbench..."

set tb_file "$sim_dir/axi_ad9361_tb.v"
if {[file exists $tb_file]} {
    add_files -fileset sim_1 -norecurse $tb_file
    set_property top axi_ad9361_tb [get_filesets sim_1]
} else {
    error "ERROR: Testbench not found: $tb_file"
}

#==============================================================================
# Convert COE File to HEX File for $readmemh
#==============================================================================

set coe_file "$sim_dir/qpsk_bram_init.coe"
set hex_file "$sim_dir/qpsk_bram_data.hex"

puts "Converting COE file to HEX format..."

if {![file exists $coe_file]} {
    error "ERROR: COE file not found: $coe_file"
}

# Read and parse the COE file
set fp_coe [open $coe_file r]
set coe_content [read $fp_coe]
close $fp_coe

# Find the memory_initialization_vector section
set in_vector 0
set hex_values [list]

foreach line [split $coe_content "\n"] {
    # Skip comments (lines starting with ;)
    set line [string trim $line]
    if {[string index $line 0] eq ";"} {
        continue
    }

    # Check for memory_initialization_vector start
    if {[string match -nocase "*memory_initialization_vector*=*" $line]} {
        set in_vector 1
        # Extract any values after the = sign
        set eq_pos [string first "=" $line]
        if {$eq_pos >= 0} {
            set line [string range $line [expr {$eq_pos + 1}] end]
        } else {
            continue
        }
    }

    if {$in_vector} {
        # Remove semicolons (end of file marker) and commas, extract hex values
        set line [string map {";" "" "," " "} $line]
        foreach val [split $line] {
            set val [string trim $val]
            # Check if it's a valid hex value (8 hex digits)
            if {[regexp {^[0-9A-Fa-f]+$} $val]} {
                lappend hex_values $val
            }
        }
    }
}

puts "  Parsed [llength $hex_values] hex values from COE file"

# Write the hex file (one value per line for $readmemh)
set fp_hex [open $hex_file w]
foreach val $hex_values {
    puts $fp_hex $val
}
close $fp_hex

puts "  Generated HEX file: $hex_file"
puts "  First value: [lindex $hex_values 0]"
puts "  Last value:  [lindex $hex_values end]"

# Copy hex file to XSim working directory (where $readmemh looks for files)
set xsim_sim_dir "$proj_dir/xsim_axi_ad9361.sim/sim_1/behav/xsim"
file mkdir $xsim_sim_dir
file copy -force $hex_file $xsim_sim_dir/
puts "  Copied HEX file to XSim directory: $xsim_sim_dir"

#==============================================================================
# Configure Simulation Settings
#==============================================================================

puts "Configuring simulation settings..."

# Set simulation runtime
set_property -name {xsim.simulate.runtime} -value {100us} -objects [get_filesets sim_1]

# Enable waveform logging
set_property -name {xsim.simulate.log_all_signals} -value {true} -objects [get_filesets sim_1]

# Set timescale and enable full debug (preserves all signals including wires)
set_property -name {xsim.elaborate.xelab.more_options} -value {-debug all -timescale 1ns/100ps} -objects [get_filesets sim_1]

# Add include directories
set_property include_dirs [list $common_dir $axi_ad9361_dir] [get_filesets sim_1]

# Update compile order
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

#==============================================================================
# Create Waveform Configuration
#==============================================================================

puts "Creating waveform configuration..."

# Write a TCL script that will be sourced after simulation starts
set wave_tcl_file "$sim_dir/add_waves.tcl"
set fp [open $wave_tcl_file w]

puts $fp {#==============================================================================
# Waveform Configuration for axi_ad9361 Testbench
#==============================================================================

# Get current simulation time to verify we're running
puts "Adding waveforms at simulation time: [current_time]"

# Create wave configuration if none exists
set curr_wave [current_wave_config]
if { [string length $curr_wave] == 0 } {
    create_wave_config "axi_ad9361_waves"
}

#------------------------------------------------------------------------------
# Clocks and Reset
#------------------------------------------------------------------------------
set grp [add_wave_group "Clocks and Reset"]
add_wave -into $grp /axi_ad9361_tb/clk_axi
add_wave -into $grp /axi_ad9361_tb/clk_delay
add_wave -into $grp /axi_ad9361_tb/clk_lvds
add_wave -into $grp /axi_ad9361_tb/rstn_axi
add_wave -into $grp /axi_ad9361_tb/uut/l_clk
add_wave -into $grp /axi_ad9361_tb/uut/rst

#------------------------------------------------------------------------------
# LVDS RX Interface (AD9361 -> FPGA)
#------------------------------------------------------------------------------
# Note: With TX-to-RX loopback, RX signals come from TX outputs
set grp [add_wave_group "LVDS RX Interface (from TX loopback)"]
add_wave -into $grp /axi_ad9361_tb/rx_clk_p

#------------------------------------------------------------------------------
# LVDS TX Interface (FPGA -> AD9361)
#------------------------------------------------------------------------------
set grp [add_wave_group "LVDS TX Interface"]
add_wave -into $grp /axi_ad9361_tb/tx_clk_out_p
add_wave -into $grp /axi_ad9361_tb/tx_frame_out_p
add_wave -into $grp -radix hex /axi_ad9361_tb/tx_data_out_p

#------------------------------------------------------------------------------
# ADC Data Interface (UUT outputs)
#------------------------------------------------------------------------------
set grp [add_wave_group "ADC Data - Channel 0"]
add_wave -into $grp /axi_ad9361_tb/adc_enable_i0
add_wave -into $grp /axi_ad9361_tb/adc_valid_i0
add_wave -into $grp -radix hex /axi_ad9361_tb/adc_data_i0
add_wave -into $grp /axi_ad9361_tb/adc_enable_q0
add_wave -into $grp /axi_ad9361_tb/adc_valid_q0
add_wave -into $grp -radix hex /axi_ad9361_tb/adc_data_q0

set grp [add_wave_group "ADC Data - Channel 1"]
add_wave -into $grp /axi_ad9361_tb/adc_enable_i1
add_wave -into $grp /axi_ad9361_tb/adc_valid_i1
add_wave -into $grp -radix hex /axi_ad9361_tb/adc_data_i1
add_wave -into $grp /axi_ad9361_tb/adc_enable_q1
add_wave -into $grp /axi_ad9361_tb/adc_valid_q1
add_wave -into $grp -radix hex /axi_ad9361_tb/adc_data_q1

#------------------------------------------------------------------------------
# DAC Data Interface (UUT inputs)
#------------------------------------------------------------------------------
set grp [add_wave_group "DAC Data - Channel 0"]
add_wave -into $grp /axi_ad9361_tb/dac_enable_i0
add_wave -into $grp /axi_ad9361_tb/dac_valid_i0
add_wave -into $grp -radix hex /axi_ad9361_tb/dac_data_i0
add_wave -into $grp /axi_ad9361_tb/dac_enable_q0
add_wave -into $grp /axi_ad9361_tb/dac_valid_q0
add_wave -into $grp -radix hex /axi_ad9361_tb/dac_data_q0

set grp [add_wave_group "DAC Data - Channel 1"]
add_wave -into $grp /axi_ad9361_tb/dac_enable_i1
add_wave -into $grp /axi_ad9361_tb/dac_valid_i1
add_wave -into $grp -radix hex /axi_ad9361_tb/dac_data_i1
add_wave -into $grp /axi_ad9361_tb/dac_enable_q1
add_wave -into $grp /axi_ad9361_tb/dac_valid_q1
add_wave -into $grp -radix hex /axi_ad9361_tb/dac_data_q1

#------------------------------------------------------------------------------
# Control Signals
#------------------------------------------------------------------------------
set grp [add_wave_group "Control"]
add_wave -into $grp /axi_ad9361_tb/enable
add_wave -into $grp /axi_ad9361_tb/txnrx
add_wave -into $grp /axi_ad9361_tb/up_enable
add_wave -into $grp /axi_ad9361_tb/up_txnrx
add_wave -into $grp /axi_ad9361_tb/adc_dovf
add_wave -into $grp /axi_ad9361_tb/dac_dunf
add_wave -into $grp /axi_ad9361_tb/adc_r1_mode
add_wave -into $grp /axi_ad9361_tb/dac_r1_mode

#------------------------------------------------------------------------------
# Testbench Statistics
#------------------------------------------------------------------------------
set grp [add_wave_group "Statistics"]
add_wave -into $grp -radix unsigned /axi_ad9361_tb/adc_sample_count
add_wave -into $grp -radix unsigned /axi_ad9361_tb/dac_request_count
add_wave -into $grp -radix unsigned /axi_ad9361_tb/cycle_count
add_wave -into $grp -radix unsigned /axi_ad9361_tb/dac_sample_index

#------------------------------------------------------------------------------
# Captured Samples (for verification)
#------------------------------------------------------------------------------
set grp [add_wave_group "Captured ADC Samples"]
add_wave -into $grp /axi_ad9361_tb/capture_valid
add_wave -into $grp -radix hex /axi_ad9361_tb/captured_i0
add_wave -into $grp -radix hex /axi_ad9361_tb/captured_q0
add_wave -into $grp -radix hex /axi_ad9361_tb/captured_i1
add_wave -into $grp -radix hex /axi_ad9361_tb/captured_q1

#------------------------------------------------------------------------------
# AXI-Lite Interface
#------------------------------------------------------------------------------
set grp [add_wave_group "AXI-Lite"]
add_wave -into $grp /axi_ad9361_tb/s_axi_awvalid
add_wave -into $grp /axi_ad9361_tb/s_axi_awready
add_wave -into $grp -radix hex /axi_ad9361_tb/s_axi_awaddr
add_wave -into $grp /axi_ad9361_tb/s_axi_wvalid
add_wave -into $grp /axi_ad9361_tb/s_axi_wready
add_wave -into $grp -radix hex /axi_ad9361_tb/s_axi_wdata
add_wave -into $grp /axi_ad9361_tb/s_axi_bvalid
add_wave -into $grp /axi_ad9361_tb/s_axi_arvalid
add_wave -into $grp /axi_ad9361_tb/s_axi_arready
add_wave -into $grp -radix hex /axi_ad9361_tb/s_axi_araddr
add_wave -into $grp /axi_ad9361_tb/s_axi_rvalid
add_wave -into $grp -radix hex /axi_ad9361_tb/s_axi_rdata

#------------------------------------------------------------------------------
# UUT Internal Signals
#------------------------------------------------------------------------------
set grp [add_wave_group "UUT Internal - ADC"]
add_wave -into $grp /axi_ad9361_tb/uut/adc_valid_s
add_wave -into $grp -radix hex /axi_ad9361_tb/uut/adc_data_s
add_wave -into $grp /axi_ad9361_tb/uut/adc_status_s

set grp [add_wave_group "UUT Internal - DAC"]
add_wave -into $grp /axi_ad9361_tb/uut/dac_valid_s
add_wave -into $grp -radix hex /axi_ad9361_tb/uut/dac_data_s

#------------------------------------------------------------------------------
# Testbench DAC Data Generation
#------------------------------------------------------------------------------
set grp [add_wave_group "TB DAC Gen"]
add_wave -into $grp -radix unsigned /axi_ad9361_tb/dac_sample_index
add_wave -into $grp -radix unsigned /axi_ad9361_tb/cycle_count
add_wave -into $grp -radix unsigned /axi_ad9361_tb/dac_request_count
add_wave -into $grp -radix unsigned /axi_ad9361_tb/adc_sample_count

#------------------------------------------------------------------------------
# LVDS TX/RX Loopback Signals
#------------------------------------------------------------------------------
set grp [add_wave_group "LVDS TX (looped to RX)"]
add_wave -into $grp /axi_ad9361_tb/clk_lvds
add_wave -into $grp /axi_ad9361_tb/tx_frame_out_p
add_wave -into $grp -radix hex /axi_ad9361_tb/tx_data_out_p

puts "Waveforms added successfully"
}

close $fp
puts "Waveform configuration written to: $wave_tcl_file"

#==============================================================================
# Launch Simulation
#==============================================================================

puts ""
puts "=============================================="
puts "  Launching XSim Simulation"
puts "=============================================="
puts ""

# Change to simulation directory so COE file can be found
cd $sim_dir

# Launch simulation
launch_simulation

# Source the waveform configuration
puts "Adding waveforms..."
source $wave_tcl_file

# Note: Simulation already ran during launch_simulation (100us configured above).
# The testbench calls $finish when complete, so no additional run is needed.

puts ""
puts "=============================================="
puts "  Simulation Complete"
puts "=============================================="
puts ""
puts "To view waveforms, use the GUI wave window."
puts "To restart simulation: restart; run 100us"
puts ""
