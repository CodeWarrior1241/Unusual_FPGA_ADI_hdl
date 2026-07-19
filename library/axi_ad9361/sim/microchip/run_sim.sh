#!/usr/bin/env bash
# ================================================================================
# axi_ad9361 PolarFire Testbench - QuestaSim Pro Simulation Launcher (Linux)
# ================================================================================
# Launches the axi_ad9361 TX-to-RX loopback simulation on the PolarFire port
# in the QuestaSim Pro simulator that ships with Libero SoC 2025.x.
#
# Mirrors ../xilinx/run_sim.sh, but needs no pre-compiled Xilinx libraries:
# the PolarFire primitive library is compiled on the fly from the Libero
# installation (see compile.do).
# ================================================================================

set -e

# Configuration
LIBERO_INSTALL_DIR="${LIBERO_INSTALL_DIR:-/media/fpgadev/Dev_Tools/Microchip/Libero_SoC}"
VSIM="${VSIM:-$LIBERO_INSTALL_DIR/QuestaSim_Pro/bin/vsim}"
SIM_MODE="gui"
SIM_TIME="100us"

# QuestaSim Pro ME checks out its license (Microchipqsimpro) from the Libero
# license server; prepend it like /media/fpgadev/Dev_Tools/Microchip/run_libero.sh
# does. MGLS_LICENSE_FILE / SALT_LICENSE_SERVER take precedence inside Questa
# and typically point at a Mentor/Siemens Questa Prime license (used by the
# ../xilinx flow) that cannot serve the Microchip edition -- drop them here.
export LM_LICENSE_FILE="${LIBERO_LICENSE_SERVER:-1702@localhost}${LM_LICENSE_FILE:+:$LM_LICENSE_FILE}"
unset MGLS_LICENSE_FILE SALT_LICENSE_SERVER
export LIBERO_INSTALL_DIR

# Change to script directory
cd "$(dirname "$0")"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --time)
            SIM_TIME="$2"
            shift 2
            ;;
        --gui)
            SIM_MODE="gui"
            shift
            ;;
        --batch)
            SIM_MODE="batch"
            shift
            ;;
        --clean)
            echo "Cleaning work directories and simulation artifacts..."
            rm -rf work polarfire
            rm -f *.wlf *.log *.vstf transcript qpsk_bram_data.hex modelsim.ini
            echo "Done."
            exit 0
            ;;
        --help)
            echo "axi_ad9361 PolarFire Testbench - QuestaSim Pro Simulation Script"
            echo ""
            echo "Usage: ./run_sim.sh [options]"
            echo ""
            echo "Options:"
            echo "  --time TIME    Set simulation time (default: 100us)"
            echo "  --gui          Run in GUI mode (default)"
            echo "  --batch        Run in batch/command-line mode"
            echo "  --clean        Remove work directories and generated files"
            echo "  --help         Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  LIBERO_INSTALL_DIR   Libero_SoC installation directory"
            echo "                       (default: /media/fpgadev/Dev_Tools/Microchip/Libero_SoC)"
            echo "  VSIM                 vsim binary to use"
            echo "                       (default: \$LIBERO_INSTALL_DIR/QuestaSim_Pro/bin/vsim)"
            echo "  LM_LICENSE_FILE      License server (default: 1702@localhost)"
            echo ""
            echo "Examples:"
            echo "  ./run_sim.sh                    Run with defaults (100us, GUI)"
            echo "  ./run_sim.sh --time 200us       Run for 200us"
            echo "  ./run_sim.sh --batch            Run in batch mode"
            echo "  ./run_sim.sh --time 1ms --batch Run 1ms in batch mode"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check if the bundled QuestaSim is available
if ! command -v "$VSIM" &> /dev/null; then
    echo "ERROR: QuestaSim Pro (vsim) not found: $VSIM"
    echo "Set LIBERO_INSTALL_DIR to your Libero_SoC installation directory,"
    echo "or set VSIM to a vsim binary directly."
    exit 1
fi

echo "=========================================="
echo "axi_ad9361 PolarFire Questa Simulation"
echo "=========================================="
echo "Simulation time: $SIM_TIME"
echo "Simulation mode: $SIM_MODE"
echo "Simulator:       $VSIM"
echo "Libero install:  $LIBERO_INSTALL_DIR"
echo "=========================================="

if [[ "$SIM_MODE" == "batch" ]]; then
    echo "Running in batch mode..."
    $VSIM -c -do "set SIM_TIME {$SIM_TIME}; do simulate.do; quit -f"

    echo ""
    echo "=========================================="
    echo "Simulation complete!"
    echo "=========================================="
else
    echo "Running in GUI mode..."
    $VSIM -do "set SIM_TIME {$SIM_TIME}; do simulate.do"
fi
