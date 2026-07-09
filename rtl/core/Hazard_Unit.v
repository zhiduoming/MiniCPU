`include "opcode.vh"
`include "trap.vh"
`include "csr.vh"


module HazardUnit (
    input clk,
    input reset, 

    input wire trap_done,
    input wire csr_ready,
    input wire standby_mode,
    input wire [2:0] trap_status,
    input wire misaligned_instruction_flush,
    input wire misaligned_memory_flush,
    input wire pth_done_flush,

    input wire [4:0] ID_rs1,
    input wire [4:0] ID_rs2,
    input wire [11:0] ID_raw_imm,
    input wire [6:0] ID_opcode,
    input wire [2:0] ID_funct3,
    
    input wire [4:0] MEM_rd,
    input wire MEM_register_write_enable,
    input wire MEM_csr_write_enable,
    input wire [11:0] MEM_csr_write_address,       // MEM_imm[11:0]

    input wire [4:0] WB_rd,
    input wire WB_register_write_enable,
    input wire WB_csr_write_enable,
    input wire [11:0] WB_csr_write_address, // WB_imm[11:0]

    input wire [4:0] EX_rd,
    input wire [6:0] EX_opcode,
    input wire [4:0] EX_rs1,
    input wire [4:0] EX_rs2,
    input wire [11:0] EX_imm,  // EX_imm[11:0]

    input wire EX_csr_write_enable,

    input wire EX_jump,
    input wire branch_prediction_miss,

    // ??????????????????
    input wire manual_stall,

    // to Forward Unit - ALU forwarding
    output reg [1:0] hazard_mem,
    output reg [1:0] hazard_wb,
    output wire csr_hazard_mem,
    output wire csr_hazard_wb,
    //output reg csr_reg_hazard,

    /// to Forward Unit - Store data forwarding
    output wire store_hazard_mem,
    output wire store_hazard_wb,

    output reg IF_ID_flush,
    output reg ID_EX_flush,
    output reg EX_MEM_flush,
    output reg MEM_WB_flush,
    
    output reg IF_ID_stall,
    output reg ID_EX_stall,
    output reg EX_MEM_stall,
    output reg MEM_WB_stall,
    // csr_bubble is asserted (1 cycle delayed from csr_raw_stall) so the
    // EX/MEM register inserts a NOP instead of re-feeding the frozen EX
    // instruction. This makes a CSR write commit exactly once during a
    // front-end RAW stall instead of being re-committed every stall cycle
    // (which would re-write the CSR with a stale/corrupted value).
    output wire csr_bubble
);

    // Store instruction detection
    wire is_store = (EX_opcode == `OPCODE_STORE);

    // Register ALU hazard detections
    wire mem_hazard_rs1 = MEM_register_write_enable && (MEM_rd != 5'd0) && (MEM_rd == EX_rs1);
    wire mem_hazard_rs2 = MEM_register_write_enable && (MEM_rd != 5'd0) && (MEM_rd == EX_rs2);
    wire wb_hazard_rs1 = WB_register_write_enable && (WB_rd != 5'd0) && (WB_rd == EX_rs1);
    wire wb_hazard_rs2 = WB_register_write_enable && (WB_rd != 5'd0) && (WB_rd == EX_rs2);

    // Store instruction rs2 hazard detections
    assign store_hazard_mem = is_store && mem_hazard_rs2;
    assign store_hazard_wb = is_store && wb_hazard_rs2 && !mem_hazard_rs2;
    
    // CSR hazard detection
    assign csr_hazard_mem = MEM_csr_write_enable && (MEM_csr_write_address == EX_imm);
    assign csr_hazard_wb = WB_csr_write_enable && (WB_csr_write_address == EX_imm);

    // CSR read-after-write (RAW) hazard detection.
    // A CSR read instruction (opcode SYSTEM, funct3 != 0) in ID may depend on
    // the result of a CSR WRITE that is still in flight in EX/MEM/WB. We must
    // hold the reading instruction in ID until the pending write has fully
    // retired, otherwise csr_read_out (sampled into the pipeline at the
    // ID->EX boundary) would capture the pre-write (stale) value.
    //
    // The write commits at WB, but the read samples at ID->EX, so the read
    // must be delayed by the full write latency. We hold the read in ID with
    // IF/ID+ID/EX stalls. Because ID/EX stall also freezes the EX stage, the
    // write register appears "stuck in EX", so we CANNOT detect the in-flight
    // write from the frozen EX pipeline register. Instead we track it with a
    // shift register (csr_wp_*) that advances every cycle -- the write keeps
    // flowing EX->MEM->WB even while the front-end is stalled -- and release
    // the stall exactly when the write retires and csr_read_out is post-write.
    wire id_true_csr_write = (ID_opcode == `OPCODE_ENVIRONMENT) &&
                             (ID_funct3 == `CSR_CSRRW  || ID_funct3 == `CSR_CSRRWI ||
                              ((ID_funct3 == `CSR_CSRRS || ID_funct3 == `CSR_CSRRC ||
                                ID_funct3 == `CSR_CSRRSI || ID_funct3 == `CSR_CSRRCI) && (ID_rs1 != 5'b0)));
    wire csr_read_in_id   = (ID_opcode == `OPCODE_ENVIRONMENT) && (ID_funct3 != 3'b0);

    reg csr_wp_ex;
    reg csr_wp_mem;
    reg csr_wp_wb;
    reg csr_wp_wb2;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            csr_wp_ex   <= 1'b0;
            csr_wp_mem  <= 1'b0;
            csr_wp_wb   <= 1'b0;
            csr_wp_wb2  <= 1'b0;
        end else if (!(EX_MEM_stall || MEM_WB_stall)) begin
            // advance only when the downstream pipe is not frozen, so the
            // tracked write position stays in sync with the real pipeline.
            csr_wp_wb2 <= csr_wp_wb;
            csr_wp_wb   <= csr_wp_mem;
            csr_wp_mem  <= csr_wp_ex;
            csr_wp_ex   <= id_true_csr_write;
        end
    end

    // The CSR write commits at the WB posedge; the reading instruction samples
    // csr_read_out (combinational) at the ID->EX boundary. Those two events
    // would otherwise land on the SAME clock edge, so the reader would capture
    // the PRE-write value. Extending the hazard by one extra stage
    // (csr_wp_wb2) forces the reader to cross ID->EX one full cycle AFTER the
    // writer has committed, so it observes the post-write CSR value.
    wire csr_raw_hazard = csr_read_in_id &&
                          (csr_wp_ex || csr_wp_mem || csr_wp_wb || csr_wp_wb2);

    // CSR read-after-write stall: hold the reading CSR instruction in ID
    // (and upstream) until the pending write has retired. EX/MEM/WB are NOT
    // stalled, so the writer keeps advancing and COMMITS (updating the CSR
    // register) before the reader proceeds and samples csr_read_out. This
    // avoids both the original "stale read" (reader was 2 stages behind a
    // lock-stepped write) and the front-end-only freeze livelock.
    wire csr_raw_stall = csr_raw_hazard;

    // 1-cycle delayed copy of csr_raw_stall, retained for the shift register
    // below. The CSR RAW hazard is now resolved with data forwarding (see
    // Forward_Unit.csr_forward_data), so we intentionally do NOT assert a
    // pipeline stall or inject a bubble here -- that previously dropped the
    // reading instruction and desynchronised the pipeline.
    reg csr_raw_stall_q;
    always @(posedge clk or posedge reset) begin
        if (reset) csr_raw_stall_q <= 1'b0;
        else      csr_raw_stall_q <= csr_raw_stall;
    end
    // csr_bubble injects a NOP into EX/MEM to suppress the re-feed of a CSR
    // WRITE that is frozen in EX while the front-end RAW stall is active. The
    // writer must make its first pass EX->MEM (so it commits), but on every
    // subsequent stall cycle the frozen EX would re-feed the same writer into
    // MEM/WB; bubbling MEM turns that re-feed into a NOP.
    //
    // CRITICAL: the bubble must ONLY fire when a CSR writer is actually frozen
    // in EX (EX_csr_write_enable). In the NON-ADJACENT write->read pattern used
    // by the board's Test 16 (e.g. CSRRS-write, then 2-3 LUI/ADDI/BNE, then
    // CSRRS-read), the write has ALREADY committed (it is in WB) when the read
    // stalls, so EX holds a *legitimate gap instruction*, NOT the writer. If we
    // bubble unconditionally (csr_raw_stall_q alone) we would drop that legal
    // instruction one cycle after the stall releases -> corrupted results.
    // Gating on EX_csr_write_enable guarantees we only suppress a real re-fed
    // writer and never discard a valid gap instruction.
    assign csr_bubble = csr_raw_stall_q && EX_csr_write_enable;

    always @(*) begin
        // ???
        hazard_mem = 2'b00;
        hazard_wb = 2'b00;
        IF_ID_flush = 1'b0;
        ID_EX_flush = 1'b0;
        EX_MEM_flush = 1'b0;
        MEM_WB_flush = 1'b0;
        
        IF_ID_stall = 1'b0;
        ID_EX_stall = 1'b0;
        EX_MEM_stall = 1'b0;
        MEM_WB_stall = 1'b0;

        // ALU forwarding hazards
        // For Store instructions, rs2 hazard shouldn't trigger ALUsrcB forwarding.
        // In this case, rs2 is store data, not ALU operand.
        hazard_mem[0] = mem_hazard_rs1;
        hazard_mem[1] = is_store ? 1'b0 : mem_hazard_rs2; // Disables ALUsrcB forwarding for store
        hazard_wb[0] = wb_hazard_rs1 && !mem_hazard_rs1;
        hazard_wb[1] = is_store ? 1'b0 : (wb_hazard_rs2 && !mem_hazard_rs2); // Disables ALUsrcB forwarding for store

        // ?????? flush? ??? trap_done
        if (trap_done && branch_prediction_miss) begin
            IF_ID_flush = 1'b1;
            ID_EX_flush = 1'b1;
        end

        // ??????(JAL/JALR)? EX_jump ????? flush ????, ??? trap_done ???????
        // JAL ?? EX ????????, flush ???? IF/ID ??? ID/EX ???????????
        if (EX_jump) begin
            IF_ID_flush = 1'b1;
            ID_EX_flush = 1'b1;
        end

        if (pth_done_flush) begin
            IF_ID_flush = 1'b1;
            ID_EX_flush = 1'b1;
            EX_MEM_flush = 1'b1;
            MEM_WB_flush = 1'b1;
        end

        // ????
        if (standby_mode) begin // For ID Phase Exception handling
            IF_ID_stall = 1'b1;
            ID_EX_stall = 1'b1;
            EX_MEM_stall = 1'b0;
            MEM_WB_stall = 1'b0;
        end else if (!trap_done) begin
            // Startup / trap-pending: freeze the ENTIRE pipeline until the
            // trap-handling prelude has finished.
            IF_ID_stall = 1'b1;
            ID_EX_stall = 1'b1;
            EX_MEM_stall = 1'b1;
            MEM_WB_stall = 1'b1;
        end

        // ???????????-- ??????
        if (manual_stall) begin
            IF_ID_stall = 1'b1;
            ID_EX_stall = 1'b1;
            EX_MEM_stall = 1'b1;
            MEM_WB_stall = 1'b1;
        end

    // CSR read-after-write stall: hold the reading CSR instruction in ID
    // (and the upstream stages) until the pending write has retired. EX/MEM
    // and WB are not stalled, so the writer keeps advancing and commits
    // (updating the CSR register) before the reader proceeds and samples
    // csr_read_out. csr_bubble (driven into the EX/MEM register) inserts a
    // NOP on the interior stall cycles so the frozen EX instruction (the
    // pending write) is not re-fed into MEM/WB (which would re-commit it).
    if (csr_raw_stall) begin
        IF_ID_stall = 1'b1;
        ID_EX_stall = 1'b1;
    end
    end

endmodule
