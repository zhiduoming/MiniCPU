`timescale 1ns / 1ps
// tb_perf: runs the full self-check program INCLUDING the perf_report,
// and dumps the REAL PerfMon register values at the moment the program
// reads each MMIO counter. Compare these with the numbers the program
// prints over UART to see if the counters are correct at RTL level.

module tb_perf;
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

    reg icache_mode;

    RV32I46F5SPMMIO #(
        .ROM_INIT_FILE("mem/program.hex")
    ) dut (
        .clk(clk),
        .reset(reset),
        .UART_busy(UART_busy),
        .manual_stall(manual_stall),
        .icache_mode(icache_mode),
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
    integer   retired_cnt;
    reg       done_flag;
    integer   fd;
    integer   perf_fd;
    integer   read_cnt;
    reg       reads_done;

    // Dump the real PerfMon register values whenever the program reads a
    // perf counter via MMIO.
    always @(posedge clk) begin
        if (dut.perf_read_hit) begin
            read_cnt = read_cnt + 1;
            $fwrite(perf_fd,
                "READ #%0d @%08h cyc=%0d inst=%0d acc=%0d hit=%0d miss=%0d\n",
                read_cnt, dut.MEM_alu_result,
                dut.perfmon.cyc, dut.perfmon.inst,
                dut.perfmon.acc, dut.perfmon.hit, dut.perfmon.miss);
            if (read_cnt >= 6) reads_done <= 1'b1;
        end
        if (mmio_uart_tx_start) begin
            out_bytes[out_cnt] = mmio_uart_tx_data;
            out_cnt = out_cnt + 1;
            if (out_cnt >= 2 &&
                out_bytes[out_cnt-1] == 8'h0A && out_bytes[out_cnt-2] == 8'h0D)
                done_flag <= 1'b1;
        end
    end

    initial begin
        UART_busy    = 1'b0;
        manual_stall = 1'b0;
        icache_mode  = 1'b0;
        out_cnt      = 0;
        retired_cnt  = 0;
        read_cnt     = 0;
        done_flag    = 1'b0;
        reads_done   = 1'b0;
        reset = 1'b1;
        @(posedge clk);
        @(posedge clk);
        reset = 1'b0;

        fd = $fopen("perf_sim_result.txt", "w");
        perf_fd = $fopen("perf_sim_dump.txt", "w");

        cyc = 0;
        begin : run_loop
            while (cyc < 5000000) begin
                @(posedge clk);
                cyc = cyc + 1;
                if (instruction_retired) retired_cnt = retired_cnt + 1;
                // stop a short while after we have captured all 6 MMIO reads
                if (reads_done && cyc > 50000) disable run_loop;
            end
        end

        $fwrite(perf_fd, "FINAL perfmon: cyc=%0d inst=%0d acc=%0d hit=%0d miss=%0d\n",
                dut.perfmon.cyc, dut.perfmon.inst,
                dut.perfmon.acc, dut.perfmon.hit, dut.perfmon.miss);
        $fclose(perf_fd);

        $fwrite(fd, "Captured UART output (first 600 bytes):\n");
        begin : outdump
            integer k;
            for (k = 0; k < out_cnt && k < 600; k = k + 1)
                $fwrite(fd, "%c", out_bytes[k]);
        end
        $fwrite(fd, "\n\nRETIRED_TOTAL=%0d CYC_SIM=%0d\n", retired_cnt, cyc);
        $fclose(fd);
        $finish;
    end
endmodule
