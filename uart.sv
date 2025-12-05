`timescale 1ns / 1ps

module uart (
    input  logic       clk,
    input  logic       rst,
    input  logic       rx,
    input  logic       tx_start,
    input  logic [7:0] tx_data,
    output logic       rx_done,
    output logic [7:0] rx_data,
    output logic       tx,
    output logic       tx_busy
);

    logic w_b_tick;

    uart_rx U_UART_RX (
        .clk    (clk),
        .rst    (rst),
        .rx     (rx),
        .b_tick (w_b_tick),
        .rx_data(rx_data),
        .rx_done(rx_done)
    );
    uart_tx U_UART_TX (
        .clk(clk),
        .rst(rst),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .b_tick(w_b_tick),
        .tx_busy(tx_busy),
        .tx(tx)
    );
    baud_tick_gen BAUD_TICK_GEN (
        .clk(clk),
        .rst(rst),
        .b_tick(w_b_tick)
    );
endmodule


module uart_rx #(
    localparam [1:0] IDLE = 2'b00,
    localparam [1:0] RX_START = 2'b01,
    localparam [1:0] RX_DATA = 2'b10,
    localparam [1:0] RX_STOP = 2'b11
) (
    input logic clk,
    input logic rst,
    input logic b_tick,
    input logic rx,
    output logic rx_done,
    output logic [7:0] rx_data
);

    logic [1:0] state_reg, state_next;
    logic [3:0] b_tick_cnt_reg, b_tick_cnt_next;
    logic [2:0] bit_cnt_reg, bit_cnt_next;
    logic [7:0] rx_data_reg, rx_data_next;
    logic rx_done_reg, rx_done_next;

    assign rx_data = rx_data_reg;
    assign rx_done = rx_done_reg;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            state_reg <= IDLE;
            b_tick_cnt_reg <= 0;
            bit_cnt_reg <= 0;
            rx_data_reg <= 0;
            rx_done_reg <= 1'b0;
        end else begin
            state_reg <= state_next;
            b_tick_cnt_reg <= b_tick_cnt_next;
            bit_cnt_reg <= bit_cnt_next;
            rx_data_reg <= rx_data_next;
            rx_done_reg <= rx_done_next;
        end
    end

    always_comb begin
        state_next = state_reg;
        b_tick_cnt_next = b_tick_cnt_reg;
        bit_cnt_next = bit_cnt_reg;
        rx_data_next = rx_data_reg;
        rx_done_next = rx_done_reg;
        case (state_reg)
            IDLE: begin
                rx_done_next = 1'b0;
                if (!rx) begin
                    bit_cnt_next = 0;
                    b_tick_cnt_next = 0;
                    state_next = RX_START;
                end
            end
            RX_START: begin
                if (b_tick) begin
                    if (b_tick_cnt_reg == 8) begin
                        b_tick_cnt_next = 0;
                        state_next = RX_DATA;
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end
            RX_DATA: begin
                if (b_tick) begin
                    if (b_tick_cnt_reg == 15) begin
                        b_tick_cnt_next = 0;
                        rx_data_next = {rx, rx_data_reg[7:1]};
                        if (bit_cnt_reg == 7) begin
                            state_next = RX_STOP;
                        end else begin
                            bit_cnt_next = bit_cnt_reg + 1;
                        end
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end
            RX_STOP: begin
                if (b_tick) begin
                    if (b_tick_cnt_reg == 15) begin
                        b_tick_cnt_next = 0;
                        rx_done_next = 1'b1;
                        state_next = IDLE;
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end
        endcase
    end
endmodule

module uart_tx #(
    localparam [1:0] IDLE = 2'b00,
    localparam [1:0] TX_START = 2'b01,
    localparam [1:0] TX_DATA = 2'b10,
    localparam [1:0] TX_STOP = 2'b11
) (
    input logic clk,
    input logic rst,
    input logic b_tick,
    input logic tx_start,
    input logic [7:0] tx_data,
    output logic tx,
    output logic tx_busy
);

    logic [1:0] state_reg, state_next;
    logic tx_busy_reg, tx_busy_next;
    logic tx_reg, tx_next;
    logic [7:0] data_buf_reg, data_buf_next;
    logic [3:0] b_tick_cnt_reg, b_tick_cnt_next;
    logic [2:0] bit_cnt_reg, bit_cnt_next;

    assign tx_busy = tx_busy_reg;
    assign tx = tx_reg;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            state_reg <= IDLE;
            b_tick_cnt_reg <= 4'b0000;
            bit_cnt_reg <= 3'b000;
            tx_busy_reg <= 1'b0;
            tx_reg <= 1'b1;
            data_buf_reg <= 8'h00;
        end else begin
            state_reg <= state_next;
            tx_busy_reg <= tx_busy_next;
            tx_reg <= tx_next;
            data_buf_reg <= data_buf_next;
            b_tick_cnt_reg <= b_tick_cnt_next;
            bit_cnt_reg <= bit_cnt_next;
        end
    end

    always_comb begin
        state_next = state_reg;
        tx_busy_next = tx_busy_reg;
        tx_next = tx_reg;
        data_buf_next = data_buf_reg;
        b_tick_cnt_next = b_tick_cnt_reg;
        bit_cnt_next = bit_cnt_reg;
        case (state_reg)
            IDLE: begin
                tx_next = 1'b1;
                tx_busy_next = 1'b0;
                if (tx_start) begin
                    b_tick_cnt_next = 0;
                    data_buf_next = tx_data;
                    state_next = TX_START;
                end
            end
            TX_START: begin
                tx_next = 1'b0;
                tx_busy_next = 1'b1;
                if (b_tick) begin
                    if (b_tick_cnt_reg == 15) begin
                        b_tick_cnt_next = 0;
                        bit_cnt_next = 0;
                        state_next = TX_DATA;
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end
            TX_DATA: begin
                tx_next = data_buf_reg[0];
                if (b_tick) begin
                    if (b_tick_cnt_reg == 15) begin
                        if (bit_cnt_reg == 7) begin
                            b_tick_cnt_next = 0;
                            state_next = TX_STOP;
                        end else begin
                            b_tick_cnt_next = 0;
                            bit_cnt_next = bit_cnt_reg + 1;
                            data_buf_next = data_buf_reg >> 1;
                        end
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end
            TX_STOP: begin
                tx_next = 1'b1;
                if (b_tick) begin
                    if (b_tick_cnt_reg == 15) begin
                        tx_busy_next = 1'b0;
                        state_next   = IDLE;
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end
        endcase
    end
endmodule

module baud_tick_gen #(
    parameter BAUD = 9600,
    parameter BAUD_TICK_COUNT = 100_000_000 / BAUD / 16
) (
    input  logic clk,
    input  logic rst,
    output logic b_tick
);

    logic [$clog2(BAUD_TICK_COUNT)-1 : 0] counter_reg;
    logic b_tick_reg;

    assign b_tick = b_tick_reg;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            counter_reg <= 0;
            b_tick_reg  <= 1'b0;
        end else begin
            if (counter_reg == BAUD_TICK_COUNT) begin
                counter_reg <= 0;
                b_tick_reg  <= 1'b1;
            end else begin
                counter_reg <= counter_reg + 1;
                b_tick_reg  <= 1'b0;
            end
        end
    end
endmodule
