// Board-level audio mixer: BGM plus start, hit, and game-over sound effects.
module Game_Audio (
    input         clk,
    input         reset,
    input         game_active,
    input  [31:0] game_status,
    input  [31:0] game_flags,
    input         bgm_signal,
    output        buzzer_output
);
    localparam SFX_NONE  = 2'd0;
    localparam SFX_START = 2'd1;
    localparam SFX_HIT   = 2'd2;
    localparam SFX_END   = 2'd3;
    localparam SFX_HEAL  = 3'd4;

    reg active_prev;
    reg medicine_pickup_prev;
    reg [7:0] p1_hp_prev, p2_hp_prev;
    reg [2:0] sfx_kind;
    reg [25:0] sfx_count;
    reg [17:0] tone_count;
    reg tone;

    wire [7:0] p1_hp = game_status[7:0];
    wire [7:0] p2_hp = game_status[15:8];
    wire game_over = (p1_hp == 8'd0) || (p2_hp == 8'd0);
    wire start_event = game_active && !active_prev;
    wire hit_event = ((p1_hp < p1_hp_prev) || (p2_hp < p2_hp_prev)) && !game_over;
    wire medicine_pickup_event = game_flags[25] && !medicine_pickup_prev;
    wire [17:0] tone_limit = (sfx_kind == SFX_HIT) ? 18'd100000 :
                             (sfx_kind == SFX_HEAL) ? 18'd80000 :
                             (sfx_kind == SFX_END) ? 18'd150000 : 18'd60000;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            active_prev <= 1'b0;
            medicine_pickup_prev <= 1'b0;
            p1_hp_prev <= 8'd100;
            p2_hp_prev <= 8'd100;
            sfx_kind <= SFX_NONE;
            sfx_count <= 26'd0;
            tone_count <= 18'd0;
            tone <= 1'b0;
        end else begin
            active_prev <= game_active;
            medicine_pickup_prev <= game_flags[25];
            p1_hp_prev <= p1_hp;
            p2_hp_prev <= p2_hp;
            if (hit_event) begin
                sfx_kind <= SFX_HIT;
                sfx_count <= 26'd8_000_000;
            end else if (medicine_pickup_event) begin
                sfx_kind <= SFX_HEAL;
                sfx_count <= 26'd5_000_000;
            end else if (start_event && sfx_kind == SFX_NONE) begin
                sfx_kind <= SFX_START;
                sfx_count <= 26'd15_000_000;
            end else if (sfx_count != 0) begin
                sfx_count <= sfx_count - 1'b1;
                if (sfx_count == 1)
                    sfx_kind <= SFX_NONE;
            end

            if (sfx_kind == SFX_NONE) begin
                tone_count <= 18'd0;
                tone <= 1'b0;
            end else if (tone_count >= tone_limit) begin
                tone_count <= 18'd0;
                tone <= ~tone;
            end else begin
                tone_count <= tone_count + 1'b1;
            end
        end
    end

    assign buzzer_output = (sfx_kind == SFX_NONE) ? bgm_signal : tone;
endmodule
