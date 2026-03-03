#!/usr/bin/env bash
# ================================================================================
# axi_ad9361 Testbench - Questa Prime Simulation Launcher (Unix/Linux/macOS)
# ================================================================================
# This script launches Questa Prime simulation for the axi_ad9361 testbench
# ================================================================================

set -e

# Configuration
VSIM="${VSIM:-vsim}"
SIM_MODE="gui"
SIM_TIME="100us"

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
            rm -rf work
            rm -f *.wlf *.log *.vstf transcript qpsk_bram_data.hex
            echo "Done."
            exit 0
            ;;
        --help)
            echo "axi_ad9361 Testbench - Questa Prime Simulation Script"
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
            echo "  XILINX_QUESTA_LIBS   Path to pre-compiled Xilinx simulation libraries"
            echo "                       (required, set before running)"
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

# Check if XILINX_QUESTA_LIBS is set
if [[ -z "${XILINX_QUESTA_LIBS}" ]]; then
    echo "ERROR: XILINX_QUESTA_LIBS environment variable not set!"
    echo ""
    echo "Please set it to point to your pre-compiled Xilinx simulation libraries:"
    echo "  export XILINX_QUESTA_LIBS=/path/to/Questa_Libraries_Vivado"
    echo ""
    echo "To compile Xilinx libraries, run in Vivado Tcl Console:"
    echo "  compile_simlib -simulator questa -simulator_exec_path {path_to_questa} -dir {output_dir}"
    exit 1
fi

# Check if Questa/Vsim is available
if ! command -v "$VSIM" &> /dev/null; then
    echo "ERROR: Questa Prime (vsim) not found in PATH!"
    echo "Please ensure Questa Prime is installed and added to your system PATH."
    exit 1
fi

echo "=========================================="
echo "axi_ad9361 Questa Simulation"
echo "=========================================="
echo "Simulation time: $SIM_TIME"
echo "Simulation mode: $SIM_MODE"
echo "Xilinx libs:     $XILINX_QUESTA_LIBS"
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
