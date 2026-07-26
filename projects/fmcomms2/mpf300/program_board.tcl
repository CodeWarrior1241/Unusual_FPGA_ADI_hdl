###############################################################################
## FMCOMMS2/4 on PolarFire MPF300 Splash Kit - Board programming script
###############################################################################
#
# Programs BOTH memories of the deployed design over the one USB cable:
#   1. PROGRAM_DEVICE          - fabric + sNVM (the bitstream: logic config
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
#   /media/fpgadev/Dev_Tools/Microchip/run_libero.sh \
#       SCRIPT:program_board.tcl LOGFILE:program_board.log
#
# Environment / prerequisites:
#   - Libero SoC 2025.2 with a license seat free (same setup as build_all.tcl;
#     run_libero.sh handles PATH and licensing).
#   - The project must already be BUILT: ./proj/ with bitstream + SPI image
#     generated (run build_all.tcl first; look for MPF300_FMCOMMS2_EXPORT_OK).
#   - Board: MPF300-SPLASH-KIT on 12 V/5 A supply, powered ON (SW1), mini-USB
#     connected to this host (on-board FTDI; J11 default 1-2 closed, J5-J9
#     default, J10 open). Jumper J32 pins 3-4 (VADJ = 2.5 V) for FMCOMMS2.
#   - The FTDI JTAG programmer must be visible to Libero (FlashPro drivers /
#     udev rules installed; check with Libero's programmer self-test or
#     'lsusb | grep -i future' for the FT4232 device).
#   - Die is MPF300TS_ES (engineering sample): if the programmer rejects the
#     device ID, enable ES-silicon support in the programmer settings.
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

open_project -file {/media/fpgadev/Dev_Tools/Work/QPSK_Triple_Comparison/deps/hdl/projects/fmcomms2/mpf300/proj/fmcomms2_mpf300.prjx}

###############################################################################
# Step 1: fabric + sNVM over JTAG
###############################################################################

puts "INFO: Programming fabric + sNVM (JTAG)..."
if {[catch {run_tool -name {PROGRAM_DEVICE}} result]} {
    puts "ERROR: PROGRAM_DEVICE failed: $result"
    puts "MPF300_PROGRAM_FAILED"
    close_project -save 0
    return -1
}
puts "MPF300_FABRIC_PROGRAMMED"

###############################################################################
# Step 2: SPI flash (RAM-init client with the NEORV32 firmware)
###############################################################################

puts "INFO: Programming SPI flash image (System Controller SPI)..."
configure_tool \
    -name {PROGRAM_SPI_FLASH_IMAGE} \
    -params {spi_flash_prog_action: PROGRAM_SPI_FLASH}
if {[catch {run_tool -name {PROGRAM_SPI_FLASH_IMAGE}} result]} {
    puts "ERROR: PROGRAM_SPI_FLASH_IMAGE failed: $result"
    puts "MPF300_PROGRAM_FAILED"
    close_project -save 0
    return -1
}
puts "MPF300_SPI_FLASH_PROGRAMMED"

puts ""
puts "==============================================================================="
puts "  Board programmed. POWER-CYCLE the board to boot the design."
puts "==============================================================================="
puts "MPF300_PROGRAM_OK"

close_project -save 0
