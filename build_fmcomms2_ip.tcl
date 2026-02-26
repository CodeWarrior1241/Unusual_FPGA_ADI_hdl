###############################################################################
## ADI FMCOMMS2/3 IP Builder for Vivado
##
## This script builds all ADI IP cores required for FMCOMMS2/3 designs and
## copies them to a local directory for use in your Vivado project.
##
## Usage (from Vivado TCL console):
##   source <path_to_this_script>/build_fmcomms2_ip.tcl
##   build_adi_fmcomms2_ip <target_directory> [force_rebuild]
##
## Arguments:
##   target_directory  - Directory where adi_fmcomms2_ip folder will be created
##   force_rebuild     - Optional: set to 1 to force rebuild of all IP even if
##                       component.xml already exists (default: 0)
##
## Examples:
##   # Normal build (skips already-built IP):
##   source C:/Work/deps/hdl/build_fmcomms2_ip.tcl
##   build_adi_fmcomms2_ip "C:/my_project"
##
##   # Force rebuild all IP:
##   source C:/Work/deps/hdl/build_fmcomms2_ip.tcl
##   build_adi_fmcomms2_ip "C:/my_project" 1
##
## The script will:
##   1. Build all required IP cores in the ADI hdl/library directory
##      (skips if already built, unless force_rebuild=1)
##   2. Copy the entire library directory structure to <target_dir>/adi_fmcomms2_ip
##   3. Add the IP repository path to the current project (if one is open)
##
## Based on LIB_DEPS from: projects/fmcomms2/kcu105/Makefile
###############################################################################

# Get the directory where this script is located
set script_dir [file dirname [file normalize [info script]]]

# Define the ADI HDL directory (this script should be in deps/hdl/)
set ad_hdl_dir [file normalize $script_dir]

# NOTE: We intentionally do NOT source adi_env.tcl at load time.
# The individual IP _ip.tcl scripts source it themselves when called.
# This avoids potential issues with version checks at script load time.

# Skip Vivado version checking - allows use with any Vivado version
set IGNORE_VERSION_CHECK 1

# Set required_vivado_version to satisfy adi_ip_xilinx.tcl global variable reference
# This value doesn't matter when IGNORE_VERSION_CHECK=1, but must exist
set required_vivado_version "any"

# Set VIVADO_IP_LIBRARY - used by adi_ip_xilinx.tcl for IP vendor library name
# Default is "user" per adi_ip_xilinx.tcl, can be overridden via ADI_VIVADO_IP_LIBRARY env var
if {[info exists ::env(ADI_VIVADO_IP_LIBRARY)]} {
    set VIVADO_IP_LIBRARY $::env(ADI_VIVADO_IP_LIBRARY)
} else {
    set VIVADO_IP_LIBRARY "user"
}

# Source the device info encoding script to define fpga_technology_list and other variables
# These are needed by adi_ip_xilinx.tcl procedures
source $ad_hdl_dir/library/scripts/adi_xilinx_device_info_enc.tcl

# List of IP libraries required for FMCOMMS2/3 (from project Makefile LIB_DEPS)
# These are in dependency order (dependencies first)
set fmcomms2_lib_deps {
    util_cdc
    util_axis_fifo
    axi_ad9361
    axi_dmac
    axi_sysid
    sysid_rom
    util_pack/util_cpack2
    util_pack/util_upack2
    util_rfifo
    util_tdd_sync
    util_wfifo
    xilinx/util_clkdiv
}

# Interface definitions that need to be built
set fmcomms2_interface_deps {
    interfaces
    axi_dmac/interfaces
}

###############################################################################
# Procedure: build_single_ip
# Builds a single IP library by sourcing its _ip.tcl script
# NOTE: IP is built serially (one at a time) to match original Makefile behavior
###############################################################################
proc build_single_ip {lib_path lib_name} {
    global ad_hdl_dir
    global IGNORE_VERSION_CHECK
    global required_vivado_version
    global VIVADO_IP_LIBRARY

    set ip_tcl_file "$lib_path/${lib_name}_ip.tcl"

    if {![file exists $ip_tcl_file]} {
        puts "WARNING: IP TCL file not found: $ip_tcl_file"
        return 0
    }

    puts "=========================================="
    puts "Building IP: $lib_name"
    puts "=========================================="

    # Save current directory
    set orig_dir [pwd]

    # Change to library directory for build
    cd $lib_path

    # Source the IP build script
    if {[catch {source $ip_tcl_file} err]} {
        puts "ERROR building $lib_name: $err"
        # Close any project that may have been opened
        catch {close_project}
        cd $orig_dir
        return 0
    }

    # Close the project to ensure it's fully complete before moving on
    # The ADI IP scripts create a project but don't close it
    if {![catch {current_project}]} {
        puts "Closing project for $lib_name..."
        close_project
    }

    # Return to original directory
    cd $orig_dir

    # Verify component.xml was created
    if {[file exists "$lib_path/component.xml"]} {
        puts "SUCCESS: $lib_name built successfully"
        return 1
    } else {
        puts "WARNING: component.xml not found after building $lib_name"
        return 0
    }
}

###############################################################################
# Procedure: build_interfaces
# Builds interface definitions
# NOTE: Interfaces are built serially to match original Makefile behavior
###############################################################################
proc build_interfaces {intf_path} {
    global ad_hdl_dir
    global IGNORE_VERSION_CHECK
    global required_vivado_version
    global VIVADO_IP_LIBRARY

    set intf_tcl_file "$intf_path/interfaces_ip.tcl"

    if {![file exists $intf_tcl_file]} {
        puts "WARNING: Interface TCL file not found: $intf_tcl_file"
        return 0
    }

    puts "=========================================="
    puts "Building interfaces in: $intf_path"
    puts "=========================================="

    # Save current directory
    set orig_dir [pwd]

    # Change to interface directory
    cd $intf_path

    # Source the interface build script
    if {[catch {source $intf_tcl_file} err]} {
        puts "ERROR building interfaces: $err"
        # Close any project that may have been opened
        catch {close_project}
        cd $orig_dir
        return 0
    }

    # Close any project that may have been opened during interface build
    if {![catch {current_project}]} {
        puts "Closing project after interface build..."
        close_project
    }

    cd $orig_dir
    puts "SUCCESS: Interfaces built"
    return 1
}

###############################################################################
# Procedure: copy_directory_recursive
# Recursively copies directory contents, excluding build artifacts
###############################################################################
proc copy_directory_recursive {src dst {exclude_patterns {}}} {
    # Default patterns to exclude (build artifacts)
    set default_excludes {
        "*.cache" "*.data" "*.xpr" "*.runs" "*.hw" "*.sim"
        "*.ip_user_files" "*.gen" ".Xil" "*.log" "*.jou"
        ".lock" "*.str" "work" "transcript" "modelsim.ini"
    }

    set excludes [concat $default_excludes $exclude_patterns]

    file mkdir $dst

    foreach item [glob -nocomplain -directory $src *] {
        set name [file tail $item]
        set dst_item "$dst/$name"

        # Check if should be excluded
        set skip 0
        foreach pattern $excludes {
            if {[string match $pattern $name]} {
                set skip 1
                break
            }
        }

        if {$skip} {
            continue
        }

        if {[file isdirectory $item]} {
            copy_directory_recursive $item $dst_item $exclude_patterns
        } else {
            file copy -force $item $dst_item
        }
    }
}

###############################################################################
# Main Procedure: build_adi_fmcomms2_ip
# Builds all FMCOMMS2 IP and copies to target directory
# Arguments:
#   target_base_dir - Directory where adi_fmcomms2_ip folder will be created
#   force_rebuild   - Optional: set to 1 to force rebuild all IP (default: 0)
###############################################################################
proc build_adi_fmcomms2_ip {target_base_dir {force_rebuild 0}} {
    global ad_hdl_dir
    global fmcomms2_lib_deps
    global fmcomms2_interface_deps

    set target_dir [file normalize "$target_base_dir/adi_fmcomms2_ip"]
    set library_src "$ad_hdl_dir/library"
    set library_dst "$target_dir/library"
    set scripts_dst "$target_dir/scripts"

    puts "============================================================"
    puts "ADI FMCOMMS2/3 IP Builder"
    puts "============================================================"
    puts "ADI HDL Directory: $ad_hdl_dir"
    puts "Target Directory:  $target_dir"
    puts "Force Rebuild:     [expr {$force_rebuild ? "YES" : "NO"}]"
    puts "============================================================"

    # Build interfaces first (if not already built or force rebuild)
    # NOTE: Each interface set is built serially (one at a time) to avoid conflicts
    puts "\n>>> Checking/Building interface definitions (serial)..."
    foreach intf $fmcomms2_interface_deps {
        set intf_path "$library_src/$intf"
        if {[file exists $intf_path]} {
            # Check if already built by looking for .xml files
            set xml_files [glob -nocomplain "$intf_path/*.xml"]
            if {$force_rebuild || [llength $xml_files] == 0} {
                if {$force_rebuild && [llength $xml_files] > 0} {
                    puts "Force rebuilding interfaces in $intf..."
                }
                build_interfaces $intf_path
            } else {
                puts "Interfaces in $intf already built, skipping"
            }
        }
    }

    # Build each IP library (if not already built or force rebuild)
    # NOTE: Each IP is built serially (one at a time) to match original Makefile behavior
    puts "\n>>> Checking/Building IP libraries (serial)..."
    set success_count 0
    set fail_count 0
    set failed_ips {}

    foreach lib $fmcomms2_lib_deps {
        set lib_path "$library_src/$lib"
        set lib_name [file tail $lib]

        if {![file exists $lib_path]} {
            puts "ERROR: Library path not found: $lib_path"
            incr fail_count
            lappend failed_ips $lib
            continue
        }

        # Check if already built (skip if exists and not forcing rebuild)
        if {[file exists "$lib_path/component.xml"] && !$force_rebuild} {
            puts "IP $lib_name already built, skipping build step"
            incr success_count
        } else {
            if {$force_rebuild && [file exists "$lib_path/component.xml"]} {
                puts "Force rebuilding $lib_name..."
            }
            if {[build_single_ip $lib_path $lib_name]} {
                incr success_count
            } else {
                incr fail_count
                lappend failed_ips $lib
            }
        }
    }

    # Copy library directory structure to target
    puts "\n>>> Copying library to target directory..."
    puts "This preserves the directory structure needed by component.xml references"

    # Create target directory structure
    file mkdir $target_dir
    file mkdir $library_dst

    # Copy common directory (needed by all IPs for relative paths)
    puts "Copying common..."
    copy_directory_recursive "$library_src/common" "$library_dst/common"

    # Copy xilinx/common (Xilinx-specific common files)
    puts "Copying xilinx/common..."
    file mkdir "$library_dst/xilinx"
    copy_directory_recursive "$library_src/xilinx/common" "$library_dst/xilinx/common"

    # Copy interfaces
    puts "Copying interfaces..."
    copy_directory_recursive "$library_src/interfaces" "$library_dst/interfaces"

    # Copy each required IP library
    foreach lib $fmcomms2_lib_deps {
        set lib_path "$library_src/$lib"
        set lib_name [file tail $lib]

        if {[file exists "$lib_path/component.xml"]} {
            puts "Copying $lib..."

            # Handle nested paths (e.g., util_pack/util_cpack2, xilinx/util_clkdiv)
            if {[string match "*/*" $lib]} {
                set parent_dir [file dirname $lib]
                file mkdir "$library_dst/$parent_dir"
            }

            copy_directory_recursive $lib_path "$library_dst/$lib"
        } else {
            puts "WARNING: Skipping $lib (no component.xml)"
        }
    }

    # Copy axi_dmac/interfaces (special case - nested interface)
    if {[file exists "$library_src/axi_dmac/interfaces"]} {
        puts "Copying axi_dmac/interfaces..."
        file mkdir "$library_dst/axi_dmac"
        copy_directory_recursive "$library_src/axi_dmac/interfaces" "$library_dst/axi_dmac/interfaces"
    }

    # Copy util_pack common files (needed by cpack2/upack2)
    if {[file exists "$library_src/util_pack/util_pack_common"]} {
        puts "Copying util_pack/util_pack_common..."
        copy_directory_recursive "$library_src/util_pack/util_pack_common" "$library_dst/util_pack/util_pack_common"
    }

    # Copy required scripts
    puts "Copying scripts..."
    file mkdir $scripts_dst
    foreach script {adi_env.tcl} {
        set src "$ad_hdl_dir/scripts/$script"
        if {[file exists $src]} {
            file copy -force $src "$scripts_dst/"
        }
    }

    # Copy library scripts
    file mkdir "$library_dst/scripts"
    foreach script {adi_ip_xilinx.tcl adi_xilinx_device_info_enc.tcl} {
        set src "$library_src/scripts/$script"
        if {[file exists $src]} {
            file copy -force $src "$library_dst/scripts/"
        }
    }

    # Summary
    puts "\n============================================================"
    puts "Build Summary"
    puts "============================================================"
    puts "IP libraries processed successfully: $success_count"
    puts "IP libraries failed: $fail_count"
    if {[llength $failed_ips] > 0} {
        puts ""
        puts "Failed IP libraries:"
        foreach failed_ip $failed_ips {
            puts "  - $failed_ip"
        }
    }
    puts ""
    puts "Target directory: $target_dir"
    puts ""
    puts "Directory structure:"
    puts "  $target_dir/"
    puts "    library/           <- Add this to ip_repo_paths"
    puts "      common/"
    puts "      xilinx/common/"
    puts "      interfaces/"
    puts "      axi_ad9361/"
    puts "      axi_dmac/"
    puts "      ... (other IPs)"
    puts "============================================================"

    # Add to current project if one is open
    if {[catch {current_project} proj]} {
        puts "\nNo project open. To use the IP in your project, add this path"
        puts "to your project's ip_repo_paths property:"
        puts ""
        puts "  set_property ip_repo_paths \[list \"$library_dst\"\] \[current_project\]"
        puts "  update_ip_catalog"
    } else {
        puts "\nAdding IP repository to current project..."
        set current_repos [get_property ip_repo_paths [current_project]]
        if {[lsearch -exact $current_repos $library_dst] == -1} {
            lappend current_repos $library_dst
            set_property ip_repo_paths $current_repos [current_project]
            update_ip_catalog
            puts "IP repository added and catalog updated."
        } else {
            puts "IP repository already in project."
        }
    }

    puts "\nDone!"
    return $target_dir
}

###############################################################################
# Procedure: add_adi_ip_repo
# Adds an existing ADI IP repository to the current project without rebuilding
###############################################################################
proc add_adi_ip_repo {ip_repo_path} {
    # Normalize the path
    set ip_repo_path [file normalize $ip_repo_path]

    # Check if this is the adi_fmcomms2_ip directory or the library subdirectory
    if {[file exists "$ip_repo_path/library"]} {
        set ip_repo_path "$ip_repo_path/library"
    }

    if {[catch {current_project} proj]} {
        puts "ERROR: No project open."
        return
    }

    set current_repos [get_property ip_repo_paths [current_project]]
    if {[lsearch -exact $current_repos $ip_repo_path] == -1} {
        lappend current_repos $ip_repo_path
        set_property ip_repo_paths $current_repos [current_project]
        update_ip_catalog
        puts "IP repository $ip_repo_path added to project."
    } else {
        puts "IP repository $ip_repo_path already in project."
    }
}

###############################################################################
# Startup message
###############################################################################
puts "============================================================"
puts "ADI FMCOMMS2/3 IP Builder loaded"
puts "============================================================"
puts "Available commands:"
puts "  build_adi_fmcomms2_ip <target_dir> \[force\]"
puts "      Build and copy all IP to target directory"
puts "      force = 1 to rebuild even if already built (default: 0)"
puts ""
puts "  add_adi_ip_repo <ip_repo_path>"
puts "      Add existing repo to current project"
puts ""
puts "Examples:"
puts "  build_adi_fmcomms2_ip \"C:/my_project\""
puts "  build_adi_fmcomms2_ip \"C:/my_project\" 1  ;# force rebuild"
puts ""
puts "The script auto-detected ADI HDL at:"
puts "  $ad_hdl_dir"
puts "============================================================"
