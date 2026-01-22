# ================================================================================
# axi_ad9361 Testbench - Questa Prime Compilation Script
# ================================================================================
# This script compiles the ADI axi_ad9361 IP core and testbench for Questa
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
set xilinx_common_dir "$hdl_library_dir/xilinx/common"

puts ""
puts "=============================================="
puts "  axi_ad9361 Questa Compilation Script"
puts "=============================================="
puts ""
puts "Sim directory:        $sim_dir"
puts "HDL library dir:      $hdl_library_dir"
puts "axi_ad9361 dir:       $axi_ad9361_dir"
puts "Common library dir:   $common_dir"
puts ""

# ================================================================================
# Required Environment Variables
# ================================================================================
# XILINX_VIVADO:      Path to Vivado installation (for glbl.v)
#   Windows: set XILINX_VIVADO=C:\Xilinx\Vivado\2024.2
#   Linux:   export XILINX_VIVADO=/opt/Xilinx/Vivado/2024.2
#
# XILINX_QUESTA_LIBS: Path to pre-compiled Xilinx simulation libraries
#   Windows: set XILINX_QUESTA_LIBS=C:\Work\Questa_Libraries_Vivado
#   Linux:   export XILINX_QUESTA_LIBS=/path/to/Questa_Libraries_Vivado
#
# To compile Xilinx libraries, run in Vivado Tcl Console:
#   compile_simlib -simulator questa -simulator_exec_path {path_to_questa} ...
# ================================================================================

if {![info exists ::env(XILINX_VIVADO)]} {
    error "XILINX_VIVADO environment variable not set.\n  Set it to point to your Vivado installation.\n  Windows: set XILINX_VIVADO=C:\\Xilinx\\Vivado\\2024.2\n  Linux:   export XILINX_VIVADO=/opt/Xilinx/Vivado/2024.2"
}
set XILINX_VIVADO $::env(XILINX_VIVADO)

if {![info exists ::env(XILINX_QUESTA_LIBS)]} {
    error "XILINX_QUESTA_LIBS environment variable not set.\n  Set it to point to your pre-compiled Xilinx simulation libraries.\n  Windows: set XILINX_QUESTA_LIBS=C:\\Work\\Questa_Libraries_Vivado\n  Linux:   export XILINX_QUESTA_LIBS=/path/to/Questa_Libraries_Vivado"
}
set XILINX_QUESTA_LIBS $::env(XILINX_QUESTA_LIBS)

# ================================================================================
# Validate pre-compiled libraries exist
# ================================================================================

if {![file exists $XILINX_QUESTA_LIBS]} {
    puts ""
    puts "==============================================================================="
    puts "  ERROR: Pre-compiled Xilinx simulation libraries not found!"
    puts "==============================================================================="
    puts ""
    puts "  Expected location: $XILINX_QUESTA_LIBS"
    puts ""
    puts "  These libraries must be compiled once using Vivado's compile_simlib command."
    puts ""
    puts "  To generate them, run the following in Vivado Tcl Console:"
    puts ""
    puts "    compile_simlib -simulator questa \\"
    puts "      -simulator_exec_path {C:/Program Files/Mentor_Graphics/Questa_Prime_2025.1/win64} \\"
    puts "      -family all -language all -library all \\"
    puts "      -dir {$XILINX_QUESTA_LIBS}"
    puts ""
    puts "  This takes 30-60 minutes but only needs to be done once per Vivado version."
    puts ""
    puts "==============================================================================="
    puts ""
    error "Pre-compiled Xilinx libraries not found at $XILINX_QUESTA_LIBS"
}

if {![file exists $XILINX_QUESTA_LIBS/modelsim.ini]} {
    error "modelsim.ini not found in $XILINX_QUESTA_LIBS"
}

if {![file exists $XILINX_QUESTA_LIBS/unisim]} {
    error "UNISIM library not found in $XILINX_QUESTA_LIBS"
}

puts "INFO: Using pre-compiled Xilinx libraries from: $XILINX_QUESTA_LIBS"

# ================================================================================
# Create work library
# ================================================================================

puts ""
puts "Creating work library..."

# Copy the pre-compiled libraries modelsim.ini as base
file copy -force $XILINX_QUESTA_LIBS/modelsim.ini modelsim.ini

# Create work library
if {[file exists work]} {
    vdel -all -lib work
}
vlib work
vmap work work

# ================================================================================
# Compile source files
# ================================================================================

puts ""
puts "Compiling source files..."

# Verilog compile options
set VLOG_OPTS "-sv +incdir+$common_dir +incdir+$axi_ad9361_dir -work work"

# Common library sources
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

# Xilinx-specific common library sources
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

# axi_ad9361 sources
set axi_ad9361_sources [list \
    "$axi_ad9361_dir/axi_ad9361.v" \
    "$axi_ad9361_dir/axi_ad9361_rx.v" \
    "$axi_ad9361_dir/axi_ad9361_rx_channel.v" \
    "$axi_ad9361_dir/axi_ad9361_rx_pnmon.v" \
    "$axi_ad9361_dir/axi_ad9361_tx.v" \
    "$axi_ad9361_dir/axi_ad9361_tx_channel.v" \
    "$axi_ad9361_dir/axi_ad9361_tdd.v" \
    "$axi_ad9361_dir/axi_ad9361_tdd_if.v" \
    "$axi_ad9361_dir/xilinx/axi_ad9361_lvds_if.v" \
    "$axi_ad9361_dir/xilinx/axi_ad9361_cmos_if.v" \
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

puts "  Compiling Xilinx common library..."
foreach src $xilinx_common_sources {
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

# Compile glbl.v for Xilinx simulation
puts "  Compiling Xilinx glbl..."

# Try pre-compiled library location first, then XILINX_VIVADO
set glbl_path ""
if {[file exists "$XILINX_QUESTA_LIBS/glbl.v"]} {
    set glbl_path "$XILINX_QUESTA_LIBS/glbl.v"
} elseif {[file exists "$XILINX_VIVADO/data/verilog/src/glbl.v"]} {
    set glbl_path "$XILINX_VIVADO/data/verilog/src/glbl.v"
} else {
    error "ERROR: glbl.v not found in XILINX_QUESTA_LIBS or XILINX_VIVADO/data/verilog/src/"
}

puts "    Using: $glbl_path"
vlog -work work $glbl_path

# ================================================================================
# Convert COE to HEX for $readmemh
# ================================================================================

puts ""
puts "Setting up test data..."

set coe_file "$sim_dir/qpsk_bram_init.coe"
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
