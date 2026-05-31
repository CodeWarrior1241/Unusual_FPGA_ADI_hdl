###############################################################################
# system_constr.xdc — FMCOMMS2/3/4 FMC daughter card on AU15P carrier
# AD9361 (FMCOMMS2/3) / AD9364 (FMCOMMS4) LVDS + control pin constraints
###############################################################################

# ─────────────────────────────────────────────────────────────────────────────
# I/O BANK MAPPING
# ─────────────────────────────────────────────────────────────────────────────
#
# AU15P FMC LA pins span two I/O banks:
#   Bank 66 (HP I/O, VCCO = VADJ = 1.8V) — supports LVDS + DIFF_TERM_ADV
#   Bank 86 (HD I/O, VCCO = VADJ = 1.8V) — supports LVDS but NOT DIFF_TERM
#
# Six LVDS signals land on HD bank 86:
#   rx_data_in[5]  (LA07 = J12/H12)  — LVCMOS18 input, NO internal termination available
#   tx_clk_out     (LA08 = H14/G14)  — LVCMOS18 output, OK
#   tx_data_out[0] (LA11 = E13/E12)  — LVCMOS18 output, OK
#
# A pseudo-LVDS interface is created for tx_clk_out and tx_data_out[0] by inverting the N pin of
# both pairs. This is because Avnet in their infinite wisdom decided to route some of the FMC pins
# on HD bank 86, which doesn't have differntial pins. Idiots - nothing in the errata on this as of 03/2026.
#
# Six single-ended LVCMOS18 signals also land on HD bank 86:
#   gpio_status[4:5]  (LA22 = B14/A14)  — input,  OK (LVCMOS18 unaffected)
#   gpio_ctl[2:3]     (LA25 = J13/H13)  — output, OK
#   spi_mosi/miso     (LA27 = J15/J14)  — output/input, OK
#
# ─────────────────────────────────────────────────────────────────────────────
# SIGNAL-INTEGRITY ADVISORY — AU15P Bank 86 (HD I/O) Limitation
# ─────────────────────────────────────────────────────────────────────────────
#
# FMC_LPC_LA07 (rx_data_in[5]) lands on Bank 86, which is an HD (High-Density)
# I/O bank on the AU15P.  HD banks do NOT support DIFF_TERM or DIFF_TERM_ADV,
# so this LVDS input pair has no internal differential termination.
#
# At DDR rates above ~125 MHz the unterminated input is subject to reflections,
# ringing, and reduced voltage-margin that can cause bit errors on this lane.
# Because the AD9361/AD9364 DATA_CLK frequency is:
#
#     DATA_CLK = Sample_Rate x M
#
#         M = 4  (2R2T — two-channel duplex, AD9361 on FMCOMMS2/3)
#         M = 2  (1R1T — single-channel duplex, AD9361 or AD9364 on FMCOMMS4)
#
# the following practical limits apply when NO external termination is fitted:
#
#   ┌───────────────────┬──────────────────┬─────────────────┬──────────────────────────────┐
#   │  Board / Mode     │  Max Safe FSAMP  │  DATA_CLK (DDR) │  Notes                       │
#   ├───────────────────┼──────────────────┼─────────────────┼──────────────────────────────┤
#   │  FMCOMMS2/3 2R2T  │  <= 30.72 MSPS   │  <= 122.88 MHz  │  Stays below 125 MHz         │
#   │  FMCOMMS2/3 1R1T  │  <= 61.44 MSPS   │  <= 122.88 MHz  │  Full rate is safe           │
#   │  FMCOMMS4 (AD9364)│  <= 61.44 MSPS   │  <= 122.88 MHz  │  1R1T only; full rate safe   │
#   └───────────────────┴──────────────────┴─────────────────┴──────────────────────────────┘
#
# The FMCOMMS4 (AD9364) is inherently 1R1T, so DATA_CLK never exceeds
# 122.88 MHz even at the maximum 61.44 MSPS sample rate.  The Bank 86
# termination limitation therefore does NOT restrict FMCOMMS4 operation
# at any supported sample rate on this carrier.
#
# When the sample rate is kept within the limits above, relax the rx_clk
# timing constraint accordingly (see create_clock at end of file).
# ─────────────────────────────────────────────────────────────────────────────

# F24/F25 are QBC (Quad-Bank Clock) pins — DBC-type clocks intended for bitslice
# and DDR I/O timing only (analogous to SERDES clocks in prior generations).
# They have no dedicated routing to BUFGCE global clock buffers. The AD9361
# rx_clk lands here due to the AU15P FMC pin mapping (LA00_CC → Bank 66 QBC).
# Allow fabric routing from the IOB to the BUFGCE; target ≤125 MHz — validate timing.
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets Top_i/axi_ad9361/inst/i_dev_if/i_clk/i_rx_clk_ibuf/O]

# ─────────────────────────────────────────────────────────────────────────────
# IDELAYCTRL placement — one per nibble containing an IDELAYE3 cell
# ─────────────────────────────────────────────────────────────────────────────
#
# The ad_data_in.v module instantiates a single IDELAYCTRL inside the rx_frame
# generate block. Per Xilinx UG571, one IDELAYCTRL is required per bank
# (UltraScale+ HRIO: per nibble) containing IDELAY primitives, with matching
# IODELAY_GROUP. Vivado's IODELAY_GROUP auto-replication does NOT engage in
# this design (verified: only one IDELAYCTRL existed, placed at
# BITSLICE_CONTROL_X0Y0 in clock region X0Y0 — far from the IDELAYE3 cells
# in clock region X0Y2). The IDELAYE3 cells in unserved nibbles are left
# uncalibrated, so dig_tune's tap sweeps produce no functional change in
# delay and the LVDS RX data lanes cannot be aligned to the chip's data eye.
#
# Fix: add 4 explicit IDELAYCTRL instances in axi_ad9361_lvds_if.v (one per
# nibble in bank 66 that contains an rx_data IDELAYE3 cell) plus constrain
# the existing rx_frame IDELAYCTRL to its target nibble. All 5 share
# IODELAY_GROUP = "dev_if_delay_group" so Vivado treats them as cooperating
# controllers for the same IDELAYE3 set.
#
# Byte / nibble layout in bank 66 (clock region X0Y2):
#   BITSLICE_CONTROL_X0Y16 = byte 8 lower nibble (BITSLICEs Y104-Y109)
#   BITSLICE_CONTROL_X0Y17 = byte 8 upper nibble (BITSLICEs Y110-Y116)
#   BITSLICE_CONTROL_X0Y18 = byte 9 lower nibble (BITSLICEs Y117-Y122)
#   BITSLICE_CONTROL_X0Y19 = byte 9 upper nibble (BITSLICEs Y123-Y129)
#   BITSLICE_CONTROL_X0Y20 = byte 10 lower nibble (BITSLICEs Y130-Y135)
#   BITSLICE_CONTROL_X0Y21 = byte 10 upper nibble (BITSLICEs Y136-Y142)
#   BITSLICE_CONTROL_X0Y22 = byte 11 lower nibble (BITSLICEs Y143-Y148)
#   BITSLICE_CONTROL_X0Y23 = byte 11 upper nibble (BITSLICEs Y149-Y155)
#
# IDELAYE3 cell -> nibble mapping:
#   rx_data[1] Y106 -> byte 8 lower (X0Y16)   shared with rx_data[2]
#   rx_data[2] Y108 -> byte 8 lower (X0Y16)
#   rx_data[3] Y110 -> byte 8 upper (X0Y17)
#   rx_frame   Y127 -> byte 9 upper (X0Y19)   served by rx_frame's i_delay_ctrl
#   rx_data[0] Y138 -> byte 10 upper (X0Y21)
#   rx_data[4] Y151 -> byte 11 upper (X0Y23)

set_property LOC BITSLICE_CONTROL_X0Y16 [get_cells Top_i/axi_ad9361/inst/i_dev_if/i_delay_ctrl_byte8_lo]
set_property LOC BITSLICE_CONTROL_X0Y17 [get_cells Top_i/axi_ad9361/inst/i_dev_if/i_delay_ctrl_byte8_hi]
set_property LOC BITSLICE_CONTROL_X0Y19 [get_cells Top_i/axi_ad9361/inst/i_dev_if/i_rx_frame/i_delay_ctrl]
set_property LOC BITSLICE_CONTROL_X0Y21 [get_cells Top_i/axi_ad9361/inst/i_dev_if/i_delay_ctrl_byte10_hi]
set_property LOC BITSLICE_CONTROL_X0Y23 [get_cells Top_i/axi_ad9361/inst/i_dev_if/i_delay_ctrl_byte11_hi]

# ─────────────────────────────────────────────────────────────────────────────
# BISC unavailability declarations
# ─────────────────────────────────────────────────────────────────────────────
#
# Each IDELAYCTRL placement above activates BITSLICE_CONTROL in its nibble,
# which triggers BISC (Built-In Self Calibration) at boot. During BISC,
# BITSLICE_0 of the byte (in lower-nibble controllers) and BITSLICE_6 of the
# byte (in upper-nibble controllers) are unavailable until BISC RDY asserts.
# BISC completes in ~1 ms after bitstream load — long before the AD9361 chip
# is released from reset by NEORV32, so undefined values on these ports
# during the BISC window do not affect chip state.
#
# Per-controller BISC-affected slices in our design:
#   X0Y16 (byte 8 lower) -> BITSLICE_0 = Y104 = tx_data_out_p[0] (top-level)
#   X0Y17 (byte 8 upper) -> BITSLICE_6 = Y110 = rx_data_in_p[3]
#   X0Y19 (byte 9 upper) -> BITSLICE_6 = Y123 = enable
#   X0Y21 (byte 10 upper) -> BITSLICE_6 = Y136 (unused, no DRC needed)
#   X0Y23 (byte 11 upper) -> BITSLICE_6 = Y149 (unused, no DRC needed)

set_property UNAVAILABLE_DURING_CALIBRATION TRUE [get_ports {tx_data_out_p[0]}]   ; ## L18 IOB_X0Y104 = BITSLICE_0 of byte 8
set_property UNAVAILABLE_DURING_CALIBRATION TRUE [get_ports {tx_data_out_n[0]}]   ; ## K18 paired N of LVDS
set_property UNAVAILABLE_DURING_CALIBRATION TRUE [get_ports {rx_data_in_p[3]}]    ; ## M19 IOB_X0Y110 = BITSLICE_6 of byte 8
set_property UNAVAILABLE_DURING_CALIBRATION TRUE [get_ports {rx_data_in_n[3]}]    ; ## L19 paired N of LVDS
set_property UNAVAILABLE_DURING_CALIBRATION TRUE [get_ports enable]               ; ## L24 IOB_X0Y123 = BITSLICE_6 of byte 9
set_property UNAVAILABLE_DURING_CALIBRATION TRUE [get_ports rx_clk_in_p]          ; ## F24 IOB_X0Y136 = BITSLICE_6 of byte 10
set_property UNAVAILABLE_DURING_CALIBRATION TRUE [get_ports rx_clk_in_n]          ; ## F25 paired N of LVDS
set_property UNAVAILABLE_DURING_CALIBRATION TRUE [get_ports {gpio_status[2]}]     ; ## D23 IOB_X0Y149 = BITSLICE_6 of byte 11

set_property  -dict {PACKAGE_PIN  F24    IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports rx_clk_in_p]           ; ## G6   FMC_LPC_LA00_CC_P
set_property  -dict {PACKAGE_PIN  F25    IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports rx_clk_in_n]           ; ## G7   FMC_LPC_LA00_CC_N
set_property  -dict {PACKAGE_PIN  J23    IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports rx_frame_in_p]         ; ## D8   FMC_LPC_LA01_CC_P
set_property  -dict {PACKAGE_PIN  J24    IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports rx_frame_in_n]         ; ## D9   FMC_LPC_LA01_CC_N
set_property  -dict {PACKAGE_PIN  H26    IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {rx_data_in_p[0]}]     ; ## H7   FMC_LPC_LA02_P
set_property  -dict {PACKAGE_PIN  G26    IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {rx_data_in_n[0]}]     ; ## H8   FMC_LPC_LA02_N
set_property  -dict {PACKAGE_PIN  M20    IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {rx_data_in_p[1]}]     ; ## G9   FMC_LPC_LA03_P
set_property  -dict {PACKAGE_PIN  M21    IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {rx_data_in_n[1]}]     ; ## G10  FMC_LPC_LA03_N
set_property  -dict {PACKAGE_PIN  J19    IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {rx_data_in_p[2]}]     ; ## H10  FMC_LPC_LA04_P
set_property  -dict {PACKAGE_PIN  J20    IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {rx_data_in_n[2]}]     ; ## H11  FMC_LPC_LA04_N
set_property  -dict {PACKAGE_PIN  M19    IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {rx_data_in_p[3]}]     ; ## D11  FMC_LPC_LA05_P
set_property  -dict {PACKAGE_PIN  L19    IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {rx_data_in_n[3]}]     ; ## D12  FMC_LPC_LA05_N
set_property  -dict {PACKAGE_PIN  D26    IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {rx_data_in_p[4]}]     ; ## C10  FMC_LPC_LA06_P
set_property  -dict {PACKAGE_PIN  C26    IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports {rx_data_in_n[4]}]     ; ## C11  FMC_LPC_LA06_N
# Bank 86 HD pins — LVCMOS18 pseudo-differential (PSEUDO_DIFF=1 in axi_ad9361_lvds_if.v)
# TX pins: N driven as inverted P via two OBUFs. RX: IBUF on P only, N unused.
# Port names avoid _p/_n suffix to prevent Vivado differential pair inference.
set_property  -dict {PACKAGE_PIN  J12    IOSTANDARD LVCMOS18}                    [get_ports rx_data_5_se]          ; ## H13  FMC_LPC_LA07_P  (HD bank 86)
set_property  -dict {PACKAGE_PIN  H12    IOSTANDARD LVCMOS18}                    [get_ports rx_data_5_se_unused]   ; ## H14  FMC_LPC_LA07_N  (HD bank 86)
set_property  -dict {PACKAGE_PIN  H14    IOSTANDARD LVCMOS18} [get_ports tx_clk_se_true]                           ; ## G12  FMC_LPC_LA08_P  (HD bank 86)
set_property  -dict {PACKAGE_PIN  G14    IOSTANDARD LVCMOS18} [get_ports tx_clk_se_comp]                           ; ## G13  FMC_LPC_LA08_N  (HD bank 86)
set_property  -dict {PACKAGE_PIN  H21    IOSTANDARD LVDS} [get_ports tx_frame_out_p]                               ; ## D14  FMC_LPC_LA09_P
set_property  -dict {PACKAGE_PIN  H22    IOSTANDARD LVDS} [get_ports tx_frame_out_n]                               ; ## D15  FMC_LPC_LA09_N
set_property  -dict {PACKAGE_PIN  E13    IOSTANDARD LVCMOS18} [get_ports tx_d0_se_true]                            ; ## H16  FMC_LPC_LA11_P  (HD bank 86) (AD9361 bit 0)
set_property  -dict {PACKAGE_PIN  E12    IOSTANDARD LVCMOS18} [get_ports tx_d0_se_comp]                            ; ## H17  FMC_LPC_LA11_N  (HD bank 86)

set_property  -dict {PACKAGE_PIN  L18    IOSTANDARD LVDS} [get_ports {tx_data_out_p[0]}]                           ; ## G15  FMC_LPC_LA12_P  (AD9361 bit 1)
set_property  -dict {PACKAGE_PIN  K18    IOSTANDARD LVDS} [get_ports {tx_data_out_n[0]}]                           ; ## G16  FMC_LPC_LA12_N
set_property  -dict {PACKAGE_PIN  K22    IOSTANDARD LVDS} [get_ports {tx_data_out_p[1]}]                           ; ## D17  FMC_LPC_LA13_P  (AD9361 bit 2)
set_property  -dict {PACKAGE_PIN  K23    IOSTANDARD LVDS} [get_ports {tx_data_out_n[1]}]                           ; ## D18  FMC_LPC_LA13_N
set_property  -dict {PACKAGE_PIN  E25    IOSTANDARD LVDS} [get_ports {tx_data_out_p[2]}]                           ; ## C14  FMC_LPC_LA10_P  (AD9361 bit 3)
set_property  -dict {PACKAGE_PIN  E26    IOSTANDARD LVDS} [get_ports {tx_data_out_n[2]}]                           ; ## C15  FMC_LPC_LA10_N
set_property  -dict {PACKAGE_PIN  L20    IOSTANDARD LVDS} [get_ports {tx_data_out_p[3]}]                           ; ## C18  FMC_LPC_LA14_P  (AD9361 bit 4)
set_property  -dict {PACKAGE_PIN  K20    IOSTANDARD LVDS} [get_ports {tx_data_out_n[3]}]                           ; ## C19  FMC_LPC_LA14_N
set_property  -dict {PACKAGE_PIN  K21    IOSTANDARD LVDS} [get_ports {tx_data_out_p[4]}]                           ; ## H19  FMC_LPC_LA15_P  (AD9361 bit 5)
set_property  -dict {PACKAGE_PIN  J21    IOSTANDARD LVDS} [get_ports {tx_data_out_n[4]}]                           ; ## H20  FMC_LPC_LA15_N

set_property  -dict {PACKAGE_PIN  L24    IOSTANDARD LVCMOS18} [get_ports enable]                                   ; ## G18  FMC_LPC_LA16_P
set_property  -dict {PACKAGE_PIN  L25    IOSTANDARD LVCMOS18} [get_ports txnrx]                                    ; ## G19  FMC_LPC_LA16_N

set_property  -dict {PACKAGE_PIN  D24    IOSTANDARD LVCMOS18} [get_ports {gpio_status[0]}]                         ; ## G21  FMC_LPC_LA20_P
set_property  -dict {PACKAGE_PIN  D25    IOSTANDARD LVCMOS18} [get_ports {gpio_status[1]}]                         ; ## G22  FMC_LPC_LA20_N
set_property  -dict {PACKAGE_PIN  D23    IOSTANDARD LVCMOS18} [get_ports {gpio_status[2]}]                         ; ## H25  FMC_LPC_LA21_P
set_property  -dict {PACKAGE_PIN  C24    IOSTANDARD LVCMOS18} [get_ports {gpio_status[3]}]                         ; ## H26  FMC_LPC_LA21_N
set_property  -dict {PACKAGE_PIN  B14    IOSTANDARD LVCMOS18} [get_ports {gpio_status[4]}]                         ; ## G24  FMC_LPC_LA22_P  (HD bank 86)
set_property  -dict {PACKAGE_PIN  A14    IOSTANDARD LVCMOS18} [get_ports {gpio_status[5]}]                         ; ## G25  FMC_LPC_LA22_N  (HD bank 86)
set_property  -dict {PACKAGE_PIN  B25    IOSTANDARD LVCMOS18} [get_ports {gpio_status[6]}]                         ; ## D23  FMC_LPC_LA23_P
set_property  -dict {PACKAGE_PIN  B26    IOSTANDARD LVCMOS18} [get_ports {gpio_status[7]}]                         ; ## D24  FMC_LPC_LA23_N
set_property  -dict {PACKAGE_PIN  H23    IOSTANDARD LVCMOS18} [get_ports {gpio_ctl[0]}]                            ; ## H28  FMC_LPC_LA24_P
set_property  -dict {PACKAGE_PIN  H24    IOSTANDARD LVCMOS18} [get_ports {gpio_ctl[1]}]                            ; ## H29  FMC_LPC_LA24_N
set_property  -dict {PACKAGE_PIN  J13    IOSTANDARD LVCMOS18} [get_ports {gpio_ctl[2]}]                            ; ## G27  FMC_LPC_LA25_P  (HD bank 86)
set_property  -dict {PACKAGE_PIN  H13    IOSTANDARD LVCMOS18} [get_ports {gpio_ctl[3]}]                            ; ## G28  FMC_LPC_LA25_N  (HD bank 86)
set_property  -dict {PACKAGE_PIN  F23    IOSTANDARD LVCMOS18} [get_ports gpio_en_agc]                              ; ## H22  FMC_LPC_LA19_P
set_property  -dict {PACKAGE_PIN  E23    IOSTANDARD LVCMOS18} [get_ports gpio_sync]                                ; ## H23  FMC_LPC_LA19_N
set_property  -dict {PACKAGE_PIN  K25    IOSTANDARD LVCMOS18} [get_ports gpio_resetb]                              ; ## H31  FMC_LPC_LA28_P

set_property  -dict {PACKAGE_PIN  L22    IOSTANDARD LVCMOS18  PULLTYPE PULLUP} [get_ports spi_csn_0]               ; ## D26  FMC_LPC_LA26_P
set_property  -dict {PACKAGE_PIN  L23    IOSTANDARD LVCMOS18} [get_ports spi_clk]                                  ; ## D27  FMC_LPC_LA26_N
set_property  -dict {PACKAGE_PIN  J15    IOSTANDARD LVCMOS18} [get_ports spi_mosi]                                 ; ## C26  FMC_LPC_LA27_P  (HD bank 86)
set_property  -dict {PACKAGE_PIN  J14    IOSTANDARD LVCMOS18} [get_ports spi_miso]                                 ; ## C27  FMC_LPC_LA27_N  (HD bank 86)

# System Reset — Active-Low Push Button PB3 (Bank 64/65, VCCO = 1.2V)
# See AUB-15P-DK-UG-V1P6 §5.1.30, Figure 29 — Reset Push Button
# Directly drives the Clock Wizard resetn input; active-low with 4.7K pull-up to VCCO_64_65.

set_property  -dict {PACKAGE_PIN  V19    IOSTANDARD LVCMOS12} [get_ports system_resetn]                               ; ## PB3 SYS_RST_N
set_false_path -from [get_ports system_resetn]

# NEORV32 UART0 — USB-to-UART bridge (U21, Bank 84, LVCMOS18)
# See AUB-15P-DK-UG-V1P6, Table 12 — FPGA to UART Connections

set_property  -dict {PACKAGE_PIN  AF15   IOSTANDARD LVCMOS18} [get_ports sys_uart_tx]                              ; ## UART_TX (FPGA -> U21 FTDI_RX)
set_property  -dict {PACKAGE_PIN  AF14   IOSTANDARD LVCMOS18} [get_ports sys_uart_rx]                              ; ## UART_RX (U21 FTDI_TX -> FPGA)

# Constrain the input 300MHz clock from the Epson ECS oscillator

set_property  -dict {PACKAGE_PIN  AE21   IOSTANDARD DIFF_SSTL12} [get_ports "ecs_clk_in_clk_n"]                    ; ## ecs_clk_in_clk_n  IO_L11N_T1U_N9_GC_64  (HP bank 65)
set_property  -dict {PACKAGE_PIN  AD21   IOSTANDARD DIFF_SSTL12} [get_ports "ecs_clk_in_clk_p"]                    ; ## ecs_clk_in_clk_p  IO_L11P_T1U_N8_GC_64  (HP bank 65)

# clocks

create_clock -name rx_clk       -period  8.0    [get_ports rx_clk_in_p]  ; ## 125 MHz max (LVDS DDR clock)
