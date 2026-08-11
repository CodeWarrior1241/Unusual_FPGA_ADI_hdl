#!/usr/bin/env bash
###############################################################################
# FMCOMMS2 on Ti375C529 Dev Kit - full headless build.
#
# Efinity replacement for the Libero run_libero.sh + build_all.tcl pair:
#   1. install the pre-built ad9361_no-os firmware image (same mechanism
#      as axau15/mpf300; the image initializes the NEORV32 IMEM ROM and
#      Efinity bakes it into the bitstream - no design-init staging)
#   2. generate the project XML (file lists, options)      [gen_project.py]
#   3. generate the periphery (PLLs/LVDS/GPIO) + rule check [gen_interface.py]
#   4. efx_run --flow compile: map -> interface -> pnr -> bitstream
#   5. milestone markers for CI parity with the other two targets
#
# Usage:  cd deps/hdl/projects/fmcomms2/ti375 && ./scripts/build_all.sh
# Override the Efinity install with EFINITY_HOME.
###############################################################################
set -euo pipefail

EFINITY_HOME="${EFINITY_HOME:-/media/fpgadev/Dev_Tools/Efinity/2026.1}"
# setup.sh appends to PYTHONPATH without a default, which is fatal under
# set -u -- give it one first
export PYTHONPATH="${PYTHONPATH:-}"
# setup.sh also runs `ldd --version | head -1`, which dies with
# SIGPIPE (exit 141) under pipefail -- relax it around the source
set +o pipefail
source "$EFINITY_HOME/bin/setup.sh"
set -o pipefail

cd "$(dirname "$0")/.."
PROJ_DIR="$(pwd)"
REPO_ROOT="$(cd ../../../../.. && pwd)"

###############################################################################
# 1. NEORV32 software image (ad9361_no-os), same mechanism as axau15/mpf300
###############################################################################

SW_APP_DIR="$REPO_ROOT/deps/neorv32/sw/ad9361_no-os"
PREBUILT="$SW_APP_DIR/neorv32_imem_image.vhd"
APP_IMAGE="$REPO_ROOT/deps/neorv32/rtl/core/neorv32_imem_image.vhd"

if [[ -f "$PREBUILT" ]]; then
    echo "INFO: Installing pre-built ad9361_no-os image..."
    cp -f "$PREBUILT" "$APP_IMAGE"
else
    echo "ERROR: Pre-built ad9361_no-os application image not found:"
    echo "         $PREBUILT"
    echo "  To build it, run (with RISC-V GCC in PATH):"
    echo "    cd $SW_APP_DIR && make clean_all image"
    exit 1
fi

###############################################################################
# 2-3. Generators (source of truth; ti375c529.xml / .peri.xml are products)
###############################################################################

python3 scripts/gen_project.py
efx_py  scripts/gen_interface.py

###############################################################################
# 4. Compile: map -> interface -> pnr -> bitstream
###############################################################################

efx_run "$PROJ_DIR/ti375c529.xml" --flow compile 2>&1 | tee build_all.log

###############################################################################
# 5. Milestones (efx_run per-stage PASS lines are reliable gates, unlike
#    Libero's Error-severity noise; markers kept for CI parity)
###############################################################################

grep -q "map[[:space:]]*:.*PASS" build_all.log && echo "TI375_FMCOMMS2_SYNTH_OK"
grep -q "pnr[[:space:]]*:.*PASS" build_all.log && echo "TI375_FMCOMMS2_PNR_OK"
grep -q "pgm[[:space:]]*:.*PASS" build_all.log && echo "TI375_FMCOMMS2_BITSTREAM_OK"

# RAM-inference audit (the one failure mode that is silent in the exit
# status): every NEORV32/BRAM/FIFO memory must land in block RAM. The
# reference build maps 212 x EFX_RAM10 / ~15k FF; a memory fallen through
# to flip-flops shows up as RAM10 collapsing and EFX_FF exploding toward
# ~200k (the pre-patch NEORV32 signature).
echo "INFO: mapped resource summary:"
grep -E "EFX_(LUT4|FF|RAM10|DSP48)[[:space:]]*:" outflow/ti375c529.log | tail -4
RAM10=$(grep -oE "EFX_RAM10[[:space:]]*:[[:space:]]*[0-9]+" outflow/ti375c529.log | tail -1 | grep -oE "[0-9]+$")
if [[ "${RAM10:-0}" -lt 150 ]]; then
    echo "WARNING: EFX_RAM10=$RAM10 (<150) - a memory may have fallen through to registers"
fi
