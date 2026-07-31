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

## Libero installation and launcher (Ubuntu 24.04)

Ubuntu 24.04 is not an officially supported Libero host; this section
records exactly what was done to make Libero SoC 2025.2 work on it. A
reference copy of the launcher lives in `./libero_configuration/`.

### Installing Libero SoC 2025.2

1. Download the offline installer (`Libero_SoC_2025.2_offline_lin.sh`)
   from Microchip and run it with root privileges:

   ```sh
   sudo ./Libero_SoC_2025.2_offline_lin.sh
   ```

   Install path used here: `/media/fpgadev/Dev_Tools/Microchip`.
   Components installed (see `LiberoConfig.txt` in the install root):
   Libero SoC 2025.2, SmartHLS 2025.2, Standalone Program Debug,
   **MegaVault 2025.2** (required — this machine has no route to the
   online IP repository; `build_all.tcl` generates PF_CCC /
   PF_INIT_MONITOR from the offline vault), Synplify Pro
   W-2025.03M-SP1-1, ModelSim/QuestaSim ME 2024.3.

2. 32-bit libraries. The FlashPro programming tools that run during
   bitstream generation (`Designer/binfp/`: `fpbitgen_bin`,
   `jobmgr_bin`, ...) are 32-bit executables. Everything they need comes
   from the Ubuntu archive — nothing is copied by hand:

   ```sh
   sudo dpkg --add-architecture i386
   sudo apt update
   # core 32-bit runtime for the FlashPro tools
   sudo apt-get install -y --no-install-recommends \
       libc6:i386 libstdc++6:i386 zlib1g:i386 libfreetype6:i386 \
       libfontconfig1:i386 libx11-6:i386 libxau6:i386 libxdmcp6:i386 \
       libxext6:i386 libxft2:i386 libxrender1:i386 libxtst6:i386 \
       libxi6:i386 libxfixes3:i386 libsm6:i386 libice6:i386 \
       libncurses6:i386
   # GUI-side extras (GTK2 file dialogs, sound module, CJK fonts, ksh)
   sudo apt install -y libglapi-mesa:i386 libglib2.0-0t64:i386 \
       libxcb-dri2-0:i386 libgtk2.0-0t64:i386 \
       libcanberra-gtk-module:i386 libflac12t64 libglapi-mesa \
       xfonts-intl-asian xfonts-intl-chinese xfonts-intl-chinese-big \
       xfonts-intl-japanese xfonts-intl-japanese-big ksh
   ```

   At runtime the 32-bit tools resolve only `libc/libm/libpthread/
   libdl/librt/libz` from `/lib/i386-linux-gnu` plus Libero's own
   bundled 32-bit libraries (`Designer/libfp`), so no manual library
   copies are needed — which is why `libero_configuration/` carries no
   `.so` backups, only the launcher: nothing is hand-copied into system
   or install directories, and a fresh machine is reproduced entirely by
   the installer + the apt commands above + the launcher.

3. License. A FlexLM server runs locally from the 64-bit daemons the
   installer places in `<install>/LicenseDaemons` (`lmgrd`, `actlmgrd`,
   `snpslmd`, `saltd`):

   ```sh
   cd /media/fpgadev/Dev_Tools/Microchip/LicenseDaemons
   ./lmgrd -c /media/fpgadev/Dev_Tools/Microchip/Libero_License_active.dat \
           -l /media/fpgadev/Dev_Tools/Microchip/license_daemon.log
   ```

   The license file's SERVER line uses port **1702**, which is what the
   launcher exports (`1702@localhost`).

### Configuring `run_libero.sh`

The launcher (installed copy: `/media/fpgadev/Dev_Tools/Microchip/
run_libero.sh`, reference copy: `./libero_configuration/run_libero.sh`)
lives outside the repositories on the host — on a new machine, copy the
reference copy next to the Libero install and edit it there. It does
exactly two things beyond exec'ing Libero; both may need editing:

1. `LM_LICENSE_FILE=1702@localhost` — point at your FlexLM server
   (`port@host` from the SERVER line of your license file).
2. `LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libstdc++.so.6` — **required
   on Ubuntu 24.04**. Libero links the system `libxml2`, which pulls the
   system `libicuuc.so.74`, which requires `GLIBCXX_3.4.30`; Libero's
   bundled RHEL `libstdc++` (max `GLIBCXX_3.4.28`) is too old, so
   without the preload `libero_bin` fails at startup. Side effect: every
   32-bit child tool prints `ERROR: ld.so: object '...libstdc++.so.6'
   ... wrong ELF class: ELFCLASS64: ignored` — this is harmless noise
   (a 32-bit process skipping a 64-bit preload), not a failure. On a
   supported RHEL host neither line 2 nor the noise applies.

Usage (headless):

```sh
run_libero.sh SCRIPT:/abs/path/build_all.tcl LOGFILE:/abs/path/build_all.log
```

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

## Deploying to the Splash Kit

### Jumper configuration (set with board powered OFF)

(references: UG0786 Table 3, board schematics in `doc/MPF300-Splash-Kit/`,
PolarFire Programming UG Table 3-4 for the SC-SPI mode straps):

| Jumper | Setting | Why |
|---|---|---|
| **J35** | **OPEN — no shunt** | Straps `IO_CFG_INTF` (ball G9). Open = pulled high = the System Controller's SPI powers up in **master** mode, required for stage-3 design init from the flash. **A shunt here puts the SC-SPI in slave programming mode, and "design initialization from an external SPI flash is not supported in SPI slave mode": the SC silently skips stage 3, `SRAM_INIT_DONE` never asserts, the CPU is held in reset and the console stays silent — while JTAG programming of the very same flash keeps working.** (`SPI_EN` is hardwired high on this board: R349 pull-up, R350 pull-down not loaded.) Undocumented in UG0786's jumper table; found the hard way. |
| **J32** | **pins 3-4 closed** (change from default 1-2) | Sets `VCCIO_LPC_VADJ` to **2.5 V**. Default is 3.3 V, which is wrong for this design *and* for the FMCOMMS2. |
| **J10** | **pins 1-2 closed** (change from default open) | Routes the SPI flash to the PolarFire's SC_SPI (a 74CBTLV3257 mux, U71, sits between the flash and either the FTDI or the PolarFire; J10 drives its select). Required both for programming the flash (the System Controller writes it over JTAG) and for **every power-up** (stage-3 init streams the firmware from flash). With J10 open the flash is muxed to the FTDI and the programmer reports "SPI - Flash is not connected or not supported". |
| J5-J9 | default (PolarFire JTAG path) | Routes the FTDI to the PolarFire's JTAG; UG0786 says "always retain the default." |
| J11 | default (1-2 closed) | Program via the on-board FTDI over USB. Open only to use an external FlashPro5. |
| J3 | default (open, 1.0 V core) | Standard core voltage. |
| J4 | default (1-2 closed) | Power via slide switch SW1. |

### FMC power verification (before the FMCOMMS2 touches the board)

The J17 FMC LPC connector receives three supplies from the carrier:
**`VCCIO_LPC_VADJ`** (the FMC VADJ pins, from the 5 A U27 regulator,
J32-selected), **12P0V**, and **3P3V**. VADJ must be 2.5 V for two
independent reasons: the FMCOMMS2's AD9361 interface expects VADJ = 2.5 V
in LVDS mode, and this design's `constraint/io.pdc` constrains every
AD9361 pin on bank 2 as `LVDS25`, which requires 2.5 V VCCIO on that
bank — at 3.3 V the I/O standard is electrically invalid on both sides
of the connector.

Procedure: set J32 -> power up the bare board (12 V/5 A adapter, SW1) ->
DMM-verify the VADJ rail at 2.5 V (VADJ pins/decoupling at J17; sanity-
check 12P0V and 3P3V) -> power down -> seat the FMCOMMS2 -> power up.
Never hot-plug the FMC.

### Two memories, two programming paths

The deployed design lives in **two physical memories**, written by
different mechanisms over the same USB cable:

- **Fabric + sNVM** (logic configuration + the 504-byte stage-1 init
  client): programmed over **JTAG** through the on-board FTDI — "the
  bitstream" in the classic sense.
- **SPI flash** (1 Gb Micron MT25QL01GB on the System Controller's
  dedicated SC-SPI, bank 3): holds the **stage-3 init client at offset
  0x400** — the ~263 KB instruction stream carrying the NEORV32
  `ad9361_no-os` firmware image and the SmartHLS buffer contents. The
  firmware (107 KB) physically cannot live on-die: sNVM is ~54 KB and
  the MPF300 uPROM is smaller still. There is no separate flash
  programmer: the JTAG session hands the image to the **System
  Controller, which writes the flash itself** through SC-SPI.

Consequence: **firmware-only iterations do not touch the fabric** —
rebuild the no-os image, re-run `build_all.tcl`, reprogram only the SPI
flash. On power-up the device runs I/O calibration (stage 1, sNVM), then
streams the LSRAM contents from flash (~60-80 ms at 40 MHz);
`SRAM_INIT_DONE` gates `sys_ctrl`'s `sys_resetn`, so the CPU cannot
fetch before the firmware is physically loaded.

### Files and programming sequence

`build_all.tcl` ends by exporting deployment artifacts to `proj/export/`
(`MPF300_FMCOMMS2_EXPORT_OK`):

| File | Type | Role |
|---|---|---|
| `fmcomms2_mpf300.job` | FlashPro Express job | fabric + sNVM bitstream; also bundles the SPI-flash image once `cfg/spiflash.cfg` is captured (see below) |
| `fmcomms2_mpf300_spi.bin` | SPI-flash image (MT25QL01GB) | standalone flash contents (only exported once `cfg/spiflash.cfg` is captured) |
| `proj/designer/Top/Top.ppd` | programming database | Libero-internal; source for direct programming and the exports |

Sequence:

1. Jumpers as above, FMCOMMS2 seated, 12 V adapter, mini-USB to host,
   SW1 on.
2. Program fabric + sNVM: `program_board.tcl` step 1 (`PROGRAMDEVICE`),
   or FlashPro Express with the exported `.job`.
3. Program the SPI flash: `program_board.tcl` step 2
   (`PROGRAM_SPI_FLASH_IMAGE`). The SPI Flash memory map comes from
   `cfg/spiflash.cfg` (ships in the repo, applied by `build_all.tcl`);
   its 256-byte STATIC_FILL placeholder client works around a Libero
   2025.2 batch-mode segfault — details in the `program_board.tcl`
   header.
4. Power-cycle (a clean init run needs it). Boot takes the three-stage
   init described above, then the no-os console appears on the FTDI UART
   (115200). The console is FT4232H channel C — the single `ttyUSB` the
   `ftdi_sio` driver binds (the FTDI enumerates with Microsemi's VID/PID
   `1514:2008` "Embedded FlashPro5", not as a generic FTDI). Only ONE
   process may read the tty at a time — two readers split the byte
   stream and both see garbage.

## Status / timing (Libero 2025.2)

The design is fully operational on the Splash Kit: power-up loads the
NEORV32 firmware from SPI flash into the IMEM LSRAMs (jumper and SPI
divider requirements are in "Deploying to the Splash Kit" above), the
CPU boots the ad9361_no-os application, and the RF QPSK link measures
**2.06% EVM** with no runtime tuning (axau15 reference: ~2.5%).

All internal clock domains meet timing at 125 MHz. The only paths the
timing report flags are the AD9361 I/O eye checks, which are analyzed
at a deliberately pessimistic 8 ns ceiling period (see the interface
section below) and are verified on hardware instead: the chip's PRBS
BIST through the RX interface shows zero PN sync losses
(`hold_bist` + `get_valid_rate` console commands), and RF EVM covers
the interface end to end. Chip BB loopback EVM is qualitative only —
the loopback path bypasses the RX analog DC/gain handling and carries a
mode artifact.

24.1k logic elements (8% of MPF300); synthesis ~2.5 min, place & route
~11 min, full build through bitstream + export ~20 min.

Timing-relevant configuration, in one place:

- **IMEM ROM in LSRAM**: `hdl/neorv32_imem_rom.vhd` pins the inferred
  128 KB ROM to `syn_romstyle = "lsram"`, and `build_all.tcl` passes
  `set_option -rom_map_logic 0` and `-automatic_compile_point 0` so
  every Synplify mapping context extracts RAM1K20s instead of building
  a LUT mux tree. Contents load at power-up via the design-init flow.
- **CDC FIFOs in LSRAM**: `hdl/axis_async_fifo.v` wraps open-logic
  `olo_base_fifo_async` with `RamStyle_g "block"` (512x41, one LSRAM
  per FIFO), keeping the die compact and the xbar handshake paths
  short.
- **Interconnect**: the PULP `axi_lite_xbar` runs with
  `LatencyMode = CUT_ALL_PORTS` — the SmartHLS bridge's `r_valid`
  depends combinationally on `r_ready`, and the spill registers sever
  the loop that would otherwise form through the fall-through demux.
- **CPU multiplier**: `CPU_FAST_MUL_REG => true` pipelines the DSP
  fast multiplier (see the dedicated section below).
- **Synplify retiming** (`set_option -retiming 1`) is enabled for the
  CPU domain.

### AD9361 LVDS interface clocking and I/O timing

The interface is two independent source-synchronous DDR links running
from one frequency reference, the AD9361's `DATA_CLK`. In this design's
fixed RF profile (1R1T, 30.72 MSPS) `DATA_CLK` is 61.44 MHz: period
16.276 ns, so one DDR unit interval (UI) — one bit time — is 8.138 ns.

```
                AD9361                              MPF300
   +---------------------------+    +-----------------------------------------+
   |                           |    |                                         |
   |  DATA_CLK (61.44 MHz) ----+----+-> INBUF_DIFF -> CLKINT_PRESERVE         |
   |    sources ALL timing     |    |                       |                 |
   |                           |    |                  PF_CCC_C1 (PLL)        |
   |                           |    |                   |          |          |
   |                           |    |          OUT0 = l_clk    OUT1 = +90 deg |
   |                           |    |           (0 deg)            |          |
   |                           |    |               |              |          |
   |  rx_frame, rx_data[5:0] --+----+-> pad/route --+-> DDR        |          |
   |    (DDR, launched on      |    |     (per bit)    capture FFs |          |
   |     DATA_CLK edges)       |    |       [RX: clocked by l_clk] |          |
   |                           |    |                              |          |
   |  FB_CLK <-----------------+----+--- DDR out mux <-------------+          |
   |    (TX sampling strobe)   |    |      [FB_CLK pad: const 01, from OUT1]  |
   |                           |    |                                         |
   |  tx_frame, tx_data[5:0] <-+----+--- DDR out muxes <-- l_clk (OUT0)       |
   |    (chip samples these    |    |      [TX DATA: 7 structures]            |
   |     on FB_CLK edges)      |    |                                         |
   +---------------------------+    +-----------------------------------------+
```

The clocks:

- **`DATA_CLK`** — generated by the AD9361, the sole frequency
  reference for the interface. Enters on an FMC-dictated pin that is
  not a CCC-function pin, so it must reach the PLL through the fabric
  global network: `INBUF_DIFF -> CLKINT_PRESERVE -> PF_CCC_C1`
  (`CLKINT_PRESERVE`, not plain `CLKINT`, or Synplify optimizes the
  buffer away and P&R reinstates the dedicated-routing rule it cannot
  satisfy, error PDCPF-13).
- **`l_clk`** (PF_CCC_C1 OUT0, 0 deg) — the interface-domain clock:
  clocks the RX capture flip-flops, the whole ADI l_clk-domain
  datapath, and the TX data/frame output structures.
- **OUT1** (+90 deg) — clocks exactly one thing: the FB_CLK output
  structure. The CCC runs Post-VCO feedback, which guarantees the
  OUT0/OUT1 phase relationship across corners.
- **`FB_CLK`** — the clock the FPGA sends back to the chip alongside
  the TX data; the AD9361 samples `tx_frame`/`tx_data` on FB_CLK edges
  (t_STX = 1.0 ns setup, t_HTX = 0 ns hold). It is produced by the
  same DDR output structure as the data pins, driven with the constant
  pattern `01` — so its launch clock's phase directly sets where the
  chip's sampling edges land in the data eye.

Two clocks enter this design through the fabric, for different reasons.
`DATA_CLK` has no choice: the Splash Kit routes FMC LA00_CC to ball
A17, which has no CCC function (the same class of board shortcoming as
the au15p, whose FMC mapping put LA00_CC on a Xilinx QBC pin with no
BUFGCE route). The 50 MHz reference on H7, by contrast, IS a
CCC-function pin (`CLKIN_W_2`, SW-corner CCC) and is routed through
the fabric **by choice**: the dedicated pad route binds the PLL to the
SW-corner CCC, while a fabric reference leaves the timing-driven
placer free to put it anywhere. PLL capacity is not a factor either
way — each of the MPF300's four corner CCCs contains two PLLs (eight
sites); this design uses two, both fabric-referenced. A fabric-routed
reference costs only a little added jitter (insertion delay is
irrelevant to a PLL reference), plus the bookkeeping this file
documents: the `CLKINT_PRESERVE` idiom and the manual generated-clock
declarations in the SDC.

#### RX direction (AD9361 -> FPGA)

The chip launches `rx_frame`/`rx_data[5:0]` edge-aligned with
`DATA_CLK`: each bit transitions t_DDDV = 0.25..1.25 ns after every
clock edge (plus ~1.2 ns from the firmware's chip-side
`rx_data_delay = 4`). The FPGA captures in fabric DDR flip-flops
clocked by `l_clk`.

```
time (ns) relative to a DATA_CLK edge "E" at the FPGA pad:

  E                                                     E+8.138 (next edge)
  |                                                     |
  |-- transition --|########## DATA VALID ##############|-- transition --|
  |   region       |          (the eye)                 |   region       |
  |                                                     |
  |--- clock path (CCC + global insertion) ---->X
                                                ^
                    effective sampling point of the capture FF
                    (clock insertion minus that bit's pad->FF routing)
```

`constraint/system.sdc` describes the transition regions with
`set_input_delay -min/-max` on both clock edges for all 14 inputs.
The tools then verify per bit and per corner that the sampling point
lands inside the eye, and — the operative part — place & route
balances the per-bit pad-to-FF routing so all sampling points cluster.
Without the constraints the per-bit skew is unmanaged, which is fatal
for a fabric (soft-logic) capture. Interface integrity is verified on
hardware with the chip's PRBS BIST: `hold_bist` drives a PN sequence
through the RX pins and `get_valid_rate` must report 0% PN sync loss.

#### TX direction (FPGA -> AD9361)

All eight TX outputs (six data, frame, FB_CLK) are identical fabric
DDR structures, so outputs launched from the same clock transition
simultaneously at the pads. Launching FB_CLK from OUT1 (+90 deg)
places its edges a quarter period after the data transitions; the
chip's own `tx_fb_clock_delay = 7` init parameter (~2.2 ns internal
FB_CLK delay) moves its sampling point further into the bit:

```
time (ns) relative to the l_clk edge that launches a TX bit:

 pads:  data transition          FB_CLK edge
        (OUT0-launched)          (OUT1-launched)
        |                        |
        |----- +4.07 (90 deg) -->|
        |                        |
 chip:                           |-- +2.2 (tx_fb_clock_delay=7) -->|
        |                                                          |
        |################# DATA VALID (this bit) ##################|#####|
        0                                                        ~6.3  8.138
                                                                   ^
                                                        chip samples here

        setup to next transition: 8.138 - 6.3 = 1.84 ns  (t_STX 1.0 -> ~0.8 ns margin)
        hold from last transition: 6.3 ns                (t_HTX 0   -> ~6.3 ns margin)
```

The SDC declares the CCC output clocks (`l_clk_pll`, `tx_fbclk_90` —
fabric-referenced PLL outputs are not derived automatically) and a
generated clock on the FB_CLK pad, with `set_output_delay` windows
from t_STX/t_HTX. Because the +90 deg is not modeled under the 8 ns
ceiling period, the TX I/O report is advisory; the shift itself is
physical (PLL-guaranteed), and RF EVM is the verification. If more TX
setup margin is ever wanted, lowering the firmware's
`tx_fb_clock_delay` toward 2 re-centers the sampling point at
~4.7 ns (~2.4 ns margin on both sides).

#### Why this differs from the Xilinx port

The axau15 uses the same edge-aligned launch topology — FB_CLK is an
ODDR fed the constant `01` pattern, exactly like the data bits — and
carries **no I/O timing constraints at all**. It gets away with that
because both sides of the problem are absorbed elsewhere: ODDR/IDDR
launch and capture live in dedicated I/O blocks with picosecond-class
matching (no per-bit fabric skew to manage), and the chip's
`tx_fb_clock_delay`/`rx_data_delay` registers provide the eye
centering (with IDELAY taps available for fine trim). PolarFire's
fabric-emulated DDR has neither property: per-bit skew is
nanosecond-class unless the tools are told to balance it (hence the RX
input constraints), and no delay element exists on the TX side big
enough to center the eye (hence manufacturing the shift with the CCC
phase pair). The chip-side delay registers are kept at the same values
as the Xilinx build; the CCC's +90 deg composes with them.

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
`hdl/neorv32_mpf300_top.vhd`.

With the register enabled, synthesis puts `P_REG` on a cascade slice,
splitting the path into 4.95 ns (MACC -> MACC cascade) and a short
remainder. MUL/MULH take `3 + 2` cycles instead of `3 + 1` (datasheet
formula) — a 25% slower multiply in exchange for the CPU domain closing
125 MHz. No software impact: no ISA change, and the no-os HAL reads the
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
