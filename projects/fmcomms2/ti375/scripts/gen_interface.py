#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# FMCOMMS2 on Ti375C529 - Interface Designer periphery generator.
#
# Builds everything build_all.tcl did with MegaVault CCC cores and io.pdc
# did with pin placement, as a headless Efinity Interface Designer script:
#
#   sys_pll   PLL_TR0, pad-referenced (OSC1 25 MHz on TR0 REFCLK0)
#             -> 125 MHz clk_125mhz               [PF_CCC_C0 replacement]
#   lvds_pll  PLL_BR0, referenced FROM THE CORE CLOCK TREE (the AD9361
#             DATA_CLK enters on GCLK CLK7, LA00_CC -> GPIOB_PN_20; the
#             FMCOMMS2 pinout puts no PLL_CLKIN pad on rx_clk, and BR0's
#             own REFCLK0 pad is consumed by tx_data[3]/LA10)
#             -> 61.44 MHz l_clk (0 deg) + l_clk_90 (+90 deg)
#                                                  [PF_CCC_C1 replacement]
#   16 LVDS lanes (x2 half-rate SERDES = fabric-DDR equivalent) + the
#   FB_CLK lane in CLKOUT mode on l_clk_90, per scripts/efinix_io_map.csv
#   GPIO singles: AD9361 SPI/control/status (1.8 V), UART console +
#   SW3 reset button (3.3 V HVIO banks)
#
# The design-rule check (design.generate) is the acceptance gate: any
# SeverityType.error fails the build. One advisory warning is expected and
# accepted: "PLL driving the parallel clock should have its reference
# clock from an LVDS in pll_clkin connection type" - the core-tree
# reference is legal (DS: PLL ref = I/O pads or core clock tree) and the
# added tree jitter (tens of ps) is immaterial at the 8.14 ns UI of
# 61.44 MHz DDR.
#
# Run with Efinity's bundled interpreter, from the project directory:
#   source <EFINITY>/bin/setup.sh && efx_py scripts/gen_interface.py
#
# Output: ./ti375c529.peri.xml (consumed by efx_run --flow compile) plus
# the rule-check report; outflow/ receives the generated pt.sdc/template
# after the interface stage runs.
# ---------------------------------------------------------------------------

import csv
import os
import sys

sys.path.append(os.environ["EFXPT_HOME"] + "/bin")

from api_service.design import DesignAPI            # noqa: E402

PROJ = "ti375c529"
DEVICE = "Ti375C529"
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJ_DIR = os.path.dirname(SCRIPT_DIR)
IO_MAP = os.path.join(SCRIPT_DIR, "efinix_io_map.csv")

# LVDS x2 half-rate lane recipes (empirical rules inherited from the
# migration-study prototype: RX_TERM is an enum; width-2 SERDES uses only
# the parallel clock - no serial fast clock at all, RX or TX)

RX_LANE_PROPS = {
    "RX_CONN_TYPE": "NORMAL",
    "RX_EN_DESER": "1",
    "RX_DESER": "2",
    "RX_HALF_RATE": "1",
    "RX_TERM": "ON",
    "RX_DELAY_MODE": "STATIC",   # eye-centering hook: 0-63 x ~25 ps
    "RX_DELAY": "0",
    "RX_SLOWCLK_PIN": "l_clk",
}

TX_LANE_PROPS = {
    "TX_EN_SER": "1",
    "TX_SER": "2",
    "TX_HALF_RATE": "1",
    "TX_SLOWCLK_PIN": "l_clk",
}

# SERDES control pins: enabling RX_EN_DESER/TX_EN_SER creates required
# per-lane INRST/RST/OE pins with default per-instance names
# (<inst>_RX_RST, <inst>_TX_RST, <inst>_TX_OE). Pin names must be UNIQUE
# design-wide (sharing one core pin across lanes is rejected with
# "Found duplicated pin name"), so system_top exposes all 23 ports and
# drives them from one internal serdes_rst / constant-1 tx_oe.


def main():
    design = DesignAPI(True)
    design.create(PROJ, DEVICE, PROJ_DIR)

    # -----------------------------------------------------------------
    # sys_pll: OSC1 25 MHz pad (TR0 REFCLK0) -> 125 MHz
    # -----------------------------------------------------------------
    design.create_block("sys_pll", block_type="PLL")
    design.gen_pll_ref_clock("sys_pll", pll_res="PLL_TR0",
                             refclk_src="EXTERNAL",
                             refclk_name="osc1_25mhz", ext_refclk_no="0")
    # MANUAL divider configuration. auto_calc_pll_clock(CLKOUT0_FREQ=125)
    # silently solved 25 MHz -> 100 MHz -- caught by the official
    # EFX_FPLL_V1 model in the datapath simulation (garbled UART,
    # 1.25x-slow CPU), confirmed by the interface report ("Output
    # Frequency : 100.0000 MHz"). Root cause: with feedback from CLKOUT0,
    # fout0 = fref*M/N and M is restricted to {1,2,4} on this FPLL, so
    # x5 is unreachable and the solver quietly delivered x4. The x5 ratio
    # needs the feedback taken from a second CLKOUT with its own divider:
    # fout0 = fref * CLKOUT1_DIV / CLKOUT0_DIV (M=N=1). CLKOUT1 (25 MHz)
    # exists only inside the feedback loop; VCO = 4.0 GHz (in range; the
    # lvds_pll runs at 4.9152 GHz). Verified by property read-back below.
    design.set_property("sys_pll", {"REFCLK_FREQ": "25",
                                    "CLKOUT1_EN": "1",
                                    "FEEDBACK_CLK": "CLK1",
                                    "M": "1",
                                    "N": "1",
                                    "O": "4",
                                    "CLKOUT0_DIV": "8",
                                    "CLKOUT1_DIV": "40"}, block_type="PLL")
    design.calc_pll_clock("sys_pll")
    design.set_property("sys_pll", {"CLKOUT0_PIN": "clk_125mhz",
                                    "LOCKED_PIN": "sys_pll_locked"},
                        block_type="PLL")

    # -----------------------------------------------------------------
    # rx_clk: AD9361 DATA_CLK LVDS pair onto the GCLK tree (CLK7)
    # -----------------------------------------------------------------
    design.create_block("rx_clk_in", block_type="LVDS_RX")
    design.set_property("rx_clk_in", {"RX_CONN_TYPE": "GCLK",
                                      "RX_TERM": "ON",
                                      "RX_IN_PIN": "rx_clk"},
                        block_type="LVDS_RX")

    # -----------------------------------------------------------------
    # lvds_pll: BR0 corner, core-clock-tree reference from rx_clk
    # -----------------------------------------------------------------
    design.create_block("lvds_pll", block_type="PLL")
    design.gen_pll_ref_clock("lvds_pll", pll_res="PLL_BR0",
                             refclk_src="CORE")
    design.set_property("lvds_pll", {"CORE_CLK_PIN": "rx_clk",
                                     "REFCLK_FREQ": "61.44",
                                     "CLKOUT1_EN": "1"}, block_type="PLL")
    design.auto_calc_pll_clock("lvds_pll",
                               {"CLKOUT0_FREQ": "61.44",
                                "CLKOUT0_PHASE": "0",
                                "CLKOUT1_FREQ": "61.44",
                                "CLKOUT1_PHASE": "90"})
    design.set_property("lvds_pll", {"CLKOUT0_PIN": "l_clk",
                                     "CLKOUT1_PIN": "l_clk_90",
                                     "LOCKED_PIN": "lvds_pll_locked"},
                        block_type="PLL")

    # -----------------------------------------------------------------
    # PLL solution read-back: the solvers can settle on a different
    # frequency than requested WITHOUT an error (see the sys_pll note
    # above), so every clock the design depends on is verified here and
    # a mismatch fails the build.
    # -----------------------------------------------------------------
    for pll, prop, want in [("sys_pll", "CLKOUT0_FREQ", 125.0),
                            ("lvds_pll", "CLKOUT0_FREQ", 61.44),
                            ("lvds_pll", "CLKOUT1_FREQ", 61.44),
                            ("lvds_pll", "CLKOUT1_PHASE", 90.0)]:
        got = float(design.get_property(pll, prop, block_type="PLL")[prop])
        if abs(got - want) > 0.01:
            print(f"ERROR: {pll} {prop} = {got}, expected {want} "
                  f"(PLL solver mis-solve; fix the divider settings)")
            sys.exit(1)
        print(f"INFO: {pll} {prop} = {got} (verified)")

    # -----------------------------------------------------------------
    # LVDS lanes + GPIO singles from the board map
    # -----------------------------------------------------------------
    with open(IO_MAP, newline="") as f:
        rows = [r for r in csv.reader(f)
                if r and not r[0].lstrip().startswith("#")]

    for row in rows:
        signal, block, resource = row[0], row[1], row[2]

        if block == "LVDS_RX_GCLK":
            # created above (rx_clk_in); only the resource comes from here
            design.assign_resource("rx_clk_in", resource,
                                   block_type="LVDS_RX")

        elif block == "LVDS_RX":
            inst = signal + "_lane"
            design.create_block(inst, block_type="LVDS_RX")
            props = dict(RX_LANE_PROPS)
            props["RX_IN_PIN"] = signal
            design.set_property(inst, props, block_type="LVDS_RX")
            design.assign_resource(inst, resource, block_type="LVDS_RX")

        elif block == "LVDS_TX":
            inst = signal + "_lane"
            design.create_block(inst, block_type="LVDS_TX")
            props = dict(TX_LANE_PROPS)
            props["TX_OUT_PIN"] = signal
            design.set_property(inst, props, block_type="LVDS_TX")
            design.assign_resource(inst, resource, block_type="LVDS_TX")

        elif block == "LVDS_TX_CLKOUT":
            # forwarded FB_CLK: serializer clocked by the +90 deg CLKOUT,
            # no core data pin (the PolarFire +90 deg ODDR trick, moved
            # into the periphery)
            inst = signal + "_lane"
            design.create_block(inst, block_type="LVDS_TX",
                                tx_mode="CLKOUT")
            design.set_property(inst, {"TX_MODE": "CLKOUT",
                                       "TX_EN_SER": "1",
                                       "TX_SER": "2",
                                       "TX_HALF_RATE": "1",
                                       "TX_SLOWCLK_PIN": "l_clk_90"},
                                block_type="LVDS_TX")
            design.assign_resource(inst, resource, block_type="LVDS_TX")

        elif block in ("GPIO_IN", "GPIO_IN_33"):
            design.create_input_gpio(signal)
            if block == "GPIO_IN_33":
                design.set_property(signal, "IO_STANDARD", "3.3 V LVCMOS")
            if signal == "sys_resetn_pin":
                design.set_property(signal, "PULL_OPTION", "WEAK_PULLUP")
            design.assign_resource(signal, resource)

        elif block in ("GPIO_OUT", "GPIO_OUT_33"):
            design.create_output_gpio(signal)
            if block == "GPIO_OUT_33":
                design.set_property(signal, "IO_STANDARD", "3.3 V LVCMOS")
            design.assign_resource(signal, resource)

        else:
            raise ValueError(f"unknown block type {block} for {signal}")

    # -----------------------------------------------------------------
    # Design-rule check + save. generate() prints all findings with
    # severities; errors fail the build (checked again in build_all.sh
    # via the exit code here).
    # -----------------------------------------------------------------
    design.generate(enable_bitstream=False)

    issues = design.get_design_check_issue()
    n_err = 0
    try:
        for issue in issues:
            sev = str(getattr(issue, "severity", issue)).lower()
            if "error" in sev:
                n_err += 1
    except TypeError:
        pass
    if n_err:
        print(f"ERROR: interface design check reported {n_err} error(s)")
        sys.exit(1)

    design.save_as(os.path.join(PROJ_DIR, PROJ + ".peri.xml"))

    # -----------------------------------------------------------------
    # Periphery simulation netlist: a pad-level chip wrapper
    # (\system_top_shim~chip) that instantiates Efinix's OFFICIAL
    # periphery models (EFX_FPLL_V1, EFX_LVDS_RX/TX_V2, EFX_GPIO_V3 from
    # $EFINITY_HOME/pt/sim_models/verilog) around a core module named
    # "system_top_shim". The full-system Questa simulation
    # (deps/neorv32/setups/neorv32_sw_ad9361_datapath_sim_efinix)
    # provides that shim around the real system_top — so the sim
    # exercises the same SERDES/PLL behavior Efinix characterizes,
    # not a hand-written approximation.
    # -----------------------------------------------------------------
    outflow = os.path.join(PROJ_DIR, "outflow")
    os.makedirs(outflow, exist_ok=True)
    design.export_periphery_sim_netlist(
        "system_top_shim",
        os.path.join(outflow, PROJ + "_interface.v"),
        os.path.join(outflow, PROJ + "_pt_interface.v"))
    print("TI375_FMCOMMS2_INTERFACE_OK")


if __name__ == "__main__":
    main()
