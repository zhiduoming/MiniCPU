module MMIO_Interface (
    input clk,
    input reset,
    input [31:0] data_memory_write_data,
    input [31:0] data_memory_address,
    input data_memory_write_enable,
    input UART_busy,

    output reg [7:0] mmio_uart_tx_data,
    output [31:0] mmio_uart_status,
    output reg mmio_uart_tx_start,
    output mmio_uart_status_hit,
    output reg perf_dump_req,          // 1-cycle pulse: request a PerfMon dump

    // ---- PerfMon counter read ports ----
    input  [31:0] perf_cyc,
    input  [31:0] perf_inst,
    input  [31:0] perf_acc,
    input  [31:0] perf_hit,
    input  [31:0] perf_miss,
    input         ic_mode,
    output [31:0] mmio_perf_read_data,
    output        perf_read_hit
);

    localparam UART_TX_ADDR = 32'h10010000;     // Write-Only
    localparam UART_STATUS_ADDR = 32'h10010004; // Read-Only
    localparam PERF_DUMP_ADDR = 32'h10010008;   // Write-Only: trigger perf report

    localparam PERF_CYC_ADDR  = 32'h10010020;
    localparam PERF_INST_ADDR = 32'h10010024;
    localparam PERF_ACC_ADDR  = 32'h10010028;
    localparam PERF_HIT_ADDR  = 32'h1001002C;
    localparam PERF_MISS_ADDR = 32'h10010030;
    localparam PERF_MODE_ADDR = 32'h10010034;

    wire uart_tx_hit = (data_memory_address == UART_TX_ADDR);
    wire uart_stat_hit = (data_memory_address == UART_STATUS_ADDR);
    wire perf_dump_hit = (data_memory_address == PERF_DUMP_ADDR);
    assign mmio_uart_status_hit = uart_tx_hit || uart_stat_hit;
    assign mmio_uart_status = uart_stat_hit ? {31'h0, UART_busy} : 32'h0;

    wire perf_cyc_hit  = (data_memory_address == PERF_CYC_ADDR);
    wire perf_inst_hit = (data_memory_address == PERF_INST_ADDR);
    wire perf_acc_hit  = (data_memory_address == PERF_ACC_ADDR);
    wire perf_hit_hit  = (data_memory_address == PERF_HIT_ADDR);
    wire perf_miss_hit = (data_memory_address == PERF_MISS_ADDR);
    wire perf_mode_hit = (data_memory_address == PERF_MODE_ADDR);
    assign perf_read_hit = perf_cyc_hit | perf_inst_hit | perf_acc_hit |
                           perf_hit_hit | perf_miss_hit | perf_mode_hit;

    assign mmio_perf_read_data =
        perf_cyc_hit  ? perf_cyc :
        perf_inst_hit ? perf_inst :
        perf_acc_hit  ? perf_acc :
        perf_hit_hit  ? perf_hit :
        perf_miss_hit ? perf_miss :
        perf_mode_hit ? {31'b0, ic_mode} :
        32'h0;

    // ---- Rising-edge detection of a UART-TX store ----
    reg        prev_tx_hit;
    wire       tx_we_rise = (data_memory_write_enable && uart_tx_hit) && !prev_tx_hit;
    reg        tx_pending;
    reg [7:0]  tx_pending_data;

    // ---- Rising-edge detection of a PERF-DUMP store ----
    reg        prev_perf_hit;
    wire       perf_we_rise = (data_memory_write_enable && perf_dump_hit) && !prev_perf_hit;

    always @ (posedge clk or posedge reset) begin
        if (reset) begin
            mmio_uart_tx_data <= 8'h0;
            mmio_uart_tx_start <= 1'b0;
            perf_dump_req <= 1'b0;
            prev_tx_hit <= 1'b0;
            prev_perf_hit <= 1'b0;
            tx_pending <= 1'b0;
            tx_pending_data <= 8'h0;
        end else begin
            mmio_uart_tx_start <= 1'b0;
            perf_dump_req <= 1'b0;

            prev_tx_hit   <= (data_memory_write_enable && uart_tx_hit);
            prev_perf_hit <= (data_memory_write_enable && perf_dump_hit);

            // latch a new transmit request on the rising edge of the store
            if (tx_we_rise) begin
                tx_pending      <= 1'b1;
                tx_pending_data <= data_memory_write_data[7:0];
            end
            // service the pending request once the UART is free
            if (tx_pending && !UART_busy) begin
                mmio_uart_tx_data  <= tx_pending_data;
                mmio_uart_tx_start <= 1'b1;
                tx_pending         <= 1'b0;
            end

            // A write to the PERF_DUMP register requests a performance report.
            if (perf_we_rise)
                perf_dump_req <= 1'b1;
        end
    end


endmodule
