`timescale 1ns / 1ps

module tb_game_external_irq;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg ext_irq = 1'b0;
    wire [31:0] game_flags;
    wire [7:0] uart_data;
    wire uart_start;
    integer cycles;
    reg [31:0] interrupted_pc;
    reg [31:0] p1_hp_before_irq;

    always #10 clk = ~clk;

    RV32I46F5SPMMIO #(
        .ROM_INIT_FILE("test_programs/game_cpu_full.hex")
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
        .mmio_uart_tx_start(uart_start),
        .game_flags(game_flags)
    );

    always @(posedge clk)
        if (uart_start) $write("%c", uart_data);

    initial begin
        repeat (4) @(posedge clk);
        reset = 1'b0;

        cycles = 0;
        while (dut.csr_file.mtvec == 32'h00001000 && cycles < 5000) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        repeat (40) @(posedge clk);
        interrupted_pc = dut.pc;
        p1_hp_before_irq = dut.register_file.registers[28];
        ext_irq = 1'b1;
        @(posedge clk);
        ext_irq = 1'b0;

        cycles = 0;
        // The performance ISR prints a full UART report before setting the
        // six-second resume counter, so allow enough cycles for formatting.
        while (dut.data_memory.memory[43] == 0 && cycles < 100000) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        cycles = 0;
        while (!game_flags[30] && cycles < 2000) begin
            @(posedge clk);
            cycles = cycles + 1;
        end

        if (dut.data_memory.memory[43] > 0 &&
            dut.data_memory.memory[43] <= 751 && game_flags[30] &&
            dut.register_file.registers[28] == p1_hp_before_irq &&
            dut.csr_file.mcause == 32'h8000000b) begin
            $display("GAME_EXTERNAL_IRQ_PASS interrupted_pc=%08h mepc=%08h screen_count=%0d p1_hp=%0d",
                     interrupted_pc, dut.csr_file.mepc,
                     dut.data_memory.memory[43], dut.register_file.registers[28]);
        end else begin
            $display("GAME_EXTERNAL_IRQ_FAIL mtvec=%08h mepc=%08h mcause=%08h count=%0d request=%0d flags=%08h hp_before=%0d hp_after=%0d",
                     dut.csr_file.mtvec, dut.csr_file.mepc,
                     dut.csr_file.mcause, dut.data_memory.memory[43], dut.data_memory.memory[71], game_flags,
                     p1_hp_before_irq, dut.register_file.registers[28]);
        end
        $finish;
    end
endmodule
