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
    parameter XLEN = 32
)(
    input  clk,                      // 100MHz ????
    input  reset_n,                  // ???? (S6????)
    input  [23:0] switch,            // ???? (SW0~SW23)
    input  btn_down,                 // S2 - ??PC+??
    input  btn_left,                 // S3 - ?????
    input  btn_right,                // S4 - ??ALU??
    // btn_center (S5) ???
    output [7:0] rled,               // ?? LED
    output [7:0] yled,               // ?? LED
    output [7:0] gled,               // ?? LED
    output uart_tx_in                // UART TX
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

    // ---------- 50MHz ??????? internal_reset ??? ----------
    reg clk_50mhz_unbuffered;
    always @(posedge clk or posedge internal_reset) begin
        if (internal_reset)
            clk_50mhz_unbuffered <= 1'b0;
        else
            clk_50mhz_unbuffered <= ~clk_50mhz_unbuffered;
    end
    wire clk_50mhz;
    BUFG clk_50mhz_bufg (
        .I(clk_50mhz_unbuffered),
        .O(clk_50mhz)
    );

    // ---------- SW9 ??????????????????? ----------
    reg sw9_sync, sw9_prev;
    always @(posedge clk_50mhz or posedge internal_reset) begin
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

    always @(posedge clk_50mhz or posedge internal_reset) begin
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

    always @(posedge clk_50mhz or posedge internal_reset) begin
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
    always @(posedge clk_50mhz or posedge internal_reset) begin
        if (internal_reset)
            auto_cnt <= 0;
        else
            auto_cnt <= (auto_cnt >= 26'd33500000) ? 26'd0 : auto_cnt + 1'b1;
    end
    assign auto_pulse = (auto_cnt == 26'd33500000 - 1);   // ?0.67s????

    // ---------- ????????????? ----------
    reg step_pulse_reg;
    reg pc_inst_trigger_reg;
    reg reg_trigger_reg;
    reg alu_trigger_reg;

    always @(posedge clk_50mhz or posedge internal_reset) begin
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
            if (btn_down_rise)  pc_inst_trigger_reg <= 1'b1;
            if (btn_left_rise)  reg_trigger_reg <= 1'b1;
            if (btn_right_rise) alu_trigger_reg <= 1'b1;
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
    always @(posedge clk_50mhz or posedge internal_reset) begin
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
        .clk(clk_50mhz),
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
    assign uart_tx_start = mmio_uart_tx_start | debug_tx_start;
    assign uart_tx_data  = mmio_uart_tx_start ? mmio_uart_tx_data : debug_tx_data;

    UARTTX uart_tx (
        .clk(clk_50mhz),
        .reset(internal_reset),
        .tx_start(uart_tx_start),
        .tx_data(uart_tx_data),
        .tx(uart_tx_in),
        .tx_busy(uart_tx_busy)
    );

    // ---------- UnifiedUARTController ----------
    wire benchmark_start;
    UnifiedUARTController unified_uart_controller (
        .clk(clk_50mhz),
        .reset(internal_reset),
        .btn_up(1'b0),    // S1 ????
        .mmio_tx_data(mmio_uart_tx_data),
        .mmio_tx_start(mmio_uart_tx_start),
        .tx_start(),
        .tx_data(),
        .benchmark_start(benchmark_start)
    );

    // ---------- CPU ? ----------
    RV32I46F5SPMMIO #(.XLEN(XLEN)) rv32i46f_5sp_mmio (
        .clk(clk_50mhz),
        .reset(internal_reset),
        .UART_busy(uart_tx_busy),
        .manual_stall(manual_stall),
        .retire_instruction(retire_instruction),
        .mmio_uart_tx_data(mmio_uart_tx_data),
        .mmio_uart_tx_start(mmio_uart_tx_start),
        .instruction_retired(instruction_retired),
        .trapped(trapped),
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
    reg [25:0] heartbeat_cnt;
    always @(posedge clk_50mhz or posedge internal_reset) begin
        if (internal_reset)
            heartbeat_cnt <= 26'd0;
        else
            heartbeat_cnt <= heartbeat_cnt + 1'b1;
    end
    assign gled = {8{heartbeat_cnt[25]}};

endmodule