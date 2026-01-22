# ================================================================================
# axi_ad9361 Testbench - Questa Prime Simulation Script
# ================================================================================
# This script runs the axi_ad9361 TX-to-RX loopback simulation
# Usage: vsim -do simulate.do
# ================================================================================

# Source the compilation script first
do compile.do

# ================================================================================
# Simulation Parameters
# ================================================================================

# Default simulation time (can be overridden from command line)
if {![info exists SIM_TIME]} {
    set SIM_TIME "100us"
}

puts ""
puts "=========================================="
puts "Starting axi_ad9361 Simulation..."
puts "Simulation time: $SIM_TIME"
puts "=========================================="

# ================================================================================
# Elaborate and Load Design
# ================================================================================

# Elaborate with optimization for the testbench
# Include all required Xilinx libraries
vopt -l elaborate.log +acc=npr -suppress 10016 \
    -L work \
    -L unisims_ver \
    -L unimacro_ver \
    -L secureip \
    work.axi_ad9361_tb work.glbl \
    -o axi_ad9361_tb_opt

# Load the optimized design
# Use -t 100ps for time resolution
# Use -onfinish stop to keep simulation alive after $finish (for waveform inspection)
vsim -t 100ps -onfinish stop -lib work axi_ad9361_tb_opt

# Suppress numeric std warnings
set NumericStdNoWarnings 1
set StdArithNoWarnings 1

# ================================================================================
# Add Waveforms
# ================================================================================

add wave -divider "Clocks and Reset"
add wave /axi_ad9361_tb/clk_axi
add wave /axi_ad9361_tb/clk_delay
add wave /axi_ad9361_tb/clk_lvds
add wave /axi_ad9361_tb/rstn_axi
add wave /axi_ad9361_tb/uut/l_clk
add wave /axi_ad9361_tb/uut/rst

add wave -divider "LVDS RX Interface (from TX loopback)"
add wave /axi_ad9361_tb/rx_clk_p

add wave -divider "LVDS TX Interface"
add wave /axi_ad9361_tb/tx_clk_out_p
add wave /axi_ad9361_tb/tx_frame_out_p
add wave -radix hex /axi_ad9361_tb/tx_data_out_p

add wave -divider "ADC Data - Channel 0"
add wave /axi_ad9361_tb/adc_enable_i0
add wave /axi_ad9361_tb/adc_valid_i0
add wave -radix decimal /axi_ad9361_tb/adc_data_i0
add wave /axi_ad9361_tb/adc_enable_q0
add wave /axi_ad9361_tb/adc_valid_q0
add wave -radix decimal /axi_ad9361_tb/adc_data_q0

add wave -divider "ADC Data - Channel 1"
add wave /axi_ad9361_tb/adc_enable_i1
add wave /axi_ad9361_tb/adc_valid_i1
add wave -radix decimal /axi_ad9361_tb/adc_data_i1
add wave /axi_ad9361_tb/adc_enable_q1
add wave /axi_ad9361_tb/adc_valid_q1
add wave -radix decimal /axi_ad9361_tb/adc_data_q1

add wave -divider "DAC Data - Channel 0"
add wave /axi_ad9361_tb/dac_enable_i0
add wave /axi_ad9361_tb/dac_valid_i0
add wave -radix decimal /axi_ad9361_tb/dac_data_i0
add wave /axi_ad9361_tb/dac_enable_q0
add wave /axi_ad9361_tb/dac_valid_q0
add wave -radix decimal /axi_ad9361_tb/dac_data_q0

add wave -divider "DAC Data - Channel 1"
add wave /axi_ad9361_tb/dac_enable_i1
add wave /axi_ad9361_tb/dac_valid_i1
add wave -radix decimal /axi_ad9361_tb/dac_data_i1
add wave /axi_ad9361_tb/dac_enable_q1
add wave /axi_ad9361_tb/dac_valid_q1
add wave -radix decimal /axi_ad9361_tb/dac_data_q1

add wave -divider "Control"
add wave /axi_ad9361_tb/enable
add wave /axi_ad9361_tb/txnrx
add wave /axi_ad9361_tb/up_enable
add wave /axi_ad9361_tb/up_txnrx
add wave /axi_ad9361_tb/adc_dovf
add wave /axi_ad9361_tb/dac_dunf
add wave /axi_ad9361_tb/adc_r1_mode
add wave /axi_ad9361_tb/dac_r1_mode

add wave -divider "Statistics"
add wave -radix unsigned /axi_ad9361_tb/adc_sample_count
add wave -radix unsigned /axi_ad9361_tb/dac_request_count
add wave -radix unsigned /axi_ad9361_tb/cycle_count
add wave -radix unsigned /axi_ad9361_tb/dac_sample_index

add wave -divider "Captured ADC Samples"
add wave /axi_ad9361_tb/capture_valid
add wave -radix decimal /axi_ad9361_tb/captured_i0
add wave -radix decimal /axi_ad9361_tb/captured_q0
add wave -radix decimal /axi_ad9361_tb/captured_i1
add wave -radix decimal /axi_ad9361_tb/captured_q1

add wave -divider "AXI-Lite"
add wave /axi_ad9361_tb/s_axi_awvalid
add wave /axi_ad9361_tb/s_axi_awready
add wave -radix hex /axi_ad9361_tb/s_axi_awaddr
add wave /axi_ad9361_tb/s_axi_wvalid
add wave /axi_ad9361_tb/s_axi_wready
add wave -radix hex /axi_ad9361_tb/s_axi_wdata
add wave /axi_ad9361_tb/s_axi_bvalid
add wave /axi_ad9361_tb/s_axi_arvalid
add wave /axi_ad9361_tb/s_axi_arready
add wave -radix hex /axi_ad9361_tb/s_axi_araddr
add wave /axi_ad9361_tb/s_axi_rvalid
add wave -radix hex /axi_ad9361_tb/s_axi_rdata

add wave -divider "UUT Internal - ADC"
add wave /axi_ad9361_tb/uut/adc_valid_s
add wave -radix hex /axi_ad9361_tb/uut/adc_data_s
add wave /axi_ad9361_tb/uut/adc_status_s

add wave -divider "UUT Internal - DAC"
add wave /axi_ad9361_tb/uut/dac_valid_s
add wave -radix hex /axi_ad9361_tb/uut/dac_data_s

add wave -divider "LVDS TX (looped to RX)"
add wave /axi_ad9361_tb/clk_lvds
add wave /axi_ad9361_tb/tx_frame_out_p
add wave -radix hex /axi_ad9361_tb/tx_data_out_p

# ================================================================================
# Configure Waveform Display
# ================================================================================

configure wave -namecolwidth 350
configure wave -valuecolwidth 120
configure wave -signalnamewidth 1

view wave
view structure
view signals

# ================================================================================
# Run Simulation
# ================================================================================

# Record start time
set start_time [clock milliseconds]

# Run simulation
run $SIM_TIME

# Calculate and display wall clock time
set end_time [clock milliseconds]
set elapsed_ms [expr {$end_time - $start_time}]
set elapsed_sec [format "%.2f" [expr {$elapsed_ms / 1000.0}]]

puts ""
puts "=========================================="
puts "Simulation Complete!"
puts "Wall clock time: $elapsed_sec seconds"
puts "=========================================="

catch {wave zoom full}
