#==============================================================================
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

