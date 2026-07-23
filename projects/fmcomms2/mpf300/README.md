# FMCOMMS2 on PolarFire MPF300 Splash Kit

PolarFire port of the [axau15](../axau15) FMCOMMS2 system: NEORV32 RISC-V
CPU + ADI `axi_ad9361` (polarfire device interface) + SmartHLS datapath
adapters + CDC FIFOs + QPSK snapshot BRAM, assembled as a Libero
SmartDesign (`Top`) by `build_all.tcl`.

## Build

```sh
cd deps/hdl/projects/fmcomms2/mpf300
/media/fpgadev/Dev_Tools/Microchip/run_libero.sh \
    SCRIPT:build_all.tcl LOGFILE:build_all.log
```

(or Libero GUI: Project -> Execute Script on `build_all.tcl`). The script
deletes and recreates `./proj`, installs the pre-built `ad9361_no-os`
software image into the NEORV32 IMEM, imports all sources, generates
PF_CCC / PF_INIT_MONITOR from the offline MegaVault, builds the
SmartDesign, then runs synthesis (`MPF300_FMCOMMS2_SYNTH_OK`) and place &
route (`MPF300_FMCOMMS2_PNR_OK`).

## System

| axau15 (Vivado) | mpf300 (Libero) |
|---|---|
| NEORV32 packaged Vivado IP | `hdl/neorv32_mpf300_top.vhd` wrapper (same generics; HDL+ cores cannot set VHDL booleans) |
| MMCM 200 MHz -> 150 + 300 MHz | PF_CCC 50 MHz (H7) -> **125 MHz** fabric (SmartHLS adapters are built for CLOCK_PERIOD 8; NEORV32 `CLOCK_FREQUENCY` updated to match, so the software needs no changes) |
| SmartConnect 1x3 | `hdl/axi_1to3_decoder.sv` — PULP `axi_lite_xbar` (deps/axi v0.39.10 + deps/common_cells v1.39.0) behind the same flat ports and address map; the single-beat NEORV32 master is run as AXI4-Lite, DECERR from the xbar's error slave |
| axi_bram_ctrl + blk_mem_gen | `hdl/axi_bram_32k.v` (LSRAM inference, project-local) |
| axis_data_fifo (async, 256, TLAST) x2 | `hdl/axis_async_fifo.v` x2 — PULP `cdc_fifo_gray` (deps/common_cells) behind the same AXIS ports; same topology and reset gating |
| proc_sys_reset x2 + pwr_dn gates + xpm_cdc | `hdl/sys_ctrl.v` (125 MHz) + `hdl/lclk_reset_sync.v` (l_clk) — reset generation and the pwr_dn CDC are open-logic `olo_base_reset_gen` / `olo_base_cc_bits` (deps/open-logic, VHDL); GPIO fan-out and pwr_dn gating stay in the wrappers |
| Vitis HLS adapters | SmartHLS ports from `src/*_microchip` (+ `hdl/dac_hold.v` for the write_en/write_data DAC outputs) |
| IODELAY/IDELAYCTRL calibration | none (polarfire port; static SDC timing) |

Third-party sources are imported by `build_all.tcl`: the PULP SystemVerilog
is amalgamated into one generated file (packages first — Libero's
hierarchy-driven synthesis fileset drops package-only files), the open-logic
VHDL is imported per file, and the project runs with
`project_settings -verilog_mode {SYSTEM_VERILOG}`.

Unchanged so `ad9361_no-os` runs as-is: address map (`axi_ad9361`
0x44A00000/64K, streaming adapter 0x44A10000/16K, BRAM 0xC0000000/32K),
GPIO map (bit0 up_enable, bit1 up_txnrx, bit2 resetb, bit3 sync, bit4
en_agc, bits7:5 ctl, bit8 pwr_dn), SPI CS bit 0, UART0 console at 115200.

## Board wiring (constraint/io.pdc)

- 50 MHz oscillator: H7 (enters via `hdl/refclk_ibuf.v` INBUF +
  CLKINT_PRESERVE so the PF_CCC is not pinned to the SW corner's dedicated
  routing)
- UART console: R5 (FPGA RX <- FTDI UART1 TXD), R4 (FPGA TX); this is the
  direct FTDI<->PolarFire UART on schematic page 8
- PF_USER_RESET push-button: N4
- FMC LPC (bank 2, **VADJ must be 2.5 V**): full FMCOMMS2 LA map from the
  axau15 XDC joined with the Splash schematic page-6 LA-to-ball table —
  LVDS pairs on LA00..LA15, ENSM/ctl/status/SPI on LA16..LA28

## Status / timing (2026-07-19, Libero 2025.2, PULP/open-logic components)

**Timing is met at 125 MHz** — `Info: Timing constraints have been met`,
zero violating paths, with the PULP `axi_lite_xbar` interconnect,
open-logic CDC FIFOs / reset blocks, and the pipelined-multiplier patch
in place. The xbar runs with `LatencyMode = CUT_ALL_PORTS`: the SmartHLS
bridge's `r_valid` depends combinationally on `r_ready`, which closes a
loop through a fall-through demux — the spill registers sever it and
also bought back ~0.4 ns on the CPU domain. Post-layout multi-corner:

| Clock | Constraint | Worst setup slack | Meets |
|---|---|---|---|
| `rx_clk_in` (AD9361 l_clk domain) | 125 MHz | +3.32 ns | yes |
| `clk_125mhz` (NEORV32/AXI domain) | 125 MHz | **+1.14 ns** | yes |
| hold, all clocks, all corners | - | +0.012 ns worst | yes |

24.1k logic elements (8% of MPF300); synthesis ~1 h 50 min (Synplify
retiming is enabled), place & route ~3 min, routing ~1.5 min.

### How the CPU domain got from 69 MHz to 125 MHz

Each step was found by reading the reports, not by raising tool effort:

1. **IMEM ROM into LSRAM** (~69 -> ~109 MHz). Synplify's default
   `rom_map_logic 1` had mapped the inferred 128 KB IMEM ROM to LUT
   logic — a 1-Mbit mux tree, 65k of the design's 74k LUTs, and a 6 h
   timing-driven placer run. `build_all.tcl` now passes
   `set_option -rom_map_logic 0`; contents are loaded at power-up by the
   design-initialization flow via PF_INIT_MONITOR.
2. **CDC FIFOs into LSRAM** (~109 -> ~112 MHz, and much less
   congestion). `hdl/axis_async_fifo.v` now wraps open-logic
   `olo_base_fifo_async` with `RamStyle_g "block"`, 512x41 in one LSRAM
   per FIFO, reclaiming ~16k flops and ~12k LUTs versus the register-based
   PULP `cdc_fifo_gray`. This also removed the xbar handshake path from
   the critical list — that path was ~8 ns of *routing* caused by the
   FIFOs spreading the design across the die, not decode depth.
3. **Pipelined fast multiplier** (~112 -> 125 MHz, +1.14 ns). The
   `CPU_FAST_MUL_REG` generic, enabled in the wrapper (see below).

### Fast-multiplier pipeline register (`CPU_FAST_MUL_REG`)

A 33x33 signed multiply becomes a cascade of three 18x18 MACC blocks on
PolarFire (vs. two 27x18 DSP48E2s / one cascade hop on the axau15's
UltraScale+). Stock `neorv32_prim_mul` has exactly one register after the
product, so the whole cascade is a single combinational cloud: measured
8.66 ns, of which 6.77 ns is hard-macro delay that no placement or routing
effort can reduce. All 20 worst paths were this structure.

`deps/neorv32` carries the `CPU_FAST_MUL_REG` generic (threaded
`neorv32_top` -> `neorv32_cpu` -> `neorv32_cpu_alu` ->
`neorv32_cpu_alu_muldiv` -> `neorv32_prim_mul`, and exposed in
`neorv32_vivado_ip`), submitted upstream as
[PR #1603](https://github.com/stnolting/neorv32/pull/1603). Default false
keeps every existing consumer bit-identical — notably the FPU, which times
`neorv32_prim_mul` with a fixed-length shift register instead of a
handshake. When enabled, `neorv32_prim_mul` gets a second register stage
and `neorv32_cpu_alu_muldiv` adds an `S_PIPE` wait state so a fast multiply
takes `T_mul_latency = 2` (division and the serial multiplier never enter
`S_PIPE`).

This project turns it on with `CPU_FAST_MUL_REG => true` in
`hdl/neorv32_mpf300_top.vhd` (no source override needed; earlier revisions
used a local `FAST_MUL_REG_c` constant patch, now removed).

Result: synthesis put `P_REG` on a cascade slice, splitting the path into
4.95 ns (MACC -> MACC cascade) and a short remainder. MUL/MULH go from
`3 + 1` to `3 + 2` cycles (datasheet formula) — 25% slower multiplies for
+13 MHz. No software impact: no ISA change, and the no-os HAL reads the
clock from SYSINFO.

## Simulation

After synthesis, the design can be simulated against the netlist or RTL
(`proj/` contains the full source set; the NEORV32 IMEM holds the
ad9361_no-os image, so a top-level sim boots the console on `sys_uart_tx`).

The streaming datapath (SmartHLS adapters + `axis_async_fifo` CDC FIFOs +
`dac_hold`) has a dedicated Verilator simulation that reuses this project's
components directly:

```sh
cd deps/neorv32/setups/neorv32_sw_ad9361_datapath_sim/verilator_sim_microchip
make clean && make          # prints TEST PASSED
```

The axi_ad9361 PolarFire device interface is covered separately by the
QuestaSim loopback TB in `deps/hdl/library/axi_ad9361/sim/microchip`.
