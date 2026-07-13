module MMIO_Interface (
    input clk,
    input reset,
    input [31:0] data_memory_write_data,
    input [31:0] data_memory_address,
    input data_memory_write_enable,
    input UART_busy,
    input [4:0] game_p1_buttons,
    input [4:0] game_p2_buttons,

    output reg [7:0] mmio_uart_tx_data,
    output [31:0] mmio_uart_status,
    output reg mmio_uart_tx_start,
    output mmio_uart_status_hit,
    output reg perf_dump_req,          // 1-cycle pulse: clear/restart PerfMon

    // ---- PerfMon counter read ports ----
    input  [31:0] perf_cyc,
    input  [31:0] perf_inst,
    input  [31:0] perf_acc,
    input  [31:0] perf_hit,
    input  [31:0] perf_miss,
    input  [31:0] perf_stall,
    input  [31:0] perf_branch,
    input  [31:0] perf_branch_miss,
    input  [31:0] perf_memory,
    input  [31:0] perf_m_ext,
    input  [31:0] perf_mac,
    input  [31:0] perf_mul_cycles,
    input         ic_mode,
    output [31:0] mmio_perf_read_data,
    output        perf_read_hit,

    // ---- CPU-owned game state, consumed by the VGA renderer ----
    output reg [10:0] game_p1_x,
    output reg [10:0] game_p1_y,
    output reg [10:0] game_p2_x,
    output reg [10:0] game_p2_y,
    output reg [31:0] game_status,
    output reg [31:0] game_flags,
    output reg [31:0] game_proj1_pos,
    output reg [31:0] game_proj2_pos,
    output reg [31:0] game_medicine_pos,
    output reg [31:0] game_timer,
    output [31:0] mmio_game_input_data,
    output        game_input_read_hit
);

    localparam UART_TX_ADDR = 32'h10010000;     // Write-Only
    localparam UART_STATUS_ADDR = 32'h10010004; // Read-Only
    localparam PERF_DUMP_ADDR = 32'h10010008;   // Write-Only: clear/restart PerfMon

    localparam PERF_CYC_ADDR  = 32'h10010020;
    localparam PERF_INST_ADDR = 32'h10010024;
    localparam PERF_ACC_ADDR  = 32'h10010028;
    localparam PERF_HIT_ADDR  = 32'h1001002C;
    localparam PERF_MISS_ADDR = 32'h10010030;
    localparam PERF_MODE_ADDR = 32'h10010034;
    localparam PERF_STALL_ADDR = 32'h10010038;
    localparam PERF_BRANCH_ADDR = 32'h1001003C;
    localparam PERF_BRANCH_MISS_ADDR = 32'h10010040;
    localparam PERF_MEMORY_ADDR = 32'h10010044;
    localparam PERF_M_EXT_ADDR = 32'h10010048;
    localparam PERF_MAC_ADDR = 32'h1001004C;
    localparam PERF_MUL_CYCLES_ADDR = 32'h10010050;

    // Store format: bits [10:0] = X, bits [26:16] = Y.
    localparam GAME_P1_POS_ADDR = 32'h10010100;
    localparam GAME_P2_POS_ADDR = 32'h10010104;
    localparam GAME_STATUS_ADDR = 32'h10010108;
    localparam GAME_FLAGS_ADDR  = 32'h1001010C;
    localparam GAME_INPUT_ADDR  = 32'h10010110; // Read-Only
    localparam GAME_PROJ1_ADDR  = 32'h10010114;
    localparam GAME_PROJ2_ADDR  = 32'h10010118;
    localparam GAME_MEDICINE_ADDR = 32'h1001011C;
    localparam GAME_TIMER_ADDR = 32'h10010120;

    wire uart_tx_hit = (data_memory_address == UART_TX_ADDR);
    wire uart_stat_hit = (data_memory_address == UART_STATUS_ADDR);
    wire perf_dump_hit = (data_memory_address == PERF_DUMP_ADDR);
    assign mmio_uart_status_hit = uart_tx_hit || uart_stat_hit;
    assign mmio_uart_status = uart_stat_hit ? {31'h0, UART_busy} : 32'h0;

    wire perf_cyc_hit  = (data_memory_address == PERF_CYC_ADDR);
    wire perf_inst_hit = (data_memory_address == PERF_INST_ADDR);
    wire perf_acc_hit  = (data_memory_address == PERF_ACC_ADDR);
    wire perf_hit_hit  = (data_memory_address == PERF_HIT_ADDR);
    wire perf_miss_hit = (data_memory_address == PERF_MISS_ADDR);
    wire perf_mode_hit = (data_memory_address == PERF_MODE_ADDR);
    wire perf_stall_hit = (data_memory_address == PERF_STALL_ADDR);
    wire perf_branch_hit = (data_memory_address == PERF_BRANCH_ADDR);
    wire perf_branch_miss_hit = (data_memory_address == PERF_BRANCH_MISS_ADDR);
    wire perf_memory_hit = (data_memory_address == PERF_MEMORY_ADDR);
    wire perf_m_ext_hit = (data_memory_address == PERF_M_EXT_ADDR);
    wire perf_mac_hit = (data_memory_address == PERF_MAC_ADDR);
    wire perf_mul_cycles_hit = (data_memory_address == PERF_MUL_CYCLES_ADDR);
    assign perf_read_hit = perf_cyc_hit | perf_inst_hit | perf_acc_hit |
                           perf_hit_hit | perf_miss_hit | perf_mode_hit |
                           perf_stall_hit | perf_branch_hit | perf_branch_miss_hit |
                           perf_memory_hit | perf_m_ext_hit | perf_mac_hit |
                           perf_mul_cycles_hit;

    wire game_p1_pos_hit = (data_memory_address == GAME_P1_POS_ADDR);
    wire game_p2_pos_hit = (data_memory_address == GAME_P2_POS_ADDR);
    wire game_status_hit = (data_memory_address == GAME_STATUS_ADDR);
    wire game_flags_hit  = (data_memory_address == GAME_FLAGS_ADDR);
    wire game_proj1_hit  = (data_memory_address == GAME_PROJ1_ADDR);
    wire game_proj2_hit  = (data_memory_address == GAME_PROJ2_ADDR);
    wire game_medicine_hit = (data_memory_address == GAME_MEDICINE_ADDR);
    wire game_timer_hit = (data_memory_address == GAME_TIMER_ADDR);
    assign game_input_read_hit = (data_memory_address == GAME_INPUT_ADDR);
    // P1 bits: [0]=4 left, [1]=6 right, [2]=2 jump, [3]=5 melee, [4]=8 projectile.
    // P2 bits: [8]=S2 left, [9]=S1 right, [10]=S3 jump, [11]=S4 melee, [12]=S5 projectile.
    assign mmio_game_input_data = {19'd0, game_p2_buttons, 3'd0, game_p1_buttons};

    assign mmio_perf_read_data =
        perf_cyc_hit  ? perf_cyc :
        perf_inst_hit ? perf_inst :
        perf_acc_hit  ? perf_acc :
        perf_hit_hit  ? perf_hit :
        perf_miss_hit ? perf_miss :
        perf_mode_hit ? {31'b0, ic_mode} :
        perf_stall_hit ? perf_stall :
        perf_branch_hit ? perf_branch :
        perf_branch_miss_hit ? perf_branch_miss :
        perf_memory_hit ? perf_memory :
        perf_m_ext_hit ? perf_m_ext :
        perf_mac_hit ? perf_mac :
        perf_mul_cycles_hit ? perf_mul_cycles :
        32'h0;

    // ---- Rising-edge detection of a UART-TX store ----
    reg        prev_tx_hit;
    wire       tx_we_rise = (data_memory_write_enable && uart_tx_hit) && !prev_tx_hit;
    reg        tx_pending;
    reg [7:0]  tx_pending_data;

    // ---- Rising-edge detection of a PERF-DUMP store ----
    reg        prev_perf_hit;
    wire       perf_we_rise = (data_memory_write_enable && perf_dump_hit) && !prev_perf_hit;

    always @ (posedge clk or posedge reset) begin
        if (reset) begin
            mmio_uart_tx_data <= 8'h0;
            mmio_uart_tx_start <= 1'b0;
            perf_dump_req <= 1'b0;
            prev_tx_hit <= 1'b0;
            prev_perf_hit <= 1'b0;
            tx_pending <= 1'b0;
            tx_pending_data <= 8'h0;
            game_p1_x <= 11'd100;
            game_p1_y <= 11'd40;
            game_p2_x <= 11'd650;
            game_p2_y <= 11'd40;
            // [7:0] P1 HP, [15:8] P2 HP, [22:16] P1 MP, [29:23] P2 MP.
            game_status <= 32'h3264_6464;
            // [0]P1 dir [1]P2 dir [2]P1 melee [3]P2 melee [4]P1 jump [5]P2 jump
            // [6]P1 hit [7]P2 hit [8]P1 projectile active [9]P2 active [10]P1 dir [11]P2 dir.
            // [12]round over [13]winner=P2 [19:16]P1 score [23:20]P2 score.
            // [24]medicine [25]heal pulse [26]mode menu [27]PVP selection.
            // [28]time menu [29]time expired. game_timer stores seconds left.
            game_flags <= 32'h0000_0001;
            game_proj1_pos <= 32'd0;
            game_proj2_pos <= 32'd0;
            game_medicine_pos <= 32'd0;
            game_timer <= 32'd0;
        end else begin
            mmio_uart_tx_start <= 1'b0;
            perf_dump_req <= 1'b0;

            prev_tx_hit   <= (data_memory_write_enable && uart_tx_hit);
            prev_perf_hit <= (data_memory_write_enable && perf_dump_hit);

            // latch a new transmit request on the rising edge of the store
            if (tx_we_rise) begin
                tx_pending      <= 1'b1;
                tx_pending_data <= data_memory_write_data[7:0];
            end
            // service the pending request once the UART is free
            if (tx_pending && !UART_busy) begin
                mmio_uart_tx_data  <= tx_pending_data;
                mmio_uart_tx_start <= 1'b1;
                tx_pending         <= 1'b0;
            end

            // A write to the PERF_DUMP register restarts the measurement window.
            if (perf_we_rise)
                perf_dump_req <= 1'b1;

            if (data_memory_write_enable && game_p1_pos_hit) begin
                game_p1_x <= data_memory_write_data[10:0];
                game_p1_y <= data_memory_write_data[26:16];
            end
            if (data_memory_write_enable && game_p2_pos_hit) begin
                game_p2_x <= data_memory_write_data[10:0];
                game_p2_y <= data_memory_write_data[26:16];
            end
            if (data_memory_write_enable && game_status_hit)
                game_status <= data_memory_write_data;
            if (data_memory_write_enable && game_flags_hit)
                game_flags <= data_memory_write_data;
            if (data_memory_write_enable && game_proj1_hit)
                game_proj1_pos <= data_memory_write_data;
            if (data_memory_write_enable && game_proj2_hit)
                game_proj2_pos <= data_memory_write_data;
            if (data_memory_write_enable && game_medicine_hit)
                game_medicine_pos <= data_memory_write_data;
            if (data_memory_write_enable && game_timer_hit)
                game_timer <= data_memory_write_data;
        end
    end


endmodule
