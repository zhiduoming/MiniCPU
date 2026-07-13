module ButtonController (
    input clk,
    input reset,
    input btn_center,
    input btn_up,
    input btn_down,
    input btn_left,
    input btn_right,
    output step_pulse,
    output continuous_mode,
    output alu_trigger,
    output pc_inst_trigger,
    output reg_trigger
);

    // ?????50ms @ 50MHz
    localparam DEBOUNCE_CYCLES = 20'd2500000;

    // ??????
    wire [4:0] btn_raw = {btn_right, btn_left, btn_down, btn_up, btn_center};

    // 3??????
    reg [4:0] sync0, sync1, sync2;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            sync0 <= 5'b0;
            sync1 <= 5'b0;
            sync2 <= 5'b0;
        end else begin
            sync0 <= btn_raw;
            sync1 <= sync0;
            sync2 <= sync1;
        end
    end

    // ??????????
    reg [19:0] cnt [0:4];
    reg [4:0] stable;
    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 5; i = i + 1) cnt[i] <= 0;
            stable <= 5'b0;
        end else begin
            for (i = 0; i < 5; i = i + 1) begin
                if (sync2[i] != stable[i]) begin
                    if (cnt[i] < DEBOUNCE_CYCLES - 1)
                        cnt[i] <= cnt[i] + 1;
                    else begin
                        stable[i] <= sync2[i];
                        cnt[i] <= 0;
                    end
                end else
                    cnt[i] <= 0;
            end
        end
    end

    // ????????????
    reg [4:0] stable_d1;
    always @(posedge clk or posedge reset) begin
        if (reset)
            stable_d1 <= 5'b0;
        else
            stable_d1 <= stable;
    end
    wire [4:0] btn_edge = ~stable & stable_d1;   // ??????????

    // ???????????0.67s???
    reg [25:0] auto_cnt;
    reg auto_pulse;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            auto_cnt <= 0;
            auto_pulse <= 1'b0;
        end else begin
            if (auto_cnt >= 26'd33500000) begin
                auto_cnt <= 0;
                auto_pulse <= 1'b1;
            end else begin
                auto_cnt <= auto_cnt + 1;
                auto_pulse <= 1'b0;
            end
        end
    end

    // ?????
    reg continuous_mode_reg;
    reg step_pulse_reg;
    reg pc_inst_trigger_reg;
    reg reg_trigger_reg;
    reg alu_trigger_reg;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            continuous_mode_reg <= 1'b0;
            step_pulse_reg <= 1'b0;
            pc_inst_trigger_reg <= 1'b0;
            reg_trigger_reg <= 1'b0;
            alu_trigger_reg <= 1'b0;
        end else begin
            // ??????
            step_pulse_reg <= 1'b0;
            pc_inst_trigger_reg <= 1'b0;
            reg_trigger_reg <= 1'b0;
            alu_trigger_reg <= 1'b0;

            // ???? (S5) - ??
            if (btn_edge[0] && !continuous_mode_reg)
                step_pulse_reg <= 1'b1;

            // ??? (S1) - ??????
            if (btn_edge[1])
                continuous_mode_reg <= ~continuous_mode_reg;

            // ??? (S2) - PC+??
            if (btn_edge[2])
                pc_inst_trigger_reg <= 1'b1;

            // ??? (S3) - ???
            if (btn_edge[3])
                reg_trigger_reg <= 1'b1;

            // ??? (S4) - ALU??
            if (btn_edge[4])
                alu_trigger_reg <= 1'b1;

            // ?????????
            if (continuous_mode_reg && auto_pulse)
                step_pulse_reg <= 1'b1;
        end
    end

    // ??
    assign step_pulse = step_pulse_reg;
    assign continuous_mode = continuous_mode_reg;
    assign pc_inst_trigger = pc_inst_trigger_reg;
    assign reg_trigger = reg_trigger_reg;
    assign alu_trigger = alu_trigger_reg;

endmodule