# =============================================================================
# FMCOMMS2/AU15P Firmware Debug — Questa Simulation Script
# =============================================================================

# Source compilation
do compile.do

# =============================================================================
# Simulation Parameters
# =============================================================================

if {![info exists SIM_TIME]} { set SIM_TIME "20ms" }
if {![info exists DETAILED]} { set DETAILED "no" }

if {$DETAILED eq "yes"} {
    set acc_flag "+acc"
    set mode_str "DETAILED (+acc, full signal visibility)"
} else {
    set acc_flag "+acc=rn"
    set mode_str "FAST (+acc=rn, no waveforms)"
}

puts "=========================================="
puts "Starting Firmware Debug Simulation..."
puts "Mode:            $mode_str"
puts "Simulation time: $SIM_TIME"
puts "=========================================="

# =============================================================================
# Map locally-compiled libraries
# =============================================================================

vmap xilinx_vip $vivado_questa_dir/questa_lib/msim/xilinx_vip
vmap xpm $vivado_questa_dir/questa_lib/msim/xpm
vmap xil_defaultlib $vivado_questa_dir/questa_lib/msim/xil_defaultlib
vmap neorv32 $vivado_questa_dir/questa_lib/msim/neorv32
vmap proc_sys_reset_v5_0_17 $vivado_questa_dir/questa_lib/msim/proc_sys_reset_v5_0_17
vmap util_vector_logic_v2_0_5 $vivado_questa_dir/questa_lib/msim/util_vector_logic_v2_0_5
vmap xlslice_v1_0_5 $vivado_questa_dir/questa_lib/msim/xlslice_v1_0_5
vmap xlconcat_v2_1_7 $vivado_questa_dir/questa_lib/msim/xlconcat_v2_1_7
vmap xlconstant_v1_1_10 $vivado_questa_dir/questa_lib/msim/xlconstant_v1_1_10
vmap smartconnect_v1_0 $vivado_questa_dir/questa_lib/msim/smartconnect_v1_0
vmap axi_infrastructure_v1_1_0 $vivado_questa_dir/questa_lib/msim/axi_infrastructure_v1_1_0
vmap axi_register_slice_v2_1_36 $vivado_questa_dir/questa_lib/msim/axi_register_slice_v2_1_36
vmap axi_vip_v1_1_22 $vivado_questa_dir/questa_lib/msim/axi_vip_v1_1_22
vmap axi_bram_ctrl_v4_1_13 $vivado_questa_dir/questa_lib/msim/axi_bram_ctrl_v4_1_13
vmap blk_mem_gen_v8_4_12 $vivado_questa_dir/questa_lib/msim/blk_mem_gen_v8_4_12
vmap axis_infrastructure_v1_1_1 $vivado_questa_dir/questa_lib/msim/axis_infrastructure_v1_1_1
vmap axis_data_fifo_v2_0_17 $vivado_questa_dir/questa_lib/msim/axis_data_fifo_v2_0_17

# =============================================================================
# Elaborate
# =============================================================================

# Stay in Vivado questa dir (CWD from compile.do)
vopt -l elaborate.log $acc_flag -suppress 10016 \
    -L xil_defaultlib \
    -L xilinx_vip \
    -L xpm \
    -Lf neorv32 \
    -L proc_sys_reset_v5_0_17 \
    -L util_vector_logic_v2_0_5 \
    -L xlslice_v1_0_5 \
    -L xlconcat_v2_1_7 \
    -L xlconstant_v1_1_10 \
    -L smartconnect_v1_0 \
    -L axi_infrastructure_v1_1_0 \
    -L axi_register_slice_v2_1_36 \
    -L axi_vip_v1_1_22 \
    -L axi_bram_ctrl_v4_1_13 \
    -L blk_mem_gen_v8_4_12 \
    -L axis_infrastructure_v1_1_1 \
    -L axis_data_fifo_v2_0_17 \
    -L unisims_ver \
    -L unimacro_ver \
    -L secureip \
    -work xil_defaultlib \
    xil_defaultlib.tb_top xil_defaultlib.glbl \
    -o tb_top_opt

# =============================================================================
# Load and run
# =============================================================================

vsim -t 1ps -lib xil_defaultlib tb_top_opt

set NumericStdNoWarnings 1
set StdArithNoWarnings 1

# =============================================================================
# Waveforms (detailed mode only)
# =============================================================================

if {$DETAILED eq "yes"} {

add wave -divider "Clock & Reset"
add wave -hex /tb_top/sys_clk_p
add wave -hex /tb_top/system_resetn

add wave -divider "SPI Interface"
add wave -hex /tb_top/spi_clk_w
add wave -hex /tb_top/spi_csn_0_w
add wave -hex /tb_top/spi_mosi_w
add wave -hex /tb_top/spi_miso_w
add wave -radix unsigned /tb_top/spi_txn_count

add wave -divider "SPI Model Internals"
add wave -hex /tb_top/spi_slave/cmd_shift
add wave -hex /tb_top/spi_slave/cmd_done
add wave -hex /tb_top/spi_slave/r_nw
add wave -hex /tb_top/spi_slave/addr
add wave -hex /tb_top/spi_slave/data_shift
add wave -radix unsigned /tb_top/spi_slave/bit_cnt
add wave -radix unsigned /tb_top/spi_slave/byte_cnt

add wave -divider "UART"
add wave -hex /tb_top/sys_uart_tx

add wave -divider "GPIO"
add wave -hex /tb_top/gpio_resetb_w
add wave -hex /tb_top/gpio_sync_w
add wave -hex /tb_top/gpio_en_agc_w
add wave -hex /tb_top/gpio_ctl_w
add wave -hex /tb_top/enable_w
add wave -hex /tb_top/txnrx_w

add wave -divider "Clock Wizard"
catch {
    add wave -hex /tb_top/dut/Top_i/ECS_Clock_300MHz/clk_out1
    add wave -hex /tb_top/dut/Top_i/ECS_Clock_300MHz/locked
}

add wave -divider "NEORV32 CPU"
catch {
    add wave -hex /tb_top/dut/Top_i/NEORV32_RISC_V/clk
    add wave -hex /tb_top/dut/Top_i/NEORV32_RISC_V/resetn
    add wave -hex /tb_top/dut/Top_i/NEORV32_RISC_V/uart0_txd_o
    add wave -hex /tb_top/dut/Top_i/NEORV32_RISC_V/gpio_o
    add wave -hex /tb_top/dut/Top_i/NEORV32_RISC_V/spi_clk_o
    add wave -hex /tb_top/dut/Top_i/NEORV32_RISC_V/spi_dat_o
    add wave -hex /tb_top/dut/Top_i/NEORV32_RISC_V/spi_dat_i
    add wave -hex /tb_top/dut/Top_i/NEORV32_RISC_V/spi_csn_o
}

add wave -divider "AXI Master"
catch {
    add wave -hex /tb_top/dut/Top_i/NEORV32_RISC_V/m_axi_araddr
    add wave -hex /tb_top/dut/Top_i/NEORV32_RISC_V/m_axi_arvalid
    add wave -hex /tb_top/dut/Top_i/NEORV32_RISC_V/m_axi_arready
    add wave -hex /tb_top/dut/Top_i/NEORV32_RISC_V/m_axi_rdata
    add wave -hex /tb_top/dut/Top_i/NEORV32_RISC_V/m_axi_rresp
    add wave -hex /tb_top/dut/Top_i/NEORV32_RISC_V/m_axi_rvalid
    add wave -hex /tb_top/dut/Top_i/NEORV32_RISC_V/m_axi_awaddr
    add wave -hex /tb_top/dut/Top_i/NEORV32_RISC_V/m_axi_awvalid
    add wave -hex /tb_top/dut/Top_i/NEORV32_RISC_V/m_axi_wdata
    add wave -hex /tb_top/dut/Top_i/NEORV32_RISC_V/m_axi_bresp
    add wave -hex /tb_top/dut/Top_i/NEORV32_RISC_V/m_axi_bvalid
}

add wave -divider "CPU Trap CSRs"
# csr and trap are VHDL records — field access uses '.', not '/'
catch {
    add wave -hex /tb_top/dut/Top_i/NEORV32_RISC_V/U0/neorv32_top_inst/core_complex_gen(0)/neorv32_cpu_inst/neorv32_cpu_control_inst/csr.mepc
    add wave -hex /tb_top/dut/Top_i/NEORV32_RISC_V/U0/neorv32_top_inst/core_complex_gen(0)/neorv32_cpu_inst/neorv32_cpu_control_inst/csr.mcause
    add wave -hex /tb_top/dut/Top_i/NEORV32_RISC_V/U0/neorv32_top_inst/core_complex_gen(0)/neorv32_cpu_inst/neorv32_cpu_control_inst/csr.mtval
    add wave -hex /tb_top/dut/Top_i/NEORV32_RISC_V/U0/neorv32_top_inst/core_complex_gen(0)/neorv32_cpu_inst/neorv32_cpu_control_inst/csr.mtinst
    add wave      /tb_top/dut/Top_i/NEORV32_RISC_V/U0/neorv32_top_inst/core_complex_gen(0)/neorv32_cpu_inst/neorv32_cpu_control_inst/trap.env_enter
}

configure wave -namecolwidth 400
configure wave -valuecolwidth 120
configure wave -signalnamewidth 1

view wave
view structure
view signals

}

# =============================================================================
# Trap probe — dump CPU CSRs on every trap entry (first 24 traps).
# Prints to the transcript regardless of GUI/batch mode so the values are
# available by copy-paste without having to inspect waveforms. Wrapped in
# catch in case the hierarchical path is unreachable for some configs.
# =============================================================================

set dbg_trap_count 0

# Proc to read a 32-bit word from DMEM at a byte address. DMEM is 4 byte-wide
# sprams per the NEORV32 default RAM structure.
proc dmem_word {byte_addr} {
    set dmem_root /tb_top/dut/Top_i/NEORV32_RISC_V/U0/neorv32_top_inst/memory_system/neorv32_dmem_enabled/neorv32_dmem_inst/dmem_ram_inst
    set word_idx [expr {($byte_addr - 0x80000000) / 4}]
    set b0 [examine -radix hex $dmem_root/ram_gen(0)/ram_inst/spram($word_idx)]
    set b1 [examine -radix hex $dmem_root/ram_gen(1)/ram_inst/spram($word_idx)]
    set b2 [examine -radix hex $dmem_root/ram_gen(2)/ram_inst/spram($word_idx)]
    set b3 [examine -radix hex $dmem_root/ram_gen(3)/ram_inst/spram($word_idx)]
    # Assemble little-endian word: byte3 || byte2 || byte1 || byte0
    return "${b3}${b2}${b1}${b0}"
}

# csr and trap are VHDL records; record fields are accessed with '.' not '/'.
# First confirm the hierarchical path resolves — if not, no probe would fire
# silently and we'd be none the wiser. Try a trial examine and report.
if { [catch {
    set _probe_test [examine -radix hex /tb_top/dut/Top_i/NEORV32_RISC_V/U0/neorv32_top_inst/core_complex_gen(0)/neorv32_cpu_inst/neorv32_cpu_control_inst/csr.mepc]
} err] } {
    echo "TRAP PROBE: DISABLED — hierarchical path to CPU CSRs did not resolve."
    echo "TRAP PROBE: Questa error was: $err"
    echo "TRAP PROBE: fall back to waveform inspection to read mepc/mcause/mtval/mtinst."
} else {
    echo "TRAP PROBE: registered — mepc initially = $_probe_test; will dump CSRs on every trap.env_enter (first 24 traps)."

    # Also confirm DMEM probe path resolves
    if { [catch { set _dmem_test [dmem_word 0x80000000] } dmem_err] } {
        echo "DMEM PROBE: DISABLED — could not read DMEM directly: $dmem_err"
    } else {
        echo "DMEM PROBE: registered — word at 0x80000000 = $_dmem_test"
    }

    when -label trap_probe {/tb_top/dut/Top_i/NEORV32_RISC_V/U0/neorv32_top_inst/core_complex_gen(0)/neorv32_cpu_inst/neorv32_cpu_control_inst/trap.env_enter == 1} {
        global dbg_trap_count
        if { $dbg_trap_count < 24 } {
            incr dbg_trap_count
            set mcause [examine -radix hex /tb_top/dut/Top_i/NEORV32_RISC_V/U0/neorv32_top_inst/core_complex_gen(0)/neorv32_cpu_inst/neorv32_cpu_control_inst/csr.mcause]
            set mepc   [examine -radix hex /tb_top/dut/Top_i/NEORV32_RISC_V/U0/neorv32_top_inst/core_complex_gen(0)/neorv32_cpu_inst/neorv32_cpu_control_inst/csr.mepc]
            set mtval  [examine -radix hex /tb_top/dut/Top_i/NEORV32_RISC_V/U0/neorv32_top_inst/core_complex_gen(0)/neorv32_cpu_inst/neorv32_cpu_control_inst/csr.mtval]
            set mtinst [examine -radix hex /tb_top/dut/Top_i/NEORV32_RISC_V/U0/neorv32_top_inst/core_complex_gen(0)/neorv32_cpu_inst/neorv32_cpu_control_inst/csr.mtinst]
            echo "\[$now\] TRAP #$dbg_trap_count: mcause=$mcause mepc=$mepc mtval=$mtval mtinst=$mtinst"

            # On the first real trap (#2 — #1 is the initial-state sample), dump
            # __malloc_av_ bins around the one malloc is walking (bin 65 at 0x568)
            # so we can see if .data copy placed the expected self-reference pointers.
            if { $dbg_trap_count == 2 } {
                catch {
                    # Sanity check: _impure_ptr at 0x80000a98 should be 0x80000768 per ELF.
                    # If dmem_word gets that right, we know word assembly is correct.
                    set impure [dmem_word 0x80000a98]
                    echo "  SANITY CHECK: _impure_ptr at 0x80000a98 = $impure (ELF expects 80000768)"

                    # Raw byte-wise dump of word 345 (0x80000564) so we can see if
                    # individual bytes are wrong vs. word assembly bug
                    set dmem_root /tb_top/dut/Top_i/NEORV32_RISC_V/U0/neorv32_top_inst/memory_system/neorv32_dmem_enabled/neorv32_dmem_inst/dmem_ram_inst
                    set bb0 [examine -radix hex $dmem_root/ram_gen(0)/ram_inst/spram(345)]
                    set bb1 [examine -radix hex $dmem_root/ram_gen(1)/ram_inst/spram(345)]
                    set bb2 [examine -radix hex $dmem_root/ram_gen(2)/ram_inst/spram(345)]
                    set bb3 [examine -radix hex $dmem_root/ram_gen(3)/ram_inst/spram(345)]
                    echo "  BYTE DUMP at word 345 (byte 0x80000564): b0=$bb0 b1=$bb1 b2=$bb2 b3=$bb3   (ELF expects 58 05 00 80)"

                    echo "  DMEM DUMP at 1st real trap — __malloc_av_ bins (expect self-refs 0x800005xx):"
                    echo "    0x80000558 = [dmem_word 0x80000558]    (bin[63].bk)"
                    echo "    0x80000560 = [dmem_word 0x80000560]    (bin[64].fd)"
                    echo "    0x80000564 = [dmem_word 0x80000564]    (bin[64].bk)"
                    echo "    0x80000568 = [dmem_word 0x80000568]    (bin[65].fd, a0)"
                    echo "    0x8000056C = [dmem_word 0x8000056C]    (bin[65].bk, what a5 loads from)"
                    echo "    0x80000570 = [dmem_word 0x80000570]    (bin[66].fd)"
                    echo "    0x80000574 = [dmem_word 0x80000574]    (bin[66].bk)"
                    echo "  Compare against .data LMA initial values (from ELF): bin[64].fd=80000558, bin[65].bk=80000560, bin[66].fd=80000568"
                }
            }
        }
    }
}

# =============================================================================
# Run
# =============================================================================

set start_time [clock milliseconds]

run $SIM_TIME

set end_time [clock milliseconds]
set elapsed_sec [format "%.2f" [expr {($end_time - $start_time) / 1000.0}]]

puts "=========================================="
puts "Simulation Complete!"
puts "Wall clock time: $elapsed_sec seconds"
puts "UART log: tb.uart0_rx.log"
puts "=========================================="

if {$DETAILED eq "yes"} {
    catch {wave zoom full}
}
