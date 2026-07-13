set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ".."]]
set check_dir [file join $repo_root .portable_import_check]
create_project portable_import_check $check_dir -part xc7a100tfgg484-1 -force
source [file join $script_dir vivado_import.tcl]
set top_name [get_property top [get_filesets sources_1]]
set generic_value [get_property generic [get_filesets sources_1]]
puts "PORTABLE_TOP=$top_name"
puts "PORTABLE_GENERIC=$generic_value"
puts "PORTABLE_SOURCE_COUNT=[llength [get_files -of_objects [get_filesets sources_1]]]"
close_project
