`timescale 1ns / 1ps
// ============================================================================
// IntDiv  --  sequential restoring unsigned divider
//   Computes  quotient  = dividend / divisor
//            remainder = dividend % divisor
//   Exactly 48 divide steps (one per clock). `start` latches the operands and
//   begins; `done` pulses for one cycle when the result is ready. A zero
//   divisor is treated as 1 (quotient = dividend) to avoid a hang.
//
//   The next-state values are computed combinationally from the current
//   registers (rem/dvd/quo), then registered on the clock edge. This keeps the
//   shift / compare / subtract / quotient-bit decisions perfectly aligned and
//   avoids the off-by-one that a naive mix of blocking and non-blocking
//   assignments would introduce.
// ============================================================================
module IntDiv (
    input          clk,
    input          reset,
    input          start,
    input  [47:0]  dividend,
    input  [31:0]  divisor,
    output reg [47:0] quotient,
    output reg [47:0] remainder,
    output reg     done
);

    reg         busy;
    reg  [5:0]  cnt;
    reg  [47:0] rem;
    reg  [47:0] quo;
    reg  [47:0] dvd;
    reg  [31:0] dvs;

    // ---- combinational next-state ----
    reg [47:0] rem_next;
    reg [47:0] quo_next;
    reg [47:0] dvd_next;
    reg        qbit;
    always @(*) begin
        // bring in the next dividend bit (MSB first)
        rem_next = {rem[46:0], dvd[47]};
        if (rem_next >= {16'b0, dvs}) begin
            rem_next = rem_next - {16'b0, dvs};
            qbit    = 1'b1;
        end else begin
            qbit    = 1'b0;
        end
        // build quotient LSB-first so the qbit for dividend bit (47-cnt) lands
        // at quotient[47-cnt] after all 48 steps
        quo_next = {quo[46:0], qbit};
        dvd_next = {dvd[46:0], 1'b0};
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            busy     <= 1'b0;
            done     <= 1'b0;
            quotient <= 48'b0;
            remainder<= 48'b0;
            rem      <= 48'b0;
            quo      <= 48'b0;
            dvd      <= 48'b0;
            dvs      <= 32'b0;
        end else begin
            done <= 1'b0;
            if (start && !busy) begin
                busy <= 1'b1;
                cnt  <= 6'd0;
                rem  <= 48'b0;
                quo  <= 48'b0;
                dvd  <= dividend;
                dvs  <= (divisor == 32'b0) ? 32'b1 : divisor;
            end else if (busy) begin
                rem  <= rem_next;
                quo  <= quo_next;
                dvd  <= dvd_next;
                cnt  <= cnt + 1'b1;
                if (cnt == 6'd47) begin
                    busy     <= 1'b0;
                    done     <= 1'b1;
                    quotient <= quo_next;
                    remainder<= rem_next;
                end
            end
        end
    end
endmodule
