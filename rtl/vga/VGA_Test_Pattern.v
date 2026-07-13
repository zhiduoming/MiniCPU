// 800x600 VGA timing generator and first-board-bring-up test pattern.
// A 50 MHz pixel clock is supplied by the SoC top module.
module VGA_Test_Pattern (
    input             pixel_clk,
    input             reset,
    output            vga_hsync,
    output            vga_vsync,
    output reg [3:0]  vga_r,
    output reg [3:0]  vga_g,
    output reg [3:0]  vga_b,
    output     [10:0] pixel_x,
    output     [9:0]  pixel_y,
    output            active_video
);

    localparam integer H_ACTIVE = 800;
    localparam integer H_FRONT  = 56;
    localparam integer H_SYNC   = 120;
    localparam integer H_BACK   = 64;
    localparam integer H_TOTAL  = H_ACTIVE + H_FRONT + H_SYNC + H_BACK;

    localparam integer V_ACTIVE = 600;
    localparam integer V_FRONT  = 37;
    localparam integer V_SYNC   = 6;
    localparam integer V_BACK   = 23;
    localparam integer V_TOTAL  = V_ACTIVE + V_FRONT + V_SYNC + V_BACK;

    reg [10:0] h_count;
    reg [9:0]  v_count;

    always @(posedge pixel_clk or posedge reset) begin
        if (reset) begin
            h_count <= 11'd0;
            v_count <= 10'd0;
        end else if (h_count == H_TOTAL - 1) begin
            h_count <= 11'd0;
            if (v_count == V_TOTAL - 1)
                v_count <= 10'd0;
            else
                v_count <= v_count + 1'b1;
        end else begin
            h_count <= h_count + 1'b1;
        end
    end

    // VGA sync pulses are active low.
    assign vga_hsync = ~((h_count >= H_ACTIVE + H_FRONT) &&
                         (h_count <  H_ACTIVE + H_FRONT + H_SYNC));
    assign vga_vsync = ~((v_count >= V_ACTIVE + V_FRONT) &&
                         (v_count <  V_ACTIVE + V_FRONT + V_SYNC));
    assign active_video = (h_count < H_ACTIVE) && (v_count < V_ACTIVE);
    assign pixel_x = active_video ? h_count : 11'd0;
    assign pixel_y = active_video ? v_count : 10'd0;

    always @(*) begin
        vga_r = 4'h0;
        vga_g = 4'h0;
        vga_b = 4'h0;

        if (active_video) begin
            // Eight vertical bars verify all 12 RGB output bits on the monitor.
            case (h_count / 100)
                0: begin vga_r = 4'hF; vga_g = 4'hF; vga_b = 4'hF; end // white
                1: begin vga_r = 4'hF; vga_g = 4'hF; vga_b = 4'h0; end // yellow
                2: begin vga_r = 4'h0; vga_g = 4'hF; vga_b = 4'hF; end // cyan
                3: begin vga_r = 4'h0; vga_g = 4'hF; vga_b = 4'h0; end // green
                4: begin vga_r = 4'hF; vga_g = 4'h0; vga_b = 4'hF; end // magenta
                5: begin vga_r = 4'hF; vga_g = 4'h0; vga_b = 4'h0; end // red
                6: begin vga_r = 4'h0; vga_g = 4'h0; vga_b = 4'hF; end // blue
                default: begin vga_r = 4'h0; vga_g = 4'h0; vga_b = 4'h0; end
            endcase
        end
    end

endmodule
