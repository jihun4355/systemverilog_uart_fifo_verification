`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/09/02 15:06:46
// Design Name: 
// Module Name: uart_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module uart_top (
    input  clk,
    input  rst,
    input  rx,
    output tx_busy,
    output tx,
    output btn_r_trig,
    output btn_l_trig,
    output btn_u_trig

);

    wire w_baud_tick;
    wire [7:0] w_uart_data;
    wire w_rx_done;

    baud_tick u_baud_tick (
        .clk(clk),
        .rst(rst),
        .baud_tick(w_baud_tick)
    );

    uart_tx u_uart_tx (
        .clk(clk),
        .rst(rst),
        .start_trig(w_rx_done),
        .baud_tick(w_baud_tick),
        .tx_data(w_uart_data),
        .tx(tx),
        .tx_busy(tx_busy)
    );

    uart_rx u_uart_rx(
    .clk(clk),
    .rst(rst),
    .rx(rx),
    .baud_tick(w_baud_tick),
    .rx_data(w_uart_data),
    .rx_done(w_rx_done)
);
    cmd_cu u_cmd_cu (
        .clk(clk),
        .rst(rst),
        .rx_done(w_rx_done),
        .rx_data(w_uart_data),
        .Btn_R_trig(btn_r_trig),
        .Btn_L_trig(btn_l_trig),
        .Btn_U_trig(btn_u_trig)
    );


endmodule




module baud_tick (
    input  clk,
    input  rst,
    output baud_tick
);

    parameter BAUD_TICK_GEN = 9600 * 16;
    localparam BAUD_COUNT = 100_000_000 / BAUD_TICK_GEN;
    reg [$clog2(BAUD_COUNT)-1:0] count_reg, count_next;
    reg baud_tick_reg, baud_tick_next;

    assign baud_tick = baud_tick_reg;

    always @(posedge clk, posedge rst) begin
        if (rst) begin
            count_reg <= 0;
            baud_tick_reg <= 0;
        end else begin
            count_reg <= count_next;
            baud_tick_reg <= baud_tick_next;
        end
    end

    always @(*) begin
        count_next = count_reg;
        baud_tick_next = baud_tick_reg;
        if (count_reg == BAUD_COUNT - 1) begin
            count_next = 0;
            baud_tick_next = 1;
        end else begin
            count_next = count_reg + 1;
            baud_tick_next = 0;
        end
    end


endmodule






module uart_tx (
    input clk,
    input rst,
    input start_trig,
    input baud_tick,
    input [7:0] tx_data,
    output tx,
    output tx_busy
);

    parameter [1:0] IDLE = 2'b00, START = 2'b01, DATA = 2'b10, STOP = 2'b11;

    reg [1:0] state, next;
    reg tx_busy_reg, tx_busy_next;
    reg tx_next, tx_reg;
    reg [3:0] baud_tick_cnt_reg, baud_tick_cnt_next;
    reg [2:0] data_cnt_reg, data_cnt_next;
    reg [7:0] data_buf, data_buf_next;

    assign tx = tx_reg;
    assign tx_busy = tx_busy_reg;

    always @(posedge clk, posedge rst) begin
        if (rst) begin
            state             <= IDLE;
            baud_tick_cnt_reg <= 4'b0000;
            data_cnt_reg      <= 3'b000;
            tx_reg            <= 1;
            tx_busy_reg       <= 1'b0;
            data_buf          <= 8'h00;
        end else begin
            state             <= next;
            baud_tick_cnt_reg <= baud_tick_cnt_next;
            data_cnt_reg      <= data_cnt_next;
            tx_reg            <= tx_next;
            tx_busy_reg       <= tx_busy_next;
            data_buf          <= data_buf_next;
        end
    end

    always @(*) begin
        next               = state;
        baud_tick_cnt_next = baud_tick_cnt_reg;
        data_cnt_next      = data_cnt_reg;
        tx_next            = tx_reg;
        tx_busy_next       = tx_busy_reg;
        data_buf_next      = data_buf;
        case (state)
            IDLE: begin
                tx_next = 1'b1;
                tx_busy_next = 1'b0;
                baud_tick_cnt_next=1'b0;
                if (start_trig) begin
                    data_buf_next = tx_data;
                    next = START;
                end
            end
            START: begin
                tx_next = 1'b0;
                tx_busy_next = 1'b1;
                if (baud_tick) begin
                    if (baud_tick_cnt_reg == 15) begin
                        baud_tick_cnt_next = 0;
                        data_cnt_next = 0;
                        next = DATA;
                    end else begin
                        baud_tick_cnt_next = baud_tick_cnt_reg + 1;
                    end
                end
            end
            DATA: begin
                tx_next = data_buf[0];
                if (baud_tick) begin
                    if (baud_tick_cnt_reg == 15) begin
                        if (data_cnt_reg == 7) begin
                            baud_tick_cnt_next = 0;
                            next = STOP;
                        end else begin
                            baud_tick_cnt_next = 0;
                            data_cnt_next = data_cnt_reg + 1;
                            data_buf_next = data_buf >> 1;
                        end
                    end else begin
                        baud_tick_cnt_next = baud_tick_cnt_reg + 1;
                    end
                end
            end
            STOP: begin
                tx_next = 1'b1;
                if (baud_tick) begin
                    if (baud_tick_cnt_reg == 15) begin
                        next = IDLE;
                    end else begin
                        baud_tick_cnt_next = baud_tick_cnt_reg + 1;
                    end
                end
            end
        endcase
    end

endmodule






module uart_rx (
    input        clk,
    input        rst,
    input        rx,
    input        baud_tick,
    output [7:0] rx_data,
    output       rx_done
);

    localparam [1:0] IDLE = 2'h0, START = 2'h1, DATA = 2'h2, STOP = 2'h3;
    reg [1:0] cur_state, next_state;
    reg [2:0] bit_cnt, bit_cnt_next;
    reg [4:0] baud_tick_cnt, baud_tick_cnt_next;
    reg rx_done_reg, rx_done_next;
    reg [7:0] rx_buf_reg, rx_buf_next;

    assign rx_data = rx_buf_reg;
    assign rx_done = rx_done_reg;

    always @(posedge clk, posedge rst) begin
        if (rst) begin
            cur_state   <= IDLE;
            bit_cnt     <= 0;
            baud_tick_cnt  <= 0;
            rx_done_reg <= 0;
            rx_buf_reg  <= 0;
        end else begin
            cur_state   <= next_state;
            bit_cnt     <= bit_cnt_next;
            baud_tick_cnt  <= baud_tick_cnt_next;
            rx_done_reg <= rx_done_next;
            rx_buf_reg  <= rx_buf_next;
        end
    end

    always @(*) begin
        next_state      = cur_state;
        bit_cnt_next    = bit_cnt;
        baud_tick_cnt_next = baud_tick_cnt;
        rx_done_next    = rx_done_reg;
        rx_buf_next     = rx_buf_reg;
        case (cur_state)
            IDLE: begin
                // bit_cnt_next = 0;
                // baud_tick_cnt_next = 0;
                rx_done_next = 1'b0;
                if (baud_tick) begin
                    if (rx == 0) begin
                        next_state = START;
                        baud_tick_cnt_next = 0;
                    end
                end
            end
            START: begin
                if (baud_tick) begin
                    if (baud_tick_cnt == 23) begin
                        next_state = DATA;
                        bit_cnt_next = 0;
                        baud_tick_cnt_next = 0;
                    end else begin
                        baud_tick_cnt_next = baud_tick_cnt + 1;
                    end
                end
            end
            DATA: begin
                if (baud_tick == 1) begin
                    if (baud_tick_cnt == 0) begin
                        rx_buf_next[7] = rx;
                    end
                    if (baud_tick_cnt == 15) begin
                        if (bit_cnt == 7) begin
                            next_state = STOP;
                        end else begin
                            bit_cnt_next = bit_cnt + 1;
                            baud_tick_cnt_next = 0;
                            rx_buf_next = rx_buf_reg >> 1;
                        end
                    end else begin
                        baud_tick_cnt_next = baud_tick_cnt + 1;
                    end
                end
            end

            STOP: begin
                if (baud_tick == 1) begin
                    rx_done_next = 1'b1;
                    next_state   = IDLE;
                end
            end
        endcase
    end
endmodule


