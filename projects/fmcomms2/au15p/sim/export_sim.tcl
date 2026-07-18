# Export Vivado simulation scripts for Questa
# Run from Vivado Tcl console:  source /path/to/sim/export_sim.tcl

set proj_dir [file normalize [file join [file dirname [info script]] ..]]
set proj_file [file join $proj_dir fmcomms2_au15p.xpr]

if {![file exists $proj_file]} {
    puts "ERROR: Vivado project not found at $proj_file"
    puts "       Build the project first via build_all.tcl"
    return
}

open_project $proj_file

export_simulation \
    -simulator questa \
    -ip_user_files_dir [file join $proj_dir fmcomms2_au15p.ip_user_files] \
    -directory [file join $proj_dir fmcomms2_au15p.ip_user_files sim_scripts] \
    -force

puts "INFO: Questa simulation scripts exported to:"
puts "      $proj_dir/fmcomms2_au15p.ip_user_files/sim_scripts/questa/"

close_project
