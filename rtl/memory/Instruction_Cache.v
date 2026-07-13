`timescale 1ns / 1ps
// ============================================================================
// InstructionCache  (non-stalling, with a SYNCHRONOUS / registered fill)
//   - Two organizations selected at runtime by `mode` (SW18 on the board):
//         mode = 0  ->  DIRECT-MAPPED  (32 sets x 1 way  = 32 lines)
//         mode = 1  ->  4-WAY SET-ASSOCIATIVE (8 sets x 4 ways = 32 lines)
//     Both use the SAME 32 physical slots so the total capacity (128 bytes)
//     is identical; only the associativity changes. This isolates the
//     associativity effect when comparing hit rate / CPI between modes.
//   - Replacement policy for the 4-way mode: PSEUDO-LRU (binary tree, 3 bits
//     per set). Direct mode has a single way so no replacement choice exists.
//
//   NON-STALLING + RELIABLE FILL
//   ----------------------------
//   The backing ROM is combinational, so the correct instruction word is
//   available in the SAME cycle on both a hit and a miss. We therefore return
//   `cpu_data` combinationally every cycle (cached line on a HIT, the ROM word
//   on a MISS) and `ic_stall` stays 0 -- the cache is functionally transparent
//   to the rest of the CPU, which is why this organization passed the
//   self-check. It keeps the pipeline behaviour IDENTICAL to the original ROM.
//
//   The previous variant performed the line fill with a *combinational*
//   write-enable: the fill was gated by `!hit_comb`, and `hit_comb` itself is a
//   read of the valid/tag RAMs. On real FPGA hardware that combinational
//   RAM-read -> write-enable path does not meet timing, so the line fill was
//   dropped (every fetch stayed a miss -> "hit rate 0% / wrong counters")
//   even though zero-delay simulation was correct.
//
//   This version keeps the non-stalling interface but makes the fill fully
//   SYNCHRONOUS: a miss latches (slot, tag, data, victim) into registers and
//   the actual array write is committed one clock later under a *registered*
//   `fill_pending` enable -- there is no combinational RAM-read -> write-enable
//   path, so the fill is reliable on hardware while the CPU keeps running off
//   the ROM in the meantime. HIT/MISS pulses are also driven from the
//   registered decision, so the PerfMon counters are glitch-free.
//
//   Exposes pulse statistics (ic_access / ic_hit / ic_miss) for the
//   performance monitor that prints hit rate and CPI over the UART.
// ============================================================================
module InstructionCache (
    input  clk,
    input  reset,
    input  mode,                 // 0 = direct-mapped, 1 = 4-way set-associative
    input  [31:0] cpu_addr,
    input  cpu_stall,            // IF-side stall (IF_ID_stall): 1 while front-end frozen
    output reg [31:0] cpu_data,
    output reg cpu_ready,        // data valid this cycle (hit line or miss ROM word)
    output reg ic_stall,         // always 0: non-stalling (see header)
    output reg ic_access,        // pulse: a fetch was attempted
    output reg ic_hit,           // pulse: hit
    output reg ic_miss,          // pulse: miss
    // backing memory (ROM) - combinational read
    output [31:0] mem_addr,
    input  [31:0] mem_data,
    output mem_req               // memory request while filling
);

    localparam SLOTS = 32;       // 32 physical slots (one word each)

    reg         valid [0:SLOTS-1];
    reg [26:0]  tagf  [0:SLOTS-1];   // stores address[31:5]
    reg [31:0]  data  [0:SLOTS-1];
    reg [2:0]   plru  [0:7];         // 3-bit pseudo-LRU state per 4-way set

    // ---------------- combinational hit detection ----------------
    reg        hit_comb;
    reg [1:0]  hit_way;
    reg [4:0]  h_slot;
    integer    wi;
    always @(*) begin
        hit_comb = 1'b0;
        hit_way  = 2'b0;
        h_slot   = 5'b0;
        if (mode == 1'b0) begin
            h_slot = cpu_addr[6:2];              // 32 sets
            if (valid[h_slot] && (tagf[h_slot] == cpu_addr[31:5]))
                hit_comb = 1'b1;
        end else begin
            for (wi = 0; wi < 4; wi = wi + 1) begin
                h_slot = {cpu_addr[4:2], wi[1:0]};   // 8 sets x 4 ways
                if (valid[h_slot] && (tagf[h_slot] == cpu_addr[31:5])) begin
                    hit_comb = 1'b1;
                    hit_way  = wi[1:0];
                end
            end
        end
    end

    // combinational victim selection (4-way): prefer an invalid way, else PLRU
    reg [1:0] victim;
    function [1:0] plru_victim;
        input [2:0] p;
        reg   [1:0] v;
        begin
            if (p[2] == 1'b0) v = p[0] ? 2'd1 : 2'd0;   // left pair (ways 0/1)
            else              v = p[1] ? 2'd3 : 2'd2;   // right pair (ways 2/3)
            plru_victim = v;
        end
    endfunction
    always @(*) begin
        victim = 2'b00;
        if (mode == 1'b1) begin
            if      (!valid[{cpu_addr[4:2], 2'b00}]) victim = 2'b00;
            else if (!valid[{cpu_addr[4:2], 2'b01}]) victim = 2'b01;
            else if (!valid[{cpu_addr[4:2], 2'b10}]) victim = 2'b10;
            else if (!valid[{cpu_addr[4:2], 2'b11}]) victim = 2'b11;
            else victim = plru_victim(plru[cpu_addr[4:2]]);
        end
    end

    // ---------------- sequential fill registers ----------------
    reg        fill_pending;
    reg [4:0]  fill_slot_r;
    reg [26:0] fill_tag_r;
    reg [31:0] fill_data_r;
    reg        fill_4way_r;
    reg [1:0]  fill_way_r;
    integer    i;

    // ---------------- combinational outputs ----------------
    // Non-stalling: the backing ROM is combinational, so `mem_data` is always
    // the correct word for the current address. We return the cached line on a
    // HIT and the ROM word on a MISS; `ic_stall` stays 0 so the pipeline is
    // never frozen for an I-cache access (the cache is transparent).
    assign mem_addr  = cpu_addr;
    assign mem_req   = fill_pending;         // backing ROM read is combinational anyway

    always @(*) begin
        cpu_ready = 1'b1;
        if (hit_comb) begin
            if (mode == 1'b0)
                cpu_data = data[cpu_addr[6:2]];
            else
                cpu_data = data[{cpu_addr[4:2], hit_way}];
        end else begin
            cpu_data = mem_data;             // correct ROM word for the miss address
        end
    end

    // ---------------- sequential control (synchronous fill) ----------------
    // fill_pending: a miss was detected last cycle; commit the line this cycle
    // using REGISTERED slot/tag/data. This removes the combinational
    // RAM-read -> write-enable path that failed timing on the FPGA.
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            ic_stall     <= 1'b0;
            ic_access   <= 1'b0;
            ic_hit      <= 1'b0;
            ic_miss     <= 1'b0;
            fill_pending <= 1'b0;
            for (i = 0; i < SLOTS; i = i + 1) begin
                valid[i] <= 1'b0;
                tagf[i]  <= 27'b0;
                data[i]  <= 32'b0;
            end
            for (i = 0; i < 8; i = i + 1)
                plru[i] <= 3'b0;
        end else begin
            // default (pulse) de-assertions -- pulses are single-cycle
            ic_access <= 1'b0;
            ic_hit    <= 1'b0;
            ic_miss   <= 1'b0;
            ic_stall  <= 1'b0;

            // ---- commit a previously-requested fill (registered enable) ----
            if (fill_pending) begin
                valid[fill_slot_r] <= 1'b1;
                tagf[fill_slot_r]  <= fill_tag_r;
                data[fill_slot_r]  <= fill_data_r;
                if (fill_4way_r) begin
                    // victim becomes MRU
                    if (fill_way_r[1] == 1'b0) begin
                        plru[fill_slot_r[4:2]][2] <= 1'b0;
                        plru[fill_slot_r[4:2]][0] <= ~fill_way_r[0];
                    end else begin
                        plru[fill_slot_r[4:2]][2] <= 1'b1;
                        plru[fill_slot_r[4:2]][1] <= ~fill_way_r[0];
                    end
                end
                fill_pending <= 1'b0;
            end

            // ---- detect this cycle's access (only when front-end progresses) ----
            if (!cpu_stall) begin
                if (hit_comb) begin
                    // HIT
                    ic_access <= 1'b1;
                    ic_hit    <= 1'b1;
                    if (mode == 1'b1) begin
                        // update PLRU on a hit
                        if (hit_way[1] == 1'b0) begin
                            plru[cpu_addr[4:2]][2] <= 1'b0;
                            plru[cpu_addr[4:2]][0] <= ~hit_way[0];
                        end else begin
                            plru[cpu_addr[4:2]][2] <= 1'b1;
                            plru[cpu_addr[4:2]][1] <= ~hit_way[0];
                        end
                    end
                end else begin
                    // MISS: latch the fill parameters; commit next cycle.
                    fill_pending  <= 1'b1;
                    fill_4way_r   <= mode;
                    fill_way_r    <= victim;
                    fill_slot_r   <= (mode == 1'b0) ? cpu_addr[6:2]
                                                  : {cpu_addr[4:2], victim};
                    fill_tag_r    <= cpu_addr[31:5];
                    fill_data_r   <= mem_data;     // ROM word for the miss address
                    ic_access     <= 1'b1;
                    ic_miss       <= 1'b1;
                end
            end
        end
    end

endmodule
