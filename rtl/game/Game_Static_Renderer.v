// Bridges the original 800x480 game renderer onto the 800x600 VGA picture.
// The game picture is vertically centered with 60-pixel black borders.
module Game_Static_Renderer (
    input             pixel_clk,
    input             reset,
    input             active_video,
    input      [10:0] pixel_x,
    input      [9:0]  pixel_y,
    input      [10:0] game_p1_x,
    input      [10:0] game_p1_y,
    input      [10:0] game_p2_x,
    input      [10:0] game_p2_y,
    input      [31:0] game_status,
    input      [31:0] game_flags,
    input      [31:0] game_proj1_pos,
    input      [31:0] game_proj2_pos,
    input      [31:0] game_medicine_pos,
    input      [31:0] game_timer,
    output     [3:0]  vga_r,
    output     [3:0]  vga_g,
    output     [3:0]  vga_b
);

    localparam integer GAME_TOP = 60;
    wire game_area = active_video && (pixel_y >= GAME_TOP) && (pixel_y < GAME_TOP + 480);
    wire [10:0] game_y = game_area ? (pixel_y - GAME_TOP) : 11'd0;
    // The original LCD panel scans the game image in the opposite vertical
    // direction from standard VGA. Flip Y at this boundary for every layer.
    wire [10:0] renderer_y = game_area ? (11'd479 - game_y) : 11'd0;

    wire [2:0] game_r;
    wire [1:0] game_g;
    wire [2:0] game_b;

    wire p1_dir = game_flags[0];
    wire p2_dir = game_flags[1];
    wire p1_attack = game_flags[2];
    wire p2_attack = game_flags[3];
    wire p1_jump = game_flags[4];
    wire p2_jump = game_flags[5];
    wire p1_got_hit = game_flags[6];
    wire p2_got_hit = game_flags[7];
    wire proj1_active = game_flags[8];
    wire proj2_active = game_flags[9];
    wire proj1_dir = game_flags[10];
    wire proj2_dir = game_flags[11];
    wire medicine_active = game_flags[24];
    wire menu_active = game_flags[26];
    wire menu_select_pvp = game_flags[27];
    wire time_menu_active = game_flags[28];
    wire time_run_out = game_flags[29];
    wire irq_result_active = game_flags[30];
    // CPU game UI state: round-end flag, winner (0=P1, 1=P2), and scores.
    wire round_over = game_flags[12];
    wire winner_p2 = game_flags[13];
    wire [3:0] p1_score = game_flags[19:16];
    wire [3:0] p2_score = game_flags[23:20];

    // Position registers are written by the RISC-V CPU through MMIO.
    video_draw game_renderer (
        .pixel_clk(pixel_clk),
        .reset(reset),
        .pixel_x(pixel_x),
        .pixel_y(renderer_y),
        .p1_x(game_p1_x),
        .p1_y(game_p1_y),
        .p2_x(game_p2_x),
        .p2_y(game_p2_y),
        .p1_dir(p1_dir),
        .p2_dir(p2_dir),
        .p1_attack(p1_attack),
        .p2_attack(p2_attack),
        .p1_jump(p1_jump),
        .p2_jump(p2_jump),
        .collision(1'b0),
        .p1_got_hit(p1_got_hit),
        .p2_got_hit(p2_got_hit),
        .p1_hp(game_status[7:0]),
        .p2_hp(game_status[15:8]),
        .p1_mp(game_status[22:16]),
        .p2_mp(game_status[29:23]),
        .proj1_x(game_proj1_pos[10:0]),
        .proj1_y(game_proj1_pos[26:16]),
        .proj1_active(proj1_active),
        .proj1_dir(proj1_dir),
        .proj2_x(game_proj2_pos[10:0]),
        .proj2_y(game_proj2_pos[26:16]),
        .proj2_active(proj2_active),
        .proj2_dir(proj2_dir),
        .medicine_x(game_medicine_pos[10:0]),
        .medicine_y(game_medicine_pos[26:16]),
        .medicine_active(medicine_active),
        .debug_col(4'd0),
        .debug_row(4'd0),
        .game_state(1'b1),
        .time_error(1'b0),
        .total_time(16'd0),
        .countdown(16'd0),
        .time_lock(1'b0),
        .lcd_r(game_r),
        .lcd_g(game_g),
        .lcd_b(game_b)
    );

    // A small 5x7 pixel font keeps score and round messages independent of
    // the original LCD asset ROMs. All coordinates below use the displayed
    // VGA orientation (not renderer_y, which is only for the legacy scene).
    function [4:0] font_row;
        input [7:0] ch;
        input [2:0] row;
        begin
            case (ch)
                "0": case (row) 0:font_row=5'b01110; 1:font_row=5'b10001; 2:font_row=5'b10011; 3:font_row=5'b10101; 4:font_row=5'b11001; 5:font_row=5'b10001; default:font_row=5'b01110; endcase
                "1": case (row) 0:font_row=5'b00100; 1:font_row=5'b01100; 2:font_row=5'b00100; 3:font_row=5'b00100; 4:font_row=5'b00100; 5:font_row=5'b00100; default:font_row=5'b01110; endcase
                "2": case (row) 0:font_row=5'b01110; 1:font_row=5'b10001; 2:font_row=5'b00001; 3:font_row=5'b00010; 4:font_row=5'b00100; 5:font_row=5'b01000; default:font_row=5'b11111; endcase
                "3": case (row) 0:font_row=5'b11110; 1:font_row=5'b00001; 2:font_row=5'b00001; 3:font_row=5'b01110; 4:font_row=5'b00001; 5:font_row=5'b00001; default:font_row=5'b11110; endcase
                "4": case (row) 0:font_row=5'b00010; 1:font_row=5'b00110; 2:font_row=5'b01010; 3:font_row=5'b10010; 4:font_row=5'b11111; 5:font_row=5'b00010; default:font_row=5'b00010; endcase
                "5": case (row) 0:font_row=5'b11111; 1:font_row=5'b10000; 2:font_row=5'b10000; 3:font_row=5'b11110; 4:font_row=5'b00001; 5:font_row=5'b00001; default:font_row=5'b11110; endcase
                "6": case (row) 0:font_row=5'b00110; 1:font_row=5'b01000; 2:font_row=5'b10000; 3:font_row=5'b11110; 4:font_row=5'b10001; 5:font_row=5'b10001; default:font_row=5'b01110; endcase
                "7": case (row) 0:font_row=5'b11111; 1:font_row=5'b00001; 2:font_row=5'b00010; 3:font_row=5'b00100; 4:font_row=5'b01000; 5:font_row=5'b01000; default:font_row=5'b01000; endcase
                "8": case (row) 0:font_row=5'b01110; 1:font_row=5'b10001; 2:font_row=5'b10001; 3:font_row=5'b01110; 4:font_row=5'b10001; 5:font_row=5'b10001; default:font_row=5'b01110; endcase
                "9": case (row) 0:font_row=5'b01110; 1:font_row=5'b10001; 2:font_row=5'b10001; 3:font_row=5'b01111; 4:font_row=5'b00001; 5:font_row=5'b00010; default:font_row=5'b11100; endcase
                ":": case (row) 2:font_row=5'b00100; 4:font_row=5'b00100; default:font_row=5'b00000; endcase
                "A": case (row) 0:font_row=5'b01110; 1:font_row=5'b10001; 2:font_row=5'b10001; 3:font_row=5'b11111; 4:font_row=5'b10001; 5:font_row=5'b10001; default:font_row=5'b10001; endcase
                "C": case (row) 0:font_row=5'b01111; 1:font_row=5'b10000; 2:font_row=5'b10000; 3:font_row=5'b10000; 4:font_row=5'b10000; 5:font_row=5'b10000; default:font_row=5'b01111; endcase
                "E": case (row) 0:font_row=5'b11111; 1:font_row=5'b10000; 2:font_row=5'b10000; 3:font_row=5'b11110; 4:font_row=5'b10000; 5:font_row=5'b10000; default:font_row=5'b11111; endcase
                "G": case (row) 0:font_row=5'b01110; 1:font_row=5'b10001; 2:font_row=5'b10000; 3:font_row=5'b10111; 4:font_row=5'b10001; 5:font_row=5'b10001; default:font_row=5'b01110; endcase
                "I": case (row) 0:font_row=5'b01110; 1:font_row=5'b00100; 2:font_row=5'b00100; 3:font_row=5'b00100; 4:font_row=5'b00100; 5:font_row=5'b00100; default:font_row=5'b01110; endcase
                "M": case (row) 0:font_row=5'b10001; 1:font_row=5'b11011; 2:font_row=5'b10101; 3:font_row=5'b10101; 4:font_row=5'b10001; 5:font_row=5'b10001; default:font_row=5'b10001; endcase
                "N": case (row) 0:font_row=5'b10001; 1:font_row=5'b11001; 2:font_row=5'b10101; 3:font_row=5'b10011; 4:font_row=5'b10001; 5:font_row=5'b10001; default:font_row=5'b10001; endcase
                "O": case (row) 0:font_row=5'b01110; 1:font_row=5'b10001; 2:font_row=5'b10001; 3:font_row=5'b10001; 4:font_row=5'b10001; 5:font_row=5'b10001; default:font_row=5'b01110; endcase
                "P": case (row) 0:font_row=5'b11110; 1:font_row=5'b10001; 2:font_row=5'b10001; 3:font_row=5'b11110; 4:font_row=5'b10000; 5:font_row=5'b10000; default:font_row=5'b10000; endcase
                "Q": case (row) 0:font_row=5'b01110; 1:font_row=5'b10001; 2:font_row=5'b10001; 3:font_row=5'b10001; 4:font_row=5'b10101; 5:font_row=5'b10010; default:font_row=5'b01101; endcase
                "R": case (row) 0:font_row=5'b11110; 1:font_row=5'b10001; 2:font_row=5'b10001; 3:font_row=5'b11110; 4:font_row=5'b10100; 5:font_row=5'b10010; default:font_row=5'b10001; endcase
                "S": case (row) 0:font_row=5'b01111; 1:font_row=5'b10000; 2:font_row=5'b10000; 3:font_row=5'b01110; 4:font_row=5'b00001; 5:font_row=5'b00001; default:font_row=5'b11110; endcase
                "T": case (row) 0:font_row=5'b11111; 1:font_row=5'b00100; 2:font_row=5'b00100; 3:font_row=5'b00100; 4:font_row=5'b00100; 5:font_row=5'b00100; default:font_row=5'b00100; endcase
                "U": case (row) 0:font_row=5'b10001; 1:font_row=5'b10001; 2:font_row=5'b10001; 3:font_row=5'b10001; 4:font_row=5'b10001; 5:font_row=5'b10001; default:font_row=5'b01110; endcase
                "V": case (row) 0:font_row=5'b10001; 1:font_row=5'b10001; 2:font_row=5'b10001; 3:font_row=5'b10001; 4:font_row=5'b10001; 5:font_row=5'b01010; default:font_row=5'b00100; endcase
                "W": case (row) 0:font_row=5'b10001; 1:font_row=5'b10001; 2:font_row=5'b10001; 3:font_row=5'b10101; 4:font_row=5'b10101; 5:font_row=5'b10101; default:font_row=5'b01010; endcase
                default: font_row = 5'b00000;
            endcase
        end
    endfunction

    function font_pixel;
        input [7:0] ch;
        input [2:0] col;
        input [2:0] row;
        reg [4:0] row_bits;
        begin
            row_bits = font_row(ch, row);
            font_pixel = (col < 5) && (row < 7) && row_bits[4-col];
        end
    endfunction

    function [7:0] score_char;
        input [1:0] index;
        begin
            case (index)
                0: score_char = "0" + p1_score;
                1: score_char = ":";
                default: score_char = "0" + p2_score;
            endcase
        end
    endfunction

    function [7:0] winner_char;
        input [3:0] index;
        begin
            case (index)
                0: winner_char = "P";
                1: winner_char = winner_p2 ? "2" : "1";
                2: winner_char = " ";
                3: winner_char = "W";
                4: winner_char = "I";
                5: winner_char = "N";
                default: winner_char = "S";
            endcase
        end
    endfunction

    function [7:0] game_over_char;
        input [3:0] index;
        begin
            case (index)
                0: game_over_char = "G";
                1: game_over_char = "A";
                2: game_over_char = "M";
                3: game_over_char = "E";
                4: game_over_char = " ";
                5: game_over_char = "O";
                6: game_over_char = "V";
                7: game_over_char = "E";
                default: game_over_char = "R";
            endcase
        end
    endfunction

    // 16x16 SimHei-derived monochrome glyphs: REN, JI, DUI, ZHAN, ZHEN.
    function [15:0] cn_row;
        input [2:0] glyph;
        input [3:0] row;
        begin
            case (glyph)
                0: case(row) 0:cn_row=16'h0100;1:cn_row=16'h0100;2:cn_row=16'h0100;3:cn_row=16'h0180;4:cn_row=16'h0180;5:cn_row=16'h0180;6:cn_row=16'h03c0;7:cn_row=16'h0240;8:cn_row=16'h0660;9:cn_row=16'h0c30;10:cn_row=16'h1818;11:cn_row=16'h300c;default:cn_row=0;endcase
                1: case(row) 0:cn_row=16'h0800;1:cn_row=16'h08f0;2:cn_row=16'h0890;3:cn_row=16'h3e90;4:cn_row=16'h1890;5:cn_row=16'h1c90;6:cn_row=16'h1e90;7:cn_row=16'h2890;8:cn_row=16'h6890;9:cn_row=16'h0910;10:cn_row=16'h0914;11:cn_row=16'h0a1c;default:cn_row=0;endcase
                2: case(row) 0:cn_row=16'h0008;1:cn_row=16'h0008;2:cn_row=16'h3e08;3:cn_row=16'h03fc;4:cn_row=16'h2208;5:cn_row=16'h1488;6:cn_row=16'h0c88;7:cn_row=16'h0c48;8:cn_row=16'h0a08;9:cn_row=16'h1208;10:cn_row=16'h3008;11:cn_row=16'h2038;default:cn_row=0;endcase
                3: case(row) 0:cn_row=16'h18d0;1:cn_row=16'h1858;2:cn_row=16'h1e50;3:cn_row=16'h187c;4:cn_row=16'h19c0;5:cn_row=16'h3e48;6:cn_row=16'h2258;7:cn_row=16'h2250;8:cn_row=16'h2220;9:cn_row=16'h3e60;10:cn_row=16'h22d4;11:cn_row=16'h030c;default:cn_row=0;endcase
                default: case(row) 0:cn_row=16'h0180;1:cn_row=16'h3ffc;2:cn_row=16'h0100;3:cn_row=16'h0ef0;4:cn_row=16'h0ff0;5:cn_row=16'h0810;6:cn_row=16'h0ff0;7:cn_row=16'h0ff0;8:cn_row=16'h0810;9:cn_row=16'h3ffc;10:cn_row=16'h0670;11:cn_row=16'h380c;default:cn_row=0;endcase
            endcase
        end
    endfunction

    function cn_pixel;
        input [2:0] glyph;
        input [3:0] col;
        input [3:0] row;
        reg [15:0] bits;
        begin
            bits = cn_row(glyph, row);
            cn_pixel = bits[15-col];
        end
    endfunction

    function [2:0] mode_glyph;
        input pvp;
        input [1:0] index;
        begin
            case (index)
                0: mode_glyph = pvp ? 3'd4 : 3'd0;
                1: mode_glyph = pvp ? 3'd0 : 3'd1;
                2: mode_glyph = 3'd2;
                default: mode_glyph = 3'd3;
            endcase
        end
    endfunction

    function [7:0] timer_char;
        input [2:0] index;
        integer minutes;
        integer seconds;
        begin
            minutes = game_timer / 60;
            seconds = game_timer % 60;
            case (index)
                0: timer_char = "0" + ((minutes / 10) % 10);
                1: timer_char = "0" + (minutes % 10);
                2: timer_char = ":";
                3: timer_char = "0" + (seconds / 10);
                default: timer_char = "0" + (seconds % 10);
            endcase
        end
    endfunction

    function [7:0] timeout_char;
        input [3:0] index;
        begin
            case (index)
                0:timeout_char="T"; 1:timeout_char="I"; 2:timeout_char="M"; 3:timeout_char="E";
                4:timeout_char=" "; 5:timeout_char="R"; 6:timeout_char="U"; 7:timeout_char="N";
                8:timeout_char=" "; 9:timeout_char="O"; 10:timeout_char="U"; default:timeout_char="T";
            endcase
        end
    endfunction

    function [7:0] duration_char;
        input [2:0] option;
        input [2:0] index;
        begin
            if (option < 3) begin
                case (index)
                    0: duration_char = (option==0) ? "1" : (option==1) ? "3" : "5";
                    1: duration_char = " "; 2: duration_char = "M";
                    3: duration_char = "I"; 4: duration_char = "N";
                    default: duration_char = " ";
                endcase
            end else begin
                case (index)
                    0: duration_char = "1"; 1: duration_char = (option==3) ? "0" : "5";
                    2: duration_char = " "; 3: duration_char = "M";
                    4: duration_char = "I"; default: duration_char = "N";
                endcase
            end
        end
    endfunction

    function [7:0] irq_char;
        input [3:0] index;
        begin
            case (index)
                0: irq_char="P"; 1: irq_char="E"; 2: irq_char="R";
                3: irq_char="F"; 4: irq_char=" "; 5: irq_char="R";
                6: irq_char="E"; 7: irq_char="P"; 8: irq_char="O";
                9: irq_char="R"; default: irq_char="T";
            endcase
        end
    endfunction

    wire score_region = game_area && (game_y >= 11'd12) && (game_y < 11'd40) &&
                        (pixel_x >= 11'd352) && (pixel_x < 11'd448);
    wire [1:0] score_index = (pixel_x - 11'd352) >> 5;
    wire [4:0] score_col = (pixel_x - 11'd352) & 11'h01f;
    wire [2:0] score_row = (game_y - 11'd12) >> 2;
    wire score_pixel_on = score_region && font_pixel(score_char(score_index), score_col >> 2, score_row);

    wire winner_region = round_over && game_area && (game_y >= 11'd92) && (game_y < 11'd120) &&
                         (pixel_x >= 11'd288) && (pixel_x < 11'd512);
    wire [3:0] winner_index = (pixel_x - 11'd288) >> 5;
    wire [4:0] winner_col = (pixel_x - 11'd288) & 11'h01f;
    wire [2:0] winner_row = (game_y - 11'd92) >> 2;
    wire winner_pixel_on = winner_region && font_pixel(winner_char(winner_index), winner_col >> 2, winner_row);

    wire over_region = round_over && game_area && (game_y >= 11'd128) && (game_y < 11'd156) &&
                       (pixel_x >= 11'd256) && (pixel_x < 11'd544);
    wire [3:0] over_index = (pixel_x - 11'd256) >> 5;
    wire [4:0] over_col = (pixel_x - 11'd256) & 11'h01f;
    wire [2:0] over_row = (game_y - 11'd128) >> 2;
    wire over_pixel_on = over_region && font_pixel(game_over_char(over_index), over_col >> 2, over_row);

    // Mode menu: selected Chinese label is enlarged from 3x to 4x.
    wire mode_left_region = menu_active && !menu_select_pvp && (pixel_x >= 11'd206) && (pixel_x < 11'd334) && (game_y >= 11'd214) && (game_y < 11'd246);
    wire mode_right_region = menu_active && menu_select_pvp && (pixel_x >= 11'd466) && (pixel_x < 11'd594) && (game_y >= 11'd214) && (game_y < 11'd246);
    wire [1:0] mode_left_index = (pixel_x - 11'd206) >> 5;
    wire [1:0] mode_right_index = (pixel_x - 11'd466) >> 5;
    wire mode_left_text = mode_left_region && cn_pixel(mode_glyph(1'b0, mode_left_index), ((pixel_x-206) & 31) >> 1, (game_y-214) >> 1);
    wire mode_right_text = mode_right_region && cn_pixel(mode_glyph(1'b1, mode_right_index), ((pixel_x-466) & 31) >> 1, (game_y-214) >> 1);
    wire mode_left_small_region = menu_active && menu_select_pvp && (pixel_x>=238) && (pixel_x<302) && (game_y>=222) && (game_y<238);
    wire mode_right_small_region = menu_active && !menu_select_pvp && (pixel_x>=498) && (pixel_x<562) && (game_y>=222) && (game_y<238);
    wire mode_left_small_text = mode_left_small_region && cn_pixel(mode_glyph(1'b0,(pixel_x-238)>>4), (pixel_x-238)&15, game_y-222);
    wire mode_right_small_text = mode_right_small_region && cn_pixel(mode_glyph(1'b1,(pixel_x-498)>>4), (pixel_x-498)&15, game_y-222);
    wire mode_left_box = menu_active && !menu_select_pvp && (pixel_x>=180) && (pixel_x<360) && (game_y>=190) && (game_y<270) && ((pixel_x<184)||(pixel_x>=356)||(game_y<194)||(game_y>=266));
    wire mode_right_box = menu_active && menu_select_pvp && (pixel_x>=440) && (pixel_x<620) && (game_y>=190) && (game_y<270) && ((pixel_x<444)||(pixel_x>=616)||(game_y<194)||(game_y>=266));
    wire menu_pixel_on = mode_left_box | mode_right_box | mode_left_text | mode_right_text | mode_left_small_text | mode_right_small_text;

    // Five duration options. game_timer contains the selected duration in seconds.
    wire [2:0] time_option = (pixel_x < 205) ? 0 : (pixel_x < 335) ? 1 : (pixel_x < 465) ? 2 : (pixel_x < 595) ? 3 : 4;
    wire time_option_selected = ((time_option==0)&&(game_timer==60)) || ((time_option==1)&&(game_timer==180)) ||
                                ((time_option==2)&&(game_timer==300)) || ((time_option==3)&&(game_timer==600)) ||
                                ((time_option==4)&&(game_timer==900));
    wire time_cell = time_menu_active && (pixel_x>=75) && (pixel_x<725) && (game_y>=205) && (game_y<275);
    wire [10:0] time_cell_left = 75 + time_option * 130;
    wire time_box = time_cell && time_option_selected && ((pixel_x<time_cell_left+4)||(pixel_x>=time_cell_left+106)||(game_y<209)||(game_y>=271));
    wire time_text_region = time_cell && (pixel_x>=time_cell_left+19) && (pixel_x<time_cell_left+91) && (game_y>=226) && (game_y<240);
    wire [2:0] time_digit_index = (pixel_x-(time_cell_left+19)) / 12;
    wire time_text = time_text_region && font_pixel(duration_char(time_option,time_digit_index), ((pixel_x-(time_cell_left+19))%12)/2, (game_y-226)/2);
    wire time_menu_pixel_on = time_box | time_text;

    // Match clock below the score, formatted as MM:SS.
    wire clock_region = game_area && !menu_active && !time_menu_active && !time_run_out && (pixel_x>=340) && (pixel_x<460) && (game_y>=44) && (game_y<72);
    wire [2:0] clock_index = (pixel_x-340) / 24;
    wire clock_pixel_on = clock_region && font_pixel(timer_char(clock_index), ((pixel_x-340)%24)/3, (game_y-44)/4);

    wire timeout_region = time_run_out && (pixel_x>=208) && (pixel_x<592) && (game_y>=220) && (game_y<248);
    wire [3:0] timeout_index = (pixel_x-208) >> 5;
    wire timeout_pixel_on = timeout_region && font_pixel(timeout_char(timeout_index), ((pixel_x-208)&31)>>2, (game_y-220)>>2);

    wire irq_region = irq_result_active && (pixel_x>=224) && (pixel_x<576) && (game_y>=220) && (game_y<248);
    wire [3:0] irq_index = (pixel_x-224) >> 5;
    wire irq_pixel_on = irq_region && font_pixel(irq_char(irq_index), ((pixel_x-224)&31)>>2, (game_y-220)>>2);

    wire ui_pixel_on = score_pixel_on | clock_pixel_on | winner_pixel_on | over_pixel_on;
    wire [3:0] base_r = {game_r, game_r[2]};
    wire [3:0] base_g = {game_g, game_g};
    wire [3:0] base_b = {game_b, game_b[2]};

    assign vga_r = game_area ? (irq_result_active ? (irq_pixel_on ? 4'hf : 4'h0) :
                               time_run_out ? (timeout_pixel_on ? 4'hf : 4'h0) :
                               menu_active ? (menu_pixel_on ? 4'hf : 4'h1) :
                               time_menu_active ? (time_menu_pixel_on ? 4'hf : 4'h1) :
                               (ui_pixel_on ? 4'hf : base_r)) : 4'h0;
    assign vga_g = game_area ? (irq_result_active ? (irq_pixel_on ? 4'hf : 4'h0) :
                               time_run_out ? (timeout_pixel_on ? 4'hf : 4'h0) :
                               menu_active ? (menu_pixel_on ? 4'hf : 4'h1) :
                               time_menu_active ? (time_menu_pixel_on ? 4'hf : 4'h1) :
                               (ui_pixel_on ? ((score_pixel_on||clock_pixel_on) ? 4'hc : 4'hf) : base_g)) : 4'h0;
    assign vga_b = game_area ? (irq_result_active ? (irq_pixel_on ? 4'hf : 4'h0) :
                               time_run_out ? (timeout_pixel_on ? 4'hf : 4'h0) :
                               menu_active ? (menu_pixel_on ? 4'hf : 4'h3) :
                               time_menu_active ? (time_menu_pixel_on ? 4'hf : 4'h3) :
                               (ui_pixel_on ? 4'h0 : base_b)) : 4'h0;

endmodule
