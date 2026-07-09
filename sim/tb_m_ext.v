`timescale 1ns / 1ps

module tb_m_ext;
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

    RV32I46F5SPMMIO #(
        .ROM_INIT_FILE("mem/m_ext_test.hex")
    ) dut (
        .clk(clk),
        .reset(reset),
        .UART_busy(UART_busy),
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

    localparam CLK_PERIOD = 20;
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    reg [7:0] out_bytes [0:255];
    integer out_cnt;
    integer cyc;
    integer i;
    reg done_flag;
    integer fd;

    always @(posedge clk) begin
        if (mmio_uart_tx_start) begin
            out_bytes[out_cnt] = mmio_uart_tx_data;
            out_cnt = out_cnt + 1;
        end
        if (mmio_uart_tx_start && out_cnt >= 2 &&
            out_bytes[out_cnt-1] == 8'h0A && out_bytes[out_cnt-2] == 8'h0D)
            done_flag <= 1'b1;
    end

    initial begin
        UART_busy = 1'b0;
        manual_stall = 1'b0;
        out_cnt = 0;
        done_flag = 1'b0;
        reset = 1'b1;
        @(posedge clk);
        @(posedge clk);
        reset = 1'b0;

        cyc = 0;
        begin : run_loop
            while (cyc < 10000) begin
                @(posedge clk);
                cyc = cyc + 1;
                if (done_flag) disable run_loop;
            end
        end

        fd = $fopen("m_ext_result.txt", "w");
        $fwrite(fd, "Captured UART output: ");
        for (i = 0; i < out_cnt; i = i + 1)
            $fwrite(fd, "%c", out_bytes[i]);
        $fwrite(fd, "\n");

        if (out_cnt >= 6 &&
            out_bytes[2] == "F" && out_bytes[3] == "A" &&
            out_bytes[4] == "I" && out_bytes[5] == "L") begin
            $fwrite(fd, "M_EXT_RESULT: FAIL at test id '%c%c'\n", out_bytes[0], out_bytes[1]);
            $fatal(1, "RV32M focused test failed");
        end else if (out_cnt >= 4 &&
            out_bytes[0] == "O" && out_bytes[1] == "K") begin
            $fwrite(fd, "M_EXT_RESULT: PASS (OK)\n");
        end else begin
            $fwrite(fd, "M_EXT_RESULT: UNKNOWN (cyc=%0d uart_bytes=%0d)\n", cyc, out_cnt);
            $fatal(1, "RV32M focused test did not produce OK/FAIL");
        end
        $fclose(fd);
        $finish;
    end
endmodule

