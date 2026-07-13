// ============================================================
// ???46F5SP_MMIO_SoC_TOP.v
// ???????????????????????
//       SW0 = ???? (1=??, 0=??)
//       SW8 = ???? (0=??, 1=??)
//       SW9 = ???? (???????????????????)
//       LED???
//         - RLED[7:5] = funct3[2:0]???[14:12]?
//         - RLED[4:0] = opcode[6:2]?OPCODE?5??
//         - YLED[7:6] = opcode[1:0]?OPCODE?2??
//         - YLED[5:0] = ??????????????????????????????
//         - GLED[7:0] = ???0.67Hz???
//       ?? S5 (btn_center) ??????
// ============================================================

module RV32I46F5SPMMIOSoCTOP #(
    parameter XLEN = 32,
    parameter integer INPUT_CLK_HZ = 100_000_000,
    parameter integer SYS_CLK_HZ = 5_000_000,
    parameter ROM_INIT_FILE = "program.hex"
)(
    input  clk,                      // 100MHz ????
    input  reset_n,                  // ???? (S6????)
    input  [23:0] switch,            // ???? (SW0~SW23)
    input  [3:0] keyboard_row,
    output [3:0] keyboard_col,
    input  btn_up,                   // S1
    input  btn_down,                 // S2 - ??PC+??
    input  btn_left,                 // S3 - ?????
    input  btn_right,                // S4 - ??ALU??
    input  btn_center,               // S5
    output [7:0] rled,               // ?? LED
    output [7:0] yled,               // ?? LED
    output [7:0] gled,               // ?? LED
    output uart_tx_in,               // UART TX
    output buzzer_output,
    output vga_hsync,
    output vga_vsync,
    output [3:0] vga_r,
    output [3:0] vga_g,
    output [3:0] vga_b
);

    // ---------- ???????? ----------
    wire sw_run  = switch[0];        // 1=??, 0=??
    wire sw_mode = switch[8];        // 0=??, 1=??
    wire sw_step = switch[9];        // ??????
    wire continuous_mode = ~sw_mode; // ????????????0=???

    // ---------- ????????? 100MHz clk? ----------
    wire reset_raw = reset_n;          // ?? S6 ? reset_n=1 ? ????
    reg [2:0] reset_sync;
    always @(posedge clk or posedge reset_raw) begin
        if (reset_raw)
            reset_sync <= 3'b111;
        else
            reset_sync <= {reset_sync[1:0], 1'b0};
    end
    wire internal_reset = reset_sync[2];   // ??????????

    localparam integer SYS_HALF_DIV = INPUT_CLK_HZ / (2 * SYS_CLK_HZ);
    localparam integer AUTO_PULSE_CYCLES = (SYS_CLK_HZ * 67) / 100;

    // ---------- Slow system clock for timing-friendly FPGA bring-up ----------
    reg [31:0] clk_sys_div_count;
    reg clk_sys_unbuffered;
    always @(posedge clk or posedge internal_reset) begin
        if (internal_reset) begin
            clk_sys_div_count <= 32'd0;
            clk_sys_unbuffered <= 1'b0;
        end else if (clk_sys_div_count == SYS_HALF_DIV - 1) begin
            clk_sys_div_count <= 32'd0;
            clk_sys_unbuffered <= ~clk_sys_unbuffered;
        end else begin
            clk_sys_div_count <= clk_sys_div_count + 1'b1;
        end
    end
    wire clk_sys;
    BUFG clk_sys_bufg (
        .I(clk_sys_unbuffered),
        .O(clk_sys)
    );

    // SW20 is the external interrupt source. It must remain stable for 50 ms
    // before one clean clk_sys pulse is emitted. Return it to zero to re-arm.
    localparam integer IRQ_DEBOUNCE_CYCLES = SYS_CLK_HZ / 20;
    reg [2:0] sw20_sync;
    reg sw20_debounced;
    reg sw20_debounced_d;
    reg [30:0] sw20_stable_count;
    always @(posedge clk_sys or posedge internal_reset) begin
        if (internal_reset) begin
            sw20_sync <= 3'b000;
            sw20_debounced <= 1'b0;
            sw20_debounced_d <= 1'b0;
            sw20_stable_count <= 31'd0;
        end else begin
            sw20_sync <= {sw20_sync[1:0], switch[20]};
            sw20_debounced_d <= sw20_debounced;
            if (sw20_sync[2] == sw20_debounced) begin
                sw20_stable_count <= 31'd0;
            end else if (sw20_stable_count >= IRQ_DEBOUNCE_CYCLES - 1) begin
                sw20_debounced <= sw20_sync[2];
                sw20_stable_count <= 31'd0;
            end else begin
                sw20_stable_count <= sw20_stable_count + 1'b1;
            end
        end
    end
    wire ext_irq_pulse = sw20_debounced & ~sw20_debounced_d;

    // Divide the 100 MHz board clock by two for the VGA pixel clock.
    reg vga_clk_unbuffered;
    always @(posedge clk or posedge internal_reset) begin
        if (internal_reset)
            vga_clk_unbuffered <= 1'b0;
        else
            vga_clk_unbuffered <= ~vga_clk_unbuffered;
    end
    wire vga_pixel_clk;
    BUFG vga_clk_bufg (
        .I(vga_clk_unbuffered),
        .O(vga_pixel_clk)
    );

    wire [3:0] vga_test_r, vga_test_g, vga_test_b;
    wire [3:0] vga_game_r, vga_game_g, vga_game_b;
    wire [10:0] game_p1_x, game_p1_y, game_p2_x, game_p2_y;
    wire [31:0] game_status, game_flags, game_proj1_pos, game_proj2_pos, game_medicine_pos, game_timer;
    wire menu_theme_signal;
    wire game_bgm_signal;
    wire death_theme_signal;
    wire timeout_theme_signal;
    wire bgm_signal;
    wire game_audio_signal;
    wire menu_music_enable = (game_flags[26] || game_flags[28]) && !game_flags[30];
    Menu_Theme_Player #(.CLK_HZ(INPUT_CLK_HZ)) game_bgm (
        .clk(clk),
        .reset(internal_reset),
        .enable(menu_music_enable),
        .music_signal(menu_theme_signal)
    );
    Buzzer_Track_Player #(.CLK_HZ(INPUT_CLK_HZ), .TRACK(2)) in_game_bgm (
        .clk(clk), .reset(internal_reset),
        .enable(game_flags[31] && !game_flags[12] && !game_flags[29] && !game_flags[30]),
        .music_signal(game_bgm_signal)
    );
    Buzzer_Track_Player #(.CLK_HZ(INPUT_CLK_HZ), .TRACK(0)) death_theme (
        .clk(clk), .reset(internal_reset),
        .enable(game_flags[12] && !game_flags[29] && !game_flags[30]),
        .music_signal(death_theme_signal)
    );
    Buzzer_Track_Player #(.CLK_HZ(INPUT_CLK_HZ), .TRACK(1)) timeout_theme (
        .clk(clk), .reset(internal_reset),
        .enable(game_flags[29] && !game_flags[30]),
        .music_signal(timeout_theme_signal)
    );
    assign bgm_signal = game_flags[31] ? game_bgm_signal : menu_theme_signal;
    Game_Audio game_audio (
        .clk(clk),
        .reset(internal_reset),
        .game_active(sw_run),
        .game_status(game_status),
        .game_flags(game_flags),
        .bgm_signal(bgm_signal),
        .buzzer_output(game_audio_signal)
    );
    wire selected_audio = game_flags[29] ? timeout_theme_signal :
                          game_flags[12] ? death_theme_signal : game_audio_signal;
    assign buzzer_output = switch[21] ? 1'b0 : selected_audio;
    wire [10:0] vga_pixel_x;
    wire [9:0] vga_pixel_y;
    wire vga_active_video;

    // P1 uses the 4x4 matrix keypad: 4/6/2/5/8 = left/right/jump/melee/projectile.
    wire [3:0] p1_key_raw;
    wire p1_projectile_key;
    wire [3:0] keypad_debug_col, keypad_debug_row;
    keyboard_4x4_scan p1_keypad (
        .clk(clk),
        .reset(internal_reset),
        .row_in(keyboard_row),
        .col_out(keyboard_col),
        .p1_key_out(p1_key_raw),
        .p1_proj_key(p1_projectile_key),
        .debug_col(keypad_debug_col),
        .debug_row(keypad_debug_row)
    );
    wire [4:0] game_p1_buttons = {
        p1_projectile_key, p1_key_raw[3], p1_key_raw[0], p1_key_raw[2], p1_key_raw[1]
    };

    // P2 uses S2/S1/S3/S4/S5. Reuse the original 20 ms five-key debouncer.
    wire [4:0] p2_button_valid;
    key_debounce_5ch p2_button_debounce (
        .clk(clk),
        .reset(internal_reset),
        .raw_button({btn_center, btn_right, btn_left, btn_down, btn_up}),
        .button_valid(p2_button_valid)
    );
    wire [4:0] game_p2_buttons = {
        p2_button_valid[4], p2_button_valid[3], p2_button_valid[2], p2_button_valid[0], p2_button_valid[1]
    };
    wire game_input_mode = switch[22];

    VGA_Test_Pattern vga_test_pattern (
        .pixel_clk(vga_pixel_clk),
        .reset(internal_reset),
        .vga_hsync(vga_hsync),
        .vga_vsync(vga_vsync),
        .vga_r(vga_test_r),
        .vga_g(vga_test_g),
        .vga_b(vga_test_b),
        .pixel_x(vga_pixel_x),
        .pixel_y(vga_pixel_y),
        .active_video(vga_active_video)
    );

    Game_Static_Renderer game_static_renderer (
        .pixel_clk(vga_pixel_clk),
        .reset(internal_reset),
        .active_video(vga_active_video),
        .pixel_x(vga_pixel_x),
        .pixel_y(vga_pixel_y),
        .game_p1_x(game_p1_x),
        .game_p1_y(game_p1_y),
        .game_p2_x(game_p2_x),
        .game_p2_y(game_p2_y),
        .game_status(game_status),
        .game_flags(game_flags),
        .game_proj1_pos(game_proj1_pos),
        .game_proj2_pos(game_proj2_pos),
        .game_medicine_pos(game_medicine_pos),
        .game_timer(game_timer),
        .vga_r(vga_game_r),
        .vga_g(vga_game_g),
        .vga_b(vga_game_b)
    );

    // SW23=1: VGA electrical/timing test bars. SW23=0: static game renderer.
    assign vga_r = switch[23] ? vga_test_r : vga_game_r;
    assign vga_g = switch[23] ? vga_test_g : vga_game_g;
    assign vga_b = switch[23] ? vga_test_b : vga_game_b;

    // ---------- SW9 ??????????????????? ----------
    reg sw9_sync, sw9_prev;
    always @(posedge clk_sys or posedge internal_reset) begin
        if (internal_reset) begin
            sw9_sync <= 1'b0;
            sw9_prev <= 1'b0;
        end else begin
            sw9_sync <= sw_step;
            sw9_prev <= sw9_sync;
        end
    end
    wire sw9_edge = sw9_sync ^ sw9_prev;   // ???????????????

    // ---------- ??????????? S2~S4?S5???? ----------
    reg btn_down_sync, btn_left_sync, btn_right_sync;
    reg btn_down_prev, btn_left_prev, btn_right_prev;

    always @(posedge clk_sys or posedge internal_reset) begin
        if (internal_reset) begin
            btn_down_sync  <= 1'b0;
            btn_left_sync  <= 1'b0;
            btn_right_sync <= 1'b0;
        end else begin
            btn_down_sync  <= btn_down;
            btn_left_sync  <= btn_left;
            btn_right_sync <= btn_right;
        end
    end

    always @(posedge clk_sys or posedge internal_reset) begin
        if (internal_reset) begin
            btn_down_prev  <= 1'b0;
            btn_left_prev  <= 1'b0;
            btn_right_prev <= 1'b0;
        end else begin
            btn_down_prev  <= btn_down_sync;
            btn_left_prev  <= btn_left_sync;
            btn_right_prev <= btn_right_sync;
        end
    end

    wire btn_down_rise  = btn_down_sync  & ~btn_down_prev;
    wire btn_left_rise  = btn_left_sync  & ~btn_left_prev;
    wire btn_right_rise = btn_right_sync & ~btn_right_prev;

    // ---------- ?????0.67s? ----------
    reg [25:0] auto_cnt;
    wire auto_pulse;
    always @(posedge clk_sys or posedge internal_reset) begin
        if (internal_reset)
            auto_cnt <= 0;
        else
            auto_cnt <= (auto_cnt >= AUTO_PULSE_CYCLES) ? 26'd0 : auto_cnt + 1'b1;
    end
    assign auto_pulse = (auto_cnt == AUTO_PULSE_CYCLES - 1);   // ?0.67s????

    // ---------- ????????????? ----------
    reg step_pulse_reg;
    reg pc_inst_trigger_reg;
    reg reg_trigger_reg;
    reg alu_trigger_reg;

    always @(posedge clk_sys or posedge internal_reset) begin
        if (internal_reset) begin
            step_pulse_reg      <= 1'b0;
            pc_inst_trigger_reg <= 1'b0;
            reg_trigger_reg     <= 1'b0;
            alu_trigger_reg     <= 1'b0;
        end else begin
            step_pulse_reg      <= 1'b0;
            pc_inst_trigger_reg <= 1'b0;
            reg_trigger_reg     <= 1'b0;
            alu_trigger_reg     <= 1'b0;

            // ?????SW9 ????????????????
            if (sw9_edge && !continuous_mode && sw_run)
                step_pulse_reg <= 1'b1;

            // ???????????????
            if (continuous_mode && sw_run && auto_pulse)
                step_pulse_reg <= 1'b1;

            // S2~S4 ?????????????????????????
            if (btn_down_rise  && !game_input_mode) pc_inst_trigger_reg <= 1'b1;
            if (btn_left_rise  && !game_input_mode) reg_trigger_reg <= 1'b1;
            if (btn_right_rise && !game_input_mode) alu_trigger_reg <= 1'b1;
        end
    end

    wire step_pulse        = step_pulse_reg;
    wire pc_inst_trigger   = pc_inst_trigger_reg;
    wire reg_trigger       = reg_trigger_reg;
    wire alu_trigger       = alu_trigger_reg;

    // ---------- manual_stall ?? ----------
    // ?????? sw_run=0 ???????????????
    reg manual_stall_reg;
    reg step_pulse_prev;
    always @(posedge clk_sys or posedge internal_reset) begin
        if (internal_reset) begin
            manual_stall_reg <= 1'b1;
            step_pulse_prev  <= 1'b0;
        end else begin
            step_pulse_prev <= step_pulse;
            if (continuous_mode) begin
                manual_stall_reg <= 1'b0;      // ???????
            end else begin
                // ?????step_pulse ???????????????
                if (step_pulse && !step_pulse_prev)
                    manual_stall_reg <= 1'b0;
                else if (instruction_retired && !manual_stall_reg)
                    manual_stall_reg <= 1'b1;
            end
        end
    end

    // ?? stall?? sw_run=0 ? manual_stall_reg=1 ???
    wire manual_stall = (~sw_run) | manual_stall_reg;

    // ---------- ???? ----------
    wire debug_tx_start;
    wire [7:0] debug_tx_data;
    wire [31:0] debug_pc;
    wire [31:0] debug_instruction;
    wire [4:0]  debug_reg_addr;
    wire [31:0] debug_reg_data;
    wire [31:0] debug_alu_result;
    wire instruction_retired;
    wire trapped;
    wire uart_tx_start;
    wire [7:0] uart_tx_data;
    wire uart_tx_busy;
    wire [31:0] retire_instruction;
    wire [7:0] mmio_uart_tx_data;
    wire mmio_uart_tx_start;

    // ---------- DebugUARTController ----------
    DebugUARTController debug_uart (
        .clk(clk_sys),
        .reset(internal_reset),
        .pc_inst_trigger(pc_inst_trigger),
        .reg_trigger(reg_trigger),
        .alu_trigger(alu_trigger),
        .debug_pc(debug_pc),
        .debug_instruction(debug_instruction),
        .debug_reg_addr(debug_reg_addr),
        .debug_reg_data(debug_reg_data),
        .debug_alu_result(debug_alu_result),
        .tx_busy(uart_tx_busy),
        .tx_start(debug_tx_start),
        .tx_data(debug_tx_data)
    );

    // ---------- UART TX MUX ----------
    // Priority: MMIO (program) > debug
    assign uart_tx_start = mmio_uart_tx_start | debug_tx_start;
    assign uart_tx_data  = mmio_uart_tx_start ? mmio_uart_tx_data : debug_tx_data;

    UARTTX #(
        .CLK_FREQ_HZ(SYS_CLK_HZ),
        .BAUD_RATE(115200)
    ) uart_tx (
        .clk(clk_sys),
        .reset(internal_reset),
        .tx_start(uart_tx_start),
        .tx_data(uart_tx_data),
        .tx(uart_tx_in),
        .tx_busy(uart_tx_busy)
    );

    // ---------- UnifiedUARTController ----------
    wire benchmark_start;
    UnifiedUARTController unified_uart_controller (
        .clk(clk_sys),
        .reset(internal_reset),
        .btn_up(1'b0),    // S1 ????
        .mmio_tx_data(mmio_uart_tx_data),
        .mmio_tx_start(mmio_uart_tx_start),
        .tx_start(),
        .tx_data(),
        .benchmark_start(benchmark_start)
    );

    // ---------- CPU ? ----------
    RV32I46F5SPMMIO #(
        .XLEN(XLEN),
        .ROM_INIT_FILE(ROM_INIT_FILE)
    ) rv32i46f_5sp_mmio (
        .clk(clk_sys),
        .reset(internal_reset),
        .UART_busy(uart_tx_busy),
        .manual_stall(manual_stall),
        .icache_mode(switch[18]),          // SW18: 0=direct, 1=4-way
        .ext_irq(ext_irq_pulse),
        .game_p1_buttons(game_p1_buttons),
        .game_p2_buttons(game_p2_buttons),
        .retire_instruction(retire_instruction),
        .mmio_uart_tx_data(mmio_uart_tx_data),
        .mmio_uart_tx_start(mmio_uart_tx_start),
        .instruction_retired(instruction_retired),
        .trapped(trapped),
        .game_p1_x(game_p1_x),
        .game_p1_y(game_p1_y),
        .game_p2_x(game_p2_x),
        .game_p2_y(game_p2_y),
        .game_status(game_status),
        .game_flags(game_flags),
        .game_proj1_pos(game_proj1_pos),
        .game_proj2_pos(game_proj2_pos),
        .game_medicine_pos(game_medicine_pos),
        .game_timer(game_timer),
        .debug_pc(debug_pc),
        .debug_instruction(debug_instruction),
        .debug_reg_addr(debug_reg_addr),
        .debug_reg_data(debug_reg_data),
        .debug_alu_result(debug_alu_result)
    );

    // ---------- ?? LED ?? ----------
    // ???????? OPCODE ? funct3
    wire [6:0] opcode = retire_instruction[6:0];
    wire [2:0] funct3 = retire_instruction[14:12];

    // ?? LED??3??? funct3??5??? OPCODE ??5?
    assign rled = {funct3, opcode[6:2]};

    // ?? LED ??2??? OPCODE ??2?
    assign yled[7:6] = opcode[1:0];
    // ?? LED ?6???????
    assign yled[0] = continuous_mode;          // ?????
    assign yled[1] = internal_reset;           // ????
    assign yled[2] = instruction_retired;      // ????
    assign yled[3] = trapped;                  // ??
    assign yled[4] = uart_tx_busy;             // ???
    assign yled[5] = sw_run;                   // ??????

    // ?????0.67Hz ???
    reg [31:0] heartbeat_cnt;
    always @(posedge clk_sys or posedge internal_reset) begin
        if (internal_reset)
            heartbeat_cnt <= 26'd0;
        else
            heartbeat_cnt <= heartbeat_cnt + 1'b1;
    end
    assign gled = {8{heartbeat_cnt[22]}};

endmodule
