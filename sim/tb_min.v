module tb_min;
    reg clk;
    initial clk = 0;
    always #10 clk = ~clk;
    initial begin
        integer fd;
        #100;
        fd = $fopen("min_result.txt", "w");
        $fwrite(fd, "MIN_OK clk=%b\n", clk);
        $fclose(fd);
        $display("MIN_DISPLAY reached");
        $finish;
    end
endmodule
