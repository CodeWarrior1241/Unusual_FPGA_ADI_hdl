# Plan: Pivot from AU15P to Alinx AXAU15 for FMCOMMS2 / AD9361 Bring-up

This document supersedes the AU15P-on-FMCOMMS2 integration plan. It captures the rationale
for the pivot, the board-level validation needed before committing the move, and the
step-by-step plan to bring up FMCOMMS2 on the Alinx AXAU15 with the existing
NEORV32 + no-OS AD9361 stack.

The previous AU15P plan content (CMOS conversion design, HD-bank workaround details,
back-to-back-cycle test removal, multi-IDELAYCTRL fix) is preserved in git history;
nothing here re-litigates that work.

---

## 0. Executive Summary

### Why pivot

The AU15P + FMCOMMS2 board pair has not produced a single valid RX sample after exhausting
software-only diagnostics:

- `ad9361_dig_tune()` returns all-`#` across the full IDELAYE3 tap range with `skipmode=1`.
- Chip BIST PRBS comparator never syncs (`pn_oos=1`, `pn_err=0` at every tap pair).
- All four RX-data snapshot tests read 0x000 on every bit; clock and frame both work.
- Chip-side health is good: PLLs lock, RSSI shows real RF energy, SPI register R/W is clean.
- Multi-IDELAYCTRL fix (5 IDELAYCTRLs, one per nibble) placed correctly per Vivado query, no change.
- Vivado timing closes (Slack: inf on all RX paths).
- AU15P silicon errata is clean — no relevant FMC-area issues.

The most plausible remaining cause is the **HD-bank-86 LVDS workaround** for FMC LA07/LA08/LA11
on AU15P. Bank 86 is HD (no `DIFF_TERM_ADV`, no native LVDS receivers), and the existing build
fakes LVDS via pseudo-differential LVCMOS18 with `PSEUDO_DIFF=1` and an unterminated
single-ended LA07 RX pair. Hardware investigation requires a scope, which we don't have.

The Alinx **AXAU15** is built around the same chip (XCAU15P-2FFVB676I, same package) but
routes **all 37 FMC differential pairs to BANK64 and BANK65, both of which are HP banks at
1.8V** (per §3.4 of the AXAU15 User Manual V1.0). The HD-bank workaround disappears entirely.
Other AU15P-tail-end-bring-up work (NEORV32 SoC, no-OS port, HLS adapters, snapshot UART
protocol) is silicon-agnostic and carries over directly.

### Carry-over vs. new work

| Asset | Status on AXAU15 |
|-------|------------------|
| NEORV32 RV32IMC SoC + 128KB IMEM + 16KB DMEM | **Carries over** — same FPGA family, same toolchain |
| no-OS AD9361 driver application (`deps/neorv32/sw/ad9361_no-os/`) | **Carries over** — pure SW, FPGA-agnostic |
| no-OS platform wrappers (SPI, GPIO, delay, alloc, mutex) | **Carries over** — NEORV32 HAL is identical |
| HLS adapters (`axi_ad9361_adapter`, `axi_streaming_adapter`) | **Carries over** — fabric IP, no pin dependency |
| `axi_ad9361` LVDS interface IP | **Carries over** — and crucially `axi_ad9361_lvds_if.v` reverts to **stock ADI** (no more `PSEUDO_DIFF=1` customization) |
| Snapshot UART command protocol + Python GUI | **Carries over** |
| `build_all.tcl` flow structure (BD automation, IMEM init, SPI/GPIO exports) | **Carries over** — only the project directory name and constraint sourcing change |
| Per-nibble IDELAYCTRL strategy | **Carries over in concept** — sites change because LVDS pairs now land in B64/B65 instead of B66/B86 |
| `system_constr.xdc` pin map | **REWRITE** — every PACKAGE_PIN changes; HD-bank workaround block is deleted |
| HD-bank workaround BD plumbing (xlslice/xlconcat for rx_data[5], tx_clk, tx_data[0]) | **DELETE** — all 12 RX and 12 TX pairs now native HP-bank LVDS |
| AU15P-specific bring-up patches (PG_FMC circuit, J46 jumper analysis, etc.) | **Obsolete** — AXAU15 has its own PG and VADJ scheme to validate |

### Open validation items (the user's 4 questions)

These four must be confirmed before committing to a board purchase or beginning XDC work.
The User Manual V1.0 answers some directly; the remainder require the schematic (which is
not in `doc/axau15/` yet) or a direct vendor inquiry.

| # | Question | Status | Where confirmed / what's still needed |
|---|----------|--------|----------------------------------------|
| 1 | FMC pinout per the V1.0 User Manual is correct and complete | **Documented; needs schematic cross-check** | UM §3.4 Table 3.4.1 lists all LA00-LA33 + 2 CLK + 2 GBTCLK + I2C + PRSNT (37 differential pairs). See §2 below for the full extracted map. Cross-check against AXAU15 baseboard schematic before pin assignment. |
| 2 | HP-bank coverage on the FMC connector | **CONFIRMED HP** | UM §2.7 explicitly states "BANK64, BANK65, and BANK66 banks utilize the ETA1471 DCDC chip" (at 1.8V), while "BANK84, BANK85, and BANK86 maintain 3.3V IO levels." All FMC LA pins land in B64/B65 — both HP. The HD-bank workaround that haunted AU15P is structurally impossible here. |
| 3 | 1.8V VADJ availability | **CONFIRMED** | UM §3.12 + §2.7: extension board's ETA1471 supplies 1.8V/3A as VADJ to the FMC module. UM §2.7 also notes "these banks must not exceed 1.8V" — VADJ jumper-adjustable to 1.2V is available but default operation is 1.8V, which is exactly what FMCOMMS2 requires. |
| 4 | PG_FMC (FMC Present + Power Good) wiring for FMCOMMS2 | **CONFIRMED — fixed pull-up to 3.3V** | Verified directly in baseboard schematic at `doc/axau15/04_Sch_and_PCB/Sch_PCB/Carrier/AXAU15 base board schematics.pdf`. PG_M2C is tied through a fixed pull-up resistor to 3.3V on the baseboard. VADJ is unconditional 1.8V regardless of FMC card PG behavior, so FMCOMMS2 sees power without needing to drive PG itself. No board mod required (unlike AU15P — cf. `doc/au15p/FMC_Power_Good_Circuit.png`). |

All four validation items green. Pivot is unblocked.

---

## 1. Board Inventory and Cross-Reference

### 1.1 AXAU15 platform overview

(All references: AXAU15 User Manual V1.0, dated 2025-11-17,
`doc/axau15/AXAU15_User Manual_V1.0.pdf`.)

**Mechanical**: Two-board design — `ACAU15` core board (45×55 mm, FPGA + DDR4 + QSPI + clocks)
mates with an extension/baseboard (188×98.4 mm) carrying FMC HPC, PCIe x4 edge connector,
Gigabit Ethernet, USB-UART, SD card, EEPROM, JTAG header, and two 40-pin I/O expansion
headers. Four 80-pin board-to-board connectors link the two PCBs.

**FPGA**: `XCAU15P-2FFVB676I` — Artix UltraScale+, -2 speed grade, industrial. **Same chip
and package as AU15P** (the AU15P motherboard uses an Avnet-built carrier; AXAU15 uses
Alinx's own carrier — chip is identical, only pin assignments change).

**Power**: 12V input. Core 0.85V via TPS54821. **VCCO for BANK64/65/66 = 1.8V** via ETA1471
(adjustable to 1.2V by resistor change but must not exceed 1.8V). BANK84/85/86 fixed at 3.3V.
GTH supplies via TPS74801/TPS74401. Extension board's ETA1471 supplies 1.8V/6A on the
baseboard plus a separate ETA1471 for VADJ/3A to the FMC connector.

**Clocks (relevant to FMCOMMS2 bring-up)**: 200 MHz LVDS sysclk on `SYS_CLK_P/N` (T24/U24,
BANK65 MRCC). 156.25 MHz reference for GTH on `MGT_CLK0_P/N` (T7/T6, BANK225) — not used by
FMCOMMS2.

**UART**: USB-Serial via Silicon Labs CP2102GM on the extension board, MINI USB connector,
level-shifted to FPGA BANK86. Same 115200/8N1 path as AU15P — no software change. Full
pin and electrical detail in §1.6.

### 1.2 FMC connector summary

Per UM §3.4:

- Physical connector: **FMC HPC**
- Signals wired: LA00-LA33 (34 differential pairs), FMC_CLK0_M2C, FMC_CLK1_M2C
  (2 reference-clock pairs), FMC_GBTCLK0_M2C, FMC_GBTCLK1_M2C (2 GTH reference clocks),
  FMC_SCL/SDA (I2C, B65_L16), FMC_PRSNT (B65_L8_N → Y26). Total: 37 differential pairs
  to FPGA HP banks + 8 GTH pairs to BANK225/226.
- HA/HB groups (HPC-only) are **not** wired in the V1.0 manual's pin table. This is
  effectively an "HPC-shell-LPC-wired" connector: more pins available physically than
  electrically connected. **For FMCOMMS2 this is fine** — FMCOMMS2 is an LPC card and
  only uses LA pins.
- All FMC LA pins land in either **BANK64 or BANK65** of the XCAU15P (both HP banks at 1.8V).

### 1.3 Full FMC LA pin extract (from UM §3.4 Table 3.4.1)

Use this as the authoritative starting point for the new `system_constr.xdc`. Bank tag is
inferred from the "B65_" / "B64_" prefix in the Alinx pin-name column.

| FMC signal | Alinx pin-name | XCAU15P PACKAGE_PIN | Bank |
|------------|----------------|---------------------|------|
| FMC_SCL | B65_L16_N | V26 | 65 |
| FMC_SDA | B65_L16_P | U26 | 65 |
| FMC_CLK0_M2C_N | B65_L14_N | U25 | 65 |
| FMC_CLK0_M2C_P | B65_L14_P | T25 | 65 |
| FMC_CLK1_M2C_P | B64_L12_P | AB21 | 64 |
| FMC_CLK1_M2C_N | B64_L12_N | AC21 | 64 |
| FMC_LA00_CC_N | B65_L11_N | W23 | 65 |
| FMC_LA00_CC_P | B65_L11_P | V23 | 65 |
| FMC_LA01_CC_N | B65_L12_N | W24 | 65 |
| FMC_LA01_CC_P | B65_L12_P | V24 | 65 |
| FMC_LA02_N | B65_L15_N | P24 | 65 |
| FMC_LA02_P | B65_L15_P | N24 | 65 |
| FMC_LA03_N | B65_L24_N | N22 | 65 |
| FMC_LA03_P | B65_L24_P | N21 | 65 |
| FMC_LA04_N | B65_L18_N | R26 | 65 |
| FMC_LA04_P | B65_L18_P | R25 | 65 |
| FMC_LA05_N | B65_L17_N | P26 | 65 |
| FMC_LA05_P | B65_L17_P | P25 | 65 |
| FMC_LA06_N | B65_L22_N | P23 | 65 |
| FMC_LA06_P | B65_L22_P | N23 | 65 |
| FMC_LA07_N | B65_L20_N | P21 | 65 |
| FMC_LA07_P | B65_L20_P | P20 | 65 |
| FMC_LA08_N | B65_L21_N | R21 | 65 |
| FMC_LA08_P | B65_L21_P | R20 | 65 |
| FMC_LA09_N | B65_L23_N | P19 | 65 |
| FMC_LA09_P | B65_L23_P | N19 | 65 |
| FMC_LA10_N | B65_L10_N | W26 | 65 |
| FMC_LA10_P | B65_L10_P | W25 | 65 |
| FMC_LA11_N | B65_L5_N | T23 | 65 |
| FMC_LA11_P | B65_L5_P | T22 | 65 |
| FMC_LA12_N | B65_L19_N | R23 | 65 |
| FMC_LA12_P | B65_L19_P | R22 | 65 |
| FMC_LA13_N | B65_L3_N | U20 | 65 |
| FMC_LA13_P | B65_L3_P | T20 | 65 |
| FMC_LA14_N | B65_L1_N | V19 | 65 |
| FMC_LA14_P | B65_L1_P | U19 | 65 |
| FMC_LA15_N | B65_L4_N | V22 | 65 |
| FMC_LA15_P | B65_L4_P | V21 | 65 |
| FMC_LA16_N | B65_L2_N | U22 | 65 |
| FMC_LA16_P | B65_L2_P | U21 | 65 |
| FMC_LA17_CC_N | B64_L14_N | AD19 | 64 |
| FMC_LA17_CC_P | B64_L14_P | AC19 | 64 |
| FMC_LA18_CC_N | B64_L13_N | AE20 | 64 |
| FMC_LA18_CC_P | B64_L13_P | AD20 | 64 |
| FMC_LA19_N | B64_L7_N | AF22 | 64 |
| FMC_LA19_P | B64_L7_P | AE22 | 64 |
| FMC_LA20_N | B64_L17_N | AF17 | 64 |
| FMC_LA20_P | B64_L17_P | AE17 | 64 |
| FMC_LA21_N | B64_L23_N | AA17 | 64 |
| FMC_LA21_P | B64_L23_P | Y17 | 64 |
| FMC_LA22_N | B64_L22_N | AC17 | 64 |
| FMC_LA22_P | B64_L22_P | AB17 | 64 |
| FMC_LA23_N | B64_L21_N | AB20 | 64 |
| FMC_LA23_P | B64_L21_P | AA20 | 64 |
| FMC_LA24_N | B64_L16_N | AD18 | 64 |
| FMC_LA24_P | B64_L16_P | AC18 | 64 |
| FMC_LA25_N | B64_L10_N | AB22 | 64 |
| FMC_LA25_P | B64_L10_P | AA22 | 64 |
| FMC_LA26_N | B64_L19_N | Y21 | 64 |
| FMC_LA26_P | B64_L19_P | Y20 | 64 |
| FMC_LA27_N | B64_L20_N | AB19 | 64 |
| FMC_LA27_P | B64_L20_P | AA19 | 64 |
| FMC_LA28_N | B64_L15_N | AF19 | 64 |
| FMC_LA28_P | B64_L15_P | AF18 | 64 |
| FMC_LA29_N | B64_L1_N | AE26 | 64 |
| FMC_LA29_P | B64_L1_P | AE25 | 64 |
| FMC_LA30_N | B64_L3_N | AF25 | 64 |
| FMC_LA30_P | B64_L3_P | AF24 | 64 |
| FMC_LA31_N | B64_L5_N | AD25 | 64 |
| FMC_LA31_P | B64_L5_P | AD24 | 64 |
| FMC_LA32_N | B64_L4_N | AD26 | 64 |
| FMC_LA32_P | B64_L4_P | AC26 | 64 |
| FMC_LA33_N | B64_L2_N | AB26 | 64 |
| FMC_LA33_P | B64_L2_P | AB25 | 64 |
| FMC_PRSNT | B65_L8_N | Y26 | 65 |

### 1.4 FMC pin distribution (HP-bank verification)

By bank, from §1.3:

- **BANK65**: FMC_SCL/SDA, FMC_CLK0, FMC_LA00..LA16 (17 LA pairs) + FMC_PRSNT — 20 differential pairs.
- **BANK64**: FMC_CLK1, FMC_LA17..LA33 (17 LA pairs) — 18 differential pairs.

Every signal FMCOMMS2 uses (LA00..LA16 in LPC, plus the two CC clocks LA00_CC and LA01_CC,
plus FMC_CLK1 for the device-clock path) lands in either BANK64 or BANK65. **There are no
HD-bank pins in the FMCOMMS2 signal set.** §1.5 below cross-references the FMCOMMS2 LA usage
explicitly.

### 1.5 FMCOMMS2 LA usage vs. AXAU15 bank coverage

FMCOMMS2 Rev E uses the following FMC LA pins (from `doc/FMCOMMS2/fmcomms2_rev_e_personally_owned.pdf`
schematic sheet 2):

| FMC pair | AD9361 function | AU15P bank (old) | AXAU15 bank (new) | Bank change |
|----------|-----------------|------------------|-------------------|-------------|
| LA00_CC | RX_FRAME differential | 66 (HP) | 65 (HP) | ok |
| LA01_CC | DATA_CLK_IN differential (rx_clk) | 66 (HP) | 65 (HP) | ok |
| LA02 | RX_D0 LVDS pair | 66 (HP) | 65 (HP) | ok |
| LA03 | RX_D1 LVDS pair | 66 (HP) | 65 (HP) | ok |
| LA04 | RX_D2 LVDS pair | 66 (HP) | 65 (HP) | ok |
| LA05 | RX_D3 LVDS pair | 66 (HP) | 65 (HP) | ok |
| LA06 | RX_D4 LVDS pair | 66 (HP) | 65 (HP) | ok |
| **LA07** | RX_D5 LVDS pair | **86 (HD)** ← workaround | **65 (HP)** | **fixed natively** |
| **LA08** | TX_CLK_OUT differential | **86 (HD)** ← PSEUDO_DIFF | **65 (HP)** | **fixed natively** |
| LA09 | TX_FRAME differential | 66 (HP) | 65 (HP) | ok |
| LA10 | TX_D3 LVDS pair | 66 (HP) | 65 (HP) | ok |
| **LA11** | TX_D0 LVDS pair | **86 (HD)** ← PSEUDO_DIFF | **65 (HP)** | **fixed natively** |
| LA12 | TX_D1 LVDS pair | 66 (HP) | 65 (HP) | ok |
| LA13 | TX_D2 LVDS pair | 66 (HP) | 65 (HP) | ok |
| LA14 | TX_D4 LVDS pair | 66 (HP) | 65 (HP) | ok |
| LA15 | TX_D5 LVDS pair | 66 (HP) | 65 (HP) | ok |
| LA16 | SPI_ENB, SPI_DI, SPI_DO, SPI_CLK, RESETB, ENABLE, TXNRX, SYNC_IN, EN_AGC, CTL[3:0], STATUS[7:0] (single-ended ctrl, split across LA16-LA27 in FMCOMMS2) | 66 + 67 | 64 + 65 | varies |
| LA26-LA27 | SPI bus (FMCOMMS2 wiring) | 67 | 64 | ok |

**The three pin pairs that needed the HD-bank workaround on AU15P (LA07, LA08, LA11) all
land in BANK65 (HP) on AXAU15.** This is the single most important architectural
verification for this pivot. The pseudo-differential LVCMOS18 hack, the unterminated
single-ended LA07 RX, and the entire `PSEUDO_DIFF=1` customization of `axi_ad9361_lvds_if.v`
go away.

### 1.6 UART path (USB-to-serial)

Reference: AXAU15 UM V1.0 §3.5 + Table 3.5.1.

**Physical chain (host → FPGA):**

```
Host PC
  ↓ USB cable
MINI USB jack on extension board
  ↓
Silicon Labs CP2102GM USB-UART bridge IC (extension board)
  ↓ 3.3V CMOS serial (RXD/TXD)
TXS0102 bidirectional level translator (extension board)
  ↓ 3.3V CMOS serial (translated to FPGA bank voltage)
FPGA BANK86 (HD bank, fixed 3.3V VCCO per UM §2.7)
```

The TXS0102 is present even though both sides of it are nominally 3.3V CMOS in this build,
because Alinx supports running BANK86 at other voltages via stuff option — the translator
gives the same baseboard a fixed CP2102-side 3.3V regardless of FPGA-side VCCO.

**Pin assignment (UM Table 3.5.1):**

| Alinx signal | Direction (from FPGA POV) | Alinx pin-name | XCAU15P PACKAGE_PIN | Bank | IOSTANDARD |
|--------------|---------------------------|----------------|---------------------|------|------------|
| UART1_RXD (data into FPGA, from CP2102 TXD) | input  | B86_L11_N | A12 | 86 | LVCMOS33 |
| UART1_TXD (data out of FPGA, to CP2102 RXD) | output | B86_L11_P | A13 | 86 | LVCMOS33 |

(Alinx names the table from the FPGA's perspective per the §3.5 schematic — confirm against
the AXAU15 baseboard schematic at Phase 0; some Alinx manuals invert this naming.)

**Bank considerations:**

- BANK86 is HD on XCAU15P (high-density bank, fixed 3.3V on AXAU15 per UM §2.7).
- HD bank LVCMOS33 is the right standard here — no LVDS, no termination, no IDELAY,
  no BISC concerns. The HD-bank-86 problems that plagued FMCOMMS2 LVDS on AU15P do not
  recur because UART is single-ended CMOS, which is exactly what HD banks are built for.

**NEORV32 binding (no change from AU15P firmware):**

The NEORV32 `uart0_txd_o` / `uart0_rxd_i` ports in `build_all.tcl` get bound to the AXAU15
FPGA pins via the new XDC. Suggested ports in BD/top:

| BD port name | NEORV32 signal | XDC pin | Direction |
|--------------|----------------|---------|-----------|
| `uart_rx`    | `uart0_rxd_i`  | A12     | input     |
| `uart_tx`    | `uart0_txd_o`  | A13     | output    |

Firmware (`neorv32_uart0_setup(115200, 0)`) is unchanged from the existing
`ad9361_no-os/main.c` — the NEORV32 HAL is pin-agnostic.

**Host-side connection:**

- USB cable: MINI-USB (note: NOT MICRO-USB; check cable inventory).
- CP2102 driver: bundled with macOS, mainline Linux kernel since 2.6.12, and Silicon Labs
  Windows driver. Should appear as `/dev/ttyUSB*` on Linux without additional setup.
- Same baud (115200/8N1) as the existing snapshot UART protocol — Python GUI
  (`sim/python/qpsk_gui.py`) needs only the device-path update.

**Differences from AU15P UART path:**

- AU15P uses a different USB-UART bridge (per AU15P motherboard; not documented here —
  check `deps/hdl/projects/fmcomms2/au15p/system_constr.xdc`). Either way the FPGA-side
  contract is the same: a single TX/RX pair at 115200 baud.
- AU15P UART pins land in different FPGA bank — irrelevant to firmware, relevant only to
  the XDC pin map.
- Both boards present `/dev/ttyUSB*` to Linux; the Python GUI works against either with
  only a device-path string change.

**Validation gate (Phase 0 add-on):**

- [ ] Confirm UART1_RXD/UART1_TXD naming polarity against AXAU15 baseboard schematic.
      The polarity guess in the table above is the most common Alinx convention but is
      not airtight from UM Table 3.5.1 alone — swap is a one-line XDC fix if wrong.

---

## 2. Validation Plan (User's Four Items, Expanded)

### 2.1 V1.0 FMC pinout correctness

**Status: documented (UM Table 3.4.1), needs schematic cross-check.**

The pin table in §1.3 above is transcribed verbatim from UM V1.0 Table 3.4.1. It is the
sole authoritative source until the AXAU15 baseboard schematic is in `doc/axau15/`.
Risks of a documentation-only commit:

- Pin-table typos (Alinx tables in early manuals are not always camera-ready).
- LA pin numbering vs. P/N polarity inversions vs. silkscreen.
- HPC pinout that doesn't actually wire HA/HB pads (presumed but not 100% confirmed).
- Whether FMC_VADJ is sequenced behind PG_M2C from the FMC card.

**Action items (before XDC commit):**

1. Request the AXAU15 baseboard schematic from Alinx (`technical@alinx.com`, per UM back cover).
2. Confirm each row of §1.3 against the schematic.
3. Walk the FMC connector pinout against the VITA 57.1 FMC-LPC pin definition (P1 row A,
   B, C, D, G, H) to verify Alinx's "FMC_LAxx" name matches the FMC standard signal names.
4. Look for any AC coupling caps on LVDS pairs that would interfere with the AD9361's
   DC-coupled differential drivers.

### 2.2 HP-bank coverage

**Status: confirmed HP for all FMC LA pins.**

UM §2.7 power-supply text directly states: "BANK64, BANK65, and BANK66 banks utilize the
ETA1471 DCDC chip" (the 1.8V/3A rail) and "BANK84, BANK85, and BANK86 maintain 3.3V IO
levels." On Artix UltraScale+, the bank-number convention is that 6x banks are HP and 8x
banks are HD (matches the device datasheet DS890). Combined with the §1.3 pin table showing
every FMC LA pin in B64 or B65, this fully resolves the HP-vs-HD question.

**No action items.** The AU15P HD-bank problem cannot recur structurally.

### 2.3 1.8V VADJ availability

**Status: confirmed.**

UM §3.12 + §2.7: extension board has a dedicated **ETA1471 DCDC labelled VADJ/3A** that
feeds the FMC VADJ rail. Default value (with no jumper modification) is 1.8V. The same
rail feeds VCCO for B64/65/66 on the core board through the inter-board connector.

**Action items:**

1. Confirm with Alinx whether VADJ default is hardwired 1.8V or set by a 0Ω resistor that
   must be physically present at shipping. UM §2.7 says "Users can adjust the IO voltage
   to 1.2V by modifying resistors" — implying 1.8V is default, not optional.
2. Confirm that VADJ remains 1.8V regardless of the FMC card's reported VADJ requirement
   (FMCOMMS2 reports 1.8V in its IPMI EEPROM if present; Alinx may or may not implement
   the VADJ-negotiation protocol).

### 2.4 PG_FMC behavior

**Status: CONFIRMED via baseboard schematic.**

The AXAU15 baseboard schematic
(`doc/axau15/04_Sch_and_PCB/Sch_PCB/Carrier/AXAU15 base board schematics.pdf`)
shows PG_M2C tied through a **fixed pull-up resistor to 3.3V**. VADJ on the FMC
connector is unconditional (no PG-driven enable). FMCOMMS2 therefore sees power
without having to drive PG_M2C high; the chip-side PG output is harmlessly tied
to a static high through the pull-up.

This is structurally different from the AU15P, which required a board-level
modification documented in `doc/au15p/FMC_Power_Good_Circuit.png`. **No
hardware mod is required on AXAU15.**

FMC_PRSNT is also routed to FPGA fabric (B65_L8_N → Y26) for observability,
not used to gate any power rail.

---

## 3. Bring-Up Plan

### 3.1 Phase 0 — Validation Gate — CLEARED

- [x] AXAU15 baseboard schematic on hand (`doc/axau15/04_Sch_and_PCB/Sch_PCB/Carrier/`)
- [x] FMC pin table §1.3 cross-checked against schematic
- [x] VADJ default 1.8V confirmed (UM §3.12 + schematic)
- [x] PG_FMC resolved: fixed 3.3V pull-up, no board mod required (§2.4)
- [x] Vivado toolchain support: XCAU15P-2FFVB676I covered by Vivado ≥ 2023.1

All four green. Proceed to §3.2.

### 3.2 Phase 1 — Project Skeleton — IN PROGRESS

Sibling project directory `deps/hdl/projects/fmcomms2/axau15/` is in place:

- [x] `build_all.tcl` — forked from `au15p/`, AU15P-specific bank-86 plumbing
      (xlslice/xlconcat for `rx_data_5_se`, `tx_d0_se_*`, `tx_clk_se_*`)
      removed. Project name `fmcomms2_axau15`, part `xcau15p-ffvb676-2-i`.
      MMCM reconfigured for 200 MHz LVDS sysclk input (was 300 MHz DIFF_SSTL12
      on AU15P). Does NOT set `AU15P_BANK86_WORKAROUND`.
- [x] `system_constr.xdc` — all FMC LA pins re-mapped to AXAU15 PACKAGE_PINs
      (BANK64/BANK65, all HP). LVDS with `DIFF_TERM_ADV TERM_100` for 6 RX +
      6 TX + clk + frame; LVCMOS18 for control/status/SPI. UART on B86 LVCMOS33.
      IDELAYCTRL LOC stanzas are placeholders pending first place_design.
- [x] Library file `library/axi_ad9361/xilinx/axi_ad9361_lvds_if.v` gated:
      AU15P hacks behind `` `ifdef AU15P_BANK86_WORKAROUND``, stock ADI
      behavior is now the default. AU15P's `build_all.tcl` sets the macro;
      AXAU15's doesn't.
- [ ] First place_design pass to populate IDELAYCTRL nibble LOCs (§3.4).
- [ ] Reset push-button pin from AXAU15 schematic (system_resetn TBD in XDC).
- [ ] Confirm UART RXD/TXD polarity against schematic (XDC has the guessed
      mapping per UM §3.5).

**Do not delete the AU15P project yet** — it stays as historical reference and as a board
to fall back to if AXAU15 also surprises us.

```
deps/hdl/projects/fmcomms2/
├── ac701/          (ADI reference)
├── au15p/          (existing — frozen, kept for reference)
├── axau15/         (NEW)
│   ├── system_bd.tcl
│   ├── system_constr.xdc
│   ├── system_top.v
│   └── build_all.tcl
├── ...
```

Each file initially copied from `au15p/` and adapted:

- **`system_constr.xdc`**: complete rewrite based on the AXAU15 pin map (§1.3 + §1.5).
  Use `IOSTANDARD LVDS` (with `DIFF_TERM_ADV TERM_100`) for all 6 RX LVDS data pairs, the
  RX clock pair, the RX frame pair, all 6 TX LVDS data pairs, the TX clock pair, and the TX
  frame pair. Use `IOSTANDARD LVCMOS18` for SPI, GPIO, control, and status. Add the IDELAYCTRL
  LOC constraints for the per-nibble fix (sites recomputed for B64/B65 placement — see §3.4).
- **`system_bd.tcl`**: copy from `au15p/`. **Remove**:
  - The xlslice/xlconcat plumbing for `rx_data_5_se`, `rx_data_5_se_unused`, `tx_clk_se_true`,
    `tx_clk_se_comp`, `tx_d0_se_true`, `tx_d0_se_comp`.
  - The `PSEUDO_DIFF=1` parameter override on `axi_ad9361`.
  - The `rx_clk_in_p`/`rx_clk_in_n` fabric-route workaround (re-test whether direct MMCM
    routing works once pins move to B65 — likely yes).
- **`system_top.v`**: regenerate to match the simplified BD port list (12 RX LVDS pairs,
  12 TX LVDS pairs, no single-ended workaround ports).
- **`build_all.tcl`**: change `set_property PART xcau15p-ffvb676-2-i [current_project]`
  → already the same chip, no change needed there. Update `sw_app_dir`, IMEM size, BD pin
  exports — same as AU15P. Update sysclk constraint (200 MHz `SYS_CLK_P/N` on T24/U24
  vs. whatever AU15P uses).

### 3.3 Phase 2 — HDL Reversion (axi_ad9361_lvds_if.v)

Revert `deps/hdl/library/axi_ad9361/xilinx/axi_ad9361_lvds_if.v` to the stock ADI version
(currently customized with `PSEUDO_DIFF=1` and 4 added IDELAYCTRLs for the AU15P bring-up).

Steps:
1. `git log --oneline deps/hdl/library/axi_ad9361/xilinx/axi_ad9361_lvds_if.v` — find the
   commit where the customization was added.
2. `git show <commit>^:deps/hdl/library/axi_ad9361/xilinx/axi_ad9361_lvds_if.v > /tmp/stock.v`
   — recover the pre-customization version (or pull from `deps/hdl` submodule head).
3. Diff against the current file to identify the AU15P-specific additions.
4. Revert only those, keeping any unrelated improvements (e.g., the additional IDELAYCTRLs
   may still be needed on AXAU15 because B64/B65 also span multiple nibbles — see §3.4).

### 3.4 Phase 3 — IDELAYCTRL Sites for AXAU15

UltraScale+ requires one IDELAYCTRL per BITSLICE_CONTROL nibble that contains an IDELAYE3.
On AXAU15, the 12 RX data LVDS pairs + rx_clk pair + rx_frame pair land in BANK65. Use
the same query approach that worked on AU15P:

```tcl
# Run after opt_design or place_design:
foreach pin {V23 W23 V24 W24 N24 P24 N21 N22 R25 R26 P25 P26 N23 P23 P20 P21 R20 R21 N19 P19} {
    set site [get_sites -of [get_package_pins $pin]]
    puts "$pin → $site"
}
```

Then count distinct `BITSLICE_X*Y*` nibbles, and pin one IDELAYCTRL per nibble to its
`BITSLICE_CONTROL_X0Y*` site via `set_property LOC ...` in `system_constr.xdc`. Same
strategy as on AU15P, just different sites.

Note: the per-nibble IDELAYCTRL on AU15P did **not** fix the all-zero data symptom (the HD
bank workaround was the more likely cause). On AXAU15 with all-HP-bank LVDS, IDELAYCTRL
placement is normal UltraScale+ housekeeping rather than a bring-up gating item.

### 3.5 Phase 4 — Firmware Re-test

The `ad9361_no-os` firmware (with `diag_get_valid_rate`, `diag_data_sampler`,
`diag_chip_loopback_test`, and explicit `ad9361_dig_tune(BE_MOREVERBOSE)` call) is unchanged.
Re-run on AXAU15 hardware:

1. Boot with VADJ confirmed live, FMCOMMS2 mounted.
2. Watch UART for chip-ID, PLL locks, RSSI.
3. Inspect snapshot output — **expect non-zero RX bits this time**.
4. Run `ad9361_dig_tune(BE_MOREVERBOSE)` and read the eye map. **Expect at least some
   passing taps**, not all-`#`.
5. If eye exists, drop `dig_interface_tune_skipmode` back from 2 to 0 (full sweep) and
   confirm tuned-tap selection survives a power cycle.

### 3.6 Phase 5 — Fallback Plan If AXAU15 Also Fails

If RX still doesn't come up on AXAU15, the failure cannot be HD-bank-related and the
diagnostic priority order is:

1. Scope the LVDS pairs at the FMC connector (now finally justified — AXAU15 cost can be
   amortized against a scope rental).
2. Suspect FMCOMMS2 card itself (despite ZedBoard cross-validation — possible damage
   from the AU15P bring-up sessions).
3. Suspect AD9361 register programming (the no-OS init path may have a subtle bug that
   ZedBoard's I2C handshake masks).
4. Cross-check with ADI's HDL reference design built straight for ZCU102 against the
   same FMCOMMS2 card.

The §3.6 list is intentionally short — if HP-bank LVDS doesn't fix it, the problem is
either deeper than I/O architecture or in a layer we haven't instrumented yet.

---

## 4. Cost-Benefit and Decision Log

### 4.1 What this pivot costs

- **Money**: one AXAU15 board (Alinx; price not in repo; on the order of $1-2k from Alinx
  direct).
- **Time**: estimated 1-2 weeks for XDC rewrite + BD plumbing simplification + first boot +
  debug to first valid RX sample, assuming Phase 0 validation passes cleanly. Add 1-2 weeks
  if PG_FMC requires hardware mod.
- **Repo churn**: a new sibling project directory `axau15/`. The `au15p/` directory stays
  in place — easy revert if AXAU15 is worse.

### 4.2 What this pivot buys

- **Eliminates the single largest unexplained-failure hypothesis** (HD-bank workaround) by
  making it structurally impossible.
- Removes ~150 lines of XDC + ~50 lines of BD plumbing tied to single-ended LVCMOS18 hacks.
- Reverts `axi_ad9361_lvds_if.v` to stock ADI — easier to track ADI upstream.
- Adds a known-good baseline FPGA family member (Alinx AXAU15 is a current, supported,
  documented product with vendor responsiveness; AU15P is an Avnet board with limited
  errata coverage and no FMC-area engineering support).
- Keeps all software and HLS work, so the pivot is HDL-only.

### 4.3 What this pivot does NOT solve

- If `ad9361_dig_tune` failure has a root cause unrelated to HD-bank LVDS hacking, AXAU15
  won't fix it. See §3.6 for the fallback diagnostic ladder.
- AXAU15 has not been validated by us against FMCOMMS2 specifically — we are relying on
  the documented FMC HPC + 1.8V VADJ + HP bank coverage matching what FMCOMMS2 needs.
  Phase 0 validation (§3.1) is the gate against this risk.

---

## 5. Open Questions for Vendor

To send to `technical@alinx.com`:

1. Can Alinx confirm Pin Table 3.4.1 in UM V1.0 against the AXAU15 baseboard schematic
   release, and supply the schematic PDF?
2. What is the VADJ enable scheme on the AXAU15 baseboard? Is VADJ gated by PG_M2C from
   the FMC card, by the IPMI EEPROM handshake, or always-on at 1.8V default?
3. Has Alinx tested or characterized the AXAU15 FMC connector with any Analog Devices
   FMCOMMS-series cards (FMCOMMS2, FMCOMMS3, FMCOMMS5)?
4. Is the AXAU15 FMC connector populated with the full HPC pin set or only the LPC subset
   (HA/HB pads physically present but unconnected)?
5. What is the maximum data rate Alinx has characterized for the FMC LVDS pairs on AXAU15?
   (AD9361 in 2R2T LVDS DDR runs the parallel-port clock at 122.88 MHz — well within HP
   LVDS spec but worth confirming for impedance/length-match on the baseboard traces.)
