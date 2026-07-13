`timescale 1ns / 1ps

module tb_external_irq;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg ext_irq = 1'b0;
    wire [7:0] uart_data;
    wire uart_start;
    integer cycles = 0;
    integer out_count = 0;
    reg [7:0] output_bytes [0:255];

    always #10 clk = ~clk;

    RV32I46F5SPMMIO #(
        .ROM_INIT_FILE("test_programs/irq_external.hex")
    ) dut (
        .clk(clk),
        .reset(reset),
        .UART_busy(1'b0),
        .manual_stall(1'b0),
        .icache_mode(1'b0),
        .ext_irq(ext_irq),
        .game_p1_buttons(5'b0),
        .game_p2_buttons(5'b0),
        .mmio_uart_tx_data(uart_data),
        .mmio_uart_tx_start(uart_start)
    );

    always @(posedge clk) begin
        if (uart_start) begin
            output_bytes[out_count] = uart_data;
            out_count = out_count + 1;
        end
    end

    initial begin
        repeat (4) @(posedge clk);
        reset = 1'b0;
        repeat (60) @(posedge clk);
        ext_irq = 1'b1;
        @(posedge clk);
        ext_irq = 1'b0;

        for (cycles = 0; cycles < 50000; cycles = cycles + 1) begin
            @(posedge clk);
            if (out_count >= 4 &&
                output_bytes[out_count-4] == "I" &&
                output_bytes[out_count-3] == "R" &&
                output_bytes[out_count-2] == "Q" &&
                output_bytes[out_count-1] == 8'h0d) begin
                $display("EXTERNAL_IRQ_PASS mepc=%08h mcause=%08h", dut.csr_file.mepc, dut.csr_file.mcause);
                $finish;
            end
        end
        $display("EXTERNAL_IRQ_FAIL output_count=%0d pc=%08h mtvec=%08h mstatus=%08h mepc=%08h mcause=%08h irq_active=%b",
                 out_count, dut.pc, dut.csr_file.mtvec,
                 dut.csr_file.mstatus, dut.csr_file.mepc, dut.csr_file.mcause,
                 dut.irq_active);
        for (cycles = 0; cycles < 32 && cycles < out_count; cycles = cycles + 1)
            $write("%c", output_bytes[cycles]);
        $write("\n");
        $finish;
    end
endmodule
