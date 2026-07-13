//=====================================================================
// 模块功能：音乐播放器（完全可综合版）
// - 根据 current_state 播放不同音乐：
//   STATE_IDLE   → 循环播放《逆战》
//   STATE_LOCKED → 单次播放《天空之城》
//   STATE_PLAYING→ 静音
// - 使用 function 实现音符 ROM，无数组初始化、无 initial、无 for 循环
// - 所有时序逻辑使用非阻塞赋值，带异步复位（低有效）
//=====================================================================

module music_player(
    input        clk,               // 全局时钟（100MHz）
    input        rst_n,             // 异步复位，低有效
    input  [1:0] current_state,     // 来自防沉迷模块的状态：0=IDLE,1=PLAYING,2=LOCKED
    output reg   music_signal       // 音乐方波输出，直接驱动蜂鸣器
);

//==================== 状态编码 ====================
localparam STATE_IDLE    = 2'd0;   // 空闲状态：播放逆战
localparam STATE_PLAYING = 2'd1;   // 游戏中：静音
localparam STATE_LOCKED  = 2'd2;   // 锁定状态：播放天空之城（单次）

//==================== 音乐时间参数 ====================
// SILENCE_CYCLES：音符之间的静音间隔（单位：时钟周期）
// BEAT_CYCLES    ：一个节拍对应的时钟周期数（用于控制音符时长）
// 注：100MHz 时钟下，BEAT_CYCLES = 20_000_000 对应 0.2 秒/拍
localparam SILENCE_CYCLES = 200_000;   // 音符间静音时长（2ms）
localparam BEAT_CYCLES    = 20_000_000; // 一个节拍的长度（0.2秒）

//==================== 音乐播放寄存器 ====================
reg [31:0] beat_cnt;       // 当前音符已持续的节拍计数器
reg [31:0] note_clk_cnt;   // 当前音高周期内的相位计数器（用于产生方波）
reg [6:0]  note_idx;       // 当前播到的音符索引（0~127 用于逆战，0~63 用于天空之城）
reg [31:0] silence_cnt;    // 静音阶段倒计时（大于0时输出0）
reg        castle_finish;  // 天空之城是否已播放完成（单次播放标志）

//==================== 逆战音符 ROM ====================
// 输入索引 idx (0~127)，输出 4-bit 音符编号
// 音符编号含义：0=休止，1~12 对应音高（见 get_limit 函数）
function [3:0] nz_note;
    input [6:0] idx;
    begin
        case (idx)
            // 前114个音符为本曲实际数据
            0: nz_note = 0;   1: nz_note = 6;   2: nz_note = 6;   3: nz_note = 8;
            4: nz_note = 6;   5: nz_note = 8;   6: nz_note = 6;   7: nz_note = 8;
            8: nz_note = 6;   9: nz_note = 0;  10: nz_note = 8;  11: nz_note = 8;
            12: nz_note = 6; 13: nz_note = 8; 14: nz_note = 6; 15: nz_note = 0;
            16: nz_note = 5; 17: nz_note = 5; 18: nz_note = 5; 19: nz_note = 8;
            20: nz_note = 8; 21: nz_note = 8; 22: nz_note = 8; 23: nz_note = 8;
            24: nz_note = 8; 25: nz_note = 7; 26: nz_note = 0; 27: nz_note = 7;
            28: nz_note = 7; 29: nz_note = 7; 30: nz_note = 7; 31: nz_note = 7;
            32: nz_note = 7; 33: nz_note = 8; 34: nz_note = 6; 35: nz_note = 0;
            36: nz_note = 8; 37: nz_note = 8; 38: nz_note = 6; 39: nz_note = 8;
            40: nz_note = 6; 41: nz_note = 0; 42: nz_note = 5; 43: nz_note = 5;
            44: nz_note = 5; 45: nz_note =10; 46: nz_note =10; 47: nz_note =10;
            48: nz_note =10; 49: nz_note =10; 50: nz_note = 9; 51: nz_note = 9;
            52: nz_note = 9; 53: nz_note = 9; 54: nz_note = 0; 55: nz_note = 6;
            56: nz_note = 7; 57: nz_note = 8; 58: nz_note = 6; 59: nz_note = 8;
            60: nz_note = 6; 61: nz_note = 8; 62: nz_note = 6; 63: nz_note = 0;
            64: nz_note = 8; 65: nz_note = 8; 66: nz_note = 6; 67: nz_note = 8;
            68: nz_note = 6; 69: nz_note = 8; 70: nz_note = 6; 71: nz_note = 8;
            72: nz_note = 8; 73: nz_note = 8; 74: nz_note = 8; 75: nz_note = 8;
            76: nz_note = 8; 77: nz_note = 7; 78: nz_note = 7; 79: nz_note = 7;
            80: nz_note = 0; 81: nz_note = 7; 82: nz_note = 7; 83: nz_note = 7;
            84: nz_note = 0; 85: nz_note = 8; 86: nz_note = 8; 87: nz_note = 6;
            88: nz_note = 8; 89: nz_note = 6; 90: nz_note = 8; 91: nz_note = 6;
            92: nz_note = 0; 93: nz_note = 8; 94: nz_note = 8; 95: nz_note = 6;
            96: nz_note = 8; 97: nz_note = 6; 98: nz_note = 8; 99: nz_note = 6;
            100: nz_note =10;101: nz_note =10;102: nz_note =10;103: nz_note =10;
            104: nz_note =10;105: nz_note =10;106: nz_note = 9;107: nz_note = 9;
            108: nz_note = 9;109: nz_note = 7;110: nz_note = 7;111: nz_note = 7;
            112: nz_note = 7;113: nz_note = 8;
            default: nz_note = 0;   // 索引 114~127 均为休止符
        endcase
    end
endfunction

//==================== 逆战节拍 ROM ====================
// 输入索引 idx，输出该音符的节拍长度（以 BEAT_CYCLES 为单位）
function [3:0] nz_beat;
    input [6:0] idx;
    begin
        case (idx)
            0: nz_beat = 2;   1: nz_beat = 1;   2: nz_beat = 1;   3: nz_beat = 1;
            4: nz_beat = 1;   5: nz_beat = 1;   6: nz_beat = 1;   7: nz_beat = 2;
            8: nz_beat = 2;   9: nz_beat = 1;  10: nz_beat = 1;  11: nz_beat = 1;
            12: nz_beat = 1; 13: nz_beat = 2; 14: nz_beat = 2; 15: nz_beat = 1;
            16: nz_beat = 1; 17: nz_beat = 1; 18: nz_beat = 1; 19: nz_beat = 2;
            20: nz_beat = 2; 21: nz_beat = 1; 22: nz_beat = 1; 23: nz_beat = 1;
            24: nz_beat = 1; 25: nz_beat = 2; 26: nz_beat = 1; 27: nz_beat = 1;
            28: nz_beat = 1; 29: nz_beat = 1; 30: nz_beat = 1; 31: nz_beat = 1;
            32: nz_beat = 1; 33: nz_beat = 2; 34: nz_beat = 2; 35: nz_beat = 1;
            36: nz_beat = 1; 37: nz_beat = 1; 38: nz_beat = 1; 39: nz_beat = 2;
            40: nz_beat = 2; 41: nz_beat = 1; 42: nz_beat = 1; 43: nz_beat = 1;
            44: nz_beat = 1; 45: nz_beat = 1; 46: nz_beat = 1; 47: nz_beat = 1;
            48: nz_beat = 1; 49: nz_beat = 1; 50: nz_beat = 1; 51: nz_beat = 1;
            52: nz_beat = 2; 53: nz_beat = 4; 54: nz_beat = 2; 55: nz_beat = 1;
            56: nz_beat = 1; 57: nz_beat = 1; 58: nz_beat = 1; 59: nz_beat = 1;
            60: nz_beat = 1; 61: nz_beat = 1; 62: nz_beat = 1; 63: nz_beat = 1;
            64: nz_beat = 1; 65: nz_beat = 1; 66: nz_beat = 1; 67: nz_beat = 1;
            68: nz_beat = 1; 69: nz_beat = 1; 70: nz_beat = 3; 71: nz_beat = 1;
            72: nz_beat = 1; 73: nz_beat = 1; 74: nz_beat = 1; 75: nz_beat = 1;
            76: nz_beat = 1; 77: nz_beat = 1; 78: nz_beat = 1; 79: nz_beat = 2;
            80: nz_beat = 1; 81: nz_beat = 1; 82: nz_beat = 1; 83: nz_beat = 1;
            84: nz_beat = 1; 85: nz_beat = 1; 86: nz_beat = 1; 87: nz_beat = 1;
            88: nz_beat = 1; 89: nz_beat = 1; 90: nz_beat = 1; 91: nz_beat = 1;
            92: nz_beat = 1; 93: nz_beat = 1; 94: nz_beat = 1; 95: nz_beat = 1;
            96: nz_beat = 1; 97: nz_beat = 1; 98: nz_beat = 1; 99: nz_beat = 3;
            100: nz_beat =1; 101: nz_beat =1; 102: nz_beat =1; 103: nz_beat =1;
            104: nz_beat =1; 105: nz_beat =1; 106: nz_beat =1; 107: nz_beat =1;
            108: nz_beat =2; 109: nz_beat =1; 110: nz_beat =1; 111: nz_beat =2;
            112: nz_beat =2; 113: nz_beat =1;
            default: nz_beat = 2;   // 索引 114~127 默认节拍为 2
        endcase
    end
endfunction

//==================== 天空之城音符 ROM ====================
// 索引范围 0~63，输出音符编号
function [3:0] castle_note;
    input [5:0] idx;
    begin
        case (idx)
            0: castle_note = 0;  1: castle_note = 0;  2: castle_note = 0;
            3: castle_note = 6;  4: castle_note = 7;  5: castle_note = 8;
            6: castle_note = 7;  7: castle_note = 8;  8: castle_note =10;
            9: castle_note = 7; 10: castle_note = 3; 11: castle_note = 6;
            12: castle_note = 5; 13: castle_note = 6; 14: castle_note = 8;
            15: castle_note = 5; 16: castle_note = 3; 17: castle_note = 4;
            18: castle_note = 3; 19: castle_note = 4; 20: castle_note = 8;
            21: castle_note = 3; 22: castle_note = 8; 23: castle_note = 8;
            24: castle_note = 7; 25: castle_note = 4; 26: castle_note = 4;
            27: castle_note = 7; 28: castle_note = 7; 29: castle_note = 6;
            30: castle_note = 7; 31: castle_note = 8; 32: castle_note = 7;
            33: castle_note = 8; 34: castle_note =10; 35: castle_note = 7;
            36: castle_note = 3; 37: castle_note = 6; 38: castle_note = 5;
            39: castle_note = 6; 40: castle_note = 8; 41: castle_note = 5;
            42: castle_note = 4; 43: castle_note = 4; 44: castle_note = 8;
            45: castle_note = 7; 46: castle_note = 7; 47: castle_note = 8;
            48: castle_note = 9; 49: castle_note =10; 50: castle_note = 8;
            51: castle_note = 8; 52: castle_note = 8; 53: castle_note = 7;
            54: castle_note = 6; 55: castle_note = 7; 56: castle_note = 5;
            57: castle_note = 6;
            default: castle_note = 0;   // 索引 58~63 为休止符
        endcase
    end
endfunction

//==================== 天空之城节拍 ROM ====================
function [3:0] castle_beat;
    input [5:0] idx;
    begin
        case (idx)
            0: castle_beat = 1;  1: castle_beat = 1;  2: castle_beat = 1;
            3: castle_beat = 1;  4: castle_beat = 1;  5: castle_beat = 3;
            6: castle_beat = 1;  7: castle_beat = 1;  8: castle_beat = 1;
            9: castle_beat = 6; 10: castle_beat = 1; 11: castle_beat = 3;
            12: castle_beat = 1; 13: castle_beat = 1; 14: castle_beat = 1;
            15: castle_beat = 6; 16: castle_beat = 1; 17: castle_beat = 3;
            18: castle_beat = 1; 19: castle_beat = 1; 20: castle_beat = 1;
            21: castle_beat = 6; 22: castle_beat = 1; 23: castle_beat = 1;
            24: castle_beat = 3; 25: castle_beat = 1; 26: castle_beat = 1;
            27: castle_beat = 1; 28: castle_beat = 6; 29: castle_beat = 1;
            30: castle_beat = 1; 31: castle_beat = 3; 32: castle_beat = 1;
            33: castle_beat = 1; 34: castle_beat = 1; 35: castle_beat = 6;
            36: castle_beat = 1; 37: castle_beat = 3; 38: castle_beat = 1;
            39: castle_beat = 1; 40: castle_beat = 1; 41: castle_beat = 6;
            42: castle_beat = 1; 43: castle_beat = 1; 44: castle_beat = 1;
            45: castle_beat = 1; 46: castle_beat = 1; 47: castle_beat = 1;
            48: castle_beat = 3; 49: castle_beat = 1; 50: castle_beat = 1;
            51: castle_beat = 3; 52: castle_beat = 1; 53: castle_beat = 1;
            54: castle_beat = 1; 55: castle_beat = 1; 56: castle_beat = 1;
            57: castle_beat = 8;
            default: castle_beat = 1;   // 索引 58~63 默认节拍为 1
        endcase
    end
endfunction

//==================== 频率计算函数 ====================
// 输入音符编号（1~12），输出方波半周期所需的时钟计数
// 计算公式：半周期 = 时钟频率 / (2 * 音高频率)
// 例如 100MHz / (2*262Hz) ≈ 190839
function [31:0] get_limit;
    input [3:0] note;
    begin
        case(note)
            1: get_limit = 100_000_000 / (2 * 262);   // C4
            2: get_limit = 100_000_000 / (2 * 294);   // D4
            3: get_limit = 100_000_000 / (2 * 330);   // E4
            4: get_limit = 100_000_000 / (2 * 349);   // F4
            5: get_limit = 100_000_000 / (2 * 392);   // G4
            6: get_limit = 100_000_000 / (2 * 440);   // A4
            7: get_limit = 100_000_000 / (2 * 494);   // B4
            8: get_limit = 100_000_000 / (2 * 523);   // C5
            9: get_limit = 100_000_000 / (2 * 587);   // D5
            10: get_limit = 100_000_000 / (2 * 659);  // E5
            11: get_limit = 100_000_000 / (2 * 220);  // A3
            12: get_limit = 100_000_000 / (2 * 247);  // B3
            default: get_limit = 50000;   // 未定义音符（0或>12）输出约 1kHz 用于测试
        endcase
    end
endfunction

//==================== 主控制逻辑 ====================
// 异步复位，时序逻辑，根据当前状态选择播放哪首歌曲
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 复位所有寄存器
        beat_cnt      <= 32'd0;
        note_clk_cnt  <= 32'd0;
        note_idx      <= 7'd0;
        silence_cnt   <= 32'd0;
        castle_finish <= 1'b0;
        music_signal  <= 1'b0;
    end else begin
        case (current_state)
            // ---------- 空闲状态：循环播放逆战 ----------
            STATE_IDLE: begin
                castle_finish <= 1'b0;   // 退出锁定状态时复位完成标志
                // 检查当前音符是否已播放完所需的节拍数
                if (beat_cnt >= nz_beat(note_idx) * BEAT_CYCLES) begin
                    beat_cnt    <= 32'd0;
                    // 索引超过127则回到0（循环播放）
                    note_idx    <= (note_idx >= 127) ? 7'd0 : note_idx + 1'b1;
                    silence_cnt <= SILENCE_CYCLES;   // 进入静音间隔
                    note_clk_cnt<= 32'd0;
                end else begin
                    beat_cnt <= beat_cnt + 1'b1;
                end

                // 静音倒计时处理
                if (silence_cnt > 0) begin
                    silence_cnt   <= silence_cnt - 1'b1;
                    music_signal  <= 1'b0;
                end else begin
                    // 非静音阶段：根据音符输出方波
                    if (nz_note(note_idx) == 0) begin
                        music_signal <= 1'b0;   // 休止符
                    end else begin
                        if (note_clk_cnt >= get_limit(nz_note(note_idx))) begin
                            note_clk_cnt <= 32'd0;
                            music_signal <= ~music_signal;   // 翻转方波
                        end else begin
                            note_clk_cnt <= note_clk_cnt + 1'b1;
                        end
                    end
                end
            end

            // ---------- 锁定状态：单次播放天空之城 ----------
            STATE_LOCKED: begin
                if (!castle_finish) begin
                    // 节拍计时
                    if (beat_cnt >= castle_beat(note_idx[5:0]) * BEAT_CYCLES) begin
                        beat_cnt <= 32'd0;
                        if (note_idx >= 57) begin
                            castle_finish <= 1'b1;   // 播放完毕，不再重复
                            music_signal  <= 1'b0;
                        end else begin
                            note_idx <= note_idx + 1'b1;
                        end
                        silence_cnt <= SILENCE_CYCLES;
                        note_clk_cnt<= 32'd0;
                    end else begin
                        beat_cnt <= beat_cnt + 1'b1;
                    end

                    // 静音间隔
                    if (silence_cnt > 0) begin
                        silence_cnt   <= silence_cnt - 1'b1;
                        music_signal  <= 1'b0;
                    end else begin
                        if (castle_note(note_idx[5:0]) == 0) begin
                            music_signal <= 1'b0;
                        end else begin
                            if (note_clk_cnt >= get_limit(castle_note(note_idx[5:0]))) begin
                                note_clk_cnt <= 32'd0;
                                music_signal <= ~music_signal;
                            end else begin
                                note_clk_cnt <= note_clk_cnt + 1'b1;
                            end
                        end
                    end
                end else begin
                    music_signal <= 1'b0;   // 播放完成后静音
                end
            end

            // ---------- 默认（游戏中）：静音，重置播放状态 ----------
            default: begin
                music_signal  <= 1'b0;
                note_idx      <= 7'd0;
                beat_cnt      <= 32'd0;
                note_clk_cnt  <= 32'd0;
                silence_cnt   <= 32'd0;
                castle_finish <= 1'b0;
            end
        endcase
    end
end

endmodule