set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ".."]]

set rtl_files [list \
    [file join $repo_root rtl/top/46F5SP_MMIO_SoC_TOP.v] \
    [file join $repo_root rtl/top/RV32I46F_5SP_MMIO.v] \
    [file join $repo_root rtl/core/ALU.v] \
    [file join $repo_root rtl/core/ALU_Controller.v] \
    [file join $repo_root rtl/core/Branch_Logic.v] \
    [file join $repo_root rtl/core/Branch_Predictor.v] \
    [file join $repo_root rtl/core/Byte_Enable_Logic.v] \
    [file join $repo_root rtl/core/Control_Unit.v] \
    [file join $repo_root rtl/core/CSR_File.v] \
    [file join $repo_root rtl/core/Exception_Detector.v] \
    [file join $repo_root rtl/core/Forward_Unit.v] \
    [file join $repo_root rtl/core/Hazard_Unit.v] \
    [file join $repo_root rtl/core/Immediate_Generator.v] \
    [file join $repo_root rtl/core/Instruction_Decoder.v] \
    [file join $repo_root rtl/core/PC_Aligner.v] \
    [file join $repo_root rtl/core/PC_Controller.v] \
    [file join $repo_root rtl/core/PC_Plus_4.v] \
    [file join $repo_root rtl/core/Program_Counter.v] \
    [file join $repo_root rtl/core/Register_File.v] \
    [file join $repo_root rtl/core/Trap_Controller.v] \
    [file join $repo_root rtl/pipeline/IF_ID_Register.v] \
    [file join $repo_root rtl/pipeline/ID_EX_Register.v] \
    [file join $repo_root rtl/pipeline/EX_MEM_Register.v] \
    [file join $repo_root rtl/pipeline/MEM_WB_Register.v] \
    [file join $repo_root rtl/memory/Data_Memory.v] \
    [file join $repo_root rtl/memory/Instruction_Cache.v] \
    [file join $repo_root rtl/memory/Instruction_Memory.v] \
    [file join $repo_root rtl/mmio/Button_Controller.v] \
    [file join $repo_root rtl/mmio/Debug_UART_Controller.v] \
    [file join $repo_root rtl/mmio/MMIO_Interface.v] \
    [file join $repo_root rtl/mmio/Unified_UART_Controller.v] \
    [file join $repo_root rtl/uart/UART_TX.v] \
]

add_files -norecurse $rtl_files
set_property include_dirs [file join $repo_root include] [current_fileset]
set_property top RV32I46F5SPMMIOSoCTOP [current_fileset]

add_files -fileset sim_1 -norecurse [file join $repo_root sim/tb_cpu_smoke.v]
set_property top tb_cpu_smoke [get_filesets sim_1]

set xdc_file [file join $repo_root constraints/minisys_fight_constraint.xdc]
add_files -fileset constrs_1 -norecurse $xdc_file
set_property used_in_synthesis true [get_files $xdc_file]
set_property used_in_implementation true [get_files $xdc_file]

set mem_files [list \
    [file join $repo_root mem/rom_init.mem] \
    [file join $repo_root mem/initial_data.mem] \
]
add_files -norecurse $mem_files
foreach mem_file $mem_files {
    set_property file_type {Memory Initialization Files} [get_files $mem_file]
    set_property used_in_synthesis true [get_files $mem_file]
    set_property used_in_simulation true [get_files $mem_file]
}

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
