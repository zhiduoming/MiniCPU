//==================================================================
// 键盘扫描模块
// 功能：扫描4x4矩阵键盘，检测2(跳)、4(左)、5(攻)、6(右)、8(火球)
//       扫描周期1ms，消抖时间20ms，输出稳定的按键值和火球键
//==================================================================
module keyboard_4x4_scan(
    input         clk,               // 100MHz时钟
    input         reset,             // 高有效复位
    input  [3:0]  row_in,            // 键盘行输入（低有效）
    output reg [3:0] col_out,        // 列扫描输出（低有效）
    output reg [3:0] p1_key_out,     // 按键输出 bit3=攻 bit2=右 bit1=左 bit0=跳
    output reg      p1_proj_key,     // 远程火球按键输出
    output reg [3:0] debug_col,      // 调试用：当前扫描的列
    output reg [3:0] debug_row       // 调试用：当前读到的行值
);

    // --------------------------------------------------------------
    // 1ms扫描节拍计数器 (100MHz -> 1kHz)
    // --------------------------------------------------------------
    reg [16:0] scan_cnt;
    wire scan_en = (scan_cnt == 17'd99_999);
    always @(posedge clk or posedge reset) begin
        if (reset)
            scan_cnt <= 17'd0;
        else if (scan_en)
            scan_cnt <= 17'd0;
        else
            scan_cnt <= scan_cnt + 1'b1;
    end

    // --------------------------------------------------------------
    // 20ms消抖计数器 (独立于扫描，直接对时钟计数)
    // --------------------------------------------------------------
    reg [19:0] deb_cnt;
    wire deb_en = (deb_cnt == 20'd1_999_999);
    always @(posedge clk or posedge reset) begin
        if (reset)
            deb_cnt <= 20'd0;
        else if (deb_en)
            deb_cnt <= 20'd0;
        else
            deb_cnt <= deb_cnt + 1'b1;
    end

    // 行输入取反（低有效变成内部高有效，方便判断）
    wire [3:0] row_real = {row_in[0], row_in[1], row_in[2], row_in[3]};

    // --------------------------------------------------------------
    // 列扫描状态机
    // --------------------------------------------------------------
    reg [1:0] col_idx;
    reg [3:0] key_sample [0:3];   // 保存每一列的行采样结果
    reg       proj_key_status;     // 火球键消抖后的状态

    // 列扫描输出及采样
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            col_idx  <= 2'd0;
            col_out  <= 4'b0111;          // 先扫描第0列
            key_sample[0] <= 4'b1111;
            key_sample[1] <= 4'b1111;
            key_sample[2] <= 4'b1111;
            key_sample[3] <= 4'b1111;
        end else if (scan_en) begin
            // 保存当前列的行值
            key_sample[col_idx] <= row_real;
            // 切换到下一列
            col_idx <= col_idx + 1'b1;
            // 根据下一列的索引输出列扫描码（低有效）
            case (col_idx + 1'b1)
                2'd0: col_out <= 4'b0111;
                2'd1: col_out <= 4'b1011;
                2'd2: col_out <= 4'b1101;
                2'd3: col_out <= 4'b1110;
            endcase
        end
    end

    // --------------------------------------------------------------
    // 消抖处理：每20ms根据采样结果计算按键值
    // --------------------------------------------------------------
    reg [3:0] key_status;
    wire [3:0] next_key_status;
    wire next_proj_key_status;

    // 根据实际按键位置定义：col2 row1=攻击, col2 row0=右, col2 row3=左, col1 row1=跳
    assign next_key_status = {
        (key_sample[2][1] == 1'b0) ? 1'b1 : 1'b0,   // bit3:攻击（5键）
        (key_sample[2][0] == 1'b0) ? 1'b1 : 1'b0,   // bit2:右（6键）
        (key_sample[2][3] == 1'b0) ? 1'b1 : 1'b0,   // bit1:左（4键）
        (key_sample[1][1] == 1'b0) ? 1'b1 : 1'b0    // bit0:跳（2键）
    };
    assign next_proj_key_status = (key_sample[0][1] == 1'b0) ? 1'b1 : 1'b0;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            key_status <= 4'b0000;
            proj_key_status <= 1'b0;
        end else if (deb_en) begin
            key_status <= next_key_status;
            proj_key_status <= next_proj_key_status;
        end
    end

    // 输出稳定后的按键值
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            p1_key_out <= 4'b0000;
            p1_proj_key <= 1'b0;
        end else if (deb_en) begin
            p1_key_out <= key_status;
            p1_proj_key <= proj_key_status;
        end
    end

    // 调试输出：显示当前按下的行列坐标
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            debug_col <= 4'd0;
            debug_row <= 4'b1111;
        end else if (deb_en) begin
            if (row_real != 4'b1111) begin
                debug_col <= {2'b00, col_idx};
                debug_row <= row_real;
            end else begin
                debug_col <= 4'd0;
                debug_row <= 4'b1111;
            end
        end
    end

endmodule