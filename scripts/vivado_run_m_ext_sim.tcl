set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ".."]]
set result_file [file join $repo_root vivado_project/MiniCPU/MiniCPU.sim/sim_1/behav/xsim/m_ext_result.txt]

source [file join $script_dir vivado_refresh_project.tcl]

set_property top tb_m_ext [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
update_compile_order -fileset sim_1

launch_simulation
run all

if {[file exists $result_file]} {
    set fp [open $result_file r]
    set result_text [read $fp]
    close $fp
    puts "RV32M focused simulation result:"
    puts $result_text
} else {
    puts "RV32M focused simulation finished, but result file was not found:"
    puts $result_file
}
