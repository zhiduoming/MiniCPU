// ============================================================================
// 模块功能：视频绘制模块（集成蓝量条+远程投射物+补血剂绘制）
// - 分辨率 800x480 @ 60Hz VGA
// - 绘制背景、血条/蓝条、角色精灵、投射物、补血剂、游戏结束文字等
// - 所有异步输入经过两级同步 + 脉冲延长，避免亚稳态
// ============================================================================

module video_draw(
    input         pixel_clk,
    input         reset,
    input  [10:0] pixel_x, pixel_y,
    // 角色参数
    input  [10:0] p1_x, p1_y, p2_x, p2_y,
    input         p1_dir, p2_dir,
    input         p1_attack, p2_attack,
    input         p1_jump, p2_jump,
    input         collision,
    input         p1_got_hit, p2_got_hit,
    input  [7:0]  p1_hp, p2_hp,
    // 蓝量与投射物
    input  [6:0]  p1_mp, p2_mp,
    input  [10:0] proj1_x, proj1_y, proj2_x, proj2_y,
    input         proj1_active, proj2_active, proj1_dir, proj2_dir,
    // 补血剂
    input  [10:0] medicine_x, medicine_y,
    input         medicine_active,
    // Debug 等
    input  [3:0]  debug_col,
    input  [3:0]  debug_row,
    input         game_state,
    input         time_error,
    input  [15:0] total_time,
    input  [15:0] countdown,
    input         time_lock,
    // VGA 颜色输出
    output reg [2:0] lcd_r,
    output reg [1:0] lcd_g,
    output reg [2:0] lcd_b
);

// ==================== 1. 全局参数定义 ====================
parameter SCREEN_W        = 11'd800;
parameter SCREEN_H        = 11'd480;
parameter TOTAL_HP        = 8'd100;
parameter BG_DEPTH        = 384000;   

parameter GROUND_Y        = 11'd479;

parameter SPRITE_W_MAX    = 11'd48;
parameter SPRITE_H_MAX    = 11'd64;
parameter SPRITE_W_NORMAL = 11'd40;
parameter FRAME_PIXEL     = 14'd3072;
parameter FRAME_IDLE      = 2'd0;
parameter FRAME_JUMP      = 2'd1;
parameter FRAME_ATTACK    = 2'd2;
parameter FRAME_HIT       = 2'd3;

// 血条参数
parameter HP_BAR_Y      = 11'd420;
parameter HP_BAR_H      = 11'd20;
parameter HP_BAR_W      = 11'd200;
parameter HP_BAR_BOX_W  = 11'd204;
parameter HP_BAR_BOX_H  = 11'd24;
parameter P1_HP_X       = 11'd50;
parameter P2_HP_X       = 11'd546;

// 蓝条参数（位于血条上方）
parameter MP_BAR_Y      = HP_BAR_Y - MP_BAR_BOX_H - 5;   // 420-16-5=399
parameter MP_BAR_H      = 11'd12;
parameter MP_BAR_W      = 11'd200;
parameter MP_BAR_BOX_W  = 11'd204;
parameter MP_BAR_BOX_H  = 11'd16;
parameter P1_MP_X       = P1_HP_X;
parameter P2_MP_X       = P2_HP_X;
parameter MP_MAX        = 7'd100;

// 数字字符参数
parameter CHAR_WIDTH  = 11'd8;
parameter CHAR_HEIGHT = 11'd8;
parameter CHAR_SPACE  = 11'd1;
// 血条数字位置 (P1)
parameter P1_NUM_BASE_X = P1_HP_X + HP_BAR_BOX_W + 10;
parameter P1_NUM_Y      = HP_BAR_Y ;
parameter P1_CHAR0_X = P1_NUM_BASE_X;
parameter P1_CHAR1_X = P1_CHAR0_X + CHAR_WIDTH + CHAR_SPACE;
parameter P1_CHAR2_X = P1_CHAR1_X + CHAR_WIDTH + CHAR_SPACE;
parameter P1_CHAR3_X = P1_CHAR2_X + CHAR_WIDTH + CHAR_SPACE;
parameter P1_CHAR4_X = P1_CHAR3_X + CHAR_WIDTH + CHAR_SPACE;
parameter P1_CHAR5_X = P1_CHAR4_X + CHAR_WIDTH + CHAR_SPACE;
parameter P1_CHAR6_X = P1_CHAR5_X + CHAR_WIDTH + CHAR_SPACE;
// 血条数字位置 (P2)
parameter P2_NUM_BASE_X = P2_HP_X - 6*CHAR_WIDTH - 5*CHAR_SPACE - 10;
parameter P2_NUM_Y      = HP_BAR_Y ;
parameter P2_CHAR0_X = P2_NUM_BASE_X;
parameter P2_CHAR1_X = P2_CHAR0_X + CHAR_WIDTH + CHAR_SPACE;
parameter P2_CHAR2_X = P2_CHAR1_X + CHAR_WIDTH + CHAR_SPACE;
parameter P2_CHAR3_X = P2_CHAR2_X + CHAR_WIDTH + CHAR_SPACE;
parameter P2_CHAR4_X = P2_CHAR3_X + CHAR_WIDTH + CHAR_SPACE;
parameter P2_CHAR5_X = P2_CHAR4_X + CHAR_WIDTH + CHAR_SPACE;
parameter P2_CHAR6_X = P2_CHAR5_X + CHAR_WIDTH + CHAR_SPACE;

// 蓝量数字位置 (P1)
parameter P1_MP_NUM_BASE_X = P1_MP_X + MP_BAR_BOX_W + 10;
parameter P1_MP_NUM_Y      = MP_BAR_Y;
parameter P1_MP_CHAR0_X = P1_MP_NUM_BASE_X;
parameter P1_MP_CHAR1_X = P1_MP_CHAR0_X + CHAR_WIDTH + CHAR_SPACE;
parameter P1_MP_CHAR2_X = P1_MP_CHAR1_X + CHAR_WIDTH + CHAR_SPACE;
parameter P1_MP_CHAR3_X = P1_MP_CHAR2_X + CHAR_WIDTH + CHAR_SPACE;
parameter P1_MP_CHAR4_X = P1_MP_CHAR3_X + CHAR_WIDTH + CHAR_SPACE;
parameter P1_MP_CHAR5_X = P1_MP_CHAR4_X + CHAR_WIDTH + CHAR_SPACE;
parameter P1_MP_CHAR6_X = P1_MP_CHAR5_X + CHAR_WIDTH + CHAR_SPACE;
// 蓝量数字位置 (P2)
parameter P2_MP_NUM_BASE_X = P2_MP_X - 6*CHAR_WIDTH - 5*CHAR_SPACE - 10;
parameter P2_MP_NUM_Y      = MP_BAR_Y;
parameter P2_MP_CHAR0_X = P2_MP_NUM_BASE_X;
parameter P2_MP_CHAR1_X = P2_MP_CHAR0_X + CHAR_WIDTH + CHAR_SPACE;
parameter P2_MP_CHAR2_X = P2_MP_CHAR1_X + CHAR_WIDTH + CHAR_SPACE;
parameter P2_MP_CHAR3_X = P2_MP_CHAR2_X + CHAR_WIDTH + CHAR_SPACE;
parameter P2_MP_CHAR4_X = P2_MP_CHAR3_X + CHAR_WIDTH + CHAR_SPACE;
parameter P2_MP_CHAR5_X = P2_MP_CHAR4_X + CHAR_WIDTH + CHAR_SPACE;
parameter P2_MP_CHAR6_X = P2_MP_CHAR5_X + CHAR_WIDTH + CHAR_SPACE;

// Game Over 显示参数
parameter GAME_OVER_X_START = SCREEN_W/2 - (9*CHAR_WIDTH)/2;
parameter GAME_OVER_Y       = SCREEN_H/2 - CHAR_HEIGHT - 4;
parameter WINNER_X_START    = SCREEN_W/2 - (6*CHAR_WIDTH)/2;
parameter WINNER_Y          = SCREEN_H/2 + CHAR_HEIGHT + 4;

// Debug 显示参数
parameter DEBUG_BASE_X     = 11'd10;
parameter DEBUG_BASE_Y     = 11'd10;
parameter DEBUG_COL_TEXT_X = DEBUG_BASE_X;
parameter DEBUG_COL_NUM_X  = DEBUG_BASE_X + 3*CHAR_WIDTH;
parameter DEBUG_ROW_TEXT_X = DEBUG_BASE_X;
parameter DEBUG_ROW_NUM_X  = DEBUG_BASE_X + 3*CHAR_WIDTH;
parameter DEBUG_COL_Y      = DEBUG_BASE_Y;
parameter DEBUG_ROW_Y      = DEBUG_BASE_Y + CHAR_HEIGHT + CHAR_SPACE;
parameter DEBUG_ROW_BIT0_X = DEBUG_ROW_NUM_X;
parameter DEBUG_ROW_BIT1_X = DEBUG_ROW_BIT0_X + CHAR_WIDTH + CHAR_SPACE;
parameter DEBUG_ROW_BIT2_X = DEBUG_ROW_BIT1_X + CHAR_WIDTH + CHAR_SPACE;
parameter DEBUG_ROW_BIT3_X = DEBUG_ROW_BIT2_X + CHAR_WIDTH + CHAR_SPACE;

// System 图片参数
parameter SYSTEM_W         = 11'd400;
parameter SYSTEM_H         = 11'd240;
parameter SYSTEM_X_START   = (SCREEN_W - SYSTEM_W) / 2;
parameter SYSTEM_Y_START   = (SCREEN_H - SYSTEM_H) / 2;

// 补血剂参数
parameter MEDICINE_SIZE    = 11'd25;

// ==================== 跨时钟域同步 + 脉冲延长 ====================
// 两级同步器，将异步输入信号同步到 pixel_clk 域
reg p1_attack_sync1, p1_attack_sync2;
reg p2_attack_sync1, p2_attack_sync2;
reg p1_jump_sync1,   p1_jump_sync2;
reg p2_jump_sync1,   p2_jump_sync2;
reg p1_got_hit_sync1, p1_got_hit_sync2;
reg p2_got_hit_sync1, p2_got_hit_sync2;

always @(posedge pixel_clk) begin
    p1_attack_sync1 <= p1_attack;
    p2_attack_sync1 <= p2_attack;
    p1_jump_sync1   <= p1_jump;
    p2_jump_sync1   <= p2_jump;
    p1_got_hit_sync1<= p1_got_hit;
    p2_got_hit_sync1<= p2_got_hit;
    
    p1_attack_sync2 <= p1_attack_sync1;
    p2_attack_sync2 <= p2_attack_sync1;
    p1_jump_sync2   <= p1_jump_sync1;
    p2_jump_sync2   <= p2_jump_sync1;
    p1_got_hit_sync2<= p1_got_hit_sync1;
    p2_got_hit_sync2<= p2_got_hit_sync1;
end

// 脉冲延长：确保动画至少显示固定帧数（避免过快消失）
reg p1_attack_ext, p2_attack_ext;
reg p1_jump_ext,   p2_jump_ext;
reg p1_got_hit_ext, p2_got_hit_ext;
reg [11:0] p1_attack_cnt, p2_attack_cnt;
reg [11:0] p1_jump_cnt,   p2_jump_cnt;
reg [11:0] p1_got_hit_cnt, p2_got_hit_cnt;

localparam EXT_HOLD = 12'd800;   // 延长帧数（约13ms @60Hz）

always @(posedge pixel_clk or posedge reset) begin
    if (reset) begin
        p1_attack_ext <= 0; p1_attack_cnt <= 0;
        p2_attack_ext <= 0; p2_attack_cnt <= 0;
        p1_jump_ext   <= 0; p1_jump_cnt   <= 0;
        p2_jump_ext   <= 0; p2_jump_cnt   <= 0;
        p1_got_hit_ext<= 0; p1_got_hit_cnt<= 0;
        p2_got_hit_ext<= 0; p2_got_hit_cnt<= 0;
    end else begin
        // P1 攻击延长
        if (p1_attack_sync2 && !p1_attack_ext) begin
            p1_attack_ext <= 1;
            p1_attack_cnt <= EXT_HOLD;
        end else if (p1_attack_cnt > 0) begin
            p1_attack_cnt <= p1_attack_cnt - 1;
        end else begin
            p1_attack_ext <= 0;
        end
        // P2 攻击延长
        if (p2_attack_sync2 && !p2_attack_ext) begin
            p2_attack_ext <= 1;
            p2_attack_cnt <= EXT_HOLD;
        end else if (p2_attack_cnt > 0) begin
            p2_attack_cnt <= p2_attack_cnt - 1;
        end else begin
            p2_attack_ext <= 0;
        end
        // 跳跃延长
        if (p1_jump_sync2 && !p1_jump_ext) begin
            p1_jump_ext <= 1;
            p1_jump_cnt <= EXT_HOLD;
        end else if (p1_jump_cnt > 0) begin
            p1_jump_cnt <= p1_jump_cnt - 1;
        end else begin
            p1_jump_ext <= 0;
        end
        if (p2_jump_sync2 && !p2_jump_ext) begin
            p2_jump_ext <= 1;
            p2_jump_cnt <= EXT_HOLD;
        end else if (p2_jump_cnt > 0) begin
            p2_jump_cnt <= p2_jump_cnt - 1;
        end else begin
            p2_jump_ext <= 0;
        end
        // 受击延长
        if (p1_got_hit_sync2 && !p1_got_hit_ext) begin
            p1_got_hit_ext <= 1;
            p1_got_hit_cnt <= EXT_HOLD;
        end else if (p1_got_hit_cnt > 0) begin
            p1_got_hit_cnt <= p1_got_hit_cnt - 1;
        end else begin
            p1_got_hit_ext <= 0;
        end
        if (p2_got_hit_sync2 && !p2_got_hit_ext) begin
            p2_got_hit_ext <= 1;
            p2_got_hit_cnt <= EXT_HOLD;
        end else if (p2_got_hit_cnt > 0) begin
            p2_got_hit_cnt <= p2_got_hit_cnt - 1;
        end else begin
            p2_got_hit_ext <= 0;
        end
    end
end

// ==================== 帧锁存（整场一致性） ====================
// 每帧开始（pixel_x=0, pixel_y=0）时锁存当前状态，保证同一帧内数据一致
reg [10:0] p1_x_s, p1_y_s, p2_x_s, p2_y_s;
reg        p1_attack_s, p2_attack_s;
reg        p1_jump_s, p2_jump_s;
reg        p1_got_hit_s, p2_got_hit_s;

// 投射物帧锁存
reg [10:0] proj1_x_s, proj1_y_s, proj2_x_s, proj2_y_s;
reg proj1_active_s, proj2_active_s, proj1_dir_s, proj2_dir_s;

// 补血剂帧锁存
reg [10:0] medicine_x_s, medicine_y_s;
reg        medicine_active_s;

always @(posedge pixel_clk) begin
    if (pixel_x == 11'd0 && pixel_y == 11'd0) begin
        p1_x_s       <= p1_x;
        p1_y_s       <= p1_y;
        p2_x_s       <= p2_x;
        p2_y_s       <= p2_y;
        
        p1_attack_s  <= p1_attack_ext;
        p2_attack_s  <= p2_attack_ext;
        p1_jump_s    <= p1_jump_ext;
        p2_jump_s    <= p2_jump_ext;
        
        p1_got_hit_s <= p1_got_hit_ext;
        p2_got_hit_s <= p2_got_hit_ext;

        // 投射物同步锁存
        proj1_x_s <= proj1_x; proj1_y_s <= proj1_y; proj1_active_s <= proj1_active; proj1_dir_s <= proj1_dir;
        proj2_x_s <= proj2_x; proj2_y_s <= proj2_y; proj2_active_s <= proj2_active; proj2_dir_s <= proj2_dir;

        // 补血剂同步锁存
        medicine_x_s    <= medicine_x;
        medicine_y_s    <= medicine_y;
        medicine_active_s <= medicine_active;
    end
end

// ==================== 2. 背景ROM ====================
wire [7:0] bg_data;
wire [31:0] bg_addr_raw = pixel_y * SCREEN_W + pixel_x;
wire bg_valid = (bg_addr_raw < BG_DEPTH);
wire [18:0] bg_addr = bg_addr_raw[18:0];  
wire [7:0] bg_data_valid = bg_valid ? bg_data : 8'b0;  

background_rom u_bg_rom_bram (
  .clka(pixel_clk),
  .addra(bg_addr),
  .douta(bg_data)
);

wire [2:0] bg_r = bg_data_valid[7:5];
wire [1:0] bg_g = bg_data_valid[4:3];
wire [2:0] bg_b = bg_data_valid[2:0];

// ==================== 3. 精灵ROM ====================
wire [7:0] p1_sprite_data;
reg [13:0] p1_sprite_addr;
p1_sprite_rom p1_sprite_rom_inst (
  .clka(pixel_clk),
  .addra(p1_sprite_addr),
  .douta(p1_sprite_data)
);

wire [7:0] p2_sprite_data;
reg [13:0] p2_sprite_addr;
p2_sprite_rom p2_sprite_rom_inst (
  .clka(pixel_clk),
  .addra(p2_sprite_addr),
  .douta(p2_sprite_data)
);

// ==================== 4. System ROM 实例化 ====================
wire [7:0] system_data;
reg [17:0] system_addr;
system_rom u_system_rom (
  .clka(pixel_clk),
  .addra(system_addr),
  .douta(system_data)
);

wire system_display_en = time_lock; 
wire [10:0] sys_rel_x = pixel_x - SYSTEM_X_START;
wire [10:0] sys_rel_y = pixel_y - SYSTEM_Y_START;
wire system_area = system_display_en &&
                   (pixel_x >= SYSTEM_X_START) && (pixel_x < SYSTEM_X_START + SYSTEM_W) &&
                   (pixel_y >= SYSTEM_Y_START) && (pixel_y < SYSTEM_Y_START + SYSTEM_H);
wire system_pixel_valid = system_area; 

always @(*) begin
    if(system_area) begin
        system_addr = sys_rel_y * SYSTEM_W + sys_rel_x;
    end else begin
        system_addr = 18'd0;
    end
end

// ==================== 补血剂 ROM 实例化 ====================
wire [7:0] medicine_data;
reg  [9:0] medicine_addr;
medicine_rom u_medicine_rom (
    .clka(pixel_clk),
    .addra(medicine_addr),
    .douta(medicine_data)
);

wire medicine_area = medicine_active_s &&
                     (pixel_x >= medicine_x_s) && (pixel_x < medicine_x_s + MEDICINE_SIZE) &&
                     (pixel_y >= medicine_y_s) && (pixel_y < medicine_y_s + MEDICINE_SIZE);
wire [4:0] med_rel_x = pixel_x - medicine_x_s;
wire [4:0] med_rel_y = pixel_y - medicine_y_s;

always @(*) begin
    if (medicine_area)
        medicine_addr = (MEDICINE_SIZE - 1 - med_rel_y) * MEDICINE_SIZE + med_rel_x;
    else
        medicine_addr = 10'd0;
end

// ==================== 新增：投射物动画计数器（带复位） ====================
reg [3:0] proj_anim_cnt;
always @(posedge pixel_clk or posedge reset) begin
    if (reset)
        proj_anim_cnt <= 4'd0;
    else if (pixel_x == 0 && pixel_y == 0)
        proj_anim_cnt <= proj_anim_cnt + 1'b1;
end

// ==================== P2投射物粒子种子（带复位） ====================
reg [15:0] particle_seed;
always @(posedge pixel_clk or posedge reset) begin
    if (reset)
        particle_seed <= 16'h1234;
    else if (pixel_x == 0 && pixel_y == 0)
        particle_seed <= { proj_anim_cnt, 8'h9C };
end

// ==================== P1投射物：紫色正圆 ====================
wire signed [10:0] proj1_center_x = proj1_x_s + 11'd10;
wire signed [10:0] proj1_center_y = proj1_y_s + 11'd10;
wire signed [10:0] dx1 = pixel_x - proj1_center_x;
wire signed [10:0] dy1 = pixel_y - proj1_center_y;

wire [21:0] dx1_sq = dx1 * dx1;
wire [21:0] dy1_sq = dy1 * dy1;
wire [22:0] sum_sq = dx1_sq + dy1_sq;
wire [11:0] dist1_sq = sum_sq[11:0];

wire core   = (dist1_sq <= 12'd16);
wire mid    = (dist1_sq > 12'd16) && (dist1_sq <= 12'd49);
wire outer  = (dist1_sq > 12'd49) && (dist1_sq <= 12'd100);
wire proj1_valid = proj1_active_s && (core || mid || outer);

wire [3:0] pulse = proj_anim_cnt[3:0];
wire [2:0] proj1_r = core ? 3'b111 : (mid ? 3'b101 : ((pulse > 8) ? 3'b110 : 3'b101));
wire [1:0] proj1_g = core ? 2'b11 : 2'b00;
wire [2:0] proj1_b = 3'b111;

// ==================== P2投射物：中心十字 + 散点 ====================
wire [10:0] p2_center_x = proj2_x_s + 11'd10;
wire [10:0] p2_center_y = proj2_y_s + 11'd10;
wire signed [10:0] dx2 = pixel_x - p2_center_x;
wire signed [10:0] dy2 = pixel_y - p2_center_y;

wire cross_h = (dy2 > -11'sd2) && (dy2 < 11'sd2) && (dx2 > -11'sd10) && (dx2 < 11'sd10);
wire cross_v = (dx2 > -11'sd2) && (dx2 < 11'sd2) && (dy2 > -11'sd10) && (dy2 < 11'sd10);
wire center_cross = proj2_active_s && (cross_h || cross_v);

wire [15:0] x_val = { pixel_x[7:0], pixel_x[3:0] };
wire [15:0] y_val = { pixel_y[7:0], pixel_y[4:1] };
wire [15:0] mix = x_val ^ y_val ^ particle_seed ^ { proj_anim_cnt, 8'hA5 };
wire [15:0] lfsr = (mix ^ (mix >> 4)) * 16'h8805;

wire checkerboard = pixel_x[0] ^ pixel_y[0];
wire particle_on = (lfsr[4:0] == 5'b00000) && checkerboard;
wire particle_valid = proj2_active_s && particle_on && !center_cross;

wire [3:0] pulse2 = proj_anim_cnt[3:0];
wire [2:0] particle_r = 3'b000;
wire [1:0] particle_g = (lfsr[5] ^ pulse2[2]) ? 2'b11 : 2'b10;
wire [2:0] particle_b = (lfsr[6]) ? 3'b111 : 3'b101;

wire [2:0] cross_r = 3'b000;
wire [1:0] cross_g = 2'b11;
wire [2:0] cross_b = 3'b111;

wire proj2_valid = center_cross || particle_valid;
wire [2:0] proj2_r = center_cross ? cross_r : particle_r;
wire [1:0] proj2_g = center_cross ? cross_g : particle_g;
wire [2:0] proj2_b = center_cross ? cross_b : particle_b;

// ==================== 玩家1精灵变量 ====================
wire p1_dead = (p1_hp == 0);
wire p1_hit_flash;
reg [17:0] hit_shake_counter;
always @(posedge pixel_clk or posedge reset) begin
    if (reset)
        hit_shake_counter <= 18'd0;
    else
        hit_shake_counter <= hit_shake_counter + 1'b1;
end
wire p1_shake = p1_hit_flash && hit_shake_counter[16];
wire [10:0] p1_sprite_offset_x = p1_shake ? 11'd0 : ((p1_frame_sel == FRAME_HIT) ? 11'd0 : 11'd4);
wire [10:0] p1_sprite_width = (p1_frame_sel == FRAME_HIT) ? SPRITE_W_MAX : SPRITE_W_NORMAL;
wire [10:0] p1_sprite_x_start = p1_x_s + p1_sprite_offset_x;
wire [10:0] p1_sprite_x_end = p1_sprite_x_start + p1_sprite_width;
wire [10:0] p1_sprite_y_start = p1_y_s;
wire [10:0] p1_sprite_y_end_tmp = p1_y_s + SPRITE_H_MAX;
wire [10:0] p1_sprite_y_end = (p1_sprite_y_end_tmp > SCREEN_H) ? SCREEN_H : p1_sprite_y_end_tmp;

wire p1_sprite_area = (pixel_x >= p1_sprite_x_start) && (pixel_x < p1_sprite_x_end) &&
                      (pixel_y >= p1_sprite_y_start) && (pixel_y < p1_sprite_y_end);
wire [10:0] p1_temp_x = pixel_x - p1_sprite_x_start;
wire [10:0] p1_width_minus_1 = p1_sprite_width - 11'd1;
wire [10:0] p1_flip_x = p1_width_minus_1 - p1_temp_x;
wire [5:0] p1_sprite_x = p1_dir ? p1_temp_x[5:0] : p1_flip_x[5:0];
wire [10:0] p1_sprite_y_temp = pixel_y - p1_sprite_y_start;
wire [5:0] p1_sprite_y = (SPRITE_H_MAX - 1) - p1_sprite_y_temp[5:0];

// ==================== 玩家2精灵变量 ====================
wire p2_dead = (p2_hp == 0);
wire p2_hit_flash;
wire p2_shake = p2_hit_flash && hit_shake_counter[16];
wire [10:0] p2_sprite_offset_x = p2_shake ? 11'd0 : ((p2_frame_sel == FRAME_HIT) ? 11'd0 : 11'd4);
wire [10:0] p2_sprite_width = (p2_frame_sel == FRAME_HIT) ? SPRITE_W_MAX : SPRITE_W_NORMAL;
wire [10:0] p2_sprite_x_start = p2_x_s + p2_sprite_offset_x;
wire [10:0] p2_sprite_x_end = p2_sprite_x_start + p2_sprite_width;
wire [10:0] p2_sprite_y_start = p2_y_s;
wire [10:0] p2_sprite_y_end_tmp = p2_y_s + SPRITE_H_MAX;
wire [10:0] p2_sprite_y_end = (p2_sprite_y_end_tmp > SCREEN_H) ? SCREEN_H : p2_sprite_y_end_tmp;

wire p2_sprite_area = (pixel_x >= p2_sprite_x_start) && (pixel_x < p2_sprite_x_end) &&
                      (pixel_y >= p2_sprite_y_start) && (pixel_y < p2_sprite_y_end);
wire [10:0] p2_temp_x = pixel_x - p2_sprite_x_start;
wire [10:0] p2_width_minus_1 = p2_sprite_width - 11'd1;
wire [10:0] p2_flip_x = p2_width_minus_1 - p2_temp_x;
wire [5:0] p2_sprite_x = p2_dir ? p2_temp_x[5:0] : p2_flip_x[5:0];
wire [10:0] p2_sprite_y_temp = pixel_y - p2_sprite_y_start;
wire [5:0] p2_sprite_y = (SPRITE_H_MAX - 1) - p2_sprite_y_temp[5:0];

// ==================== 受击闪烁逻辑 ====================
reg p1_hp_bar_flash, p2_hp_bar_flash;
reg [21:0] flash_cnt_p1, flash_cnt_p2;
reg p1_got_hit_prev, p2_got_hit_prev;
always @(posedge pixel_clk or posedge reset) begin
    if(reset) begin
        p1_hp_bar_flash <= 1'b0;
        p2_hp_bar_flash <= 1'b0;
        flash_cnt_p1 <= 20'd0;
        flash_cnt_p2 <= 20'd0;
        p1_got_hit_prev <= 1'b0;
        p2_got_hit_prev <= 1'b0;
    end else begin
        p1_got_hit_prev <= p1_got_hit_s;
        p2_got_hit_prev <= p2_got_hit_s;

        if(!p1_got_hit_prev && p1_got_hit_s && !p1_dead) begin
            flash_cnt_p1 <= 20'd3375000;
            p1_hp_bar_flash <= 1'b1;
        end else if(flash_cnt_p1 > 20'd0) begin
            flash_cnt_p1 <= flash_cnt_p1 - 20'd1;
            p1_hp_bar_flash <= flash_cnt_p1[17];
        end else begin
            p1_hp_bar_flash <= 1'b0;
        end

        if(!p2_got_hit_prev && p2_got_hit_s && !p2_dead) begin
            flash_cnt_p2 <= 20'd3375000;
            p2_hp_bar_flash <= 1'b1;
        end else if(flash_cnt_p2 > 20'd0) begin
            flash_cnt_p2 <= flash_cnt_p2 - 20'd1;
            p2_hp_bar_flash <= flash_cnt_p2[17];
        end else begin
            p2_hp_bar_flash <= 1'b0;
        end
    end
end

assign p1_hit_flash = (flash_cnt_p1 > 20'd0) && !p1_dead;
assign p2_hit_flash = (flash_cnt_p2 > 20'd0) && !p2_dead;

// ==================== 帧选择：使用 case 语句（规范要求） ====================
reg [1:0] p1_frame_sel;
reg [1:0] p2_frame_sel;

always @(*) begin
    case (1'b1)  // 条件真值表
        p1_dead:      p1_frame_sel = FRAME_HIT;
        p1_attack_s:  p1_frame_sel = FRAME_ATTACK;
        p1_jump_s:    p1_frame_sel = FRAME_JUMP;
        default:      p1_frame_sel = FRAME_IDLE;
    endcase

    case (1'b1)
        p2_dead:      p2_frame_sel = FRAME_HIT;
        p2_attack_s:  p2_frame_sel = FRAME_ATTACK;
        p2_jump_s:    p2_frame_sel = FRAME_JUMP;
        default:      p2_frame_sel = FRAME_IDLE;
    endcase
end

// ==================== 精灵地址计算 ====================
always @(*) begin
    p1_sprite_addr = 14'd0;
    p2_sprite_addr = 14'd0;
    if(p1_sprite_area) begin
        p1_sprite_addr = p1_frame_sel * FRAME_PIXEL + p1_sprite_y * SPRITE_W_MAX + p1_sprite_x;
    end
    if(p2_sprite_area) begin
        p2_sprite_addr = p2_frame_sel * FRAME_PIXEL + p2_sprite_y * SPRITE_W_MAX + p2_sprite_x;
    end
end

// ==================== BCD转换 ====================
reg [3:0] p1_hp_hun, p1_hp_ten, p1_hp_one;
reg [3:0] p2_hp_hun, p2_hp_ten, p2_hp_one;
reg [3:0] p1_mp_hun, p1_mp_ten, p1_mp_one;
reg [3:0] p2_mp_hun, p2_mp_ten, p2_mp_one;
wire [3:0] total_hun = 4'd1;
wire [3:0] total_ten = 4'd0;
wire [3:0] total_one = 4'd0;

always @(*) begin
    // 血量BCD - 使用加减法避免除法器（范围0-100）
    p1_hp_hun = (p1_hp >= 8'd100) ? 4'd1 : 4'd0;
    p1_hp_ten = (p1_hp % 100) / 10;
    p1_hp_one = p1_hp % 10;

    p2_hp_hun = (p2_hp >= 8'd100) ? 4'd1 : 4'd0;
    p2_hp_ten = (p2_hp % 100) / 10;
    p2_hp_one = p2_hp % 10;

    // 蓝量BCD
    p1_mp_hun = (p1_mp >= 7'd100) ? 4'd1 : 4'd0;
    p1_mp_ten = (p1_mp % 100) / 10;
    p1_mp_one = p1_mp % 10;

    p2_mp_hun = (p2_mp >= 7'd100) ? 4'd1 : 4'd0;
    p2_mp_ten = (p2_mp % 100) / 10;
    p2_mp_one = p2_mp % 10;
end

// ==================== 8×8字模函数 ====================
function [7:0] char_font_row;
    input [7:0] ascii;
    input [2:0] row;
    begin
        case ({ascii, row})
            {8'd48, 3'd0}: char_font_row = 8'b00111100; {8'd48, 3'd1}: char_font_row = 8'b01000010;
            {8'd48, 3'd2}: char_font_row = 8'b01000010; {8'd48, 3'd3}: char_font_row = 8'b01000010;
            {8'd48, 3'd4}: char_font_row = 8'b01000010; {8'd48, 3'd5}: char_font_row = 8'b01000010;
            {8'd48, 3'd6}: char_font_row = 8'b01000010; {8'd48, 3'd7}: char_font_row = 8'b00111100;
            {8'd49, 3'd0}: char_font_row = 8'b00001000; {8'd49, 3'd1}: char_font_row = 8'b00011000;
            {8'd49, 3'd2}: char_font_row = 8'b00001000; {8'd49, 3'd3}: char_font_row = 8'b00001000;
            {8'd49, 3'd4}: char_font_row = 8'b00001000; {8'd49, 3'd5}: char_font_row = 8'b00001000;
            {8'd49, 3'd6}: char_font_row = 8'b00001000; {8'd49, 3'd7}: char_font_row = 8'b00111110;
            {8'd50, 3'd0}: char_font_row = 8'b00111100; {8'd50, 3'd1}: char_font_row = 8'b01000010;
            {8'd50, 3'd2}: char_font_row = 8'b00000010; {8'd50, 3'd3}: char_font_row = 8'b00000100;
            {8'd50, 3'd4}: char_font_row = 8'b00001000; {8'd50, 3'd5}: char_font_row = 8'b00010000;
            {8'd50, 3'd6}: char_font_row = 8'b00100000; {8'd50, 3'd7}: char_font_row = 8'b01111110;
            {8'd51, 3'd0}: char_font_row = 8'b00111100; {8'd51, 3'd1}: char_font_row = 8'b01000010;
            {8'd51, 3'd2}: char_font_row = 8'b00000010; {8'd51, 3'd3}: char_font_row = 8'b00001100;
            {8'd51, 3'd4}: char_font_row = 8'b00000010; {8'd51, 3'd5}: char_font_row = 8'b00000010;
            {8'd51, 3'd6}: char_font_row = 8'b01000010; {8'd51, 3'd7}: char_font_row = 8'b00111100;
            {8'd52, 3'd0}: char_font_row = 8'b00001000; {8'd52, 3'd1}: char_font_row = 8'b00011000;
            {8'd52, 3'd2}: char_font_row = 8'b00101000; {8'd52, 3'd3}: char_font_row = 8'b01001000;
            {8'd52, 3'd4}: char_font_row = 8'b11111110; {8'd52, 3'd5}: char_font_row = 8'b00001000;
            {8'd52, 3'd6}: char_font_row = 8'b00001000; {8'd52, 3'd7}: char_font_row = 8'b00011100;
            {8'd53, 3'd0}: char_font_row = 8'b01111100; {8'd53, 3'd1}: char_font_row = 8'b01000000;
            {8'd53, 3'd2}: char_font_row = 8'b01000000; {8'd53, 3'd3}: char_font_row = 8'b01111100;
            {8'd53, 3'd4}: char_font_row = 8'b00000010; {8'd53, 3'd5}: char_font_row = 8'b00000010;
            {8'd53, 3'd6}: char_font_row = 8'b01000010; {8'd53, 3'd7}: char_font_row = 8'b00111100;
            {8'd54, 3'd0}: char_font_row = 8'b00111100; {8'd54, 3'd1}: char_font_row = 8'b01000000;
            {8'd54, 3'd2}: char_font_row = 8'b01000000; {8'd54, 3'd3}: char_font_row = 8'b01111100;
            {8'd54, 3'd4}: char_font_row = 8'b01000010; {8'd54, 3'd5}: char_font_row = 8'b01000010;
            {8'd54, 3'd6}: char_font_row = 8'b01000010; {8'd54, 3'd7}: char_font_row = 8'b00111100;
            {8'd55, 3'd0}: char_font_row = 8'b01111110; {8'd55, 3'd1}: char_font_row = 8'b00000010;
            {8'd55, 3'd2}: char_font_row = 8'b00000100; {8'd55, 3'd3}: char_font_row = 8'b00001000;
            {8'd55, 3'd4}: char_font_row = 8'b00010000; {8'd55, 3'd5}: char_font_row = 8'b00010000;
            {8'd55, 3'd6}: char_font_row = 8'b00010000; {8'd55, 3'd7}: char_font_row = 8'b00010000;
            {8'd56, 3'd0}: char_font_row = 8'b00111100; {8'd56, 3'd1}: char_font_row = 8'b01000010;
            {8'd56, 3'd2}: char_font_row = 8'b01000010; {8'd56, 3'd3}: char_font_row = 8'b00111100;
            {8'd56, 3'd4}: char_font_row = 8'b01000010; {8'd56, 3'd5}: char_font_row = 8'b01000010;
            {8'd56, 3'd6}: char_font_row = 8'b01000010; {8'd56, 3'd7}: char_font_row = 8'b00111100;
            {8'd57, 3'd0}: char_font_row = 8'b00111100; {8'd57, 3'd1}: char_font_row = 8'b01000010;
            {8'd57, 3'd2}: char_font_row = 8'b01000010; {8'd57, 3'd3}: char_font_row = 8'b00111110;
            {8'd57, 3'd4}: char_font_row = 8'b00000010; {8'd57, 3'd5}: char_font_row = 8'b00000010;
            {8'd57, 3'd6}: char_font_row = 8'b01000010; {8'd57, 3'd7}: char_font_row = 8'b00111100;
            {8'd65, 3'd0}: char_font_row = 8'b00011000; {8'd65, 3'd1}: char_font_row = 8'b00100100;
            {8'd65, 3'd2}: char_font_row = 8'b01000010; {8'd65, 3'd3}: char_font_row = 8'b01111110;
            {8'd65, 3'd4}: char_font_row = 8'b01000010; {8'd65, 3'd5}: char_font_row = 8'b01000010;
            {8'd65, 3'd6}: char_font_row = 8'b01000010; {8'd65, 3'd7}: char_font_row = 8'b01000010;
            {8'd69, 3'd0}: char_font_row = 8'b01111110; {8'd69, 3'd1}: char_font_row = 8'b01000000;
            {8'd69, 3'd2}: char_font_row = 8'b01000000; {8'd69, 3'd3}: char_font_row = 8'b01111100;
            {8'd69, 3'd4}: char_font_row = 8'b01000000; {8'd69, 3'd5}: char_font_row = 8'b01000000;
            {8'd69, 3'd6}: char_font_row = 8'b01000000; {8'd69, 3'd7}: char_font_row = 8'b01111110;
            {8'd71, 3'd0}: char_font_row = 8'b00111100; {8'd71, 3'd1}: char_font_row = 8'b01000010;
            {8'd71, 3'd2}: char_font_row = 8'b01000000; {8'd71, 3'd3}: char_font_row = 8'b01000000;
            {8'd71, 3'd4}: char_font_row = 8'b01001110; {8'd71, 3'd5}: char_font_row = 8'b01000010;
            {8'd71, 3'd6}: char_font_row = 8'b01000010; {8'd71, 3'd7}: char_font_row = 8'b00111100;
            {8'd73, 3'd0}: char_font_row = 8'b00111110; {8'd73, 3'd1}: char_font_row = 8'b00001000;
            {8'd73, 3'd2}: char_font_row = 8'b00001000; {8'd73, 3'd3}: char_font_row = 8'b00001000;
            {8'd73, 3'd4}: char_font_row = 8'b00001000; {8'd73, 3'd5}: char_font_row = 8'b00001000;
            {8'd73, 3'd6}: char_font_row = 8'b00001000; {8'd73, 3'd7}: char_font_row = 8'b00111110;
            {8'd77, 3'd0}: char_font_row = 8'b01000010; {8'd77, 3'd1}: char_font_row = 8'b01100110;
            {8'd77, 3'd2}: char_font_row = 8'b01011010; {8'd77, 3'd3}: char_font_row = 8'b01000010;
            {8'd77, 3'd4}: char_font_row = 8'b01000010; {8'd77, 3'd5}: char_font_row = 8'b01000010;
            {8'd77, 3'd6}: char_font_row = 8'b01000010; {8'd77, 3'd7}: char_font_row = 8'b01000010;
            {8'd78, 3'd0}: char_font_row = 8'b01000010; {8'd78, 3'd1}: char_font_row = 8'b01100010;
            {8'd78, 3'd2}: char_font_row = 8'b01010010; {8'd78, 3'd3}: char_font_row = 8'b01001010;
            {8'd78, 3'd4}: char_font_row = 8'b01000110; {8'd78, 3'd5}: char_font_row = 8'b01000010;
            {8'd78, 3'd6}: char_font_row = 8'b01000010; {8'd78, 3'd7}: char_font_row = 8'b01000010;
            {8'd79, 3'd0}: char_font_row = 8'b00111100; {8'd79, 3'd1}: char_font_row = 8'b01000010;
            {8'd79, 3'd2}: char_font_row = 8'b01000010; {8'd79, 3'd3}: char_font_row = 8'b01000010;
            {8'd79, 3'd4}: char_font_row = 8'b01000010; {8'd79, 3'd5}: char_font_row = 8'b01000010;
            {8'd79, 3'd6}: char_font_row = 8'b01000010; {8'd79, 3'd7}: char_font_row = 8'b00111100;
            {8'd80, 3'd0}: char_font_row = 8'b01111100; {8'd80, 3'd1}: char_font_row = 8'b01000010;
            {8'd80, 3'd2}: char_font_row = 8'b01000010; {8'd80, 3'd3}: char_font_row = 8'b01111100;
            {8'd80, 3'd4}: char_font_row = 8'b01000000; {8'd80, 3'd5}: char_font_row = 8'b01000000;
            {8'd80, 3'd6}: char_font_row = 8'b01000000; {8'd80, 3'd7}: char_font_row = 8'b00000000;
            {8'd82, 3'd0}: char_font_row = 8'b01111100; {8'd82, 3'd1}: char_font_row = 8'b01000010;
            {8'd82, 3'd2}: char_font_row = 8'b01000010; {8'd82, 3'd3}: char_font_row = 8'b01111100;
            {8'd82, 3'd4}: char_font_row = 8'b01001000; {8'd82, 3'd5}: char_font_row = 8'b01000100;
            {8'd82, 3'd6}: char_font_row = 8'b01000010; {8'd82, 3'd7}: char_font_row = 8'b01000001;
            {8'd86, 3'd0}: char_font_row = 8'b01000010; {8'd86, 3'd1}: char_font_row = 8'b01000010;
            {8'd86, 3'd2}: char_font_row = 8'b01000010; {8'd86, 3'd3}: char_font_row = 8'b01000010;
            {8'd86, 3'd4}: char_font_row = 8'b01000010; {8'd86, 3'd5}: char_font_row = 8'b00100100;
            {8'd86, 3'd6}: char_font_row = 8'b00011000; {8'd86, 3'd7}: char_font_row = 8'b00000000;
            {8'd87, 3'd0}: char_font_row = 8'b01000010; {8'd87, 3'd1}: char_font_row = 8'b01000010;
            {8'd87, 3'd2}: char_font_row = 8'b01010101; {8'd87, 3'd3}: char_font_row = 8'b01010101;
            {8'd87, 3'd4}: char_font_row = 8'b01010101; {8'd87, 3'd5}: char_font_row = 8'b01010101;
            {8'd87, 3'd6}: char_font_row = 8'b00101010; {8'd87, 3'd7}: char_font_row = 8'b00000000;
            {8'd47, 3'd0}: char_font_row = 8'b00000010; {8'd47, 3'd1}: char_font_row = 8'b00000100;
            {8'd47, 3'd2}: char_font_row = 8'b00001000; {8'd47, 3'd3}: char_font_row = 8'b00010000;
            {8'd47, 3'd4}: char_font_row = 8'b00100000; {8'd47, 3'd5}: char_font_row = 8'b01000000;
            {8'd47, 3'd6}: char_font_row = 8'b00000000; {8'd47, 3'd7}: char_font_row = 8'b00000000;
            default: char_font_row = 8'b00000000;
        endcase
    end
endfunction

// ==================== 血条数字绘制（P1） ====================
reg p1_char_pixel;
reg [3:0] p1_curr_digit;
reg [2:0] p1_curr_row;
reg [2:0] p1_curr_col;
reg [7:0] p1_curr_font_row;
always @(*) begin
    p1_char_pixel = 1'b0;
    p1_curr_digit = 4'd0;
    p1_curr_row = 3'd0;
    p1_curr_col = 3'd0;
    p1_curr_font_row = 8'd0;

    if(pixel_y >= P1_NUM_Y && pixel_y < P1_NUM_Y + CHAR_HEIGHT) begin
        p1_curr_row = (CHAR_HEIGHT - 1) - (pixel_y - P1_NUM_Y);
        if(pixel_x >= P1_CHAR0_X && pixel_x < P1_CHAR0_X + CHAR_WIDTH) begin
            p1_curr_col = pixel_x - P1_CHAR0_X;
            p1_curr_digit = p1_hp_hun;
            p1_curr_font_row = char_font_row(8'd48 + p1_curr_digit, p1_curr_row);
            p1_char_pixel = p1_curr_font_row[7 - p1_curr_col];
        end else if(pixel_x >= P1_CHAR1_X && pixel_x < P1_CHAR1_X + CHAR_WIDTH) begin
            p1_curr_col = pixel_x - P1_CHAR1_X;
            p1_curr_digit = p1_hp_ten;
            p1_curr_font_row = char_font_row(8'd48 + p1_curr_digit, p1_curr_row);
            p1_char_pixel = p1_curr_font_row[7 - p1_curr_col];
        end else if(pixel_x >= P1_CHAR2_X && pixel_x < P1_CHAR2_X + CHAR_WIDTH) begin
            p1_curr_col = pixel_x - P1_CHAR2_X;
            p1_curr_digit = p1_hp_one;
            p1_curr_font_row = char_font_row(8'd48 + p1_curr_digit, p1_curr_row);
            p1_char_pixel = p1_curr_font_row[7 - p1_curr_col];
        end else if(pixel_x >= P1_CHAR3_X && pixel_x < P1_CHAR3_X + CHAR_WIDTH) begin
            p1_curr_col = pixel_x - P1_CHAR3_X;
            p1_curr_font_row = char_font_row(8'd47, p1_curr_row);
            p1_char_pixel = p1_curr_font_row[7 - p1_curr_col];
        end else if(pixel_x >= P1_CHAR4_X && pixel_x < P1_CHAR4_X + CHAR_WIDTH) begin
            p1_curr_col = pixel_x - P1_CHAR4_X;
            p1_curr_font_row = char_font_row(8'd48 + total_hun, p1_curr_row);
            p1_char_pixel = p1_curr_font_row[7 - p1_curr_col];
        end else if(pixel_x >= P1_CHAR5_X && pixel_x < P1_CHAR5_X + CHAR_WIDTH) begin
            p1_curr_col = pixel_x - P1_CHAR5_X;
            p1_curr_font_row = char_font_row(8'd48 + total_ten, p1_curr_row);
            p1_char_pixel = p1_curr_font_row[7 - p1_curr_col];
        end else if(pixel_x >= P1_CHAR6_X && pixel_x < P1_CHAR6_X + CHAR_WIDTH) begin
            p1_curr_col = pixel_x - P1_CHAR6_X;
            p1_curr_font_row = char_font_row(8'd48 + total_one, p1_curr_row);
            p1_char_pixel = p1_curr_font_row[7 - p1_curr_col];
        end
    end
end

// ==================== 血条数字绘制（P2） ====================
reg p2_char_pixel;
reg [3:0] p2_curr_digit;
reg [2:0] p2_curr_row;
reg [2:0] p2_curr_col;
reg [7:0] p2_curr_font_row;
always @(*) begin
    p2_char_pixel = 1'b0;
    p2_curr_digit = 4'd0;
    p2_curr_row = 3'd0;
    p2_curr_col = 3'd0;
    p2_curr_font_row = 8'd0;

    if(pixel_y >= P2_NUM_Y && pixel_y < P2_NUM_Y + CHAR_HEIGHT) begin
        p2_curr_row = (CHAR_HEIGHT - 1) - (pixel_y - P2_NUM_Y);
        if(pixel_x >= P2_CHAR0_X && pixel_x < P2_CHAR0_X + CHAR_WIDTH) begin
            p2_curr_col = pixel_x - P2_CHAR0_X;
            p2_curr_digit = p2_hp_hun;
            p2_curr_font_row = char_font_row(8'd48 + p2_curr_digit, p2_curr_row);
            p2_char_pixel = p2_curr_font_row[7 - p2_curr_col];
        end else if(pixel_x >= P2_CHAR1_X && pixel_x < P2_CHAR1_X + CHAR_WIDTH) begin
            p2_curr_col = pixel_x - P2_CHAR1_X;
            p2_curr_digit = p2_hp_ten;
            p2_curr_font_row = char_font_row(8'd48 + p2_curr_digit, p2_curr_row);
            p2_char_pixel = p2_curr_font_row[7 - p2_curr_col];
        end else if(pixel_x >= P2_CHAR2_X && pixel_x < P2_CHAR2_X + CHAR_WIDTH) begin
            p2_curr_col = pixel_x - P2_CHAR2_X;
            p2_curr_digit = p2_hp_one;
            p2_curr_font_row = char_font_row(8'd48 + p2_curr_digit, p2_curr_row);
            p2_char_pixel = p2_curr_font_row[7 - p2_curr_col];
        end else if(pixel_x >= P2_CHAR3_X && pixel_x < P2_CHAR3_X + CHAR_WIDTH) begin
            p2_curr_col = pixel_x - P2_CHAR3_X;
            p2_curr_font_row = char_font_row(8'd47, p2_curr_row);
            p2_char_pixel = p2_curr_font_row[7 - p2_curr_col];
        end else if(pixel_x >= P2_CHAR4_X && pixel_x < P2_CHAR4_X + CHAR_WIDTH) begin
            p2_curr_col = pixel_x - P2_CHAR4_X;
            p2_curr_font_row = char_font_row(8'd48 + total_hun, p2_curr_row);
            p2_char_pixel = p2_curr_font_row[7 - p2_curr_col];
        end else if(pixel_x >= P2_CHAR5_X && pixel_x < P2_CHAR5_X + CHAR_WIDTH) begin
            p2_curr_col = pixel_x - P2_CHAR5_X;
            p2_curr_font_row = char_font_row(8'd48 + total_ten, p2_curr_row);
            p2_char_pixel = p2_curr_font_row[7 - p2_curr_col];
        end else if(pixel_x >= P2_CHAR6_X && pixel_x < P2_CHAR6_X + CHAR_WIDTH) begin
            p2_curr_col = pixel_x - P2_CHAR6_X;
            p2_curr_font_row = char_font_row(8'd48 + total_one, p2_curr_row);
            p2_char_pixel = p2_curr_font_row[7 - p2_curr_col];
        end
    end
end

// ==================== 蓝量数字绘制（P1） ====================
reg p1_mp_char_pixel;
reg [3:0] p1_mp_curr_digit;
reg [2:0] p1_mp_curr_row;
reg [2:0] p1_mp_curr_col;
reg [7:0] p1_mp_curr_font_row;
always @(*) begin
    p1_mp_char_pixel = 1'b0;
    p1_mp_curr_digit = 4'd0;
    p1_mp_curr_row = 3'd0;
    p1_mp_curr_col = 3'd0;
    p1_mp_curr_font_row = 8'd0;

    if(pixel_y >= P1_MP_NUM_Y && pixel_y < P1_MP_NUM_Y + CHAR_HEIGHT) begin
        p1_mp_curr_row = (CHAR_HEIGHT - 1) - (pixel_y - P1_MP_NUM_Y);
        if(pixel_x >= P1_MP_CHAR0_X && pixel_x < P1_MP_CHAR0_X + CHAR_WIDTH) begin
            p1_mp_curr_col = pixel_x - P1_MP_CHAR0_X;
            p1_mp_curr_digit = p1_mp_hun;
            p1_mp_curr_font_row = char_font_row(8'd48 + p1_mp_curr_digit, p1_mp_curr_row);
            p1_mp_char_pixel = p1_mp_curr_font_row[7 - p1_mp_curr_col];
        end else if(pixel_x >= P1_MP_CHAR1_X && pixel_x < P1_MP_CHAR1_X + CHAR_WIDTH) begin
            p1_mp_curr_col = pixel_x - P1_MP_CHAR1_X;
            p1_mp_curr_digit = p1_mp_ten;
            p1_mp_curr_font_row = char_font_row(8'd48 + p1_mp_curr_digit, p1_mp_curr_row);
            p1_mp_char_pixel = p1_mp_curr_font_row[7 - p1_mp_curr_col];
        end else if(pixel_x >= P1_MP_CHAR2_X && pixel_x < P1_MP_CHAR2_X + CHAR_WIDTH) begin
            p1_mp_curr_col = pixel_x - P1_MP_CHAR2_X;
            p1_mp_curr_digit = p1_mp_one;
            p1_mp_curr_font_row = char_font_row(8'd48 + p1_mp_curr_digit, p1_mp_curr_row);
            p1_mp_char_pixel = p1_mp_curr_font_row[7 - p1_mp_curr_col];
        end else if(pixel_x >= P1_MP_CHAR3_X && pixel_x < P1_MP_CHAR3_X + CHAR_WIDTH) begin
            p1_mp_curr_col = pixel_x - P1_MP_CHAR3_X;
            p1_mp_curr_font_row = char_font_row(8'd47, p1_mp_curr_row);
            p1_mp_char_pixel = p1_mp_curr_font_row[7 - p1_mp_curr_col];
        end else if(pixel_x >= P1_MP_CHAR4_X && pixel_x < P1_MP_CHAR4_X + CHAR_WIDTH) begin
            p1_mp_curr_col = pixel_x - P1_MP_CHAR4_X;
            p1_mp_curr_font_row = char_font_row(8'd48 + 4'd1, p1_mp_curr_row);
            p1_mp_char_pixel = p1_mp_curr_font_row[7 - p1_mp_curr_col];
        end else if(pixel_x >= P1_MP_CHAR5_X && pixel_x < P1_MP_CHAR5_X + CHAR_WIDTH) begin
            p1_mp_curr_col = pixel_x - P1_MP_CHAR5_X;
            p1_mp_curr_font_row = char_font_row(8'd48 + 4'd0, p1_mp_curr_row);
            p1_mp_char_pixel = p1_mp_curr_font_row[7 - p1_mp_curr_col];
        end else if(pixel_x >= P1_MP_CHAR6_X && pixel_x < P1_MP_CHAR6_X + CHAR_WIDTH) begin
            p1_mp_curr_col = pixel_x - P1_MP_CHAR6_X;
            p1_mp_curr_font_row = char_font_row(8'd48 + 4'd0, p1_mp_curr_row);
            p1_mp_char_pixel = p1_mp_curr_font_row[7 - p1_mp_curr_col];
        end
    end
end

// ==================== 蓝量数字绘制（P2） ====================
reg p2_mp_char_pixel;
reg [3:0] p2_mp_curr_digit;
reg [2:0] p2_mp_curr_row;
reg [2:0] p2_mp_curr_col;
reg [7:0] p2_mp_curr_font_row;
always @(*) begin
    p2_mp_char_pixel = 1'b0;
    p2_mp_curr_digit = 4'd0;
    p2_mp_curr_row = 3'd0;
    p2_mp_curr_col = 3'd0;
    p2_mp_curr_font_row = 8'd0;

    if(pixel_y >= P2_MP_NUM_Y && pixel_y < P2_MP_NUM_Y + CHAR_HEIGHT) begin
        p2_mp_curr_row = (CHAR_HEIGHT - 1) - (pixel_y - P2_MP_NUM_Y);
        if(pixel_x >= P2_MP_CHAR0_X && pixel_x < P2_MP_CHAR0_X + CHAR_WIDTH) begin
            p2_mp_curr_col = pixel_x - P2_MP_CHAR0_X;
            p2_mp_curr_digit = p2_mp_hun;
            p2_mp_curr_font_row = char_font_row(8'd48 + p2_mp_curr_digit, p2_mp_curr_row);
            p2_mp_char_pixel = p2_mp_curr_font_row[7 - p2_mp_curr_col];
        end else if(pixel_x >= P2_MP_CHAR1_X && pixel_x < P2_MP_CHAR1_X + CHAR_WIDTH) begin
            p2_mp_curr_col = pixel_x - P2_MP_CHAR1_X;
            p2_mp_curr_digit = p2_mp_ten;
            p2_mp_curr_font_row = char_font_row(8'd48 + p2_mp_curr_digit, p2_mp_curr_row);
            p2_mp_char_pixel = p2_mp_curr_font_row[7 - p2_mp_curr_col];
        end else if(pixel_x >= P2_MP_CHAR2_X && pixel_x < P2_MP_CHAR2_X + CHAR_WIDTH) begin
            p2_mp_curr_col = pixel_x - P2_MP_CHAR2_X;
            p2_mp_curr_digit = p2_mp_one;
            p2_mp_curr_font_row = char_font_row(8'd48 + p2_mp_curr_digit, p2_mp_curr_row);
            p2_mp_char_pixel = p2_mp_curr_font_row[7 - p2_mp_curr_col];
        end else if(pixel_x >= P2_MP_CHAR3_X && pixel_x < P2_MP_CHAR3_X + CHAR_WIDTH) begin
            p2_mp_curr_col = pixel_x - P2_MP_CHAR3_X;
            p2_mp_curr_font_row = char_font_row(8'd47, p2_mp_curr_row);
            p2_mp_char_pixel = p2_mp_curr_font_row[7 - p2_mp_curr_col];
        end else if(pixel_x >= P2_MP_CHAR4_X && pixel_x < P2_MP_CHAR4_X + CHAR_WIDTH) begin
            p2_mp_curr_col = pixel_x - P2_MP_CHAR4_X;
            p2_mp_curr_font_row = char_font_row(8'd48 + 4'd1, p2_mp_curr_row);
            p2_mp_char_pixel = p2_mp_curr_font_row[7 - p2_mp_curr_col];
        end else if(pixel_x >= P2_MP_CHAR5_X && pixel_x < P2_MP_CHAR5_X + CHAR_WIDTH) begin
            p2_mp_curr_col = pixel_x - P2_MP_CHAR5_X;
            p2_mp_curr_font_row = char_font_row(8'd48 + 4'd0, p2_mp_curr_row);
            p2_mp_char_pixel = p2_mp_curr_font_row[7 - p2_mp_curr_col];
        end else if(pixel_x >= P2_MP_CHAR6_X && pixel_x < P2_MP_CHAR6_X + CHAR_WIDTH) begin
            p2_mp_curr_col = pixel_x - P2_MP_CHAR6_X;
            p2_mp_curr_font_row = char_font_row(8'd48 + 4'd0, p2_mp_curr_row);
            p2_mp_char_pixel = p2_mp_curr_font_row[7 - p2_mp_curr_col];
        end
    end
end

// ==================== 游戏结束文字绘制 ====================
wire game_over_active = (p1_dead || p2_dead);
reg game_over_pixel;
reg [2:0] game_char_row;
reg [2:0] game_char_col;
reg [7:0] game_char_ascii;
reg [7:0] game_font_row;
always @(*) begin
    game_over_pixel = 1'b0;
    game_char_row = 3'd0;
    game_char_col = 3'd0;
    game_char_ascii = 8'd32;
    game_font_row = 8'd0;

    if(game_over_active) begin
        if(pixel_y >= GAME_OVER_Y && pixel_y < GAME_OVER_Y + CHAR_HEIGHT) begin
            game_char_row = (CHAR_HEIGHT - 1) - (pixel_y - GAME_OVER_Y);
            if(pixel_x >= GAME_OVER_X_START && pixel_x < GAME_OVER_X_START + 9*CHAR_WIDTH) begin
                game_char_col = (pixel_x - GAME_OVER_X_START) % CHAR_WIDTH;
                case((pixel_x - GAME_OVER_X_START) / CHAR_WIDTH)
                    0: game_char_ascii = 8'd71;
                    1: game_char_ascii = 8'd65;
                    2: game_char_ascii = 8'd77;
                    3: game_char_ascii = 8'd69;
                    4: game_char_ascii = 8'd32;
                    5: game_char_ascii = 8'd79;
                    6: game_char_ascii = 8'd86;
                    7: game_char_ascii = 8'd69;
                    8: game_char_ascii = 8'd82;
                    default: game_char_ascii = 8'd32;
                endcase
                game_font_row = char_font_row(game_char_ascii, game_char_row);
                game_over_pixel = game_font_row[7 - game_char_col];
            end
        end
        
        if(pixel_y >= WINNER_Y && pixel_y < WINNER_Y + CHAR_HEIGHT) begin
            game_char_row = (CHAR_HEIGHT - 1) - (pixel_y - WINNER_Y);
            if(pixel_x >= WINNER_X_START && pixel_x < WINNER_X_START + 6*CHAR_WIDTH) begin
                game_char_col = (pixel_x - WINNER_X_START) % CHAR_WIDTH;
                case((pixel_x - WINNER_X_START) / CHAR_WIDTH)
                    0: game_char_ascii = 8'd80;
                    1: game_char_ascii = p1_dead ? 8'd50 : 8'd49;
                    2: game_char_ascii = 8'd32;
                    3: game_char_ascii = 8'd87;
                    4: game_char_ascii = 8'd73;
                    5: game_char_ascii = 8'd78;
                    default: game_char_ascii = 8'd32;
                endcase
                game_font_row = char_font_row(game_char_ascii, game_char_row);
                game_over_pixel = game_over_pixel || game_font_row[7 - game_char_col];
            end
        end
    end
end

// ==================== Debug字符绘制逻辑 ====================
reg debug_pixel;
reg [2:0] debug_char_row;
reg [2:0] debug_char_col;
reg [7:0] debug_char_ascii;
reg [7:0] debug_font_row;
always @(*) begin
    debug_pixel = 1'b0;
    debug_char_row = 3'd0;
    debug_char_col = 3'd0;
    debug_char_ascii = 8'd32;
    debug_font_row = 8'd0;

    if(pixel_y >= DEBUG_COL_Y && pixel_y < DEBUG_COL_Y + CHAR_HEIGHT) begin
        debug_char_row = (CHAR_HEIGHT - 1) - (pixel_y - DEBUG_COL_Y);
        if(pixel_x >= DEBUG_COL_TEXT_X && pixel_x < DEBUG_COL_TEXT_X + CHAR_WIDTH) begin
            debug_char_col = pixel_x - DEBUG_COL_TEXT_X;
            debug_char_ascii = 8'd67;
            debug_font_row = char_font_row(debug_char_ascii, debug_char_row);
            debug_pixel = debug_font_row[7 - debug_char_col];
        end else if(pixel_x >= DEBUG_COL_TEXT_X + CHAR_WIDTH + CHAR_SPACE && pixel_x < DEBUG_COL_TEXT_X + 2*CHAR_WIDTH + CHAR_SPACE) begin
            debug_char_col = pixel_x - (DEBUG_COL_TEXT_X + CHAR_WIDTH + CHAR_SPACE);
            debug_char_ascii = 8'd79;
            debug_font_row = char_font_row(debug_char_ascii, debug_char_row);
            debug_pixel = debug_font_row[7 - debug_char_col];
        end else if(pixel_x >= DEBUG_COL_TEXT_X + 2*(CHAR_WIDTH + CHAR_SPACE) && pixel_x < DEBUG_COL_TEXT_X + 3*CHAR_WIDTH + 2*CHAR_SPACE) begin
            debug_char_col = pixel_x - (DEBUG_COL_TEXT_X + 2*(CHAR_WIDTH + CHAR_SPACE));
            debug_char_ascii = 8'd76;
            debug_font_row = char_font_row(debug_char_ascii, debug_char_row);
            debug_pixel = debug_font_row[7 - debug_char_col];
        end else if(pixel_x >= DEBUG_COL_NUM_X && pixel_x < DEBUG_COL_NUM_X + CHAR_WIDTH) begin
            debug_char_col = pixel_x - DEBUG_COL_NUM_X;
            debug_char_ascii = 8'd48 + debug_col[1:0];
            debug_font_row = char_font_row(debug_char_ascii, debug_char_row);
            debug_pixel = debug_font_row[7 - debug_char_col];
        end
    end

    if(pixel_y >= DEBUG_ROW_Y && pixel_y < DEBUG_ROW_Y + CHAR_HEIGHT) begin
        debug_char_row = (CHAR_HEIGHT - 1) - (pixel_y - DEBUG_ROW_Y);
        if(pixel_x >= DEBUG_ROW_TEXT_X && pixel_x < DEBUG_ROW_TEXT_X + CHAR_WIDTH) begin
            debug_char_col = pixel_x - DEBUG_ROW_TEXT_X;
            debug_char_ascii = 8'd82;
            debug_font_row = char_font_row(debug_char_ascii, debug_char_row);
            debug_pixel = debug_font_row[7 - debug_char_col];
        end else if(pixel_x >= DEBUG_ROW_TEXT_X + CHAR_WIDTH + CHAR_SPACE && pixel_x < DEBUG_ROW_TEXT_X + 2*CHAR_WIDTH + CHAR_SPACE) begin
            debug_char_col = pixel_x - (DEBUG_ROW_TEXT_X + CHAR_WIDTH + CHAR_SPACE);
            debug_char_ascii = 8'd79;
            debug_font_row = char_font_row(debug_char_ascii, debug_char_row);
            debug_pixel = debug_font_row[7 - debug_char_col];
        end else if(pixel_x >= DEBUG_ROW_TEXT_X + 2*(CHAR_WIDTH + CHAR_SPACE) && pixel_x < DEBUG_ROW_TEXT_X + 3*CHAR_WIDTH + 2*CHAR_SPACE) begin
            debug_char_col = pixel_x - (DEBUG_ROW_TEXT_X + 2*(CHAR_WIDTH + CHAR_SPACE));
            debug_char_ascii = 8'd87;
            debug_font_row = char_font_row(debug_char_ascii, debug_char_row);
            debug_pixel = debug_font_row[7 - debug_char_col];
        end else if(pixel_x >= DEBUG_ROW_BIT0_X && pixel_x < DEBUG_ROW_BIT0_X + CHAR_WIDTH) begin
            debug_char_col = pixel_x - DEBUG_ROW_BIT0_X;
            debug_char_ascii = 8'd48 + debug_row[0];
            debug_font_row = char_font_row(debug_char_ascii, debug_char_row);
            debug_pixel = debug_font_row[7 - debug_char_col];
        end else if(pixel_x >= DEBUG_ROW_BIT1_X && pixel_x < DEBUG_ROW_BIT1_X + CHAR_WIDTH) begin
            debug_char_col = pixel_x - DEBUG_ROW_BIT1_X;
            debug_char_ascii = 8'd48 + debug_row[1];
            debug_font_row = char_font_row(debug_char_ascii, debug_char_row);
            debug_pixel = debug_font_row[7 - debug_char_col];
        end else if(pixel_x >= DEBUG_ROW_BIT2_X && pixel_x < DEBUG_ROW_BIT2_X + CHAR_WIDTH) begin
            debug_char_col = pixel_x - DEBUG_ROW_BIT2_X;
            debug_char_ascii = 8'd48 + debug_row[2];
            debug_font_row = char_font_row(debug_char_ascii, debug_char_row);
            debug_pixel = debug_font_row[7 - debug_char_col];
        end else if(pixel_x >= DEBUG_ROW_BIT3_X && pixel_x < DEBUG_ROW_BIT3_X + CHAR_WIDTH) begin
            debug_char_col = pixel_x - DEBUG_ROW_BIT3_X;
            debug_char_ascii = 8'd48 + debug_row[3];
            debug_font_row = char_font_row(debug_char_ascii, debug_char_row);
            debug_pixel = debug_font_row[7 - debug_char_col];
        end
    end
end

// ==================== 血条、蓝条区域计算 ====================
wire [14:0] p1_hp_mult = p1_hp * HP_BAR_W;
wire [14:0] p2_hp_mult = p2_hp * HP_BAR_W;
wire [10:0] p1_hp_show_w = p1_hp_mult / TOTAL_HP;
wire [10:0] p2_hp_show_w = p2_hp_mult / TOTAL_HP;

wire p1_hp_box = (pixel_x >= P1_HP_X) && (pixel_x < P1_HP_X + HP_BAR_BOX_W) &&
                 (pixel_y >= HP_BAR_Y) && (pixel_y < HP_BAR_Y + HP_BAR_BOX_H);
wire p1_hp_bar = (pixel_x >= P1_HP_X + 2) && (pixel_x < P1_HP_X + 2 + p1_hp_show_w) &&
                 (pixel_y >= HP_BAR_Y + 2) && (pixel_y < HP_BAR_Y + 2 + HP_BAR_H);
wire p2_hp_box = (pixel_x >= P2_HP_X) && (pixel_x < P2_HP_X + HP_BAR_BOX_W) &&
                 (pixel_y >= HP_BAR_Y) && (pixel_y < HP_BAR_Y + HP_BAR_BOX_H);
wire p2_hp_bar = (pixel_x >= P2_HP_X + 2) && (pixel_x < P2_HP_X + 2 + p2_hp_show_w) &&
                 (pixel_y >= HP_BAR_Y + 2) && (pixel_y < HP_BAR_Y + 2 + HP_BAR_H);

wire p1_hp_box_edge = (p1_hp_box) && !( (pixel_x >= P1_HP_X+1) && (pixel_x < P1_HP_X+HP_BAR_BOX_W-1) &&
                                        (pixel_y >= HP_BAR_Y+1) && (pixel_y < HP_BAR_Y+HP_BAR_BOX_H-1) );
wire p2_hp_box_edge = (p2_hp_box) && !( (pixel_x >= P2_HP_X+1) && (pixel_x < P2_HP_X+HP_BAR_BOX_W-1) &&
                                        (pixel_y >= HP_BAR_Y+1) && (pixel_y < HP_BAR_Y+HP_BAR_BOX_H-1) );

// 蓝条区域
wire [14:0] p1_mp_mult = p1_mp * MP_BAR_W;
wire [14:0] p2_mp_mult = p2_mp * MP_BAR_W;
wire [10:0] p1_mp_show_w = p1_mp_mult / MP_MAX;
wire [10:0] p2_mp_show_w = p2_mp_mult / MP_MAX;

wire p1_mp_box = (pixel_x >= P1_MP_X) && (pixel_x < P1_MP_X + MP_BAR_BOX_W) &&
                 (pixel_y >= MP_BAR_Y) && (pixel_y < MP_BAR_Y + MP_BAR_BOX_H);
wire p1_mp_bar = (pixel_x >= P1_MP_X + 2) && (pixel_x < P1_MP_X + 2 + p1_mp_show_w) &&
                 (pixel_y >= MP_BAR_Y + 2) && (pixel_y < MP_BAR_Y + 2 + MP_BAR_H);
wire p2_mp_box = (pixel_x >= P2_MP_X) && (pixel_x < P2_MP_X + MP_BAR_BOX_W) &&
                 (pixel_y >= MP_BAR_Y) && (pixel_y < MP_BAR_Y + MP_BAR_BOX_H);
wire p2_mp_bar = (pixel_x >= P2_MP_X + 2) && (pixel_x < P2_MP_X + 2 + p2_mp_show_w) &&
                 (pixel_y >= MP_BAR_Y + 2) && (pixel_y < MP_BAR_Y + 2 + MP_BAR_H);
wire p1_mp_box_edge = p1_mp_box && !( (pixel_x >= P1_MP_X+1) && (pixel_x < P1_MP_X+MP_BAR_BOX_W-1) &&
                                      (pixel_y >= MP_BAR_Y+1) && (pixel_y < MP_BAR_Y+MP_BAR_BOX_H-1) );
wire p2_mp_box_edge = p2_mp_box && !( (pixel_x >= P2_MP_X+1) && (pixel_x < P2_MP_X+MP_BAR_BOX_W-1) &&
                                      (pixel_y >= MP_BAR_Y+1) && (pixel_y < MP_BAR_Y+MP_BAR_BOX_H-1) );

// ==================== 最终绘制逻辑 ====================
always @(posedge pixel_clk or posedge reset) begin
    if(reset) begin
        lcd_r <= 3'b000;
        lcd_g <= 2'b00;
        lcd_b <= 3'b000;
    end else begin
        // 1. 背景层
        lcd_r <= bg_r;
        lcd_g <= bg_g;
        lcd_b <= bg_b;

        // 2. 血条层
        if(p1_hp_box_edge) begin
            lcd_r <= 3'b000; lcd_g <= 2'b00; lcd_b <= 3'b000;
        end else if(p1_hp_bar) begin
            if(!p1_hp_bar_flash) begin
                lcd_r <= 3'b111; lcd_g <= 2'b00; lcd_b <= 3'b000;  // 红色
            end else begin
                lcd_r <= 3'b111; lcd_g <= 2'b11; lcd_b <= 3'b111;  // 白色闪烁
            end
        end else if(p1_hp_box) begin
            lcd_r <= 3'b111; lcd_g <= 2'b11; lcd_b <= 3'b111;
        end
        
        if(p2_hp_box_edge) begin
            lcd_r <= 3'b000; lcd_g <= 2'b00; lcd_b <= 3'b000;
        end else if(p2_hp_bar) begin
            if(!p2_hp_bar_flash) begin
                lcd_r <= 3'b111; lcd_g <= 2'b00; lcd_b <= 3'b000;  // 玩家2血条红色
            end else begin
                lcd_r <= 3'b111; lcd_g <= 2'b11; lcd_b <= 3'b111;
            end
        end else if(p2_hp_box) begin
            lcd_r <= 3'b111; lcd_g <= 2'b11; lcd_b <= 3'b111;
        end

        // 3. 蓝条层
        if(p1_mp_box_edge) begin
            lcd_r <= 3'b000; lcd_g <= 2'b00; lcd_b <= 3'b000;
        end else if(p1_mp_bar) begin
            lcd_r <= 3'b000; lcd_g <= 2'b00; lcd_b <= 3'b111;  // 蓝色
        end else if(p1_mp_box) begin
            lcd_r <= 3'b111; lcd_g <= 2'b11; lcd_b <= 3'b111;
        end
        if(p2_mp_box_edge) begin
            lcd_r <= 3'b000; lcd_g <= 2'b00; lcd_b <= 3'b000;
        end else if(p2_mp_bar) begin
            lcd_r <= 3'b000; lcd_g <= 2'b00; lcd_b <= 3'b111;
        end else if(p2_mp_box) begin
            lcd_r <= 3'b111; lcd_g <= 2'b11; lcd_b <= 3'b111;
        end

        // 4. 血条数字层（绿色）
        if(p1_char_pixel) begin
            lcd_r <= 3'b000; lcd_g <= 2'b11; lcd_b <= 3'b000;
        end
        if(p2_char_pixel) begin
            lcd_r <= 3'b000; lcd_g <= 2'b11; lcd_b <= 3'b000;
        end

        // 5. 蓝量数字层（绿色）
        if(p1_mp_char_pixel) begin
            lcd_r <= 3'b000; lcd_g <= 2'b11; lcd_b <= 3'b000;
        end
        if(p2_mp_char_pixel) begin
            lcd_r <= 3'b000; lcd_g <= 2'b11; lcd_b <= 3'b000;
        end

        // 6. Debug信息层
        if(debug_pixel) begin
            lcd_r <= 3'b111; lcd_g <= 2'b01; lcd_b <= 3'b000;
        end

        // 7. 投射物层
        if(proj1_valid) begin
            lcd_r <= proj1_r; lcd_g <= proj1_g; lcd_b <= proj1_b;
        end
        if(proj2_valid) begin
            lcd_r <= proj2_r; lcd_g <= proj2_g; lcd_b <= proj2_b;
        end

        // 8. 补血剂层（透明色为8'h00）
        if (medicine_area && medicine_data != 8'h00) begin
            lcd_r <= medicine_data[7:5];
            lcd_g <= medicine_data[4:3];
            lcd_b <= medicine_data[2:0];
        end

        // 9. 精灵层
        if(p1_sprite_area && p1_sprite_data != 8'hFF) begin
            if(p1_hit_flash) begin
                lcd_r <= 3'b111; lcd_g <= 2'b00; lcd_b <= 3'b000;
            end else begin
                lcd_r <= p1_sprite_data[7:5];
                lcd_g <= p1_sprite_data[4:3];
                lcd_b <= p1_sprite_data[2:0];
            end
        end

        if(p2_sprite_area && p2_sprite_data != 8'hFF) begin
            if(p2_hit_flash) begin
                lcd_r <= 3'b111; lcd_g <= 2'b00; lcd_b <= 3'b000;
            end else begin
                lcd_r <= p2_sprite_data[7:5];
                lcd_g <= p2_sprite_data[4:3];
                lcd_b <= p2_sprite_data[2:0];
            end
        end

        // 10. Game Over文字层
        if(game_over_pixel) begin
            lcd_r <= 3'b111;
            lcd_g <= 2'b11;
            lcd_b <= 3'b000;
        end

        // 11. System图片层（最高优先级）
        if(system_pixel_valid) begin
            lcd_r <= system_data[7:5];
            lcd_g <= system_data[4:3];
            lcd_b <= system_data[2:0];
        end
    end
end

endmodule