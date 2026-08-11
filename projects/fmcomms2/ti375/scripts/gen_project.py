#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# FMCOMMS2 on Ti375C529 - Efinity project XML generator.
#
# Replaces the project-creation / file-import half of the Libero
# build_all.tcl: emits ti375c529.xml with the complete HDL file list
# (NEORV32 in VHDL library "neorv32", everything else in the default
# library), include directories and Verilog macros. No amalgamation and
# no file copies - deps/ sources are referenced in place (the Libero
# fileset bug that forced PULP/Bedrock amalgamation does not exist here).
#
# The tool REWRITES the project XML it is given (reformatting, attribute
# reordering): never hand-edit ti375c529.xml - edit this generator.
#
# Plain python3 (no Efinity libs needed). Run from anywhere:
#   python3 scripts/gen_project.py
# ---------------------------------------------------------------------------

import os
import shutil
from xml.sax.saxutils import quoteattr

PROJ = "ti375c529"
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJ_DIR = os.path.dirname(SCRIPT_DIR)
REPO = os.path.normpath(os.path.join(PROJ_DIR, "..", "..", "..", "..", ".."))

LIB = os.path.join(REPO, "deps", "hdl", "library")
NEORV32 = os.path.join(REPO, "deps", "neorv32")
HLS_AD9361 = os.path.join(REPO, "src", "axi_ad9361_adapter_microchip")
HLS_STREAM = os.path.join(REPO, "src", "axi_lite_to_streaming_adapter_microchip")

# vendor-neutral ADI library modules (same list as build_all.tcl)
ADI_COMMON = [
    "ad_addsub.v", "ad_datafmt.v", "ad_dds.v", "ad_dds_1.v", "ad_dds_2.v",
    "ad_dds_cordic_pipe.v", "ad_dds_sine.v", "ad_dds_sine_cordic.v",
    "ad_iqcor.v", "ad_pnmon.v", "ad_pps_receiver.v", "ad_rst.v",
    "ad_tdd_control.v", "up_adc_channel.v", "up_adc_common.v", "up_axi.v",
    "up_clock_mon.v", "up_dac_channel.v", "up_dac_common.v",
    "up_delay_cntrl.v", "up_tdd_cntrl.v", "up_xfer_cntrl.v",
    "up_xfer_status.v",
]

ADI_CORE = [
    "axi_ad9361.v", "axi_ad9361_rx.v", "axi_ad9361_rx_channel.v",
    "axi_ad9361_rx_pnmon.v", "axi_ad9361_tdd.v", "axi_ad9361_tdd_if.v",
    "axi_ad9361_tx.v", "axi_ad9361_tx_channel.v",
]

# Efinix device interface + the portable PolarFire-common arithmetic
# helpers (ad_mul infers DSP48 as-is; proven in the migration study)
ADI_DEVICE = [
    ("efinix", "axi_ad9361_lvds_if.v"),
    ("polarfire/common", "ad_dcfilter.v"),
    ("polarfire/common", "ad_mul.v"),
]

# PULP platform (deps/common_cells v1.39.0, deps/axi v0.39.10): the
# AXI-Lite crossbar behind axi_1to3_decoder - individual files, packages
# first (compile order preserved from build_all.tcl)
PULP_COMMON_CELLS = [
    "cf_math_pkg.sv", "addr_decode_dync.sv", "addr_decode.sv",
    "spill_register_flushable.sv", "spill_register.sv", "fifo_v3.sv",
    "lzc.sv", "rr_arb_tree.sv", "counter.sv", "delta_counter.sv",
    "stream_register.sv", "sync.sv", "binary_to_gray.sv",
    "gray_to_binary.sv", "cdc_fifo_gray.sv",
]

PULP_AXI = [
    "axi_pkg.sv", "axi_intf.sv", "axi_lite_demux.sv", "axi_lite_mux.sv",
    "axi_lite_to_axi.sv", "axi_err_slv.sv", "axi_lite_xbar.sv",
]

# Bedrock-RTL (CDC FIFO controller, bit synchronizer, reset sync) in
# dependency order - same list as build_all.tcl / compile.do
BEDROCK = [
    "pkg/br_math_pkg.sv",
    "gate/rtl/br_gate_mock.sv",
    "misc/rtl/br_misc_unused.sv",
    "misc/rtl/br_misc_tieoff_zero.sv",
    "misc/rtl/br_misc_tieoff_one.sv",
    "cdc/rtl/br_cdc_pkg.sv",
    "cdc/rtl/br_cdc_bit_toggle.sv",
    "counter/rtl/br_counter_incr.sv",
    "flow/rtl/internal/br_flow_checks_valid_data_intg.sv",
    "fifo/rtl/internal/br_fifo_push_ctrl_core.sv",
    "enc/rtl/br_enc_bin2gray.sv",
    "delay/rtl/br_delay_nr.sv",
    "cdc/rtl/internal/br_cdc_fifo_reset_overlap_checks.sv",
    "enc/rtl/br_enc_gray2bin.sv",
    "cdc/rtl/internal/br_cdc_fifo_push_flag_mgr.sv",
    "cdc/rtl/internal/br_cdc_fifo_push_ctrl.sv",
    "cdc/rtl/internal/br_cdc_fifo_gray_count_sync.sv",
    "cdc/rtl/br_cdc_fifo_ctrl_push_1r1w.sv",
    "cdc/rtl/internal/br_cdc_fifo_pop_flag_mgr.sv",
    "delay/rtl/br_delay_valid.sv",
    "delay/rtl/br_delay_shift_reg.sv",
    "counter/rtl/br_counter.sv",
    "flow/rtl/internal/br_flow_checks_valid_data_impl.sv",
    "flow/rtl/br_flow_reg_fwd.sv",
    "mux/rtl/br_mux_onehot.sv",
    "fifo/rtl/internal/br_fifo_staging_buffer.sv",
    "fifo/rtl/internal/br_fifo_pop_ctrl_core.sv",
    "cdc/rtl/internal/br_cdc_fifo_pop_ctrl.sv",
    "cdc/rtl/br_cdc_fifo_ctrl_pop_1r1w.sv",
    "cdc/rtl/br_cdc_fifo_ctrl_1r1w.sv",
    "cdc/rtl/br_cdc_rst_sync.sv",
]

# project-local helper blocks (this directory's hdl/)
HELPERS = [
    "axi_1to3_decoder.sv", "axi_bram_32k.v", "axis_async_fifo.v",
    "efx_reset_gen.sv", "sys_ctrl.v", "lclk_reset_sync.v", "dac_hold.v",
    "system_top.v",
]

INCLUDE_DIRS = [
    os.path.join(REPO, "deps", "axi", "include"),
    os.path.join(REPO, "deps", "common_cells", "include"),
    os.path.join(REPO, "deps", "bedrock-rtl", "macros"),
]


def rel(p):
    return os.path.relpath(p, PROJ_DIR)


def neorv32_files():
    """NEORV32 core file list ($NEORV32_HOME substitution, like
    build_all.tcl). file_list_soc.f was renamed file_list_core.f
    upstream (PR #1611); accept either."""
    fl = os.path.join(NEORV32, "rtl", "file_list_soc.f")
    if not os.path.exists(fl):
        fl = os.path.join(NEORV32, "rtl", "file_list_core.f")
    out = []
    with open(fl) as f:
        for line in f:
            line = line.strip()
            if line:
                out.append(line.replace("$NEORV32_HOME", NEORV32))
    return out


# Integration shell + XBUS-to-AXI4 bridge + this project's configuration
# wrapper: compiled into the DEFAULT library (Libero used 'work'), not
# 'neorv32' -- the wrapper binds `entity work.neorv32_vivado_ip` (same-
# library reference) and the Verilog system_top can only cross-language
# bind entities in the default library. neorv32_vivado_ip reaches the CPU
# core through its explicit `library neorv32` clause.
def neorv32_integration_files():
    return [
        os.path.join(NEORV32, "rtl", "system_integration",
                     "xbus2axi4_bridge.vhd"),
        os.path.join(NEORV32, "rtl", "system_integration",
                     "neorv32_vivado_ip.vhd"),
        os.path.join(PROJ_DIR, "hdl", "neorv32_ti375_top.vhd"),
    ]


def stage_mem_init():
    """Merged mem_init directory for the SmartHLS RAM init files (both
    adapters share one MEM_INIT_DIR macro; file names do not collide)."""
    dst = os.path.join(PROJ_DIR, "mem_init")
    os.makedirs(dst, exist_ok=True)
    for d in (HLS_AD9361, HLS_STREAM):
        src = os.path.join(d, "hls_output", "rtl", "mem_init")
        for f in sorted(os.listdir(src)):
            if f.endswith(".mem"):
                shutil.copy2(os.path.join(src, f), dst)


def design_file(path, library="default", version="default"):
    return (f'        <efx:design_file name={quoteattr(rel(path))} '
            f'version="{version}" library="{library}"/>')


def main():
    stage_mem_init()

    files = []

    # NEORV32 (VHDL, library neorv32; requires the neorv32_prim.vhd
    # generate-scope patch carried in deps/neorv32 for RAM inference)
    for f in neorv32_files():
        files.append(design_file(f, library="neorv32", version="vhdl_2008"))
    for f in neorv32_integration_files():
        files.append(design_file(f, version="vhdl_2008"))

    # ADI library + axi_ad9361 core + efinix device interface
    for f in ADI_COMMON:
        files.append(design_file(os.path.join(LIB, "common", f)))
    for f in ADI_CORE:
        files.append(design_file(os.path.join(LIB, "axi_ad9361", f)))
    for sub, f in ADI_DEVICE:
        files.append(design_file(os.path.join(LIB, "axi_ad9361", sub, f)))

    # SmartHLS adapters (generated Verilog used as portable source)
    files.append(design_file(os.path.join(
        HLS_AD9361, "hls_output", "rtl",
        "axi_ad9361_adapter_axi_ad9361_adapter.v")))
    files.append(design_file(os.path.join(
        HLS_STREAM, "hls_output", "rtl",
        "axi_lite_to_streaming_adapter_axi_lite_to_streaming_adapter.v")))

    # PULP + Bedrock (SystemVerilog, individual files, no amalgamation)
    for f in PULP_COMMON_CELLS:
        files.append(design_file(
            os.path.join(REPO, "deps", "common_cells", "src", f)))
    for f in PULP_AXI:
        files.append(design_file(os.path.join(REPO, "deps", "axi", "src", f)))
    for f in BEDROCK:
        files.append(design_file(
            os.path.join(REPO, "deps", "bedrock-rtl", f)))

    # project-local helpers + top
    for f in HELPERS:
        files.append(design_file(os.path.join(PROJ_DIR, "hdl", f)))

    includes = "\n".join(
        f'        <efx:param name="include" value={quoteattr(rel(d))} '
        f'value_type="e_string"/>' for d in INCLUDE_DIRS)

    xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<efx:project name="{PROJ}" description="FMCOMMS2 on Ti375C529 Dev Kit (NEORV32 + axi_ad9361 + SmartHLS adapters)" sw_version="2026.1.132" config_result_in_sync="true" xmlns:efx="http://www.efinixinc.com/enf_proj" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.efinixinc.com/enf_proj enf_proj.xsd">
    <efx:device_info>
        <efx:family name="Titanium"/>
        <efx:device name="Ti375C529"/>
        <efx:timing_model name="C4"/>
    </efx:device_info>
    <efx:design_info def_veri_version="verilog_2k" def_vhdl_version="vhdl_2008" unified_flow="false">
        <efx:top_module name="system_top"/>
{chr(10).join(files)}
        <efx:top_vhdl_arch name=""/>
    </efx:design_info>
    <efx:constraint_info>
        <efx:sdc_file name="constraint/system.sdc"/>
        <efx:inter_file name=""/>
    </efx:constraint_info>
    <efx:sim_info/>
    <efx:misc_info/>
    <efx:ip_info/>
    <efx:synthesis tool_name="efx_map">
        <efx:param name="work_dir" value="work_syn" value_type="e_string"/>
        <efx:param name="write_efx_verilog" value="on" value_type="e_bool"/>
        <efx:param name="mode" value="speed" value_type="e_option"/>
        <efx:param name="max_ram" value="-1" value_type="e_integer"/>
        <efx:param name="max_mult" value="-1" value_type="e_integer"/>
        <efx:param name="infer-clk-enable" value="3" value_type="e_option"/>
        <efx:param name="infer-sync-set-reset" value="1" value_type="e_option"/>
        <efx:param name="retiming" value="1" value_type="e_option"/>
        <efx:param name="seq_opt" value="1" value_type="e_option"/>
        <efx:param name="max_threads" value="-1" value_type="e_integer"/>
{includes}
        <efx:defmacro name="BR_PPA_SYNTHESIS" value="1"/>
        <efx:defmacro name="MEM_INIT_DIR" value="&quot;mem_init/&quot;"/>
    </efx:synthesis>
    <efx:place_and_route tool_name="efx_pnr">
        <efx:param name="work_dir" value="work_pnr" value_type="e_string"/>
        <efx:param name="verbose" value="off" value_type="e_bool"/>
        <efx:param name="seed" value="1" value_type="e_integer"/>
        <efx:param name="placer_effort_level" value="2" value_type="e_option"/>
        <efx:param name="max_threads" value="-1" value_type="e_integer"/>
        <efx:param name="print_critical_path" value="10" value_type="e_integer"/>
    </efx:place_and_route>
    <efx:bitstream_generation tool_name="efx_pgm">
        <efx:param name="mode" value="active" value_type="e_string"/>
        <efx:param name="width" value="1" value_type="e_string"/>
        <efx:param name="enable_roms" value="smart" value_type="e_option"/>
        <efx:param name="bitstream_compression" value="on" value_type="e_bool"/>
        <efx:param name="generate_bit" value="on" value_type="e_bool"/>
        <efx:param name="generate_hex" value="on" value_type="e_bool"/>
    </efx:bitstream_generation>
    <efx:debugger>
        <efx:param name="work_dir" value="work_dbg" value_type="e_string"/>
        <efx:param name="auto_instantiation" value="off" value_type="e_bool"/>
    </efx:debugger>
    <efx:security/>
</efx:project>
"""
    out = os.path.join(PROJ_DIR, PROJ + ".xml")
    with open(out, "w") as f:
        f.write(xml)
    print(f"wrote {out} ({len(files)} design files)")


if __name__ == "__main__":
    main()
