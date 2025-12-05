`timescale 1ns / 1ps

module uart_fifo (
    input  logic clk,
    input  logic rst,
    input  logic rx,
    output logic tx
);

    logic [7:0] fifo_loopback;
    logic [7:0] uart_rx_data_to_fifo_rx_wdata;
    logic [7:0] fifo_tx_rdata_to_uart_tx_data;

    logic fifo_rx_full;
    logic fifo_rx_empty;
    logic fifo_tx_full;
    logic fifo_tx_empty;
    logic uart_rx_done;
    logic uart_tx_busy;
    uart U_UART (
        .clk     (clk),
        .rst     (rst),
        .rx      (rx),
        .tx_start(~fifo_tx_empty & ~uart_tx_busy),
        .tx_data (fifo_tx_rdata_to_uart_tx_data),
        .rx_done (uart_rx_done),
        .rx_data (uart_rx_data_to_fifo_rx_wdata),
        .tx      (tx),
        .tx_busy (uart_tx_busy)
    );

    fifo U_FIFO_RX (
        .clk  (clk),
        .rst  (rst),
        .wr   (uart_rx_done & ~fifo_rx_full),        // rx_done이고 fifo_rx 자기자신이 full이 아니면
        .rd   (~fifo_tx_full & ~fifo_rx_empty), // fifo_tx가 full이 아니고 fifo_rx 자기자신이 empty가 아니면
        .wdata(uart_rx_data_to_fifo_rx_wdata), 
        .full (fifo_rx_full),
        .empty(fifo_rx_empty),
        .rdata(fifo_loopback)
    );

    fifo U_FIFO_TX (
        .clk  (clk),
        .rst  (rst),
        .wr   (~fifo_tx_full & ~fifo_rx_empty), // fifo_rx의 rd와 같다.  // fifo_rx가 empty가 아니고 fifo_tx 자기자신이 full이 아니면
        .rd   (~uart_tx_busy & ~fifo_tx_empty), // uart_tx가 busy가 아니고, fifo_tx 자기자신이 empty가 아니면
        .wdata(fifo_loopback),
        .full (fifo_tx_full),
        .empty(fifo_tx_empty),
        .rdata(fifo_tx_rdata_to_uart_tx_data)
    );



endmodule
