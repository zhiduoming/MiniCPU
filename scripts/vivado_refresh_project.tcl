set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ".."]]
set game_root [file normalize [file join $repo_root vendor/game/sources_1]]

set xdc_file [file join $repo_root constraints/minisys_fight_constraint.xdc]
set program_file [file join $repo_root mem/program.hex]
set m_ext_test_file [file join $repo_root mem/m_ext_test.hex]
set csr_test_file [file join $repo_root mem/csr_test.hex]
set smoke_file [file join $repo_root mem/smoke.hex]
set rom_file [file join $repo_root mem/rom_init.mem]
set ram_file [file join $repo_root mem/initial_data.mem]

set rtl_files [list \
    [file join $repo_root rtl/top/46F5SP_MMIO_SoC_TOP.v] \
    [file join $repo_root rtl/top/RV32I46F_5SP_MMIO.v] \
    [file join $repo_root rtl/vga/VGA_Test_Pattern.v] \
    [file join $repo_root rtl/game/Game_Static_Renderer.v] \
    [file join $repo_root rtl/game/Game_Audio.v] \
    [file join $repo_root rtl/game/Menu_Theme_Player.v] \
    [file join $repo_root rtl/game/Buzzer_Track_Player.v] \
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
    [file join $repo_root rtl/perf/PerfMon.v] \
    [file join $repo_root rtl/perf/IntDiv.v] \
    [file join $repo_root rtl/uart/UART_TX.v] \
    [file join $game_root new/keyboard_4x4_scan.v] \
    [file join $game_root new/key_debounce_5ch.v] \
    [file join $game_root new/music_player.v] \
]

set game_asset_files [list \
    [file join $game_root new/video_draw.v] \
    [file join $game_root ip/background_rom/background_rom.xci] \
    [file join $game_root ip/p1_sprite_rom/p1_sprite_rom.xci] \
    [file join $game_root ip/p2_sprite_rom/p2_sprite_rom.xci] \
    [file join $game_root ip/medicine_rom/medicine_rom.xci] \
    [file join $game_root ip/system_rom/system_rom.xci] \
    [file join $game_root bg_pixels.coe] \
    [file join $game_root p1_sprite.coe] \
    [file join $game_root p2_sprite.coe] \
    [file join $game_root medicine.coe] \
    [file join $game_root system_pixels.coe] \
]

if {[llength [get_filesets -quiet sources_1]] == 0} {
    error "sources_1 fileset not found. Open the Vivado project before sourcing this script."
}

if {[llength [get_filesets -quiet constrs_1]] == 0} {
    create_fileset -constrset constrs_1
}

if {[llength [get_files -quiet $xdc_file]] == 0} {
    add_files -fileset constrs_1 -norecurse [list $xdc_file]
}
set_property used_in_synthesis true [get_files [list $xdc_file]]
set_property used_in_implementation true [get_files [list $xdc_file]]

foreach mem_file [list $program_file $m_ext_test_file $csr_test_file $smoke_file $rom_file $ram_file] {
    if {[llength [get_files -quiet $mem_file]] == 0} {
        add_files -norecurse $mem_file
    }
}

foreach rtl_file $rtl_files {
    if {[llength [get_files -quiet $rtl_file]] == 0} {
        add_files -norecurse $rtl_file
    }
}

foreach game_asset_file $game_asset_files {
    if {[llength [get_files -quiet $game_asset_file]] == 0} {
        add_files -norecurse $game_asset_file
    }
}

set_property include_dirs [file join $repo_root include] [get_filesets sources_1]
set_property top RV32I46F5SPMMIOSoCTOP [get_filesets sources_1]
set_property generic [list "ROM_INIT_FILE=$program_file"] [get_filesets sources_1]

if {[llength [get_filesets -quiet sim_1]] != 0} {
    foreach sim_file [list \
        [file join $repo_root sim/tb_selfcheck.v] \
        [file join $repo_root sim/tb_m_ext.v] \
        [file join $repo_root sim/tb_csr.v] \
        [file join $repo_root sim/tb_cpu_smoke.v] \
        [file join $repo_root sim/tb_min.v] \
    ] {
        if {[llength [get_files -quiet $sim_file]] == 0} {
            add_files -fileset sim_1 -norecurse $sim_file
        }
    }
    set_property verilog_define [list "M_EXT_ROM_FILE=\"$m_ext_test_file\""] [get_filesets sim_1]
    set_property top tb_selfcheck [get_filesets sim_1]
    update_compile_order -fileset sim_1
}

update_compile_order -fileset sources_1
puts "MiniCPU Vivado project refreshed."
puts "XDC: $xdc_file"
puts "Program ROM: $program_file"
puts "RV32M focused ROM: $m_ext_test_file"
