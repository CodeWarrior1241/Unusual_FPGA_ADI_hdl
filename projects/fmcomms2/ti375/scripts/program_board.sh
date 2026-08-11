#!/usr/bin/env bash
###############################################################################
# FMCOMMS2 on Ti375C529 Dev Kit - board programming.
#
# Efinity replacement for the Libero/FlashPro program_board.tcl. The C529
# kit programs over the on-board FTDI 4232H (USB1 Type-C): channel B is
# FPGA JTAG, channel C is the UART console - one cable for both.
#
#   ./scripts/program_board.sh            volatile JTAG load (bench default)
#   ./scripts/program_board.sh flash      write NOR flash via the JTAG-SPI
#                                         bridge (standalone/power-bench boot;
#                                         SW1 = CRESET_N to reconfigure)
#
# There is no design-initialization/SPI-staging step: RAM init (including
# the NEORV32 firmware image) is part of the bitstream.
###############################################################################
set -euo pipefail

EFINITY_HOME="${EFINITY_HOME:-/media/fpgadev/Dev_Tools/Efinity/2026.1}"
# setup.sh appends to PYTHONPATH without a default (fatal under set -u)
export PYTHONPATH="${PYTHONPATH:-}"
# setup.sh also runs `ldd --version | head -1`, which dies with
# SIGPIPE (exit 141) under pipefail -- relax it around the source
set +o pipefail
source "$EFINITY_HOME/bin/setup.sh"
set -o pipefail

cd "$(dirname "$0")/.."

MODE="${1:-jtag}"

case "$MODE" in
    jtag)
        python3 "$EFINITY_HOME/pgm/bin/efx_pgm/ftdi_program.py" \
            outflow/ti375c529.bit -m jtag
        ;;
    flash)
        efx_run ti375c529.xml --flow program --pgm_opts mode=jtag_bridge
        ;;
    *)
        echo "usage: $0 [jtag|flash]" >&2
        exit 1
        ;;
esac
