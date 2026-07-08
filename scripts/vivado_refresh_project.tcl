set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ".."]]

set xdc_file [file join $repo_root constraints/minisys_fight_constraint.xdc]
set rom_file [file join $repo_root mem/rom_init.mem]
set ram_file [file join $repo_root mem/initial_data.mem]

if {[llength [get_filesets -quiet sources_1]] == 0} {
    error "sources_1 fileset not found. Open the Vivado project before sourcing this script."
}

if {[llength [get_filesets -quiet constrs_1]] == 0} {
    create_fileset -constrset constrs_1
}

if {[llength [get_files -quiet $xdc_file]] == 0} {
    add_files -fileset constrs_1 -norecurse $xdc_file
}
set_property used_in_synthesis true [get_files $xdc_file]
set_property used_in_implementation true [get_files $xdc_file]

foreach mem_file [list $rom_file $ram_file] {
    if {[llength [get_files -quiet $mem_file]] == 0} {
        add_files -norecurse $mem_file
    }
    if {[llength [get_files -quiet $mem_file]] != 0} {
        set_property used_in_synthesis true [get_files $mem_file]
        set_property used_in_simulation true [get_files $mem_file]
    }
}

set_property include_dirs [file join $repo_root include] [current_fileset]
set_property top RV32I46F5SPMMIOSoCTOP [current_fileset]

if {[llength [get_filesets -quiet sim_1]] != 0} {
    set_property top tb_cpu_smoke [get_filesets sim_1]
    update_compile_order -fileset sim_1
}

update_compile_order -fileset sources_1
puts "MiniCPU Vivado project refreshed."
puts "XDC: $xdc_file"
puts "ROM: $rom_file"
