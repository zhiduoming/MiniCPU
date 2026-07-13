// Monophonic buzzer arrangement extracted from the supplied menu-theme MP3.
// One tick is 125 ms; the 24-second phrase loops while a menu is visible.
module Menu_Theme_Player #(
    parameter integer CLK_HZ = 100_000_000
)(
    input  wire clk,
    input  wire reset,
    input  wire enable,
    output reg  music_signal
);
    localparam integer TICK_CYCLES = CLK_HZ / 8;
    localparam integer NOTE_COUNT = 25;

    reg [4:0] note_index;
    reg [31:0] note_cycle_count;
    reg [31:0] tone_count;

    function [15:0] note_frequency;
        input [4:0] index;
        begin
            case (index)
                0: note_frequency=0;   1: note_frequency=466;
                2: note_frequency=370; 3: note_frequency=311;
                4: note_frequency=370; 5: note_frequency=415;
                6: note_frequency=554; 7: note_frequency=622;
                8: note_frequency=554; 9: note_frequency=622;
                10:note_frequency=494; 11:note_frequency=415;
                12:note_frequency=494; 13:note_frequency=554;
                14:note_frequency=622; 15:note_frequency=554;
                16:note_frequency=415; 17:note_frequency=494;
                18:note_frequency=554; 19:note_frequency=466;
                20:note_frequency=415; 21:note_frequency=554;
                22:note_frequency=415; 23:note_frequency=494;
                default: note_frequency=415;
            endcase
        end
    endfunction

    function [4:0] note_ticks;
        input [4:0] index;
        begin
            case (index)
                0:note_ticks=2;  1:note_ticks=2;  2:note_ticks=15;
                3:note_ticks=4;  4:note_ticks=8;  5:note_ticks=6;
                6:note_ticks=4;  7:note_ticks=18; 8:note_ticks=11;
                9:note_ticks=11; 10:note_ticks=1; 11:note_ticks=15;
                12:note_ticks=2; 13:note_ticks=1; 14:note_ticks=17;
                15:note_ticks=3; 16:note_ticks=11;17:note_ticks=4;
                18:note_ticks=10;19:note_ticks=1; 20:note_ticks=14;
                21:note_ticks=5; 22:note_ticks=15;23:note_ticks=5;
                default: note_ticks=7;
            endcase
        end
    endfunction

    wire [15:0] frequency = note_frequency(note_index);
    wire [31:0] half_period = (frequency == 0) ? 0 : CLK_HZ / (frequency * 2);
    wire [31:0] note_cycles = TICK_CYCLES * note_ticks(note_index);

    always @(posedge clk or posedge reset) begin
        if (reset || !enable) begin
            note_index <= 0;
            note_cycle_count <= 0;
            tone_count <= 0;
            music_signal <= 1'b0;
        end else begin
            if (note_cycle_count >= note_cycles - 1) begin
                note_cycle_count <= 0;
                tone_count <= 0;
                music_signal <= 1'b0;
                note_index <= (note_index == NOTE_COUNT - 1) ? 0 : note_index + 1'b1;
            end else begin
                note_cycle_count <= note_cycle_count + 1'b1;
                if (frequency == 0) begin
                    tone_count <= 0;
                    music_signal <= 1'b0;
                end else if (tone_count >= half_period - 1) begin
                    tone_count <= 0;
                    music_signal <= ~music_signal;
                end else begin
                    tone_count <= tone_count + 1'b1;
                end
            end
        end
    end
endmodule
