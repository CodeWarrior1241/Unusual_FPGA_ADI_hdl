#!/usr/bin/env bash
# =============================================================================
# FMCOMMS2/AU15P Firmware Debug — Questa Launcher
# =============================================================================
# Reproduces the ad9361_no-os firmware crash in simulation with a minimal
# AD9361 SPI slave model. Full waveform visibility for debugging.
#
# Prerequisites:
#   1. Vivado project built (build_all.tcl)
#   2. Firmware built and installed:
#        cd deps/neorv32/sw/ad9361_no-os && make clean_all exe install
#   3. Vivado sim scripts exported:
#        vivado -mode tcl -source sim/export_sim.tcl
#
# Usage:
#   ./run_sim.sh                    # 20ms, GUI, fast
#   ./run_sim.sh --detailed         # 20ms, GUI, full waveforms
#   ./run_sim.sh --detailed --batch # 20ms, headless
#   ./run_sim.sh --time 50ms        # longer run
# =============================================================================

set -e

VSIM="${VSIM:-vsim}"
SIM_MODE="gui"
SIM_TIME="100ms"
DETAILED="no"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Derive repo root from git
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$REPO_ROOT" ]; then
    echo "ERROR: Cannot determine repository root from $SCRIPT_DIR"
    exit 1
fi
# This script is inside deps/hdl — go up to the parent repo
PROJECT_ROOT="$(git -C "$REPO_ROOT/.." rev-parse --show-toplevel 2>/dev/null || echo "")"
if [ -z "$PROJECT_ROOT" ]; then
    PROJECT_ROOT="$REPO_ROOT/../.."
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --time)     SIM_TIME="$2"; shift 2 ;;
        --gui)      SIM_MODE="gui"; shift ;;
        --batch)    SIM_MODE="batch"; shift ;;
        --detailed) DETAILED="yes"; shift ;;
        --clean)
            echo "Cleaning..."
            rm -rf questa_lib work
            rm -f *.wlf *.log *.vstf transcript modelsim.ini
            echo "Done."
            exit 0
            ;;
        --help)
            echo "FMCOMMS2/AU15P Firmware Debug — Questa Simulation"
            echo ""
            echo "Usage: ./run_sim.sh [options]"
            echo ""
            echo "  --time TIME    Simulation time (default: 20ms)"
            echo "  --gui          GUI mode (default)"
            echo "  --batch        Batch/headless mode"
            echo "  --detailed     Full signal visibility with waveforms"
            echo "  --clean        Remove generated files"
            echo "  --help         Show this help"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if ! command -v "$VSIM" &> /dev/null; then
    echo "ERROR: Questa (vsim) not found in PATH"
    exit 1
fi

# Check Vivado sim scripts exist
QUESTA_SCRIPTS="../fmcomms2_au15p.ip_user_files/sim_scripts/questa"
if [ ! -d "$QUESTA_SCRIPTS" ]; then
    echo "ERROR: Vivado simulation scripts not found."
    echo "       Run in Vivado Tcl console:"
    echo "         source [file normalize sim/export_sim.tcl]"
    exit 1
fi

# Sync NEORV32 IMEM image to ipshared locations
NEORV32_HOME="$PROJECT_ROOT/deps/neorv32"
IMEM_SRC="$NEORV32_HOME/rtl/core/neorv32_imem_image.vhd"

if [ -f "$IMEM_SRC" ]; then
    echo "Syncing IMEM image from $IMEM_SRC"
    IPSHARED_DIRS=$(find ../fmcomms2_au15p.ip_user_files ../fmcomms2_au15p.gen \
        -name "neorv32_imem_image.vhd" -printf '%h\n' 2>/dev/null | sort -u)
    for dir in $IPSHARED_DIRS; do
        cp -f "$IMEM_SRC" "$dir/neorv32_imem_image.vhd"
        echo "  -> $dir/"
    done
else
    echo "WARNING: IMEM image not found at $IMEM_SRC"
    echo "  Build firmware: cd deps/neorv32/sw/ad9361_no-os && make clean_all exe install"
fi

echo "=========================================="
echo "  FMCOMMS2/AU15P Firmware Debug Sim"
echo "=========================================="
echo "  Sim time: $SIM_TIME"
echo "  Mode:     $SIM_MODE"
echo "  Detailed: $DETAILED"
echo "=========================================="

SIM_VARS="set SIM_TIME {$SIM_TIME}; set DETAILED {$DETAILED}"

if [[ "$SIM_MODE" == "batch" ]]; then
    "$VSIM" -c -do "$SIM_VARS; source simulate.do; quit -f"
else
    "$VSIM" -do "$SIM_VARS; source simulate.do"
fi
