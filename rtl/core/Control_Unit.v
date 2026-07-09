`include "alu_src_select.vh"
`include "csr.vh"
`include "itype.vh"
`include "opcode.vh"
`include "rf_wd_select.vh"


module ControlUnit (
	input write_done,	// signal indicating if write is done
	input trap_done,	// signal indicating if Pre-Trap Handling is done
	input csr_ready,
	input IF_ID_stall,
	input [6:0] opcode, // opcode from Instruction Decoder
	input [2:0] funct3, // funct3 from Instruction Decoder
	input [4:0] rs1,    // rs1 field (also the zimm for CSRRWI/CSI variants)
    
	output reg jump,
	output reg branch,
	output reg [1:0] alu_src_A_select,
	output reg [2:0] alu_src_B_select,
	output reg csr_write_enable,
	output reg register_file_write,
	output reg [2:0] register_file_write_data_select,
	output reg memory_read,
	output reg memory_write,
	output reg pc_stall
);

    always @(*) begin
		// NOTE: !csr_ready is intentionally NOT part of pc_stall. csr_ready
		// oscillates every cycle while a CSR instruction is in the WB stage
		// (csr_processing toggles), and freezing the PC on those cycles while
		// IF/ID is *not* frozen desynchronises the pipeline (instructions get
		// re-fetched). CSR access is single-cycle (combinational read + 1-cycle
		// register write), so the PC can advance normally; the RAW hazard
		// stall (IF_ID_stall) already freezes PC+front-end when needed.
		pc_stall = (!write_done || !trap_done || IF_ID_stall);
        jump = 1'b0;
        branch = 1'b0;
        alu_src_A_select = `ALU_SRC_A_NONE;
        alu_src_B_select = `ALU_SRC_B_NONE; 
        csr_write_enable = 1'b0;
        register_file_write = 1'b0;
        register_file_write_data_select = `RF_WD_NONE;
        memory_read = 1'b0;
        memory_write = 1'b0;

		case (opcode)
			`OPCODE_LUI: begin // Load upper immediate
				// No jump
				jump = 0;
				
				// No branch
				branch = 0;
				
				// No alu operation
				alu_src_A_select = `ALU_SRC_A_NONE;
				alu_src_B_select = `ALU_SRC_B_NONE; 
				
				// No CSR operation
				csr_write_enable = 0;
				
				// LUI instruction
				register_file_write = 1;
				register_file_write_data_select = `RF_WD_LUI;
				
				// No memory access
				memory_read = 0;
				memory_write = 0;
			end
			`OPCODE_AUIPC: begin
				// No jump
				jump = 0;
				
				// No branch
				branch = 0;
				
				// PC + {imm, 12'b0}
				alu_src_A_select = `ALU_SRC_A_PC;
				alu_src_B_select = `ALU_SRC_B_IMM;
				
				// No CSR operation
				csr_write_enable = 0;
				
				// Fetch added address (ALU)
				register_file_write = 1;
				register_file_write_data_select = `RF_WD_ALU;
				
				// No memory access
				memory_read = 0;
				memory_write = 0;
			end
			`OPCODE_JAL: begin
				// Jump
				jump = 1;
				
				// No branch
				branch = 0;
				
				// PC + {imm, 1'b0}
				alu_src_A_select = `ALU_SRC_A_PC;
				alu_src_B_select = `ALU_SRC_B_IMM;
				
				// No CSR operation
				csr_write_enable = 0;
				
				// PC+4 is saved which means jump
				register_file_write = 1;
				register_file_write_data_select = `RF_WD_JUMP;
				
				// No memory access
				memory_read = 0;
				memory_write = 0;
			end
			`OPCODE_JALR: begin
				// Jump
				jump = 1;
				
				// No branch
				branch = 0;
				
				// R[rs1] + imm
				alu_src_A_select = `ALU_SRC_A_RD1;
				alu_src_B_select = `ALU_SRC_B_IMM;
				
				// No CSR operation
				csr_write_enable = 0;
				
				// PC+4 is saved which means jump
				register_file_write = 1;
				register_file_write_data_select = `RF_WD_JUMP;
				
				// No memory access
				memory_read = 0;
				memory_write = 0;
			end
			`OPCODE_BRANCH: begin
				// No jump
				jump = 0;
				
				// Branch
				branch = 1;
				
				// Compare R[rs1] and R[rs2]
				alu_src_A_select = `ALU_SRC_A_RD1;
				alu_src_B_select = `ALU_SRC_B_RD2;
				
				// No CSR operation
				csr_write_enable = 0;
				
				// No Register File write
				register_file_write = 0;
				register_file_write_data_select = `RF_WD_NONE;
				
				// No memory access
				memory_read = 0;
				memory_write = 0;
			end
			`OPCODE_LOAD: begin
				// No jump
				jump = 0;
				
				// No branch
				branch = 0;
				
				// R[rs1] + imm
				alu_src_A_select = `ALU_SRC_A_RD1;
				alu_src_B_select = `ALU_SRC_B_IMM;
				
				// No CSR operation
				csr_write_enable = 0;
				
				// Load instructions
				register_file_write = 1;
				register_file_write_data_select = `RF_WD_LOAD;
				
				// Read from memory
				memory_read = 1;
				memory_write = 0;
			end
			`OPCODE_STORE: begin
				// No jump
				jump = 0;
				
				// No branch
				branch = 0;
				
				// R[rs1] + imm
				alu_src_A_select = `ALU_SRC_A_RD1;
				alu_src_B_select = `ALU_SRC_B_IMM;
				
				// No CSR operation
				csr_write_enable = 0;
				
				// No Register File write
				register_file_write = 0;
				register_file_write_data_select = `RF_WD_NONE;
				
				// Write to memory
				memory_read = 0;
				memory_write = 1;
			end
			`OPCODE_ITYPE: begin
				// No jump
				jump = 0;
				
				// No branch
				branch = 0;
				
				// Operation on R[rs1] and imm
				alu_src_A_select = `ALU_SRC_A_RD1;

				if (funct3 == `ITYPE_SRXI) begin
					alu_src_B_select = `ALU_SRC_B_SHAMT;
				end
				else begin
					alu_src_B_select = `ALU_SRC_B_IMM;
				end
				
				// No CSR operation
				csr_write_enable = 0;
				
				// Write alu result to Register File
				register_file_write = 1;
				register_file_write_data_select = `RF_WD_ALU;
				
				// No memory access
				memory_read = 0;
				memory_write = 0;
			end
			`OPCODE_RTYPE: begin
				// No jump
				jump = 0;
				
				// No branch
				branch = 0;
				
				// Operation on R[rs1] and R[rs2]
				alu_src_A_select = `ALU_SRC_A_RD1;
				alu_src_B_select = `ALU_SRC_B_RD2;
				
				// No CSR operation
				csr_write_enable = 0;
				
				// Write alu result to Register File
				register_file_write = 1;
				register_file_write_data_select = `RF_WD_ALU;
				
				// No memory access
				memory_read = 0;
				memory_write = 0;
			end
			`OPCODE_FENCE: begin
				// No jump
				jump = 0;
				
				// No branch
				branch = 0;
				
				// No ALU operation
				alu_src_A_select = `ALU_SRC_A_NONE;
				alu_src_B_select = `ALU_SRC_B_NONE;
				
				// No CSR operation
				csr_write_enable = 0;
				
				// No Register File write
				register_file_write = 0;
				register_file_write_data_select = `RF_WD_NONE;
				
				// No memory access
				memory_read = 0;
				memory_write = 0;
			end
			`OPCODE_ENVIRONMENT: begin
				// No jump
				jump = 0;
				
				// No branch
				branch = 0;

				// Only a TRUE write must set csr_write_enable:
				//   - CSRRW / CSRRWI always write (rd <- old, CSR <- src)
				//   - CSRRS / CSRRC / CSRRSI / CSRRCI write only when src != 0
				//     (src == x0 is a pure read and must NOT be treated as a
				//      write, else the Hazard_Unit mistakes it for a
				//      write-in-flight and livelocks the raw hazard stall).
				//   - funct3 == 0 (ECALL/EBREAK) never writes.
				if (funct3 == `CSR_NONE)
					csr_write_enable = 1'b0;
				else if (funct3 == `CSR_CSRRW || funct3 == `CSR_CSRRWI)
					csr_write_enable = 1'b1;
				else // CSRRS / CSRRC / CSRRSI / CSRRCI
					csr_write_enable = (rs1 != 5'b0);

				if (funct3 == 3'b0) begin
					// No alu operation
					alu_src_A_select = `ALU_SRC_A_NONE;
					alu_src_B_select = `ALU_SRC_B_NONE; 

					// No Register File write
					register_file_write = 0;
					register_file_write_data_select = `RF_WD_NONE;
				end
				else begin
					if (funct3 == `CSR_CSRRW || funct3 == `CSR_CSRRWI) begin
						alu_src_B_select = `ALU_SRC_B_NONE;
					end
					else begin
						alu_src_B_select = `ALU_SRC_B_CSR; // src_B is CSR value
					end

					if (funct3 == `CSR_CSRRW || funct3 == `CSR_CSRRS || funct3 == `CSR_CSRRC) begin
						alu_src_A_select = `ALU_SRC_A_RD1; // non-immediate CSR instructions require src_A to be rd1
					end
					else begin
						alu_src_A_select = `ALU_SRC_A_RS1; // immediate CSR instructions require src_A to be rs1
					end

					// Write CSR value to Register File
					register_file_write = 1;
					register_file_write_data_select = `RF_WD_CSR;
				end

				// No memory access
				memory_read = 0;
				memory_write = 0;
			end
			default: begin
            jump = 1'b0;
            branch = 1'b0;
            alu_src_A_select = `ALU_SRC_A_NONE;
            alu_src_B_select = `ALU_SRC_B_NONE; 
            csr_write_enable = 1'b0;
            register_file_write = 1'b0;
            register_file_write_data_select = `RF_WD_NONE;
            memory_read = 1'b0;
            memory_write = 1'b0;
            end
		endcase
    end

endmodule