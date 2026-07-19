# axi_ad9361 Testbench Simulation — Microchip PolarFire port

This directory contains the Microchip PolarFire port of the axi_ad9361
TX-to-RX loopback testbench (see `../xilinx/` for the original). The same
test sequence and pass criteria are used; the UUT is built from the
PolarFire device interface (`../../polarfire/`) instead of the Xilinx one —
the same file set that `src/mpf300_test_proj` proves in Synplify synthesis.

The simulation runs in **QuestaSim Pro ME**, the simulator that ships with
Libero SoC 2025.x. No pre-compiled vendor libraries are required: the
PolarFire primitive models (`INBUF_DIFF`, `OUTBUF_DIFF`, `CLKINT`, ...) are
compiled on the fly from the Libero installation
(`Designer/lib/vlog/polarfire.v`) into a local `polarfire` library.

## Test Description

The testbench:
1. Loads 1024 QPSK samples from `../xilinx/qpsk_bram_init.coe` (shared data set)
2. Configures the axi_ad9361 for DMA mode via AXI-Lite
3. Feeds samples through the DAC interface
4. Loops TX LVDS outputs back to RX LVDS inputs
5. Verifies ADC output matches expected values (DAC/16 due to 12-bit resolution)

## Prerequisites

- Libero SoC 2025.x installed (provides QuestaSim Pro and the PolarFire
  primitive models). Default location assumed:
  `/media/fpgadev/Dev_Tools/Microchip/Libero_SoC` — override with
  `LIBERO_INSTALL_DIR`.
- A license server carrying the `Microchipqsimpro` feature (the standard
  Libero license includes it). Default `1702@localhost`, matching
  `/media/fpgadev/Dev_Tools/Microchip/run_libero.sh`; override with
  `LIBERO_LICENSE_SERVER`.

Note: `run_sim.sh` clears `MGLS_LICENSE_FILE` / `SALT_LICENSE_SERVER` for
the simulator process. Those variables usually point at a Siemens Questa
Prime license (used by the `../xilinx` flow), which takes precedence inside
Questa but cannot serve the Microchip edition.

## Running the Simulation

```bash
cd deps/hdl/library/axi_ad9361/sim/microchip
./run_sim.sh                     # GUI, 100us (testbench self-terminates)
./run_sim.sh --batch             # batch/command-line mode
./run_sim.sh --time 200us        # longer run
./run_sim.sh --clean             # remove generated files
```

Or directly from the QuestaSim Tcl console:

```tcl
cd {.../deps/hdl/library/axi_ad9361/sim/microchip}
do simulate.do
```

Or compile and simulate separately:

```tcl
do compile.do
# ... then later ...
do simulate.do
```

## Files

| File | Description |
|------|-------------|
| `axi_ad9361_tb.v` | Main testbench (port of `../xilinx/axi_ad9361_tb.v`) |
| `compile.do` | QuestaSim compilation script (also builds the `polarfire` primitive library) |
| `simulate.do` | QuestaSim simulation script (elaborate, waves, run) |
| `run_sim.sh` | Linux launcher for the Libero-bundled QuestaSim Pro |

## Differences from the Xilinx simulation

- **Device interface:** `polarfire/axi_ad9361_lvds_if.v` +
  `polarfire/common/ad_data_{in,out,clk}.v` replace the Xilinx
  IDDR/ODDR/IDELAY-based interface. DDR I/O is fabric-emulated
  (posedge + negedge register pairs), matching `SAME_EDGE` semantics.
- **No delay calibration:** the IDELAY control interface is inert on
  PolarFire (`delay_locked` tied high, readback zero), so the delay clock
  is a dummy input; the testbench does not exercise delay sweeps.
- **`FPGA_TECHNOLOGY` = 0:** informational parameter, unused by the
  PolarFire device interface.
- **No `glbl.v` / UNISIM:** the only vendor library is `polarfire`,
  compiled by `compile.do`.

## Expected Output

Identical to the Xilinx simulation — 3 complete passes through the 1024
sample buffer (3072 samples), then:

```
========================================
  LOOPBACK TEST PASSED
  Data flows correctly through:
    DAC -> TX LVDS -> RX LVDS -> ADC
========================================

Simulation complete.
```

Last verified 2026-07-19 with Libero SoC 2025.2 (QuestaSim Pro ME 2024.3):
batch run completes in ~2 s wall clock, ADC/DAC sample counts and values
byte-identical to the Xilinx Questa run.
