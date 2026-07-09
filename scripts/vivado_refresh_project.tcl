set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ".."]]

set xdc_file [file join $repo_root constraints/minisys_fight_constraint.xdc]
set program_file [file join $repo_root mem/program.hex]
set csr_test_file [file join $repo_root mem/csr_test.hex]
set smoke_file [file join $repo_root mem/smoke.hex]
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

foreach mem_file [list $program_file $csr_test_file $smoke_file $rom_file $ram_file] {
    if {[llength [get_files -quiet $mem_file]] == 0} {
        add_files -norecurse $mem_file
    }
}

set_property include_dirs [file join $repo_root include] [current_fileset]
set_property top RV32I46F5SPMMIOSoCTOP [current_fileset]

if {[llength [get_filesets -quiet sim_1]] != 0} {
    foreach sim_file [list \
        [file join $repo_root sim/tb_selfcheck.v] \
        [file join $repo_root sim/tb_csr.v] \
        [file join $repo_root sim/tb_cpu_smoke.v] \
        [file join $repo_root sim/tb_min.v] \
    ] {
        if {[llength [get_files -quiet $sim_file]] == 0} {
            add_files -fileset sim_1 -norecurse $sim_file
        }
    }
    set_property top tb_selfcheck [get_filesets sim_1]
    update_compile_order -fileset sim_1
}

update_compile_order -fileset sources_1
puts "MiniCPU Vivado project refreshed."
puts "XDC: $xdc_file"
puts "Program ROM: $program_file"
