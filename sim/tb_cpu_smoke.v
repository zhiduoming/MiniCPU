`timescale 1ns / 1ps

// ?? JAL ?????? + ??????? EBREAK ???
// ???ADDI x1,0,0x0A / JAL x0,+8 / ADDI x2,0,0x123 / ADDI x3,0,0x55 / JAL x0,0
// ???x1 == 0x0A, x2 == 0, x3 == 0x55

module tb_cpu_smoke;
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
        .ROM_INIT_FILE("mem/smoke.hex")
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

    localparam CLK_PERIOD = 20; // ns
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    integer cyc;
    reg [31:0] x1_val, x2_val, x3_val;

    always @(posedge clk) begin
        if (mmio_uart_tx_start) begin
            $display("[UART] Sent char: 0x%02h ('%c')", mmio_uart_tx_data, mmio_uart_tx_data);
        end
    end

    initial begin
        $display("==== CPU ?? JAL ?? + ??????? ID_opcode/raw_imm?====");
        UART_busy  = 1'b0;
        manual_stall = 1'b0;
        reset = 1'b1;
        @(posedge clk);
        @(posedge clk);
        reset = 1'b0;

        cyc = 0;
        repeat (60) begin
            @(posedge clk);
            cyc = cyc + 1;

            // ----- ???? -----
            $display("cyc=%02d  pc=0x%08h  WB_inst=0x%08h  WB_rd=%02d  WB_wd=0x%08h",
                     cyc, debug_pc, debug_instruction, debug_reg_addr, debug_reg_data);

            // ----- EX ???? -----
            $display("         EX_jump=%b  EX_pc=0x%08h  EX_imm=0x%08h  jump_target=0x%08h",
                     dut.id_ex_register.EX_jump,
                     dut.id_ex_register.EX_pc,
                     dut.id_ex_register.EX_imm,
                     dut.pc_controller.jump_target);

            // ----- ID ???? -----
            $display("         ID_pc=0x%08h  ID_jump(CU)=%b  IF_ID_flush=%b  ID_EX_flush=%b",
                     dut.if_id_register.ID_pc,
                     dut.control_unit.jump,
                     dut.if_id_register.flush,
                     dut.id_ex_register.flush);

            // ----- PCController ???? -----
            $display("         pc_stall=%b  trapped=%b  branch_miss=%b  branch_est=%b  next_pc=0x%08h",
                     dut.pc_controller.pc_stall,
                     dut.pc_controller.trapped,
                     dut.pc_controller.branch_prediction_miss,
                     dut.pc_controller.branch_estimation,
                     dut.pc_controller.next_pc);

            // ----- ???????? -----
            $display("         trap_status=%b  ID_trapped=%b  EX_trapped=%b  MEM_trapped=%b",
                     dut.exception_detector.trap_status,
                     dut.exception_detector.ID_trapped,
                     dut.exception_detector.EX_trapped,
                     dut.exception_detector.MEM_trapped);

            // ----- ???ExceptionDetector ???? -----
            $display("         ID_opcode=0x%02h  ID_funct3=%b  raw_imm=0x%03h",
                     dut.exception_detector.ID_opcode,
                     dut.exception_detector.ID_funct3,
                     dut.exception_detector.raw_imm);

            // ----- stall ?? -----
            $display("         IF_ID_stall=%b  ID_EX_stall=%b  EX_MEM_stall=%b  MEM_WB_stall=%b",
                     dut.hazard_unit.IF_ID_stall,
                     dut.hazard_unit.ID_EX_stall,
                     dut.hazard_unit.EX_MEM_stall,
                     dut.hazard_unit.MEM_WB_stall);
        end

        x1_val = dut.register_file.registers[1];
        x2_val = dut.register_file.registers[2];
        x3_val = dut.register_file.registers[3];

        $display("---- ?? ----");
        $display("x1 = 0x%08h (%0d)", x1_val, x1_val);
        $display("x2 = 0x%08h (%0d)", x2_val, x2_val);
        $display("x3 = 0x%08h (%0d)", x3_val, x3_val);

        if (x1_val !== 32'd10) begin
            $display("!!! ????: x1 ?? 10, ?? %0d", x1_val);
            $fatal(1, "x1 != 10");
        end
        if (x2_val !== 32'd0) begin
            $display("!!! ????: x2 ?? 0, ?? %0d", x2_val);
            $fatal(1, "x2 != 0");
        end
        if (x3_val !== 32'd85) begin
            $display("!!! ????: x3 ?? 85, ?? %0d", x3_val);
            $fatal(1, "x3 != 85");
        end

        $display("==== PASS: JAL target=PC+offset correct AND following instr flushed ====");
        $finish;
    end
endmodule
