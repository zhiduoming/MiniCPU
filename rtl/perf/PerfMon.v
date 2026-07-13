`timescale 1ns / 1ps
// ============================================================================
// PerfMon  --  Instruction-Cache performance monitor (simplified)
//   Continuously counts (since reset):
//       r_cyc   cycles
//       r_inst  retired instructions
//       r_acc   ICache accesses
//       r_hit   ICache hits
//       r_miss  ICache misses
//   Counters are exposed as MMIO-readable registers at 0x10010020+.
//   A one-cycle clear pulse restarts the measurement window.
//   Division and ASCII conversion are done in software.
// ============================================================================
module PerfMon (
    input          clk,
    input          reset,
    input          clear,
    input          hold,
    input          instruction_retired,
    input          ic_access,
    input          ic_hit,
    input          ic_miss,
    input          ic_mode,
    input          pipeline_stall,
    input          branch_retired,
    input          branch_mispredict,
    input          memory_retired,
    input          m_ext_retired,
    input          mac_retired,
    output [31:0]  r_cyc,
    output [31:0]  r_inst,
    output [31:0]  r_acc,
    output [31:0]  r_hit,
    output [31:0]  r_miss,
    output [31:0]  r_stall,
    output [31:0]  r_branch,
    output [31:0]  r_branch_miss,
    output [31:0]  r_memory,
    output [31:0]  r_m_ext,
    output [31:0]  r_mac,
    output [31:0]  r_mul_cycles
);
    reg [31:0] cyc, inst, acc, hit, miss;
    reg [31:0] stall, branch_count, branch_miss_count, memory_count;
    reg [31:0] m_ext_count, mac_count, mul_cycles;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            cyc <= 32'b0; inst <= 32'b0; acc <= 32'b0;
            hit <= 32'b0; miss <= 32'b0;
            stall <= 32'b0; branch_count <= 32'b0; branch_miss_count <= 32'b0;
            memory_count <= 32'b0; m_ext_count <= 32'b0; mac_count <= 32'b0;
            mul_cycles <= 32'b0;
        end else if (clear) begin
            cyc <= 32'b0; inst <= 32'b0; acc <= 32'b0;
            hit <= 32'b0; miss <= 32'b0;
            stall <= 32'b0; branch_count <= 32'b0; branch_miss_count <= 32'b0;
            memory_count <= 32'b0; m_ext_count <= 32'b0; mac_count <= 32'b0;
            mul_cycles <= 32'b0;
        end else if (!hold) begin
            cyc <= cyc + 1'b1;
            if (instruction_retired) inst <= inst + 1'b1;
            if (ic_access)           acc  <= acc  + 1'b1;
            if (ic_hit)              hit  <= hit  + 1'b1;
            if (ic_miss)             miss <= miss + 1'b1;
            if (pipeline_stall)      stall <= stall + 1'b1;
            if (branch_retired)      branch_count <= branch_count + 1'b1;
            if (branch_mispredict)   branch_miss_count <= branch_miss_count + 1'b1;
            if (memory_retired)      memory_count <= memory_count + 1'b1;
            if (m_ext_retired)       m_ext_count <= m_ext_count + 1'b1;
            if (mac_retired)         mac_count <= mac_count + 1'b1;
            if (m_ext_retired || mac_retired) mul_cycles <= mul_cycles + 1'b1;
        end
    end
    assign r_cyc  = cyc;
    assign r_inst = inst;
    assign r_acc  = acc;
    assign r_hit  = hit;
    assign r_miss = miss;
    assign r_stall = stall;
    assign r_branch = branch_count;
    assign r_branch_miss = branch_miss_count;
    assign r_memory = memory_count;
    assign r_m_ext = m_ext_count;
    assign r_mac = mac_count;
    assign r_mul_cycles = mul_cycles;
endmodule
