###############################################################################
## Copyright (C) 2017-2023 Analog Devices, Inc. All rights reserved.
### SPDX short identifier: ADIBSD
###############################################################################

# constraints
# ad9361 (active FMCOMMS2/3 FMC daughter card on AU15P carrier)

# NOTE: AU15P FMC LA pins span two I/O banks:
#   Bank 66 (HP I/O, VCCO = VADJ = 1.8V) — HP_DP_* pins — supports LVDS + DIFF_TERM_ADV
#   Bank 86 (HD I/O, VCCO = VADJ = 1.8V) — HD_DP_* pins — supports LVDS but NOT DIFF_TERM
#
# Three LVDS signals land on HD bank 86:
#   rx_data_in[5]  (LA07 = J12/H12)  — LVDS input, NO internal termination available
#   tx_clk_out     (LA08 = H14/G14)  — LVDS output, OK
#   tx_data_out[0] (LA11 = E13/E12)  — LVDS output, OK

set_property  -dict {PACKAGE_PIN  F24    IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports rx_clk_in_p]           ; ## G6   FMC_LPC_LA00_CC_P
set_property  -dict {PACKAGE_PIN  F25    IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports rx_clk_in_n]           ; ## G7   FMC_LPC_LA00_CC_N
set_property  -dict {PACKAGE_PIN  J23    IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports rx_frame_in_p]         ; ## D8   FMC_LPC_LA01_CC_P
set_property  -dict {PACKAGE_PIN  J24    IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports rx_frame_in_n]         ; ## D9   FMC_LPC_LA01_CC_N
set_property  -dict {PACKAGE_PIN  H26    IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports rx_data_in_p[0]]       ; ## H7   FMC_LPC_LA02_P
set_property  -dict {PACKAGE_PIN  G26    IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports rx_data_in_n[0]]       ; ## H8   FMC_LPC_LA02_N
set_property  -dict {PACKAGE_PIN  M20    IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports rx_data_in_p[1]]       ; ## G9   FMC_LPC_LA03_P
set_property  -dict {PACKAGE_PIN  M21    IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports rx_data_in_n[1]]       ; ## G10  FMC_LPC_LA03_N
set_property  -dict {PACKAGE_PIN  J19    IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports rx_data_in_p[2]]       ; ## H10  FMC_LPC_LA04_P
set_property  -dict {PACKAGE_PIN  J20    IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports rx_data_in_n[2]]       ; ## H11  FMC_LPC_LA04_N
set_property  -dict {PACKAGE_PIN  M19    IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports rx_data_in_p[3]]       ; ## D11  FMC_LPC_LA05_P
set_property  -dict {PACKAGE_PIN  L19    IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports rx_data_in_n[3]]       ; ## D12  FMC_LPC_LA05_N
set_property  -dict {PACKAGE_PIN  D26    IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports rx_data_in_p[4]]       ; ## C10  FMC_LPC_LA06_P
set_property  -dict {PACKAGE_PIN  C26    IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports rx_data_in_n[4]]       ; ## C11  FMC_LPC_LA06_N
set_property  -dict {PACKAGE_PIN  J12    IOSTANDARD LVDS}                        [get_ports rx_data_in_p[5]]       ; ## H13  FMC_LPC_LA07_P  (HD bank 86 — no DIFF_TERM)
set_property  -dict {PACKAGE_PIN  H12    IOSTANDARD LVDS}                        [get_ports rx_data_in_n[5]]       ; ## H14  FMC_LPC_LA07_N  (HD bank 86 — no DIFF_TERM)
set_property  -dict {PACKAGE_PIN  H14    IOSTANDARD LVDS} [get_ports tx_clk_out_p]                                 ; ## G12  FMC_LPC_LA08_P  (HD bank 86)
set_property  -dict {PACKAGE_PIN  G14    IOSTANDARD LVDS} [get_ports tx_clk_out_n]                                 ; ## G13  FMC_LPC_LA08_N  (HD bank 86)
set_property  -dict {PACKAGE_PIN  H21    IOSTANDARD LVDS} [get_ports tx_frame_out_p]                               ; ## D14  FMC_LPC_LA09_P
set_property  -dict {PACKAGE_PIN  H22    IOSTANDARD LVDS} [get_ports tx_frame_out_n]                               ; ## D15  FMC_LPC_LA09_N
set_property  -dict {PACKAGE_PIN  E13    IOSTANDARD LVDS} [get_ports tx_data_out_p[0]]                             ; ## H16  FMC_LPC_LA11_P  (HD bank 86)
set_property  -dict {PACKAGE_PIN  E12    IOSTANDARD LVDS} [get_ports tx_data_out_n[0]]                             ; ## H17  FMC_LPC_LA11_N  (HD bank 86)
set_property  -dict {PACKAGE_PIN  L18    IOSTANDARD LVDS} [get_ports tx_data_out_p[1]]                             ; ## G15  FMC_LPC_LA12_P
set_property  -dict {PACKAGE_PIN  K18    IOSTANDARD LVDS} [get_ports tx_data_out_n[1]]                             ; ## G16  FMC_LPC_LA12_N
set_property  -dict {PACKAGE_PIN  K22    IOSTANDARD LVDS} [get_ports tx_data_out_p[2]]                             ; ## D17  FMC_LPC_LA13_P
set_property  -dict {PACKAGE_PIN  K23    IOSTANDARD LVDS} [get_ports tx_data_out_n[2]]                             ; ## D18  FMC_LPC_LA13_N
set_property  -dict {PACKAGE_PIN  E25    IOSTANDARD LVDS} [get_ports tx_data_out_p[3]]                             ; ## C14  FMC_LPC_LA10_P
set_property  -dict {PACKAGE_PIN  E26    IOSTANDARD LVDS} [get_ports tx_data_out_n[3]]                             ; ## C15  FMC_LPC_LA10_N
set_property  -dict {PACKAGE_PIN  L20    IOSTANDARD LVDS} [get_ports tx_data_out_p[4]]                             ; ## C18  FMC_LPC_LA14_P
set_property  -dict {PACKAGE_PIN  K20    IOSTANDARD LVDS} [get_ports tx_data_out_n[4]]                             ; ## C19  FMC_LPC_LA14_N
set_property  -dict {PACKAGE_PIN  K21    IOSTANDARD LVDS} [get_ports tx_data_out_p[5]]                             ; ## H19  FMC_LPC_LA15_P
set_property  -dict {PACKAGE_PIN  J21    IOSTANDARD LVDS} [get_ports tx_data_out_n[5]]                             ; ## H20  FMC_LPC_LA15_N

set_property  -dict {PACKAGE_PIN  L24    IOSTANDARD LVCMOS18} [get_ports enable]                                   ; ## G18  FMC_LPC_LA16_P
set_property  -dict {PACKAGE_PIN  L25    IOSTANDARD LVCMOS18} [get_ports txnrx]                                    ; ## G19  FMC_LPC_LA16_N

set_property  -dict {PACKAGE_PIN  D24    IOSTANDARD LVCMOS18} [get_ports gpio_status[0]]                           ; ## G21  FMC_LPC_LA20_P
set_property  -dict {PACKAGE_PIN  D25    IOSTANDARD LVCMOS18} [get_ports gpio_status[1]]                           ; ## G22  FMC_LPC_LA20_N
set_property  -dict {PACKAGE_PIN  D23    IOSTANDARD LVCMOS18} [get_ports gpio_status[2]]                           ; ## H25  FMC_LPC_LA21_P
set_property  -dict {PACKAGE_PIN  C24    IOSTANDARD LVCMOS18} [get_ports gpio_status[3]]                           ; ## H26  FMC_LPC_LA21_N
set_property  -dict {PACKAGE_PIN  B14    IOSTANDARD LVCMOS18} [get_ports gpio_status[4]]                           ; ## G24  FMC_LPC_LA22_P  (HD bank 86)
set_property  -dict {PACKAGE_PIN  A14    IOSTANDARD LVCMOS18} [get_ports gpio_status[5]]                           ; ## G25  FMC_LPC_LA22_N  (HD bank 86)
set_property  -dict {PACKAGE_PIN  B25    IOSTANDARD LVCMOS18} [get_ports gpio_status[6]]                           ; ## D23  FMC_LPC_LA23_P
set_property  -dict {PACKAGE_PIN  B26    IOSTANDARD LVCMOS18} [get_ports gpio_status[7]]                           ; ## D24  FMC_LPC_LA23_N
set_property  -dict {PACKAGE_PIN  H23    IOSTANDARD LVCMOS18} [get_ports gpio_ctl[0]]                              ; ## H28  FMC_LPC_LA24_P
set_property  -dict {PACKAGE_PIN  H24    IOSTANDARD LVCMOS18} [get_ports gpio_ctl[1]]                              ; ## H29  FMC_LPC_LA24_N
set_property  -dict {PACKAGE_PIN  J13    IOSTANDARD LVCMOS18} [get_ports gpio_ctl[2]]                              ; ## G27  FMC_LPC_LA25_P  (HD bank 86)
set_property  -dict {PACKAGE_PIN  H13    IOSTANDARD LVCMOS18} [get_ports gpio_ctl[3]]                              ; ## G28  FMC_LPC_LA25_N  (HD bank 86)
set_property  -dict {PACKAGE_PIN  F23    IOSTANDARD LVCMOS18} [get_ports gpio_en_agc]                              ; ## H22  FMC_LPC_LA19_P
set_property  -dict {PACKAGE_PIN  E23    IOSTANDARD LVCMOS18} [get_ports gpio_sync]                                ; ## H23  FMC_LPC_LA19_N
set_property  -dict {PACKAGE_PIN  K25    IOSTANDARD LVCMOS18} [get_ports gpio_resetb]                              ; ## H31  FMC_LPC_LA28_P

set_property  -dict {PACKAGE_PIN  L22    IOSTANDARD LVCMOS18  PULLTYPE PULLUP} [get_ports spi_csn_0]               ; ## D26  FMC_LPC_LA26_P
set_property  -dict {PACKAGE_PIN  L23    IOSTANDARD LVCMOS18} [get_ports spi_clk]                                  ; ## D27  FMC_LPC_LA26_N
set_property  -dict {PACKAGE_PIN  J15    IOSTANDARD LVCMOS18} [get_ports spi_mosi]                                 ; ## C26  FMC_LPC_LA27_P  (HD bank 86)
set_property  -dict {PACKAGE_PIN  J14    IOSTANDARD LVCMOS18} [get_ports spi_miso]                                 ; ## C27  FMC_LPC_LA27_N  (HD bank 86)

# clocks

create_clock -name rx_clk       -period  4.00 [get_ports rx_clk_in_p]
