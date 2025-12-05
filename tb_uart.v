

`timescale 1ns / 1ps

module tb_uart ();
    //(system_clk / baud) * clock time * 10bit
    parameter rx_DELAY = 100_000_000 / 9600 * 100;
    parameter BAUD_RATE = 9600;
    parameter CLOCK_PERIOD_NS = 10;  //100Mhz
    parameter BITPERCLOCK = 10416;  // 1 / BAUD_RATE;  // 1bit per clock 1/9600
    parameter BIT_PERIOD = BITPERCLOCK * CLOCK_PERIOD_NS; // number of clock * 10

    reg clk, rst;
    reg [7:0] rx_data;
    reg rx;
    wire tx;


    //verification variable
    reg [7:0] expected_data;
    reg [7:0] receive_data;
    integer pass_count = 0;
    integer fail_count = 0;
    integer bit_count = 0;
    integer j = 0;

    uart_top dut (
        .clk(clk),
        .rst(rst),
        .rx(rx),
        // .tx_busy(tx_busy),
        .tx(tx)
    );

    always #5 clk = ~clk;

    initial begin
        #0;
        clk = 0;
        rst = 1;
        rx_data = 0;
        rx = 1;
        #10;
        rst = 0;
        #10;
        $display("UART rx testbench started");
        $display("BAUD Rate      : %d", BAUD_RATE);
        $display("Clock per Bits : %d", BITPERCLOCK);
        $display("Bit period     : %d", BIT_PERIOD);
        for (j = 0; j < 100; j = j + 1) begin
            single_uart_byte_test($random() % 256);
            #1000;
        end //100번 0~255 랜덤값 받기
        $display("pass : %d", pass_count);
        $display("fail : %d", fail_count);
        $stop;
    end

    // //for verification
    task send(input [7:0] send_data);
        integer i;
        begin
            $display("rx_start");
            expected_data = send_data; // data값 입력
            rx = 1'b0; // rx가 떨어지면서 시작
            #(BIT_PERIOD); // start비트에서 한비트 쉬고
            for (i = 0; i < 8; i = i + 1) begin
                rx = send_data[i]; //데이터를 한 비트씩 삽입
                #(BIT_PERIOD); //8bit를 한비트의 시간을 주면서 지연 시켜줌
            end
            rx = 1'b1; 
            #(BIT_PERIOD); //rx를 1로 올리면서 stop bit
        end
    endtask

    task receive_uart();
        begin
            $display("tx_start");
            receive_data = 0;
            @(negedge tx); //tx가 하강엣지일 때 start rx_done이 튀면서 tx_start가 1이고 tx가 1->0이 되면서 시작
            #(BIT_PERIOD / 2);  //middle of start bit 
            //start bit pass/fail
            if (tx) begin
                //fail 
                $display("Fail start bit"); //tx가 내려가지 않아서 fail 출력
            end
            //receive data bit
            for (bit_count = 0; bit_count < 8; bit_count = bit_count + 1) begin
                #(BIT_PERIOD);
                receive_data[bit_count] = tx; //8비트 데이터를 rx에서 받아
            end
            //stop bit
            #(BIT_PERIOD); //stop bit 중앙으로 이동
            if (!tx) begin
                $display("Fail STOP bit");
            end //tx 수신이 완료되면 0->1 이 되야되는데 0이면 fail 출력
            #(BIT_PERIOD / 2); //stop비트로 이동
            if (expected_data == receive_data) begin
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
            end
        end
    endtask

    task single_uart_byte_test(input [7:0] send_data);
        fork
            send(send_data);
            receive_uart();
        join
    endtask


endmodule




