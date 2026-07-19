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
| SmartConnect 1x3 | `hdl/axi_1to3_decoder.v` (same address map) |
| axi_bram_ctrl + blk_mem_gen | `hdl/axi_bram_32k.v` (LSRAM inference) |
| axis_data_fifo (async, 256, TLAST) x2 | `hdl/axis_async_fifo.v` x2, same topology and reset gating |
| proc_sys_reset x2 + pwr_dn gates + xpm_cdc | `hdl/sys_ctrl.v` (125 MHz) + `hdl/lclk_reset_sync.v` (l_clk) |
| Vitis HLS adapters | SmartHLS ports from `src/*_microchip` (+ `hdl/dac_hold.v` for the write_en/write_data DAC outputs) |
| IODELAY/IDELAYCTRL calibration | none (polarfire port; static SDC timing) |

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

## Status / timing (2026-07-19, Libero 2025.2)

Synthesis, place & route, and timing analysis all complete
(`MPF300_FMCOMMS2_SYNTH_OK` / `MPF300_FMCOMMS2_PNR_OK`); all 57 pins
locked; ~75k logic elements (25% of MPF300), post-layout multi-corner:

| Clock | Constraint | Worst setup slack | Meets |
|---|---|---|---|
| `rx_clk_in` (AD9361 l_clk domain) | 125 MHz | +2.59 ns | yes |
| `clk_125mhz` (NEORV32/AXI domain) | 125 MHz | **-6.46 ns (~69 MHz)** | **no** |
| hold, all clocks, all corners | - | positive | yes |

Root cause (found 2026-07-19, `Top_ram_rpt.txt`): Synplify's default
`rom_map_logic 1` mapped the inferred 128 KB NEORV32 IMEM ROM to **LUT
logic** instead of LSRAM — ~65k of the 74k 4LUTs were a 1-Mbit ROM mux
tree, and the failing paths (fetch address -> ~15 LUT levels -> IMEM
rdata) were that mux, not the CPU. It also explains the 6 h timing-driven
placer runtime. `build_all.tcl` now passes `set_option -rom_map_logic 0`
so the IMEM goes to LSRAM (contents loaded at power-up by the
design-initialization flow via PF_INIT_MONITOR); the numbers above are
from the last build *before* that fix and need to be re-measured. The
datapath (axi_ad9361 + adapters + FIFOs, l_clk side) met 125 MHz even
with the bad mapping.

Fallback if the re-measured CPU domain still misses 125 MHz: drop the
CPU/AXI domain to 100 MHz (PF_CCC `GL0_0_OUT_FREQ`, NEORV32
`CLOCK_FREQUENCY` generic, and the SDC generated clock — three numbers,
no software change: the no-os HAL reads the clock from SYSINFO). The CDC
FIFOs isolate it from l_clk; only the "AXI clock >= l_clk" RX-drain
guideline matters, i.e. keep sample rates such that l_clk <= 100 MHz.

## Simulation

After synthesis, the design can be simulated against the netlist or RTL
(`proj/` contains the full source set; the NEORV32 IMEM holds the
ad9361_no-os image, so a top-level sim boots the console on `sys_uart_tx`).
