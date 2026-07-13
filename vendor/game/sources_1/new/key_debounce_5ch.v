//==================================================================
// 5通道按键消抖模块
// 功能：对右侧5个独立按键进行消抖处理，消除机械抖动
//       消抖时间20ms（100MHz时钟下计数2,000,000次）
//==================================================================
module key_debounce_5ch(
    input        clk,           // 100MHz时钟
    input        reset,         // 高有效复位
    input  [4:0] raw_button,    // 原始按键输入（高有效）
    output [4:0] button_valid   // 消抖后输出（稳定电平）
);

    // 20ms消抖计数阈值 (100MHz * 0.02s = 2,000,000)
    localparam DEBOUNCE_CNT = 20'd2_000_000;

    // 两级同步寄存器，消除亚稳态
    reg [4:0] button_reg1;
    reg [4:0] button_reg2;

    // 消抖计数器与稳定值寄存器
    reg [19:0] debounce_cnt;
    reg [4:0]  button_valid_reg;

    // 输入同步
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            button_reg1 <= 5'b0;
            button_reg2 <= 5'b0;
        end else begin
            button_reg1 <= raw_button;
            button_reg2 <= button_reg1;
        end
    end

    // 消抖计数与稳定值更新
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            debounce_cnt <= 20'd0;
            button_valid_reg <= 5'b0;
        end else begin
            // 当前同步值与稳定值不一致时，开始计数
            if (button_reg2 != button_valid_reg) begin
                if (debounce_cnt == DEBOUNCE_CNT - 1) begin
                    // 连续计数达到阈值，更新稳定值
                    button_valid_reg <= button_reg2;
                    debounce_cnt <= 20'd0;
                end else begin
                    debounce_cnt <= debounce_cnt + 1'b1;
                end
            end else begin
                // 一致时清零计数器
                debounce_cnt <= 20'd0;
            end
        end
    end

    assign button_valid = button_valid_reg;

endmodule