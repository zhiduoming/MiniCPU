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
//   Division and ASCII conversion are done in software.
// ============================================================================
module PerfMon (
    input          clk,
    input          reset,
    input          instruction_retired,
    input          ic_access,
    input          ic_hit,
    input          ic_miss,
    input          ic_mode,
    output [31:0]  r_cyc,
    output [31:0]  r_inst,
    output [31:0]  r_acc,
    output [31:0]  r_hit,
    output [31:0]  r_miss
);
    reg [31:0] cyc, inst, acc, hit, miss;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            cyc <= 32'b0; inst <= 32'b0; acc <= 32'b0;
            hit <= 32'b0; miss <= 32'b0;
        end else begin
            cyc <= cyc + 1'b1;
            if (instruction_retired) inst <= inst + 1'b1;
            if (ic_access)           acc  <= acc  + 1'b1;
            if (ic_hit)              hit  <= hit  + 1'b1;
            if (ic_miss)             miss <= miss + 1'b1;
        end
    end
    assign r_cyc  = cyc;
    assign r_inst = inst;
    assign r_acc  = acc;
    assign r_hit  = hit;
    assign r_miss = miss;
endmodule
