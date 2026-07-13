`timescale 1ns / 1ps
`ifndef ICACHE_MODE
`define ICACHE_MODE 1'b0
`endif

// Self-check simulation: runs program.hex on the RV32IM CPU core and
// captures the UART output. Prints PASS if "OK" is received, FAIL
// (with the failing test id) otherwise.

module tb_matrix_mac;
    reg clk;
    reg reset;
    reg UART_busy;
    reg manual_stall;

    wire [31:0] retire_instruction;
    wire [7:0]  mmio_uart_tx_data;
    wire        mmio_uart_tx_start;
    wire        instruction_retired;
    wire        trapped;
    wire [31:0] debug_pc;
    wire [31:0] debug_instruction;
    wire [4:0]  debug_reg_addr;
    wire [31:0] debug_reg_data;
    wire [31:0] debug_alu_result;

    reg         icache_mode;

    RV32I46F5SPMMIO #(
        .ROM_INIT_FILE("mem/matrix_mac.hex")
    ) dut (
        .clk(clk),
        .reset(reset),
        .UART_busy(UART_busy),
        .manual_stall(manual_stall),
        .icache_mode(icache_mode),
        .ext_irq(1'b0),
        .game_p1_buttons(5'b0),
        .game_p2_buttons(5'b0),
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

    localparam CLK_PERIOD = 20; // ns
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    reg [7:0] out_bytes [0:4095];
    integer   out_cnt;
    integer   cyc;
    integer   i;
    integer   fail_pos;
    integer   retired_cnt;
    reg       done_flag;
    integer   dbg_fd;

    always @(posedge clk) begin
        if (instruction_retired) retired_cnt = retired_cnt + 1;
        if (mmio_uart_tx_start) begin
            out_bytes[out_cnt] = mmio_uart_tx_data;
            out_cnt = out_cnt + 1;
            $fwrite(dbg_fd, "UART cyc=%0d byte=0x%02h '%c' pc=0x%08h ret=%0d\n",
                    cyc, mmio_uart_tx_data, mmio_uart_tx_data, debug_pc, retired_cnt);
        end
        if (mmio_uart_tx_start && out_cnt >= 2 &&
            out_bytes[out_cnt-1] == 8'h0A && out_bytes[out_cnt-2] == 8'h0D)
            done_flag <= 1'b1;
    end

    initial begin
        integer fd;
        UART_busy    = 1'b0;
        manual_stall = 1'b0;
        icache_mode  = `ICACHE_MODE;
        out_cnt      = 0;
        retired_cnt  = 0;
        done_flag    = 1'b0;
        reset = 1'b1;
        @(posedge clk);
        @(posedge clk);
        reset = 1'b0;

        dbg_fd = $fopen("sim_dbg.txt", "w");

        cyc = 0;
        begin : run_loop
            while (cyc < 200000) begin
                @(posedge clk);
                cyc = cyc + 1;
                if (cyc <= 1000)
                    $fwrite(dbg_fd, "cyc=%0d pc=0x%08h inst=0x%08h ic_st=%b hitc=%b hit=%b miss=%b ret=%b uart=%0d\n",
                            cyc, debug_pc, debug_instruction,
                            dut.icache.ic_stall, dut.icache.hit_comb, dut.icache.ic_hit, dut.icache.ic_miss,
                            instruction_retired, out_cnt);
                if ((cyc % 2000) == 0)
                    $fwrite(dbg_fd, "cyc=%0d pc=0x%08h retired=%0d uart=%0d trapped=%b\n",
                            cyc, debug_pc, retired_cnt, out_cnt, trapped);
                if (done_flag && out_cnt >= 21) disable run_loop;
            end
        end

        $fwrite(dbg_fd, "FINAL cyc=%0d pc=0x%08h retired=%0d uart=%0d trapped=%b\n",
                cyc, debug_pc, retired_cnt, out_cnt, trapped);
        $fclose(dbg_fd);

        fd = $fopen("sim_result.txt", "w");
        $fwrite(fd, "Captured UART output: ");
        for (i = 0; i < out_cnt; i = i + 1)
            $fwrite(fd, "%c", out_bytes[i]);
        $fwrite(fd, "\n");

        fail_pos = -1;
        for (i = 0; i + 3 < out_cnt; i = i + 1) begin
            if (fail_pos < 0 &&
                out_bytes[i] == "F" && out_bytes[i+1] == "A" &&
                out_bytes[i+2] == "I" && out_bytes[i+3] == "L")
                fail_pos = i;
        end

        if (fail_pos >= 0) begin
            $fwrite(fd, "RESULT: FAIL\n");
        end else if (out_cnt >= 21 &&
            out_bytes[0] == "M" && out_bytes[1] == "M" &&
            out_bytes[3] == "2" && out_bytes[4] == "4" &&
            out_bytes[6] == "2" && out_bytes[7] == "9" &&
            out_bytes[9] == "4" && out_bytes[10] == "0" &&
            out_bytes[12] == "4" && out_bytes[13] == "9") begin
            $fwrite(fd, "RESULT: PASS (MAC matrix)\n");
        end else begin
            $fwrite(fd, "RESULT: UNKNOWN (no OK/FAIL pattern, cyc=%0d retired=%0d)\n", cyc, retired_cnt);
        end
        $fclose(fd);
        $finish;
    end
endmodule
