`include "alu_op.vh"

module ALU (
    input [31:0] src_A,             // source operand A
    input [31:0] src_B,             // source operand B
    input [31:0] src_C,             // accumulator for custom MAC
    input [4:0] alu_op,        		// ALU operation signal (from ALU Control module)
    
    output reg [31:0] alu_result,   // ALU result
    output reg alu_zero             // zero flag
);

    wire signed [63:0] mul_ss_product = $signed({{32{src_A[31]}}, src_A}) *
                                         $signed({{32{src_B[31]}}, src_B});
    wire [63:0] mul_uu_product = {32'b0, src_A} * {32'b0, src_B};
    wire signed [65:0] mul_su_product = $signed({src_A[31], src_A}) *
                                         $signed({1'b0, src_B});
    wire signed [31:0] signed_src_A = src_A;
    wire signed [31:0] signed_src_B = src_B;
    wire div_by_zero = (src_B == 32'b0);
    wire signed_div_overflow = (src_A == 32'h8000_0000) && (src_B == 32'hFFFF_FFFF);
    wire [63:0] mac_product = {32'b0, src_A} * {32'b0, src_B};

    always @(*) begin
        case (alu_op)
            `ALU_OP_ADD: begin
                alu_result = src_A + src_B;
            end

            `ALU_OP_SUB: begin
                alu_result = src_A - src_B;
            end
            
            `ALU_OP_AND: begin
                alu_result = src_A & src_B;
            end
            
            `ALU_OP_OR: begin
                alu_result = src_A | src_B;
            end
            
            `ALU_OP_XOR: begin
                alu_result = src_A ^ src_B;
            end
            
            `ALU_OP_SLT: begin
                alu_result = ($signed(src_A) < $signed(src_B)) ? 32'd1 : 32'd0;
            end

            `ALU_OP_SLTU: begin
                alu_result = (src_A < src_B) ? 32'd1 : 32'd0;
            end
			
			`ALU_OP_SLL: begin
				alu_result = src_A << src_B;
			end
			
			`ALU_OP_SRL: begin
				alu_result = src_A >> src_B;
			end
			
			`ALU_OP_SRA: begin
				alu_result = $signed(src_A) >>> src_B;
			end
			
			`ALU_OP_ABJ: begin
				alu_result = src_B & (~src_A);
			end

            `ALU_OP_MUL: begin
                alu_result = mul_uu_product[31:0];
            end

            `ALU_OP_MULH: begin
                alu_result = mul_ss_product[63:32];
            end

            `ALU_OP_MULHSU: begin
                alu_result = mul_su_product[63:32];
            end

            `ALU_OP_MULHU: begin
                alu_result = mul_uu_product[63:32];
            end

            `ALU_OP_DIV: begin
                if (div_by_zero) begin
                    alu_result = 32'hFFFF_FFFF;
                end else if (signed_div_overflow) begin
                    alu_result = 32'h8000_0000;
                end else begin
                    alu_result = signed_src_A / signed_src_B;
                end
            end

            `ALU_OP_DIVU: begin
                if (div_by_zero) begin
                    alu_result = 32'hFFFF_FFFF;
                end else begin
                    alu_result = src_A / src_B;
                end
            end

            `ALU_OP_REM: begin
                if (div_by_zero) begin
                    alu_result = src_A;
                end else if (signed_div_overflow) begin
                    alu_result = 32'b0;
                end else begin
                    alu_result = signed_src_A % signed_src_B;
                end
            end

            `ALU_OP_REMU: begin
                if (div_by_zero) begin
                    alu_result = src_A;
                end else begin
                    alu_result = src_A % src_B;
                end
            end

            `ALU_OP_MAC: begin
                alu_result = src_C + mac_product[31:0];
            end

            `ALU_OP_BPA: begin
                alu_result = src_A;
            end

			`ALU_OP_NOP: begin
				alu_result = 32'd0;
			end

            default: begin
                alu_result = 32'd0; // Default case: zero result
            end
        endcase

        alu_zero = (alu_result == 32'd0); // Zero flag: set if result is zero
    end

endmodule
