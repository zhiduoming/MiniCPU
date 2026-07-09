`include "branch.vh"
`include "itype.vh"
`include "load.vh"
`include "rtype.vh"
`include "store.vh"
`include "opcode.vh"
`include "csr.vh"

module InstructionMemory #(
    parameter ROM_INIT_FILE = "program.hex"
)(
    input [31:0] pc,
    output reg [31:0] instruction,

    input [31:0] rom_address,
    output reg [31:0] rom_read_data
);

    
        // æ³¨æ?ï¼šä?è¦?å…ˆç”¨ for å¾ªçŽ¯æŠŠæ•´?—å?å§‹åŒ–ä¸ºå?Œä¸€å¸¸é?å†?è¦†ç›–ï¼?
        // ?¦åˆ™ Vivado ä¼šæŠŠå®ƒç»¼?ˆæ?"å…?NOP å¸¸é? ROM"å¹¶ä¸¢å¼ƒä¸‹?¢çš„ç¨‹å?ã€?
        // è¿™é‡Œ?ªå?šéƒ¨åˆ†æ˜¾å¼?èµ‹å€¼ï¼ŒVivado ä¼šç»¼?ˆæ?å¸?INIT çš?RAMã€?

        // ============================================================
        // Strict JAL self-check program
        // JAL at a NON-ZERO PC with a NON-ZERO aligned offset, followed
        // by a side-effect instruction that MUST be flushed/skipped.
        // Verifies: (a) jump target = PC+offset is computed correctly,
        //           (b) the instruction after JAL is correctly flushed.
        // ============================================================
        // PC=0x00  ADDI x1, x0, 0x0A      -> x1 = 0x0A
        // PC=0x04  JAL  x0, +8            -> jumps to 0x0C
        // PC=0x08  ADDI x2, x0, 0x123     -> MUST be flushed (x2 stays 0)
        // PC=0x0C  ADDI x3, x0, 0x55      -> jump target (x3 = 0x55)
        // PC=0x10  JAL  x0, 0             -> infinite loop
        // PC=0x14/0x18 NOP (loop body, must be explicit or sim reads X / synth reads 0)
        reg [31:0] data [0:2047];
        initial begin
            $readmemh(ROM_INIT_FILE, data);
        end
   

    always @(*) begin
        instruction = data[pc[31:2]];
    end

    wire rom_access = (rom_address[31:16] == 16'h0000);
    always @(*) begin
        if (rom_access) begin
            rom_read_data = data[rom_address[15:2]];
        end else begin
            rom_read_data = 32'b0;
        end
    end
endmodule
