# axi_ad9361 — Microchip PolarFire port

PolarFire (Libero SoC / Synplify) device interface for the ADI `axi_ad9361`
core, LVDS mode. Follows the same structure as ADI's `intel/` port: the
vendor-neutral core (`axi_ad9361.v`, rx/tx/tdd, `../common/*.v`) is used
unchanged; only the device interface layer is replaced.

## Files

| File | Replaces (Xilinx) | Notes |
|------|-------------------|-------|
| `axi_ad9361_lvds_if.v` | `xilinx/axi_ad9361_lvds_if.v` | Same framing/delineation/ENSM logic; PolarFire I/O |
| `common/ad_data_in.v` | `xilinx/common/ad_data_in.v` | `INBUF_DIFF` + fabric-emulated DDR capture |
| `common/ad_data_out.v` | `xilinx/common/ad_data_out.v` | Fabric-emulated DDR output + `OUTBUF_DIFF` |
| `common/ad_data_clk.v` | `xilinx/common/ad_data_clk.v` | `INBUF_DIFF` + `CLKINT` |
| `common/ad_mul.v` | `xilinx/common/ad_mul.v` | Behavioral, 3-stage pipeline, maps to MACC_PA |
| `common/ad_dcfilter.v` | `xilinx/common/ad_dcfilter.v` | Same algorithm, DSP48 written behaviorally |
| `axi_ad9361_constr_pf.sdc` | `axi_ad9361_constr.xdc` | Interface clocks + async clock groups |

## Design notes / limitations

- **DDR I/O is fabric-emulated.** PolarFire has no fabric-instantiable
  `DDR_IN`/`DDR_OUT` macro (those are SmartFusion2/IGLOO2/RTG4); real IOD
  DDR registers are only reachable through the `PF_IOD_GENERIC_RX/TX`
  generated cores. The emulation (posedge + negedge fabric registers,
  clock-muxed output) synthesizes with healthy margin at the full 245.76 MHz
  DATA_CLK constraint, but I/O timing is not pad-deterministic the way IOD
  registers are. For full-rate hardware bring-up, swap the capture/output
  paths in `common/ad_data_in.v` / `common/ad_data_out.v` for
  `PF_IOD_GENERIC_RX/TX` cores.
- **No dynamic delay calibration.** The Xilinx IDELAY interface (`up_*_dld`,
  `up_*_dwdata`) is accepted and ignored; readback is zero, `delay_locked`
  is tied high (the Intel port does the same). Interface timing relies on
  static SDC constraints; software delay sweeps (`dig_tune`) will be
  no-ops.
- **LVDS mode only** (`CMOS_OR_LVDS_N = 0`), matching the working
  fmcomms2/axau15 configuration. The CMOS generate branch is never
  elaborated and needs no PolarFire module.
- Both edge-sample pairings and the tx first-out bit ordering match the
  Xilinx port (`SAME_EDGE` semantics), so the AD9361-side framing is
  unchanged.

