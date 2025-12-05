`timescale 1ns / 1ps
module tb_uart_fifo_simul ();

    //  ( system clock / baud ) * clock time * 10bit 
    parameter TX_DELAY = 10416 * 10 * 10;
    parameter BAUD_RATE = 9600;
    parameter CLOCK_PERIOD_NS = 10;  //100MHz
    parameter BITPERCLOCK = 10416;  // 1bit per clock 1/9600 
    parameter BIT_PERIOD = BITPERCLOCK * CLOCK_PERIOD_NS; // number of clock * 10 

    logic clk, rst, rx;
    logic tx;

    // for문 돌리기위해 bit_count 선언
    integer send_bit_count = 0;
    integer receive_bit_count = 0;

    // random test를 위한 rando_rx_data와 검증을 위한 receive_data. tx로 receive_data를 만든다.
    reg [7:0] send_data;
    reg [7:0] receive_data;

    // for문을 위한 integer i 선언 , 그리고 pass fail count 레그 추가.
    integer i = 0;
    reg [7:0] pass_count = 0;
    reg [7:0] fail_count = 0;

    uart_fifo DUT (
        .clk(clk),
        .rst(rst),
        .rx (rx),
        .tx (tx)
    );

    always #5 clk = ~clk;

    initial begin
        #0;
        clk = 0;
        rst = 1;
        rx  = 1;
        #10;
        rst = 0;
        #100;

        // verification process 
        $display("UART RX testbench started");
        $display("BAUD RATE         : %d", BAUD_RATE);
        $display("Clock per Bits    : %d", BITPERCLOCK);
        $display("Bit period        : %d", BIT_PERIOD);

        // test task
        for (i = 0; i < 256; i = i + 1) begin
            send_data = $random() % 256;
            single_uart_rx_test(send_data);
            #1000;
            if (send_data == receive_data) begin
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
            end
        end
        $stop;
    end

    // send는 우리가 인공적으로 send신호를 (uart_rx의 입력신호 rx)를 만들고, uart_rx의 출력을 받는다
    task send(input [7:0] send_data);
        begin
            // start bit
            rx = 0;
            #(BIT_PERIOD);
            for (send_bit_count = 0; send_bit_count < 8; send_bit_count = send_bit_count + 1) begin
                if (send_data[send_bit_count]) begin
                    rx = 1'b1;
                end else begin
                    rx = 1'b0;
                end
                #(BIT_PERIOD);
            end
            //stop bit
            rx = 1'b1;
            #(BIT_PERIOD);
        end
    endtask

    // receive는 send의 출력을 입력으로 받아서 uart_rx의 출력을 만들어 send에 보낸다.
    task receive_uart();
        begin
            receive_data = 0;
            @(negedge tx);
            // middle of start bit
            #52080;  //BIT_PERIOD / 2

            // start bit pass / fail
            if (tx) begin  // fail일 경우
                $display("Fail Start bit");
            end

            // received data bit
            for (receive_bit_count = 0; receive_bit_count < 8; receive_bit_count = receive_bit_count + 1) begin
                #(BIT_PERIOD);
                receive_data[receive_bit_count] = tx;
            end

            // check stop bit
            #(BIT_PERIOD);
            if (!tx) begin  // fail일 경우
                $display("Fail STOP bit");
            end

            #52080;  //BIT_PERIOD / 2

            if (send_data == receive_data) begin
                $display("Pass : Data Matched");
                $display("send_data %2x", send_data);
                $display("receive_data %2x", receive_data);
            end else begin
                $display("Fail : Data Mismatched");
                $display("send_data %2x", send_data);
                $display("receive_data %2x", receive_data);
            end
        end
    endtask

    task single_uart_rx_test(input [7:0] send_data);
        fork
            send(send_data);
            receive_uart();
        join
    endtask
endmodule
