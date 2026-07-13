`timescale 1ns / 1ps
// Focused CSR write->read (RAW) test. Runs a LINEAR (branch-free)
// program so the iverilog X-propagation branch-target bug does not
// interfere. Verifies CSRRW then back-to-back CSRRS read back the
// post-write value (the exact scenario of Test 16b that the
// Hazard_Unit CSR RAW stall fixes).

module tb_csr;
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
        .ROM_INIT_FILE("mem/csr_test.hex")
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

    integer cyc;

    initial begin
        integer fd;
        integer fd_dbg;
        reg [31:0] v2, v3, v4, v6, v7;
        UART_busy    = 1'b0;
        manual_stall = 1'b0;
        reset = 1'b1;
        fd_dbg = $fopen("csr_dbg.txt", "w");
        @(posedge clk);
        @(posedge clk);
        reset = 1'b0;

        cyc = 0;
        while (cyc < 400) begin
            @(posedge clk);
            cyc = cyc + 1;
            if (cyc >= 1 && cyc <= 24)
                $fwrite(fd_dbg, "cyc=%0d IFID=0x%08h IDEX=0x%08h EXMEM=0x%08h MEMWB=0x%08h | IDEXrd=%0d EXMEMrd=%0d MEMWBrd=%0d | EXMEMwe=%b MEMWBwe=%b | rawstall=%b bub=%b | mtvec=0x%08h proc=%b rdy=%b | wp=%b%b%b%b | csrRd_out=0x%08h EXcsrRd=0x%08h | IFIDst=%b IDEXst=%b EXMEMst=%b MEMWBst=%b\n",
                    cyc,
                    dut.if_id_register.ID_instruction, dut.EX_instruction, dut.MEM_instruction, dut.WB_instruction,
                    dut.id_ex_register.EX_rd, dut.ex_mem_register.MEM_rd, dut.mem_wb_register.WB_rd,
                    dut.ex_mem_register.MEM_register_write_enable, dut.mem_wb_register.WB_register_write_enable,
                    dut.hazard_unit.csr_raw_stall, dut.hazard_unit.csr_bubble,
                    dut.csr_file.mtvec, dut.csr_file.csr_processing, dut.csr_file.csr_ready,
                    dut.hazard_unit.csr_wp_ex, dut.hazard_unit.csr_wp_mem, dut.hazard_unit.csr_wp_wb, dut.hazard_unit.csr_wp_wb2,
                    dut.csr_read_out, dut.id_ex_register.EX_csr_read_data,
                    dut.hazard_unit.IF_ID_stall, dut.hazard_unit.ID_EX_stall, dut.hazard_unit.EX_MEM_stall, dut.hazard_unit.MEM_WB_stall);
            if (cyc >= 11 && cyc <= 16)
                $fwrite(fd_dbg, "  --> alu_result=0x%08h csr_fwd=0x%08h csr_wr_data=0x%08h WB_alu=0x%08h EXrs1=0x%08h EXrd1=0x%08h\n",
                    dut.alu_result, dut.csr_forward_data, dut.csr_write_data,
                    dut.mem_wb_register.WB_alu_result, dut.id_ex_register.EX_read_data1, dut.id_ex_register.EX_rd);
        end

        v2 = dut.register_file.registers[2];
        v3 = dut.register_file.registers[3];
        v4 = dut.register_file.registers[4];
        v6 = dut.register_file.registers[6];
        v7 = dut.register_file.registers[7];

        fd = $fopen("csr_result.txt", "w");
        $fwrite(fd, "x1     =0x%08h\n", dut.register_file.registers[1]);
        $fwrite(fd, "pc     =0x%08h\n", debug_pc);
        $fwrite(fd, "retired=%0d\n", cyc);
        $fwrite(fd, "trap_done=%b csr_ready=%b mtvec=0x%08h\n", dut.hazard_unit.trap_done, dut.csr_file.csr_ready, dut.csr_file.mtvec);
        $fwrite(fd, "x5     =0x%08h\n", dut.register_file.registers[5]);
        $fwrite(fd, "x2(old) =0x%08h\n", v2);
        $fwrite(fd, "x3(rd1) =0x%08h  (expect 0x12345678)\n", v3);
        $fwrite(fd, "x4(rd2) =0x%08h  (expect 0x12345678)\n", v4);
        $fwrite(fd, "x6(set) =0x%08h  (expect 0x12345678)\n", v6);
        $fwrite(fd, "x7(rd3) =0x%08h  (expect 0x12345679)\n", v7);

        if (v3 == 32'h12345678 && v4 == 32'h12345678 &&
            v7 == 32'h12345679 && v2 == 32'h00001000 && v6 == 32'h12345678)
            $fwrite(fd, "CSR_RAW_RESULT: PASS\n");
        else
            $fwrite(fd, "CSR_RAW_RESULT: FAIL\n");
        $fclose(fd);
        $fclose(fd_dbg);
        $finish;
    end
endmodule
