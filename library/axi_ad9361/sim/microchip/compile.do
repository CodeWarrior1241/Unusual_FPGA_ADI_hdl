# ================================================================================
# axi_ad9361 PolarFire Testbench - QuestaSim Pro Compilation Script
# ================================================================================
# Compiles the ADI axi_ad9361 core with the Microchip PolarFire device
# interface (../../polarfire/) plus the loopback testbench, for the QuestaSim
# Pro / ModelSim Pro simulator that ships with Libero SoC 2025.x.
#
# Mirrors ../xilinx/compile.do. Differences:
#   - No Xilinx UNISIM/glbl libraries. The only vendor library needed is the
#     PolarFire primitive library (INBUF_DIFF, OUTBUF_DIFF, CLKINT, ...),
#     compiled from the Libero installation into a local 'polarfire' lib.
#   - The device interface layer comes from library/axi_ad9361/polarfire and
#     library/axi_ad9361/polarfire/common (same file set that
#     src/mpf300_test_proj synthesizes).
# ================================================================================

# Quit any existing simulation
quit -sim

# Save the current directory
set sim_dir [pwd]

# ================================================================================
# Define paths relative to script location
# ================================================================================

set axi_ad9361_dir [file normalize "$sim_dir/../.."]
set hdl_library_dir [file normalize "$sim_dir/../../.."]
set common_dir "$hdl_library_dir/common"
set pf_dir "$axi_ad9361_dir/polarfire"
set pf_common_dir "$pf_dir/common"

puts ""
puts "=============================================="
puts "  axi_ad9361 PolarFire Questa Compilation"
puts "=============================================="
puts ""
puts "Sim directory:        $sim_dir"
puts "HDL library dir:      $hdl_library_dir"
puts "axi_ad9361 dir:       $axi_ad9361_dir"
puts "PolarFire port dir:   $pf_dir"
puts ""

# ================================================================================
# Locate the Libero installation (for the PolarFire primitive models)
# ================================================================================
# LIBERO_INSTALL_DIR: path to the Libero_SoC directory of a Libero SoC 2025.x
# installation (the directory containing Designer/, QuestaSim_Pro/, ...).

if {[info exists ::env(LIBERO_INSTALL_DIR)]} {
    set libero_dir $::env(LIBERO_INSTALL_DIR)
} else {
    set libero_dir "/media/fpgadev/Dev_Tools/Microchip/Libero_SoC"
    puts "INFO: LIBERO_INSTALL_DIR not set, using default: $libero_dir"
}

set pf_prims "$libero_dir/Designer/lib/vlog/polarfire.v"

if {![file exists $pf_prims]} {
    error "PolarFire primitive models not found: $pf_prims\n  Set LIBERO_INSTALL_DIR to your Libero_SoC installation directory."
}

# ================================================================================
# Create libraries
# ================================================================================

puts ""
puts "Creating libraries..."

if {[file exists work]} {
    vdel -all -lib work
}
vlib work
vmap work work

# PolarFire primitive library, compiled from the Libero installation source.
# (Libero also ships precompiled copies under Designer/lib/questasim and
# Designer/lib/modelsimpro; compiling from source keeps this script working
# with either bundled simulator.)
if {[file exists polarfire]} {
    vdel -all -lib polarfire
}
vlib polarfire
vmap polarfire polarfire

# -sv: the primitive models use SystemVerilog constructs (queues in the
# RAM ECC models)
puts "  Compiling PolarFire primitive library..."
vlog -sv -work polarfire $pf_prims

# ================================================================================
# Compile source files
# ================================================================================

puts ""
puts "Compiling source files..."

# Verilog compile options
set VLOG_OPTS "-sv +incdir+$common_dir +incdir+$axi_ad9361_dir -work work"

# Common (vendor-neutral) library sources -- same set that
# src/mpf300_test_proj/build_mpf300.tcl imports for synthesis
set common_sources [list \
    "$common_dir/ad_addsub.v" \
    "$common_dir/ad_datafmt.v" \
    "$common_dir/ad_dds.v" \
    "$common_dir/ad_dds_1.v" \
    "$common_dir/ad_dds_2.v" \
    "$common_dir/ad_dds_cordic_pipe.v" \
    "$common_dir/ad_dds_sine.v" \
    "$common_dir/ad_dds_sine_cordic.v" \
    "$common_dir/ad_iqcor.v" \
    "$common_dir/ad_pnmon.v" \
    "$common_dir/ad_pps_receiver.v" \
    "$common_dir/ad_rst.v" \
    "$common_dir/ad_tdd_control.v" \
    "$common_dir/up_adc_channel.v" \
    "$common_dir/up_adc_common.v" \
    "$common_dir/up_axi.v" \
    "$common_dir/up_clock_mon.v" \
    "$common_dir/up_dac_channel.v" \
    "$common_dir/up_dac_common.v" \
    "$common_dir/up_delay_cntrl.v" \
    "$common_dir/up_tdd_cntrl.v" \
    "$common_dir/up_xfer_cntrl.v" \
    "$common_dir/up_xfer_status.v" \
]

# PolarFire device interface layer (replaces xilinx/common + xilinx/ files)
set pf_sources [list \
    "$pf_common_dir/ad_data_clk.v" \
    "$pf_common_dir/ad_data_in.v" \
    "$pf_common_dir/ad_data_out.v" \
    "$pf_common_dir/ad_dcfilter.v" \
    "$pf_common_dir/ad_mul.v" \
    "$pf_dir/axi_ad9361_lvds_if.v" \
]

# axi_ad9361 core (vendor-neutral)
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

# Testbench
set tb_file "$sim_dir/axi_ad9361_tb.v"

puts "  Compiling common library..."
foreach src $common_sources {
    if {[file exists $src]} {
        vlog {*}$VLOG_OPTS $src
    } else {
        puts "    WARNING: File not found: $src"
    }
}

puts "  Compiling PolarFire device interface..."
foreach src $pf_sources {
    if {[file exists $src]} {
        vlog {*}$VLOG_OPTS $src
    } else {
        puts "    WARNING: File not found: $src"
    }
}

puts "  Compiling axi_ad9361..."
foreach src $axi_ad9361_sources {
    if {[file exists $src]} {
        vlog {*}$VLOG_OPTS $src
    } else {
        puts "    WARNING: File not found: $src"
    }
}

puts "  Compiling testbench..."
if {[file exists $tb_file]} {
    vlog {*}$VLOG_OPTS $tb_file
} else {
    error "ERROR: Testbench not found: $tb_file"
}

# ================================================================================
# Convert COE to HEX for $readmemh
# ================================================================================
# The QPSK sample set is shared with the Xilinx simulation.

puts ""
puts "Setting up test data..."

set coe_file "$sim_dir/../xilinx/qpsk_bram_init.coe"
set hex_file "$sim_dir/qpsk_bram_data.hex"

if {[file exists $coe_file]} {
    puts "  Converting COE file to HEX format..."

    set fp_coe [open $coe_file r]
    set coe_content [read $fp_coe]
    close $fp_coe

    set in_vector 0
    set hex_values [list]

    foreach line [split $coe_content "\n"] {
        set line [string trim $line]
        if {[string index $line 0] eq ";"} {
            continue
        }

        if {[string match -nocase "*memory_initialization_vector*=*" $line]} {
            set in_vector 1
            set eq_pos [string first "=" $line]
            if {$eq_pos >= 0} {
                set line [string range $line [expr {$eq_pos + 1}] end]
            } else {
                continue
            }
        }

        if {$in_vector} {
            set line [string map {";" "" "," " "} $line]
            foreach val [split $line] {
                set val [string trim $val]
                if {[regexp {^[0-9A-Fa-f]+$} $val]} {
                    lappend hex_values $val
                }
            }
        }
    }

    puts "  Parsed [llength $hex_values] hex values from COE file"

    set fp_hex [open $hex_file w]
    foreach val $hex_values {
        puts $fp_hex $val
    }
    close $fp_hex

    puts "  Generated HEX file: $hex_file"
} else {
    puts "WARNING: COE file not found: $coe_file"
}

puts ""
puts "=========================================="
puts "Compilation Complete!"
puts "=========================================="
