set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ".."]]

if {[llength [get_projects -quiet]] == 0} {
    error "Open the Vivado project before sourcing this script."
}

if {[llength [get_filesets -quiet sources_1]] == 0} {
    error "sources_1 fileset not found."
}

proc remove_files_from_fileset {fileset_name} {
    if {[llength [get_filesets -quiet $fileset_name]] == 0} {
        return
    }

    set files [get_files -quiet -of_objects [get_filesets $fileset_name]]
    if {[llength $files] != 0} {
        remove_files $files
    }
}

remove_files_from_fileset sources_1
remove_files_from_fileset constrs_1
remove_files_from_fileset sim_1

source [file join $script_dir vivado_import.tcl]

puts "MiniCPU Vivado project reset and re-imported from:"
puts "  $repo_root"
