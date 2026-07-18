# =============================================================================
# FMCOMMS2/AU15P Firmware Debug — Questa Compilation Script
# =============================================================================
# Follows the proven pattern from neorv32_sw_ad9361_datapath_sim/sim/compile.do
# =============================================================================

quit -sim

set sim_dir [pwd]
set proj_dir [file normalize "$sim_dir/.."]
set vivado_questa_dir "$proj_dir/fmcomms2_au15p.ip_user_files/sim_scripts/questa"

# =============================================================================
# Validate environment
# =============================================================================

if {![info exists ::env(XILINX_VIVADO)]} {
    error "XILINX_VIVADO not set. Export it to your Vivado installation root."
}
set XILINX_VIVADO $::env(XILINX_VIVADO)

if {![info exists ::env(XILINX_QUESTA_LIBS)]} {
    error "XILINX_QUESTA_LIBS not set. Export it to your pre-compiled Xilinx simulation libraries."
}
set XILINX_QUESTA_LIBS $::env(XILINX_QUESTA_LIBS)

if {![file exists $vivado_questa_dir]} {
    error "Vivado sim scripts not found at:\n  $vivado_questa_dir\n\nRun in Vivado Tcl console:\n  source $sim_dir/export_sim.tcl"
}

if {![file exists $XILINX_QUESTA_LIBS/modelsim.ini]} {
    error "modelsim.ini not found in $XILINX_QUESTA_LIBS"
}

if {![file exists $XILINX_QUESTA_LIBS/unisim]} {
    error "UNISIM library not found in $XILINX_QUESTA_LIBS"
}

puts "INFO: Using pre-compiled Xilinx libraries from: $XILINX_QUESTA_LIBS"

# =============================================================================
# Setup: cd to Vivado questa dir, copy modelsim.ini, map pre-compiled libs
# =============================================================================

cd $vivado_questa_dir

# Copy pre-compiled modelsim.ini as base — provides all Xilinx library mappings
file copy -force $XILINX_QUESTA_LIBS/modelsim.ini modelsim.ini

# Re-map Xilinx libraries with absolute paths (copied ini may have stale paths)
vmap unisim $XILINX_QUESTA_LIBS/unisim
vmap unisims_ver $XILINX_QUESTA_LIBS/unisims_ver
vmap unimacro $XILINX_QUESTA_LIBS/unimacro
vmap unimacro_ver $XILINX_QUESTA_LIBS/unimacro_ver
vmap secureip $XILINX_QUESTA_LIBS/secureip

# =============================================================================
# Run Vivado's generated compile.do
# =============================================================================

puts "=========================================="
puts "Running Vivado-generated compile script..."
puts "=========================================="

# Vivado's compile.do uses $bin_path/vlib, $bin_path/vcom, etc.
set bin_path [file dirname [exec which vsim]]

# Pre-create questa_lib parent directories — vlib only creates the leaf
file mkdir questa_lib/msim

do compile.do

# =============================================================================
# Compile testbench sources
# =============================================================================

puts "=========================================="
puts "Compiling Testbench Components..."
puts "=========================================="

# Map libraries created by Vivado's compile script
vmap xil_defaultlib $vivado_questa_dir/questa_lib/msim/xil_defaultlib
vmap neorv32 $vivado_questa_dir/questa_lib/msim/neorv32

# Compile testbench files (absolute paths — CWD is Vivado questa dir)
vlog -work xil_defaultlib -incr \
    $sim_dir/ad9361_spi_slave.v

vlog -work xil_defaultlib -incr \
    $sim_dir/tb_top.v

puts "=========================================="
puts "Compilation Complete!"
puts "=========================================="
