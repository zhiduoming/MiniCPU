// Synthesizable monophonic note ROM for death, time-out and in-game tracks.
module Buzzer_Track_Player #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer TRACK = 0  // 0=death, 1=time-out, 2=in-game BGM
)(
    input wire clk,
    input wire reset,
    input wire enable,
    output reg music_signal
);
    reg [5:0] note_index;
    reg [31:0] note_cycle_count;
    reg [31:0] tone_count;
    localparam [5:0] NOTE_COUNT = (TRACK == 0) ? 6'd12 :
                                  (TRACK == 1) ? 6'd32 : 6'd39;

    function [15:0] frequency;
        input [5:0] n;
        begin
            if (TRACK == 0) begin
                case(n)
                    0:frequency=220;1:frequency=196;2:frequency=0;3:frequency=196;
                    4:frequency=220;5:frequency=247;6:frequency=262;7:frequency=233;
                    8:frequency=196;9:frequency=147;10:frequency=131;default:frequency=0;
                endcase
            end else if (TRACK == 1) begin
                case(n)
                    0:frequency=0;1:frequency=698;2:frequency=0;3:frequency=698;
                    4:frequency=622;5:frequency=0;6:frequency=622;7:frequency=698;
                    8:frequency=0;9:frequency=622;10:frequency=0;11:frequency=622;
                    12:frequency=659;13:frequency=0;14:frequency=659;15:frequency=622;
                    16:frequency=659;17:frequency=698;18:frequency=622;19:frequency=0;
                    20:frequency=698;21:frequency=0;22:frequency=698;23:frequency=622;
                    24:frequency=0;25:frequency=622;26:frequency=523;27:frequency=0;
                    28:frequency=523;29:frequency=554;30:frequency=523;default:frequency=698;
                endcase
            end else begin
                case(n)
                    0:frequency=440;1:frequency=392;2:frequency=330;3:frequency=294;
                    4:frequency=262;5:frequency=294;6:frequency=392;7:frequency=440;
                    8:frequency=587;9:frequency=784;10:frequency=1047;11:frequency=784;
                    12:frequency=880;13:frequency=1047;14:frequency=880;15:frequency=659;
                    16:frequency=587;17:frequency=523;18:frequency=392;19:frequency=294;
                    20:frequency=262;21:frequency=294;22:frequency=262;23:frequency=294;
                    24:frequency=262;25:frequency=294;26:frequency=330;27:frequency=392;
                    28:frequency=440;29:frequency=523;30:frequency=392;31:frequency=330;
                    32:frequency=392;33:frequency=523;34:frequency=587;35:frequency=659;
                    36:frequency=587;37:frequency=523;default:frequency=392;
                endcase
            end
        end
    endfunction

    function [5:0] ticks;
        input [5:0] n;
        begin
            if (TRACK == 0) begin
                case(n)
                    0:ticks=2;1:ticks=1;2:ticks=2;3:ticks=9;4:ticks=2;5:ticks=2;
                    6:ticks=2;7:ticks=1;8:ticks=1;9:ticks=1;10:ticks=3;default:ticks=28;
                endcase
            end else if (TRACK == 1) begin
                case(n)
                    0:ticks=1;1:ticks=1;2:ticks=2;3:ticks=3;4:ticks=1;5:ticks=1;
                    6:ticks=1;7:ticks=3;8:ticks=7;9:ticks=2;10:ticks=3;11:ticks=5;
                    12:ticks=5;13:ticks=2;14:ticks=1;15:ticks=6;16:ticks=2;17:ticks=2;
                    18:ticks=1;19:ticks=1;20:ticks=4;21:ticks=1;22:ticks=1;23:ticks=7;
                    24:ticks=3;25:ticks=6;26:ticks=4;27:ticks=3;28:ticks=3;29:ticks=2;
                    30:ticks=3;default:ticks=3;
                endcase
            end else begin
                case(n)
                    0:ticks=6;1:ticks=2;2:ticks=1;3:ticks=6;4:ticks=9;5:ticks=1;
                    6:ticks=1;7:ticks=8;8:ticks=2;9:ticks=1;10:ticks=12;11:ticks=2;
                    12:ticks=2;13:ticks=11;14:ticks=1;15:ticks=3;16:ticks=11;17:ticks=1;
                    18:ticks=1;19:ticks=2;20:ticks=11;21:ticks=4;22:ticks=27;23:ticks=4;
                    24:ticks=5;25:ticks=2;26:ticks=13;27:ticks=2;28:ticks=4;29:ticks=3;
                    30:ticks=6;31:ticks=2;32:ticks=7;33:ticks=6;34:ticks=2;35:ticks=4;
                    36:ticks=1;37:ticks=2;default:ticks=4;
                endcase
            end
        end
    endfunction

    wire [15:0] current_frequency = frequency(note_index);
    wire [31:0] tick_cycles = (TRACK == 0) ? (CLK_HZ / 10) : (CLK_HZ / 8);
    wire [31:0] note_cycles = tick_cycles * ticks(note_index);
    wire [31:0] half_period = (current_frequency == 0) ? 0 :
                              CLK_HZ / (current_frequency * 2);

    always @(posedge clk or posedge reset) begin
        if (reset || !enable) begin
            note_index <= 0;
            note_cycle_count <= 0;
            tone_count <= 0;
            music_signal <= 1'b0;
        end else if (note_cycle_count >= note_cycles - 1) begin
            note_cycle_count <= 0;
            tone_count <= 0;
            music_signal <= 1'b0;
            note_index <= (note_index == NOTE_COUNT - 1'b1) ? 0 : note_index + 1'b1;
        end else begin
            note_cycle_count <= note_cycle_count + 1'b1;
            if (current_frequency == 0) begin
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
endmodule
