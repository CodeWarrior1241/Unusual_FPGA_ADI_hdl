# FMCOMMS2 on Efinix Titanium Ti375 C529 Development Kit

Efinix port of the FMCOMMS2/3 (AD9361) QPSK SDR design that runs on the
Xilinx `axau15` and Microchip `mpf300` targets: NEORV32 RISC-V CPU +
ADI `axi_ad9361` + SmartHLS-generated datapath adapters + Bedrock-RTL CDC
FIFOs + QPSK snapshot BRAM. The AXI address map and GPIO map are identical
to the other two ports, so the `ad9361_no-os` firmware in
`deps/neorv32/sw/ad9361_no-os` runs **unmodified** (125 MHz CPU clock, same
UART protocol, same `sim/python` GUI).

Target: **Ti375C529** (362 k LEs, C4 timing) on the Ti375 C529 Development
Kit, FMCOMMS2/3 on the FMC LPC connector J17. Toolchain: **Efinity 2026.1**
(no license server needed). The port rationale, board analysis, and the
feasibility smoke-test record live in the migration study
(`Efinix_Migration.md`); this README is the operational summary.

## Build

```bash
cd deps/hdl/projects/fmcomms2/ti375
./scripts/build_all.sh          # firmware image + generators + full compile
```

`EFINITY_HOME` overrides the default install location
(`/media/fpgadev/Dev_Tools/Efinity/2026.1`). The build emits
`TI375_FMCOMMS2_SYNTH_OK` / `_PNR_OK` / `_BITSTREAM_OK` milestone markers
(CI parity with the other targets) and produces
`outflow/ti375c529.bit` (JTAG) + `outflow/ti375c529.hex` (SPI flash).

The three Python generators are the **source of truth**; their outputs are
build products (gitignored):

| Generator | Output | Replaces (Libero flow) |
|---|---|---|
| `scripts/gen_project.py` | `ti375c529.xml` (157 HDL files, per-file VHDL library, include dirs, macros) | `new_project` + `import_files` + amalgamation hacks |
| `scripts/gen_interface.py` | `ti375c529.peri.xml` (2 PLLs, 16 LVDS lanes, GPIO) + design-rule check | MegaVault PF_CCC cores + `io.pdc` |
| `scripts/gen_top.py` | `doc/system_top.svg` block diagram | the SmartDesign/IPI canvas view |

Never hand-edit `ti375c529.xml` — the tool rewrites it in place; edit the
generator. There is **no** design-initialization/SPI-staging step: RAM init
(including the NEORV32 IMEM firmware image) is baked into the bitstream.
Firmware iteration = rebuild image (`make clean_all image` in
`deps/neorv32/sw/ad9361_no-os`) and re-run `build_all.sh`.

## System

Same topology as the mpf300 SmartDesign `Top` (see that README's diagram or
`doc/system_top.svg` here):

- 125 MHz domain: NEORV32 (`hdl/neorv32_ti375_top.vhd`, identical generics
  to the other ports incl. `CPU_FAST_MUL_REG`), `axi_1to3_decoder` (PULP
  `axi_lite_xbar`), 32 KB QPSK BRAM at `0xC000_0000`, `axi_ad9361`
  registers at `0x44A0_0000`, streaming adapter at `0x44A1_0000`,
  `sys_ctrl` (resets, `pwr_dn`, GPIO fan-out).
- l_clk domain (61.44 MHz from the AD9361 DATA_CLK): ADI datapath,
  `axi_ad9361_adapter` (SmartHLS), `dac_hold`, `lclk_reset_sync`.
- CDC: two Bedrock-RTL `axis_async_fifo` (512×41, 3× RAM10 each) +
  `br_cdc_bit_toggle` for `pwr_dn`.
- Periphery (Interface Designer, no RTL): `sys_pll` (25 MHz OSC1 → 125 MHz),
  `lvds_pll` (61.44 MHz 0°/+90°), 8 LVDS RX + 8 LVDS TX lanes, GPIO.

### The Efinix LVDS interface (`deps/hdl/library/axi_ad9361/efinix/`)

Titanium has no I/O primitives in RTL — LVDS buffers, ×2 half-rate SERDES
(the IDDR/ODDR equivalent), termination and delay elements live in the
configured periphery. The Efinix `axi_ad9361_lvds_if.v` keeps ADI's
delineation/framing/ensm logic verbatim and **repurposes the physical port
list** (same module name/ports, so the shared `axi_ad9361.v` is untouched):

| Port | Efinix meaning |
|---|---|
| `rx_clk_in_p` | `l_clk` in (lvds_pll CLKOUT0, 0°) |
| `rx_data_in_p/n[i]`, `rx_frame_in_p/n` | 2-bit deserializer word: `_n` = first captured bit, `_p` = second |
| `tx_data_out_p/n[i]`, `tx_frame_out_p/n` | 2-bit serializer word: `_n` transmitted first |
| `tx_clk_out_p/n` | unused — FB_CLK is a periphery CLKOUT-mode lane clocked by `l_clk_90` (+90° eye centering, the PF_CCC OUT1 trick moved into the periphery) |
| `delay_clk` | lvds_pll LOCKED in (folded into `adc_status` → preserves the `power_up` relock gating) |

Clocking topology note: the FMCOMMS2 pinout lands `rx_clk` (LA00_CC) on a
**GCLK pad** (GPIOB_PN_20 / CLK7), not a PLL pad, so `lvds_pll` (BR0) takes
its reference **through the core clock tree** — explicitly supported by the
device; Efinity's design check flags one advisory warning (accepted; tree
jitter is tens of ps against the 8.14 ns UI). Chip-side delay values
(`rx_data_delay=4`, `tx_fb_clock_delay=7`, `ADC_INIT_DELAY=11`) carry over
from the MPF300 port unchanged.

**Bring-up knobs, in order** (bench, with the AD9361 PRBS BIST as oracle):

1. Swap the `_n`/`_p` bit order at the `system_top.v` wiring (deserializer
   word order vs. the assumed PolarFire DDR timing).
2. Sweep per-lane `RX_DELAY` (0–63 × ~25 ps) in `gen_interface.py`.
3. Chip-side `rx_data_delay` / clock delay via firmware (as on MPF300).

## Board wiring (scripts/efinix_io_map.csv)

Full AD9361 → FMC → Ti375 pin map is machine-readable in
`scripts/efinix_io_map.csv` (consumed by `gen_interface.py`). Highlights:
all LVDS lanes land in bottom-side HSIO banks 4B/4C/4D (one device side,
per the Titanium same-side rule); VADJ is fixed at 1.8 V = exactly the
Titanium LVDS requirement (the MPF300's LVDS25 becomes plain LVDS);
UART console on GPIOR_144/145 (FT4232H channel C, 3.3 V); reset button
SW3 on GPIOL_52 (3.3 V, weak pull-up, active low).

### Kit setup (board powered OFF)

| Item | Setting |
|---|---|
| PJ5/PJ8/PJ9 (VCCIO 4B/4C/4D) | default 1-2 = 1.8 V (`1V8_FMC`) — never 1.2 V (bank 4B carries the config flash) |
| J7 / J10 | jumpers fitted; replace with ammeter for I/O+mezzanine / core-rail power measurement |
| PJ18 (FMC I2C level) | 1.8 V position |
| J20 (FPGA-programming-through-FMC) | **open** when the FMCOMMS card is fitted |
| USB1 Type-C | ch B = JTAG, ch C = UART console (115200 8N1, 3rd VCP port), ch D = power telemetry I2C |
| SW1 | CRESET_N (reconfigure); SW3 = design reset |

Config-pin hazards (checked once, then ignore): tx_data[0]/LA11 doubles as
NSTATUS/TEST_N, tx_data[1]/LA12 as the CBSEL config straps,
gpio_status[2..3]/LA21 as CDONE/INIT_RST_N — all AD9361-side Hi-Z at
power-up; verify no pulls on the FMCOMMS2 schematic before first power-on
(migration study §6.5/§6.8).

## Deploying

```bash
./scripts/program_board.sh          # volatile JTAG load (bench default)
./scripts/program_board.sh flash    # NOR flash via JTAG bridge (standalone boot)
```

One USB cable: program over ch B, watch the firmware banner on ch C.
No two-memory dance — the bitstream carries everything.

## Power measurement (the point of the project)

- Core rail 0.95 V: J10 series header (bench ammeter) or on-board
  2.5 mΩ/INA281 telemetry via USB1 ch D (UCD9081 + PCA9548A @0x70).
- I/O + mezzanine: `1V8_FMC` feeds both the FPGA LVDS banks **and** the
  FMCOMMS2 VADJ on this kit — record as "I/O+mezzanine" (methodology
  difference vs. MPF300, where the two were separate).
- Keep the Ti375's hard SoC / LPDDR4 blocks unconfigured (this build does)
  and record the empty-bitstream baseline for the three-way comparison.
- `power_down`/`power_up` UART commands work as on the other ports:
  `pwr_dn` gates the register-domain resets and both CDC FIFOs; PLL relock
  is re-verified on wake via `adc_status` (the LOCKED plumbing above).

## Status (Efinity 2026.1.132, first full build 2026-08-10)

`map / interface / pnr / pgm` all **PASS** headless; `outflow/ti375c529.bit`
(JTAG) and `.hex` (SPI) produced with the ad9361_no-os firmware image baked
into IMEM. Not yet hardware-tested — bench bring-up (console, PRBS BIST,
EVM, power protocol) is the remaining work.

| Metric | Value |
|---|---|
| Logic | 11 769 LUT4 / 15 276 FF / 5 256 ADD / 130 SRL8 (~3-4 % of the device) |
| Block RAM | 212 × RAM10 (IMEM 128 KB + DMEM 32 KB + QPSK BRAM 32 KB + CDC FIFOs + HLS buffers — no register fall-through) |
| DSP | 26 × DSP48 (ADI `ad_mul` datapath + NEORV32 fast-mul) |
| Timing (C4) | clk_125mhz: +2.43 ns setup slack at 8 ns (fmax ≈ 179 MHz); l_clk: +11.13 ns at 16.276 ns (fmax ≈ 194 MHz); hold clean |
| Pinout | matches the §6.3 kit map (rx_clk on GCLK CLK7 D1/D2; VADJ-bank LVDS at 1.8 V; UART GPIOR_144/145 at 3.3 V) |

## Efinity pitfalls (this port's equivalent of the Libero list)

1. **`setup.sh` vs. strict shell modes**: it appends to an unset
   `PYTHONPATH` (fatal under `set -u`) and runs `ldd --version | head -1`
   (SIGPIPE = exit 141 under `pipefail`). `build_all.sh` guards both.
2. **The tool rewrites the project XML it is given** (reformatting,
   reordering). Generator = source of truth, XML = build product.
3. **VHDL-only file sets fail on the `-v` CLI path** (`EFX-0015`); a
   project XML with per-file `library=` attributes is required — and is
   how the NEORV32 `neorv32` library is expressed.
4. **Interface Designer property gotchas** (each cost an iteration):
   `RX_TERM` is an enum (`ON`/`OFF`/`DYNAMIC`, not `1`); CORE-mode PLLs
   require `CORE_CLK_PIN`; width-2 SERDES must NOT specify a serial fast
   clock; the TX data pin property is `TX_OUT_PIN`; 3.3 V HVIO banks need
   an explicit `IO_STANDARD` (GPIO defaults to 1.8 V); the SW3 resource is
   plain `GPIOL_52` (ball name `GPIOL_52_PLLIN1` is rejected).
5. **RAM inference audit**: every memory must print `extracting RAM` in
   the map log. A clock network with tens of thousands of sequential loads
   = a memory fell through to flip-flops. The NEORV32 primitives need the
   generate-scope patch carried in `deps/neorv32`
   (`rtl/core/neorv32_prim.vhd` — memory arrays declared inside their
   generate branches; PR-ready for upstream, migration study §5.6-5.7).
6. **SDC names are lowercase** (synthesis lowercases VHDL identifiers) and
   constrain the **core-periphery boundary**, not package pins. No per-pin
   LVDS I/O delays — the SERDES margins live in the interface report
   (`outflow/ti375c529.pt_timing.rpt`) and the per-lane static delays.
7. **Use the classic flow, not the unified flow**, for a fully scripted
   periphery: with `unified_flow="true"` the map stage auto-infers GPIO
   blocks from the netlist and the interface stage merges them onto the
   loaded `.peri.xml` — every hand-defined pin collides ("GPIO x exists").
   `unified_flow="false"` makes `.peri.xml` the sole periphery source.
8. **SERDES lanes demand per-lane core control pins at P&R**: enabling
   deserialization/serialization creates required `<inst>_RX_RST`,
   `<inst>_TX_RST`, `<inst>_TX_OE` pins (INTF: INRST/RST are async
   serdes resets, OE is output enable). The packer fails with "Required
   pin ... not found" if the top level doesn't drive them, pin names must
   be **unique design-wide** (no sharing one core pin across lanes —
   "Found duplicated pin name"), and the names are **case-sensitive**.
   `system_top.v` exposes all 23 and fans them out from one internal
   `serdes_rst_s` (asserted while the l_clk domain is in reset or the
   lvds_pll is unlocked) and a constant-1 OE.
9. **`auto_calc_pll_clock` can silently miss the target frequency**: asked
   for 125 MHz from the 25 MHz OSC1, the solver delivered **100 MHz**
   (with CLKOUT0-feedback the output = ref×M/N and M is limited to
   {1,2,4}; ×5 needs feedback from a second CLKOUT with its own divider).
   Nothing errored — the interface report simply said 100 MHz. Found by
   the datapath simulation running Efinix's official `EFX_FPLL_V1` model
   (garbled UART at the wrong CPU clock); `gen_interface.py` now sets the
   sys_pll dividers manually (`FEEDBACK_CLK=CLK1`, `CLKOUT1_DIV/CLKOUT0_DIV
   = 40/8`) and **read-back-verifies every PLL output frequency**, failing
   the build on mismatch.
10. **The exported periphery sim netlist leaves LVDS `FASTCLK` unconnected**
   for ×2 half-rate lanes while the official models clock their DDR paths
   only from FASTCLK — the sim setup patches the netlist copy
   (see `deps/neorv32/setups/neorv32_sw_ad9361_datapath_sim_efinix/`).
11. **VHDL↔Verilog binding is default-library only**: the NEORV32
   integration files (`xbus2axi4_bridge`, `neorv32_vivado_ip`,
   `neorv32_ti375_top`) must be in the default library (they also bind
   each other via `entity work....`); only the core file list goes into
   library `neorv32`. And the project XML requires a `sw_version`
   attribute — without it `efx_map`'s parser fails with an opaque
   internal assertion.

## Simulation

The full-system datapath simulation lives at
`deps/neorv32/setups/neorv32_sw_ad9361_datapath_sim_efinix/` (Questa;
counterpart of the Xilinx and Microchip setups): the NEORV32 boots the
`ad9361_loopback` firmware against the real `hdl/system_top.v` and runs
config → TX burst → LVDS loopback → RX readback → power-gate cycle →
`TEST PASSED`.

**The simulation uses the official Efinix simulation models wherever
possible**: `scripts/gen_interface.py` exports
`outflow/ti375c529_pt_interface.v` (Interface Designer
`export_periphery_sim_netlist`), a pad-level wrapper instantiating the
shipped `EFX_FPLL_V1` / `EFX_LVDS_RX_V2` / `EFX_LVDS_TX_V2` / `EFX_GPIO_V3`
models from `$EFINITY_HOME/pt/sim_models/verilog` with this project's
exact periphery configuration — so the ×2 SERDES word order and PLL
behavior are Efinix's own, not a hand-written approximation. The netlist
is a build product, regenerated on every `gen_interface.py` run.

`sim/efinix/` (repo top) remains reserved for an isolated axi_ad9361
loopback TB if wanted; vendor-neutral subsystem sims (`sim/`,
Verilator/NVC) are unaffected by this port.
