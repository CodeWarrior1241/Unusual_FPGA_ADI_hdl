###############################################################################
## Copyright (C) 2017-2025 Analog Devices, Inc. All rights reserved.
### SPDX short identifier: ADIBSD
###############################################################################
#
# FMCOMMS2/4 on Avnet AU15P
#
# This design uses NEORV32 RISC-V softcore (not MicroBlaze)
# No DDR/MIG is used - design runs from internal BRAM
#
###############################################################################

source $ad_hdl_dir/projects/common/au15p/au15p_system_bd.tcl
source ../common/fmcomms2_bd.tcl
source $ad_hdl_dir/projects/scripts/adi_pd.tcl

#system ID
ad_ip_parameter axi_sysid_0 CONFIG.ROM_ADDR_BITS 9
ad_ip_parameter rom_sys_0 CONFIG.PATH_TO_FILE "$mem_init_sys_file_path/mem_init_sys.txt"
ad_ip_parameter rom_sys_0 CONFIG.ROM_ADDR_BITS 9

sysid_gen_sys_init_file

# UltraScale+ device settings
ad_ip_parameter util_ad9361_divclk CONFIG.SIM_DEVICE ULTRASCALE

# ADC initialization delay - may need tuning for AU15P
ad_ip_parameter axi_ad9361 CONFIG.ADC_INIT_DELAY 11
