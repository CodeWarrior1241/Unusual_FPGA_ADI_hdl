###############################################################################
# system_constr.xdc — FMCOMMS2/3/4 FMC daughter card on Alinx AXAU15 carrier
# AD9361 (FMCOMMS2/3) / AD9364 (FMCOMMS4) LVDS + control pin constraints
###############################################################################
#
# Pinout source: AXAU15 User Manual V1.0 (2025-11-17) Table 3.4.1, and
# baseboard schematic at:
#   doc/axau15/04_Sch_and_PCB/Sch_PCB/Carrier/AXAU15 base board schematics.pdf
#
# ─────────────────────────────────────────────────────────────────────────────
# I/O BANK MAPPING
# ─────────────────────────────────────────────────────────────────────────────
#
# Every FMC LA pin used by FMCOMMS2 (LA00..LA16, LA19..LA28) lands in either
# BANK64 or BANK65 on AXAU15. Both are HP banks at VCCO = VADJ = 1.8V per
# UM §2.7 ("BANK64, BANK65, and BANK66 banks utilize the ETA1471 DCDC chip").
# All LVDS receivers support DIFF_TERM_ADV TERM_100 — no HD-bank pseudo-
# differential workaround is needed (cf. au15p/system_constr.xdc).
#
# AD9361 LVDS signal landings on AXAU15:
#   rx_clk, rx_frame, rx_data[0..5], tx_clk, tx_frame, tx_data[0..5]
#   - all in BANK65 (HP, 1.8V)
#
# Bank 65 also covers: SPI bus, GPIO control, status, and the buttons / SD
# card. Bank 64 covers GPIO control extensions and the LEDs.
#
# ─────────────────────────────────────────────────────────────────────────────
# IDELAYCTRL placement — per-nibble IDELAYCTRLs for the RX LVDS data path
# ─────────────────────────────────────────────────────────────────────────────
#
# UltraScale+ HRIO requires one IDELAYCTRL per nibble containing an IDELAYE3.
# ad_data_in.v inside rx_frame instantiates ONE (IODELAY_CTRL=1); the 6 rx_data
# lanes use IDELAYE3 with IODELAY_CTRL=0 and rely on a shared IDELAYCTRL. On
# AXAU15 the FMCOMMS2 pins scatter across 4 BANK65 nibbles that rx_frame's
# IDELAYCTRL (byte5 upper, X0Y11) does NOT serve, so those BITSLICEs never reach
# BISC RDY and capture a constant 0x000 (dig_tune all-fail). 4 extra IDELAYCTRLs
# are instantiated in the `ifdef AXAU15_BANK65_IDELAYCTRLS block of
# axi_ad9361_lvds_if.v (enabled via verilog_define in build_all.tcl).
#
# Nibble map from place_design (BITSLICE_RX_TX Y / 13 = byte; 0-5 lo, 6-12 hi):
#   rx_frame     Y75       -> byte5 upper (X0Y11)  served by i_rx_frame/i_delay_ctrl
#   rx_data[0]   Y82       -> byte6 lower (X0Y12)
#   rx_data[2,3] Y88,Y86   -> byte6 upper (X0Y13)
#   rx_data[5]   Y93       -> byte7 lower (X0Y14)
#   rx_data[1,4] Y101,Y97  -> byte7 upper (X0Y15)

set_property LOC BITSLICE_CONTROL_X0Y11 [get_cells Top_i/axi_ad9361/inst/i_dev_if/i_rx_frame/i_delay_ctrl]
set_property LOC BITSLICE_CONTROL_X0Y12 [get_cells Top_i/axi_ad9361/inst/i_dev_if/i_delay_ctrl_byte6_lo]
set_property LOC BITSLICE_CONTROL_X0Y13 [get_cells Top_i/axi_ad9361/inst/i_dev_if/i_delay_ctrl_byte6_hi]
set_property LOC BITSLICE_CONTROL_X0Y14 [get_cells Top_i/axi_ad9361/inst/i_dev_if/i_delay_ctrl_byte7_lo]
set_property LOC BITSLICE_CONTROL_X0Y15 [get_cells Top_i/axi_ad9361/inst/i_dev_if/i_delay_ctrl_byte7_hi]

# BISC consumes BITSLICE_0 (lower nibble) / BITSLICE_6 (upper nibble) of each
# activated nibble until RDY (~1 ms post-bitstream, before AD9361 reset release);
# ports on those slices need UNAVAILABLE_DURING_CALIBRATION. Reserved slices:
#   Y71 (X0Y11), Y78 (X0Y12), Y84 (X0Y13), Y91 (X0Y14), Y97 (X0Y15)
# Reserved-slice port survey (place_design query):
#   Y71 (X0Y11) -> tx_data_out[3]      Y84 (X0Y13) -> unused (no constraint)
#   Y78 (X0Y12) -> sys_clk_in_clk_p    Y91 (X0Y14) -> tx_data_out[1]
#   Y97 (X0Y15) -> rx_data[4]
set_property UNAVAILABLE_DURING_CALIBRATION true [get_ports {rx_data_in_p[4]}]
set_property UNAVAILABLE_DURING_CALIBRATION true [get_ports {rx_data_in_n[4]}]
set_property UNAVAILABLE_DURING_CALIBRATION true [get_ports {tx_data_out_p[3]}]
set_property UNAVAILABLE_DURING_CALIBRATION true [get_ports {tx_data_out_n[3]}]
set_property UNAVAILABLE_DURING_CALIBRATION true [get_ports {tx_data_out_p[1]}]
set_property UNAVAILABLE_DURING_CALIBRATION true [get_ports {tx_data_out_n[1]}]

# sys_clk_in_clk_p (Y78) is a CLOCK-ONLY pin: it drives the IBUFDS->MMCM path,
# not an RX_BITSLICE datapath, AND via the MMCM it is the source of delay_clk —
# the IDELAYCTRL REFCLK that BISC itself needs. It may therefore NOT trip the
# reserved-slice DRC. Enable the two lines below ONLY if implementation raises a
# reserved-slice DRC naming sys_clk_in_clk_p, then confirm MMCM LOCKED +
# IDELAYCTRL RDY at first boot. (No AU15P precedent — byte6 was not activated there.)
# set_property UNAVAILABLE_DURING_CALIBRATION TRUE [get_ports {sys_clk_in_clk_p}]
# set_property UNAVAILABLE_DURING_CALIBRATION TRUE [get_ports {sys_clk_in_clk_n}]
#
# ─────────────────────────────────────────────────────────────────────────────
# FMC LA pin assignments — AD9361 LVDS data path
# ─────────────────────────────────────────────────────────────────────────────

# RX clock and frame (LA00_CC, LA01_CC)
set_property -dict {PACKAGE_PIN V23 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports rx_clk_in_p]
set_property -dict {PACKAGE_PIN W23 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports rx_clk_in_n]
set_property -dict {PACKAGE_PIN V24 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports rx_frame_in_p]
set_property -dict {PACKAGE_PIN W24 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports rx_frame_in_n]

# RX data [5:0] — all LVDS in BANK65 (LA02..LA07)
set_property -dict {PACKAGE_PIN N24 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {rx_data_in_p[0]}]
set_property -dict {PACKAGE_PIN P24 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {rx_data_in_n[0]}]
set_property -dict {PACKAGE_PIN N21 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {rx_data_in_p[1]}]
set_property -dict {PACKAGE_PIN N22 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {rx_data_in_n[1]}]
set_property -dict {PACKAGE_PIN R25 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {rx_data_in_p[2]}]
set_property -dict {PACKAGE_PIN R26 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {rx_data_in_n[2]}]
set_property -dict {PACKAGE_PIN P25 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {rx_data_in_p[3]}]
set_property -dict {PACKAGE_PIN P26 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {rx_data_in_n[3]}]
set_property -dict {PACKAGE_PIN N23 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {rx_data_in_p[4]}]
set_property -dict {PACKAGE_PIN P23 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {rx_data_in_n[4]}]
set_property -dict {PACKAGE_PIN P20 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {rx_data_in_p[5]}]
set_property -dict {PACKAGE_PIN P21 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {rx_data_in_n[5]}]

# TX clock and frame (LA08, LA09)
set_property -dict {PACKAGE_PIN R20 IOSTANDARD LVDS} [get_ports tx_clk_out_p]
set_property -dict {PACKAGE_PIN R21 IOSTANDARD LVDS} [get_ports tx_clk_out_n]
set_property -dict {PACKAGE_PIN N19 IOSTANDARD LVDS} [get_ports tx_frame_out_p]
set_property -dict {PACKAGE_PIN P19 IOSTANDARD LVDS} [get_ports tx_frame_out_n]

# TX data [5:0] — all LVDS in BANK65 (LA10..LA15).
# AD9361-bit ordering follows the FMCOMMS2 schematic:
#   AD9361 bit 0 -> LA11, bit 1 -> LA12, bit 2 -> LA13,
#   AD9361 bit 3 -> LA10, bit 4 -> LA14, bit 5 -> LA15
set_property -dict {PACKAGE_PIN T22 IOSTANDARD LVDS} [get_ports {tx_data_out_p[0]}]
set_property -dict {PACKAGE_PIN T23 IOSTANDARD LVDS} [get_ports {tx_data_out_n[0]}]
set_property -dict {PACKAGE_PIN R22 IOSTANDARD LVDS} [get_ports {tx_data_out_p[1]}]
set_property -dict {PACKAGE_PIN R23 IOSTANDARD LVDS} [get_ports {tx_data_out_n[1]}]
set_property -dict {PACKAGE_PIN T20 IOSTANDARD LVDS} [get_ports {tx_data_out_p[2]}]
set_property -dict {PACKAGE_PIN U20 IOSTANDARD LVDS} [get_ports {tx_data_out_n[2]}]
set_property -dict {PACKAGE_PIN W25 IOSTANDARD LVDS} [get_ports {tx_data_out_p[3]}]
set_property -dict {PACKAGE_PIN W26 IOSTANDARD LVDS} [get_ports {tx_data_out_n[3]}]
set_property -dict {PACKAGE_PIN U19 IOSTANDARD LVDS} [get_ports {tx_data_out_p[4]}]
set_property -dict {PACKAGE_PIN V19 IOSTANDARD LVDS} [get_ports {tx_data_out_n[4]}]
set_property -dict {PACKAGE_PIN V21 IOSTANDARD LVDS} [get_ports {tx_data_out_p[5]}]
set_property -dict {PACKAGE_PIN V22 IOSTANDARD LVDS} [get_ports {tx_data_out_n[5]}]

# ─────────────────────────────────────────────────────────────────────────────
# FMC LA pin assignments — AD9361 single-ended control / status
# ─────────────────────────────────────────────────────────────────────────────

# enable, txnrx (LA16)
set_property -dict {PACKAGE_PIN U21 IOSTANDARD LVCMOS18} [get_ports enable]
set_property -dict {PACKAGE_PIN U22 IOSTANDARD LVCMOS18} [get_ports txnrx]

# gpio_status[7:0] (LA20..LA23) — all in BANK64
set_property -dict {PACKAGE_PIN AE17 IOSTANDARD LVCMOS18} [get_ports {gpio_status[0]}]
set_property -dict {PACKAGE_PIN AF17 IOSTANDARD LVCMOS18} [get_ports {gpio_status[1]}]
set_property -dict {PACKAGE_PIN Y17 IOSTANDARD LVCMOS18} [get_ports {gpio_status[2]}]
set_property -dict {PACKAGE_PIN AA17 IOSTANDARD LVCMOS18} [get_ports {gpio_status[3]}]
set_property -dict {PACKAGE_PIN AB17 IOSTANDARD LVCMOS18} [get_ports {gpio_status[4]}]
set_property -dict {PACKAGE_PIN AC17 IOSTANDARD LVCMOS18} [get_ports {gpio_status[5]}]
set_property -dict {PACKAGE_PIN AA20 IOSTANDARD LVCMOS18} [get_ports {gpio_status[6]}]
set_property -dict {PACKAGE_PIN AB20 IOSTANDARD LVCMOS18} [get_ports {gpio_status[7]}]

# gpio_ctl[3:0] (LA24, LA25)
set_property -dict {PACKAGE_PIN AC18 IOSTANDARD LVCMOS18} [get_ports {gpio_ctl[0]}]
set_property -dict {PACKAGE_PIN AD18 IOSTANDARD LVCMOS18} [get_ports {gpio_ctl[1]}]
set_property -dict {PACKAGE_PIN AA22 IOSTANDARD LVCMOS18} [get_ports {gpio_ctl[2]}]
set_property -dict {PACKAGE_PIN AB22 IOSTANDARD LVCMOS18} [get_ports {gpio_ctl[3]}]

# gpio_en_agc, gpio_sync (LA19)
set_property -dict {PACKAGE_PIN AE22 IOSTANDARD LVCMOS18} [get_ports gpio_en_agc]
set_property -dict {PACKAGE_PIN AF22 IOSTANDARD LVCMOS18} [get_ports gpio_sync]

# gpio_resetb (LA28_P) — N leg unused
set_property -dict {PACKAGE_PIN AF18 IOSTANDARD LVCMOS18} [get_ports gpio_resetb]

# ─────────────────────────────────────────────────────────────────────────────
# FMC LA pin assignments — SPI bus
# ─────────────────────────────────────────────────────────────────────────────

# SPI (LA26, LA27) — pull-up on chip-select
set_property PACKAGE_PIN Y20 [get_ports {spi_csn_0[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {spi_csn_0[0]}]
set_property PULLTYPE PULLUP [get_ports {spi_csn_0[0]}]
set_property -dict {PACKAGE_PIN Y21 IOSTANDARD LVCMOS18} [get_ports spi_clk]
set_property -dict {PACKAGE_PIN AA19 IOSTANDARD LVCMOS18} [get_ports spi_mosi]
set_property -dict {PACKAGE_PIN AB19 IOSTANDARD LVCMOS18} [get_ports spi_miso]

# ─────────────────────────────────────────────────────────────────────────────
# System reset — no external pin (internal tie-off)
# ─────────────────────────────────────────────────────────────────────────────
#
# system_resetn is tied internally to 1'b1 in the BD via an xlconstant cell
# (see build_all.tcl, after the MMCM startgroup). The MMCM starts locking as
# soon as the 200 MHz sysclk is valid (UG572 — no reset assertion required).
# Recovery from a hung state is power-cycle only; KEY1 (N26) and KEY2 (AA23)
# remain free for application use.

# ─────────────────────────────────────────────────────────────────────────────
# NEORV32 UART0 — USB-to-UART bridge (CP2102GM on AXAU15 baseboard)
# ─────────────────────────────────────────────────────────────────────────────
#
# Per AXAU15 UM V1.0 Table 3.5.1 (BANK86, LVCMOS33). Naming polarity assumed
# from FPGA perspective; verify against schematic.

set_property -dict {PACKAGE_PIN A12 IOSTANDARD LVCMOS33} [get_ports sys_uart_rx]
set_property -dict {PACKAGE_PIN A13 IOSTANDARD LVCMOS33} [get_ports sys_uart_tx]

# ─────────────────────────────────────────────────────────────────────────────
# System clock — 200 MHz from on-board SiTime SiT9121AI-2B1-33E oscillator
# ─────────────────────────────────────────────────────────────────────────────
#
# Per AXAU15 core-board (ACAU15) schematic page 09 — System Clock block:
#   Source       : SiT9121AI-2B1-33E-200.000000
#                  (3.3V supply, "E" = LVPECL output)
#   Coupling     : AC-coupled via C86, C88 (0.1uF/25V) — DC-blocked
#   FPGA receiver: T24/U24 in BANK65 (VCCO = 1.8V), MRCC pair (HPIOB_M)
#
# Replaces AU15P's Epson ECS 300 MHz DIFF_SSTL12 reference. The MMCM (named
# `SiTime_300MHz` in build_all.tcl) takes the 200 MHz input and generates
# 300 MHz on clk_out2 for the IODELAY refclk.
#
# IOSTANDARD = LVDS is correct on the receiver side (it describes the FPGA's
# input behavior, not the source's output technology). DIFF_TERM_ADV TERM_100
# is REQUIRED because the AC coupling strips the DC bias from the LVPECL
# source; the internal 100Ω termination re-establishes the differential
# common-mode at the receiver. Without it the receiver sees no defined CMRR
# and the clock will be unreliable. Reference: Xilinx UG571 §5
# ("AC-Coupled LVDS Inputs") and SiTime AN10024.

set_property -dict {PACKAGE_PIN T24 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports sys_clk_in_clk_p]
set_property -dict {PACKAGE_PIN U24 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports sys_clk_in_clk_n]

# ─────────────────────────────────────────────────────────────────────────────
# Timing constraints
# ─────────────────────────────────────────────────────────────────────────────

# AD9361 rx_clk — DDR clock from chip. Maximum 122.88 MHz in 2R2T LVDS DDR.
# Period 8.0 ns covers 125 MHz with margin.
create_clock -period 8.000 -name rx_clk [get_ports rx_clk_in_p]
