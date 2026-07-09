`timescale 1ns / 1ps
module tb_intdiv;
    reg clk, reset, start;
    reg [47:0] dividend;
    reg [31:0] divisor;
    wire [47:0] quotient, remainder;
    wire done;
    IntDiv div(.clk(clk), .reset(reset), .start(start),
               .dividend(dividend), .divisor(divisor),
               .quotient(quotient), .remainder(remainder), .done(done));
    always #10 clk = ~clk;
    integer cyc, fd;
    initial begin
        clk = 0; reset = 1; start = 0; cyc = 0;
        dividend = 0; divisor = 1;
        fd = $fopen("intdiv_dbg.txt", "w");
        #30 reset = 0;
        #20;
        $fwrite(fd, "TEST dividend=128 div=4\n");
        dividend = 48'd128; divisor = 32'd4;
        cyc = 0; start = 1;
        while (cyc < 60) begin
            @(posedge clk); cyc = cyc + 1;
            if (cyc == 5) start = 0;
            $fwrite(fd, "cyc=%0d start=%b busy=%b done=%b quo=%0d rem=%0d dv=%0d rb=%0d qb=%0d\n",
                    cyc, start, div.busy, done, div.quo, div.rem, div.dvd, div.rem_next, div.qbit);
        end
        $fwrite(fd, "RESULT quo=%0d rem=%0d (exp 32 / 0)\n", quotient, remainder);
        $fclose(fd);
        $finish;
    end
endmodule
