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

### Power down / power up

The `power_down`/`power_up` console commands park the datapath and put
the chip in ENSM SLEEP with both LOs powered down; the fabric is never
gated. Measured during power_down, the l_clk clock monitor reads
**61439514 Hz** — unchanged from operation: this SLEEP sequence leaves
the AD9361's DATA_CLK running, so the PF_CCC keeps its reference and
never unlocks. The CCC lock is visible to software as
`l_clk_pll_locked` in `get_adc_status` (fabric: `adc_status` = lock &&
frame-ok), and `power_up` re-verifies the l_clk rate before resuming
the datapath.

```
                        UART console: "power_down" / "power_up"
                                        |
                                        v
+--------------- NEORV32 firmware -- 125 MHz domain, NEVER gated ---------------+
|                                                                               |
|   chip control (SPI)         datapath control (GPIO/AXI)    observability     |
|   -----------------          -------------------------     (AXI reads)       |
|   ENSM ALERT/SLEEP/FDD       bridge_reset / bridge_enable   ------------      |
|   RX/TX LO power up/down     up_enable, up_txnrx GPIOs      up_clock_mon      |
|   RFDC re-cal on wake        gpio_o[8] "pwr_dn" Tier-1      -> l_clk_hz       |
|   boot TX-quad restore        reset gate: wired but         adc_status[0] =   |
|   BIST-residual toggle        DORMANT (never asserted)      CCC lock &&       |
|                                                             frame ok          |
+--------+--------------------------+----------------------------+--------------+
         | SPI (alive in SLEEP)     | GPIO / AXI                 | AXI-Lite
         v                          v                            |
+------- AD9361 -------+   +------------------ fabric ------------------------+
|                      |   |                                                  |
| in SLEEP + LO pd:    |   |  DATA_CLK --> CLKINT_PRESERVE --> PF_CCC_C1      |
|  RF synths     OFF   |   |  61.44 MHz              stays LOCKED through     |
|  mixers        OFF   |   |     ^                   sleep (measured:         |
|  ADC/DAC/BB    OFF   |   |     |                   61439514 Hz, no drop)    |
|  SPI port      ON    |   |     |                   OUT0 l_clk / OUT1 +90    |
|  BBPLL         ON  --+---+-----+                        |                   |
|  DATA_CLK      ON    |   |                              v                   |
|                      |   |  l_clk domain: dev_if, HLS adapter, CDC-FIFO     |
+----------------------+   |  halves -- still CLOCKED, but PARKED (enables    |
                           |  low, bridge in IDLE) before the chip descends   |
                           |                                                  |
                           |  125 MHz domain: CPU, AXI, up regs -- fully ON,  |
                           |  which is why status is readable while asleep    |
                           +--------------------------------------------------+
```

#### Xilinx vs Microchip distinction for clocking the I/O

Both ports run the same Tier-0 sleep policy — put the chip down, never
touch the fabric — with the same firmware sequence on the same chip.
The architectural difference is what sits between DATA_CLK and l_clk:

```
axau15 (Xilinx):
  DATA_CLK --> IBUFGDS --> BUFG --> l_clk
              (a stateless pipe: no lock, no memory, no phase state)

mpf300 (PolarFire):
  DATA_CLK --> INBUF_DIFF --> CLKINT_PRESERVE --> PF_CCC PLL --> OUT0 = l_clk
              (a stateful machine: VCO, lock,               \--> OUT1 = l_clk +90
               and a phase relationship to maintain)
```

On the axau15, l_clk is DATA_CLK after two buffers: if the source
stops, l_clk stops the same nanosecond, and when it returns it is
instantly valid — no lock concept, nothing to re-acquire, nothing to
observe (the Xilinx interface hardwires `locked` to 1).

Here l_clk is the output of a PLL whose reference is DATA_CLK itself
(the +90 deg OUT1 for FB_CLK can only come from a PLL). That machine
can lose lock, keeps running if the reference dies (free-run at a drift
frequency) rather than stopping, and must re-acquire on reference
return — including the OUT0/OUT1 90 deg relationship, which Post-VCO
feedback re-establishes after any lock event. This is why `power_up`
gates on the l_clk rate monitor and why the CCC lock is exported to
`adc_status`. In Tier-0 sleep the measured behavior above (DATA_CLK
persists, the CCC rides through locked) makes the gate pass
immediately; the relock machinery becomes load-bearing only if a
deeper, clocks-off chip sleep is ever used.

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

## Libero Awkwardness

A catalog of issues encountered on this project that are not design bugs
but Microchip tooling behaving in unexpected and inconvenient ways —
kept here so the next person greps this file before losing an afternoon.
Each entry: (a) the issue, (b) how it manifests, \(c) how it was
rectified here, (d) whether the equivalent exists in the Vivado/Vitis
flow this project was ported from (`projects/fmcomms2/axau15`).

### 1. The `SYNPLIFY_OPTIONS` parser silently discards its entire payload

**a. Issue.** `configure_tool -name {SYNTHESIZE} -params
"SYNPLIFY_OPTIONS:…"` does not splice text into the generated Synplify
project verbatim. Libero parses each `set_option` statement into its own
parameter store and *re-serializes* it when writing
`proj/synthesis/Top_syn.prj` (observable: it adds brace-wrapping we
never wrote). Any statement its parser cannot digest — e.g. a
brace-quoted multi-token `-hdl_define -set {A="x" B}` value, which is
*valid Synplify Tcl* — causes it to discard the **whole** options
string, every statement, with **zero diagnostics**; `configure_tool`
returns success.

**b. Manifestation.** The generated `Top_syn.prj` quietly reverts to
Libero defaults: `-retiming 0`, `-rom_map_logic 1`,
`-automatic_compile_point 1`. In this design that alone would rebuild
the 128 KB NEORV32 IMEM as a ~57k-LUT mux tree (see the Status/timing
section) — a catastrophic outcome from a cosmetic-looking option edit,
discovered only because an unrelated error prompted a diff of the
generated prj.

**c. Rectification.** Keep `SYNPLIFY_OPTIONS` statements to simple
single-token values (the one escaped-quote `MEM_INIT_DIR` form is the
proven ceiling). Anything needing quoting or multiple values goes into
source instead — the Bedrock `` `define BR_PPA_SYNTHESIS `` rides at
the top of the amalgamated `bedrock_sources.sv`. After *any* change to
the options string, grep `proj/synthesis/Top_syn.prj` (or Synplify's
`run_options.txt`) to confirm every option actually arrived.

**d. Vivado comparison.** Would not have happened. Vivado synthesis
options are Tcl properties (`set_property
STEPS.SYNTH_DESIGN.ARGS.* …`, `verilog_define` as a real Tcl list on
the fileset) validated at `set_property` time — an invalid value errors
immediately, and there is no free-text re-parse step to fail silently.

### 2. The synthesis fileset is derived from the instantiation hierarchy — bare SV package files are silently dropped

**a. Issue.** Libero does not hand Synplify your import list. On
`build_design_hierarchy` it parses every imported HDL file, builds a
**module instantiation graph** from the design root, and generates the
Synplify fileset from that graph — both membership and file order
(leaf-to-root dependency order; import order is irrelevant). A file
containing only a SystemVerilog `package` defines no module, and SV
`import`/`::` references are not tracked as graph edges — so the file
is read during the audit (it shows the same `Reading file` lines as
every module file), produces **no warning**, and never reaches
Synplify.

**b. Manifestation.** Synplify fails far from the cause:
`CG707 "Could not find function"` at the first
`some_pkg::function()` call inside a dependent module — here
`br_math::max2()` in Bedrock-RTL's `br_cdc_fifo_push_flag_mgr.sv`,
three files removed from the dropped `br_math_pkg.sv`. This project hit
the identical trap earlier with PULP's `cf_math_pkg.sv`/`axi_pkg.sv`.

**c. Rectification.** Amalgamation: concatenate each package-bearing
library into one generated file, packages first, in dependency order
(`pulp_sources.sv`, `bedrock_sources.sv` in `build_all.tcl`). This
fixes membership (the merged file defines plenty of instantiated
modules), order (packages are physically first), and gives compile-unit
defines a guaranteed home. `organize_tool_files -tool {SYNTHESIZE}`
exists as the official override but is all-or-nothing and leaves
ordering unspecified.

**d. Vivado comparison.** Would not have happened. Vivado keeps an
explicit user-owned fileset (`add_files`); package-only `.sv` files
stay in it, and `update_compile_order` understands package dependencies
when ordering compilation. The PULP and Bedrock trees compile in Vivado
unmodified.

### 3. Batch-mode segfault in SPI-flash image generation (GUI dialog through a NULL window pointer)

**a. Issue.** Libero 2025.2's SPI-flash image flow raises a **GUI
dialog** ("There are no SPI Flash clients selected for programming")
when the SPI Flash client list is empty. In batch mode there is no main
window, so the dialog call dereferences a NULL window pointer and the
whole process dies with a segmentation fault — for a condition that is
merely a configuration state, in a flow that is explicitly supported
headless.

**b. Manifestation.** `run_libero.sh SCRIPT:… ` dies with
`Segmentation fault` during design-initialization / flash-image
generation, no Tcl-level error, no actionable message. Trivially
reproducible whenever `cfg/spiflash.cfg` defines no clients yet.

**c. Rectification.** `cfg/spiflash.cfg` ships a **256-byte
`STATIC_FILL` placeholder client at 0x100000** — it writes the flash's
erased state, so it is electrically inert, but it keeps the client list
non-empty and the dialog code path unreached. Documented in
`program_board.tcl`.

**d. Vivado comparison.** No equivalent failure class. The Vivado
counterpart (`write_cfgmem`) is a pure CLI command: an empty/invalid
configuration produces a textual error and a nonzero exit. Vivado batch
mode does not route error reporting through GUI dialog code.

### 4. SmartHLS falls apart on HLS compile times (and crashes) for bus-slave interfaces

**a. Issue.** SmartHLS 2025.2 has no equivalent of Vitis HLS's
template-generated `s_axilite` decoder; both of its AXI slave options
route through the scheduler with pathological results:
`type(axi_target)` arbitrates every HLS-side access through a shared
2-cycle memory port (II=2 floor) and its load→FIFO-write path crashes
the scheduler outright (`findRecurrencePathFailure`); `type(axi_slave)`
generates the address decoder as C++ that **enumerates all 2054 words
of the register map**, and scheduling it takes hours — ~2 h for the
write decoder, the read decoder still unfinished after **9+ hours** —
for a bridge whose Vitis equivalent builds in seconds.

**b. Manifestation.** `shls -a hw` appears hung; the scheduler is
grinding a combinatorially enumerated decoder. Nothing in the report
points at the interface choice as the cause.

**c. Rectification.** Hand-write the AXI slave in user C++ over the raw
AXI channel structs (`hls/axi_interface.hpp`) with computed address
decoding (three range compares + a RAM index) — SmartHLS then groups
the channels into a proper AXI4 slave bus in RTL. Result: II=1 at the
target clock and `shls -a hw` in **under 10 seconds**, with the
register map byte-identical to the Vitis IP. Three scheduler-shape
rules (blocking writes for read-dependent payloads, one if/else access
chain per RAM, one write call site per FIFO) are documented in
`src/axi_lite_to_streaming_adapter_microchip/README.md`.

**d. Vivado/Vitis comparison.** Did not happen there. Vitis HLS emits
`s_axilite` as a template RTL decoder — constant generation time
regardless of map size — and the identical design (same C++, same
register map) built in seconds in the axau15 flow.

### 5. Intermittent batch-mode segfault on project open

**a. Issue.** Libero 2025.2 batch mode occasionally segfaults while
*re-opening* an existing project, during the open-time HDL file audit —
before the script's first action runs.

**b. Manifestation.** A `program_board.tcl` (or any re-open) run dies
with `Segmentation fault` immediately after the `Reading file '…'`
lines. Intermittent; the same invocation succeeds on retry.

**c. Rectification.** None available — just rerun the script.
Documented in `program_board.tcl` so the retry is a known move, not a
debugging session.

**d. Vivado comparison.** Not observed in the axau15 flow; headless
`open_project` there has been reliable across the same repository
lifetime.

### 6. `PROGRAMDEVICE` refuses with "Bitstream programming action is disabled" (ERROR_CODE 804f)

**a. Issue.** After repeated program/power cycles the PolarFire System
Controller can latch a state in which programming is refused instantly
— scan chain still passes — with EXPORT `ERROR_CODE 804f`, EXIT -38.

**b. Manifestation.** `Executing action PROGRAM` fails in under a
second; a plain retry fails identically. Nothing is written, so the
on-device design is untouched.

**c. Rectification.** Power-cycle the board (DEVRST clears the stuck
state), then rerun. Documented in `program_board.tcl`.

**d. Vivado comparison.** Xilinx configuration has its own transient
programming failures, but a device-side latched refusal requiring a
power cycle has no direct analogue in the axau15 flow — JTAG
configuration there recovers with a cable reset from the host.

### 7. Automatic compile points silently ignore ROM-mapping attributes

**a. Issue.** Libero's default Synplify multiprocessing flow
(`-automatic_compile_point 1`) carves the design into compile points
and re-maps the enclosing top inside a compile-point context in which
ROM→LSRAM extraction (and the `syn_romstyle` attribute) is ignored.

**b. Manifestation.** The 128 KB NEORV32 IMEM rebuilds as a ~57k-LUT
mux tree, retimes for 30+ minutes — and that netlist then *loses* to
the real top-level mapping anyway. Wwasted runtime with a
misleading resource blowup mid-log.

**c. Rectification.** `set_option -automatic_compile_point 0` (with
`-rom_map_logic 0`); a single mapper job maps the whole design, IMEM in
RAM1K20s, in well under a minute. See the comment block in
`build_all.tcl`.

**d. Vivado comparison.** Would not have happened. Vivado's default
flow has no automatic partitioning (OOC is explicit per-IP), and
`rom_style`/`ram_style` attributes are honored in every context.

### 8. Passing flows print `Error:`-severity lines (sNVM design-init first pass)

**a. Issue.** During design-initialization generation the first pass
places init clients in sNVM, prints two hard `Error: The SNVM
configuration has the following errors:` blocks (client overlap, end
page 1044 out of a 0–220 range) — and then the flow *retargets the RAM
clients to SPI flash, regenerates, and completes successfully*. The
errors describe a transient intermediate state, at Error severity.

**b. Manifestation.** Any log-scraping automation keyed on `Error`
flags a passing build; a human reading the log gets two heart attacks
per build. (This build's `EXPORT_OK` gate greps for the script's own
milestone markers instead, precisely because of this.)

**c. Rectification.** Treat Libero log severity as advisory; gate
automation on explicit milestone markers echoed by the build script
(`MPF300_FMCOMMS2_SYNTH_OK` / `_PNR_OK` / `_EXPORT_OK`).

**d. Vivado comparison.** Vivado's message system severities are
dependable (a passing flow does not emit `ERROR:`), and grep-based CI
on them is standard practice.

### 9. Synplify optimizes away plain `CLKINT` buffers, reinstating dedicated-routing DRCs

**a. Issue.** A clock that must reach a CCC through the fabric global
network (because its pin is not a CCC-function pin — the FMC pinout
dictates this for DATA_CLK) needs an explicit fabric buffer. Synplify
optimizes a plain `CLKINT` away, after which P&R re-applies the
dedicated-routing rule and errors.

**b. Manifestation.** P&R fails with `PDCPF-13` even though the RTL
explicitly instantiates the buffer the error asks for.

**c. Rectification.** Use `CLKINT_PRESERVE` (see
`library/axi_ad9361/polarfire/common/ad_data_clk.v` and the project
refclk — same idiom in both places).

**d. Vivado comparison.** Ehh... Vivado keeps explicitly instantiated
`BUFG`s, and the equivalent pin-placement DRC offers a documented
per-net override (`CLOCK_DEDICATED_ROUTE FALSE`) rather than requiring
a special preserved primitive variant.

### 10. Generated-core simulation models live in disposable project output (and are Questa-locked)

**a. Issue.** Simulation models for Libero-generated cores (PF_CCC,
PF_INIT_MONITOR, …) are emitted into the regenerated-every-build
`proj/` tree rather than a stable library, and the sophisticated hard
IP underneath (transceiver PCS/PMA, and effectively the CCC's guts) is
available only as encrypted/precompiled ModelSim/Questa libraries — no
open-tool path. (Related: `new_project` rejects wrong die names with an
error message whose list of accepted names includes neither `MPF300T`
nor `MPF300TS_ES`, both of which are accepted.)

**b. Manifestation.** Self-contained simulations break every time
`proj/` is regenerated, and Verilator cannot consume the vendor models
at all.

**c. Rectification.** Behavioral stand-ins maintained with the
testbenches: `pf_ccc_sim.v` (+ `PF_CCC_C1`, `pf_init_monitor_sim`) for
Questa, `pf_ccc_behavioral.sv` for Verilator. See
`doc/MPF300-Splash-Kit/bedrock_migration_design.md` and the Verilator
sim READMEs.

**d. Vivado comparison.** This is similar in Vivado. Vivado emits unencrypted
behavioral sim netlists for clocking IP into the managed IP output
(stable location), so the Xilinx datapath sims consume them directly;
for serdes hard IP, Xilinx SecureIP is encrypted just like Microchip's
XCVR models — that particular lock-in is industry-wide.
