`include "branch.vh"
`include "itype.vh"
`include "load.vh"
`include "rtype.vh"
`include "store.vh"
`include "opcode.vh"
`include "csr.vh"

// ============================================================================
// InstructionMemory
//   Pure backing store (ROM) for the instruction cache. It is read
//   combinationally:
//     * cache_addr / cache_data  -> used by the ICache to fill on a miss
//     * rom_address / rom_read_data -> used by loads that hit the ROM region
//       (0x0000_xxxx) coming from the data side (Data_Memory).
// ============================================================================
module InstructionMemory #(
    parameter ROM_INIT_FILE = "program.hex"
)(
    input  [31:0] cache_addr,      // requested address from ICache (miss fill)
    output [31:0] cache_data,      // combinational read of ROM
    input  [31:0] rom_address,     // data-load access to ROM region (from Data_Memory)
    output reg [31:0] rom_read_data
);

    // Distributed RAM (LUTRAM) on purpose:
    //  * the non-stalling I-cache reads the ROM combinationally (mem_addr=cpu_addr,
    //    cpu_data=mem_data in the same cycle), which a true Block RAM CANNOT do;
    //  * $readmemh INIT is reliably packed into the bitstream for distributed RAM,
    //    whereas a Block RAM inferred here would both break the combinational read
    //    and frequently drop the $readmemh INIT (-> all-zero BRAM).
    (* ram_style = "distributed" *) reg [31:0] data [0:2047];

    // Xilinx Vivado gotcha (see D-drive Instruction_Memory.v header note):
    // a RAM initialized ONLY via $readmemh is "optimized" by Vivado into a constant
    // ROM and the loaded program is DISCARDED -> the bitstream comes up all zeros
    // (BRAM reads 0x00000000 = NOP forever, no UART output).
    // FIX: explicitly assign EVERY location first (so Vivado keeps the RAM and its
    // INIT in the netlist), then $readmemh overwrites with the real program.
    integer init_i;
    initial begin
        for (init_i = 0; init_i < 2048; init_i = init_i + 1)
            data[init_i] = 32'h00000013;   // ADDI x0,x0,0  (NOP default)
        $readmemh(ROM_INIT_FILE, data);
    end

    // Word-aligned combinational read for cache fills (8KB ROM -> 11 addr bits)
    assign cache_data = data[cache_addr[12:2]];

    wire rom_access = (rom_address[31:16] == 16'h0000);
    always @(*) begin
        if (rom_access)
            rom_read_data = data[rom_address[12:2]];
        else
            rom_read_data = 32'b0;
    end
endmodule
