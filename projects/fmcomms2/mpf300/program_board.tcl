###############################################################################
## FMCOMMS2/4 on PolarFire MPF300 Splash Kit - Board programming script
###############################################################################
#
# Programs BOTH memories of the deployed design over the one USB cable:
#   1. PROGRAMDEVICE           - fabric + sNVM (the bitstream: logic config
#                                and the 504-byte stage-1 init client)
#   2. PROGRAM_SPI_FLASH_IMAGE - the 1 Gb Micron MT25QL01GB SPI flash on the
#                                System Controller SPI (stage-3 RAM-init
#                                client at flash offset 0x400: NEORV32
#                                ad9361_no-os firmware image + SmartHLS
#                                buffer contents). The FPGA's System
#                                Controller writes the flash itself; no
#                                external flash programmer is involved.
#
# After both steps, POWER-CYCLE the board: on power-up the device runs I/O
# calibration (stage 1, sNVM), then streams the LSRAM contents from the SPI
# flash (~60-80 ms); SRAM_INIT_DONE releases sys_resetn and the CPU boots.
#
# How to run (headless):
#   cd deps/hdl/projects/fmcomms2/mpf300
#   ./libero_configuration/run_libero.sh \
#       SCRIPT:program_board.tcl LOGFILE:program_board.log
#   (set LIBERO_INSTALL_DIR if Libero is not at the launcher's default
#   location; see libero_configuration/run_libero.sh)
#
# Environment / prerequisites:
#   - Libero SoC with a license seat free (same setup as build_all.tcl;
#     run_libero.sh handles PATH and licensing; verified on 2025.2 and
#     2026.1 -- the known-flakiness notes below were observed on 2025.2).
#   - Run with the SAME Libero release that built ./proj: a .prjx created
#     by a newer Libero cannot be opened by an older one.
#   - The project must already be BUILT: ./proj/ with bitstream + SPI image
#     generated (run build_all.tcl first; look for MPF300_FMCOMMS2_EXPORT_OK).
#   - Board: MPF300-SPLASH-KIT on 12 V/5 A supply, powered ON (SW1), mini-USB
#     connected to this host (on-board FTDI; J11 default 1-2 closed, J5-J9
#     default). Jumper J32 pins 3-4 (VADJ = 2.5 V) for FMCOMMS2.
#   - Jumper J10 pins 1-2 CLOSED (NOT the factory default): J10 selects the
#     mux (U71) between the SPI flash and either the FTDI or the PolarFire
#     SC_SPI. Step 2 fails with "SPI - Flash is not connected or not
#     supported" when J10 is open, and power-up init from flash needs it
#     closed permanently.
#   - The FTDI JTAG programmer must be visible to Libero (FlashPro drivers /
#     udev rules installed; check with Libero's programmer self-test or
#     'lsusb | grep -i future' for the FT4232 device).
#   - Die is MPF300T (production, MPF300T-1FCG484E per the kit QuickStart;
#     covered by the Silver license) -- a bitstream built for the
#     MPF300TS_ES eval die is rejected by the scan-chain check with
#     "Found: MPF300(T|TS|...), Expected: MPF300TS_ES".
#
# Firmware-only update: after rebuilding the no-os image and re-running
# build_all.tcl, only step 2 (SPI flash) is needed -- the fabric bitstream
# does not contain the firmware. Comment out step 1 to skip it.
#
# Known flakiness: Libero 2025.2 batch mode occasionally SEGFAULTS while
# re-opening this project (during the open-time HDL file audit), before any
# programming action runs. It is intermittent -- if the run dies with
# "Segmentation fault" right after the "Reading file ..." lines, just run
# the script again.
#
# Known refusal: PROGRAMDEVICE can fail instantly with "Bitstream
# programming action is disabled" (EXPORT ERROR_CODE 804f, EXIT -38) even
# though the scan chain passes -- a stuck System Controller programming
# state, seen after repeated program/power cycles. Remedy: power-cycle the
# board (DEVRST clears it), then rerun; a retry without the power-cycle
# fails the same way. Nothing is written before the refusal, so the
# on-device design is untouched.
#
# SPI flash prerequisite: build_all.tcl must have run with cfg/spiflash.cfg
# present (ships in the repo), which configures the SPI Flash memory map and
# generates the flash image in batch mode. The cfg carries a 256-byte
# STATIC_FILL placeholder client at 0x100000 -- it works around a Libero
# 2025.2 batch bug where an empty SPI Flash client list makes the flow
# raise a GUI dialog ("There are no SPI Flash clients selected for
# programming") through a NULL main-window pointer and segfault. The
# placeholder writes the flash's erased state, so it is electrically inert.
#
###############################################################################

# Locate the project relative to this script so any checkout works
open_project -file [file join [file dirname [file normalize [info script]]] proj fmcomms2_mpf300.prjx]

# Set to 1 to skip step 1 (fabric + sNVM) and program only the SPI flash --
# the firmware-only update path. The fabric has a ~1000-programming-cycle
# lifetime (PolarFire DS Table 5-67); skip it whenever the design on the
# device already matches (compare the printed bitstream digests).
set SKIP_FABRIC 0

# Set to 1 to skip step 2 (SPI flash). CAUTION: only safe when the flash
# already holds the image from THIS build. The stage-3 init stream writes
# firmware into specific physical RAM1K20 blocks chosen at place & route
# (TAKEOVER_LSRAM block IDs) -- after any rebuild that re-placed the
# design, the old flash image targets the old block locations and the CPU
# would boot garbage. When in doubt, program both memories.
set SKIP_SPI 0

###############################################################################
# Step 1: fabric + sNVM over JTAG
###############################################################################

if {!$SKIP_FABRIC} {
puts "INFO: Programming fabric + sNVM (JTAG)..."
if {[catch {run_tool -name {PROGRAMDEVICE}} result]} {
    puts "ERROR: PROGRAMDEVICE failed: $result"
    puts "MPF300_PROGRAM_FAILED"
    close_project -save 0
    return -1
}
puts "MPF300_FABRIC_PROGRAMMED"
} else {
    puts "INFO: SKIP_FABRIC=1 -- skipping fabric/sNVM programming."
}

###############################################################################
# Step 2: SPI flash (RAM-init client with the NEORV32 firmware)
###############################################################################

if {!$SKIP_SPI} {
puts "INFO: Programming SPI flash image (System Controller SPI)..."
configure_tool \
    -name {PROGRAM_SPI_FLASH_IMAGE} \
    -params {spi_flash_prog_action:PROGRAM_SPI_IMAGE}
if {[catch {run_tool -name {PROGRAM_SPI_FLASH_IMAGE}} result]} {
    puts "ERROR: PROGRAM_SPI_FLASH_IMAGE failed: $result"
    puts "MPF300_PROGRAM_FAILED"
    close_project -save 0
    return -1
}
puts "MPF300_SPI_FLASH_PROGRAMMED"
} else {
    puts "INFO: SKIP_SPI=1 -- skipping SPI flash programming."
}

puts ""
puts "==============================================================================="
puts "  Board programmed. POWER-CYCLE the board to boot the design."
puts "==============================================================================="
puts "MPF300_PROGRAM_OK"

close_project -save 0
