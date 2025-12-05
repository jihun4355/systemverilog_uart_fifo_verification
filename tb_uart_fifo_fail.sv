`timescale 1ns / 1ps

interface uart_fifo_interface;
    logic clk;
    logic rst;
    logic rx;
    logic tx;
endinterface  //uart_fifo_interface

class transaction;

    // 랜덤값 부여
    rand logic [7:0] send_data;
    // scoreboard 로직 선언. // 지금은 특정 시간의 데이터를 추출해서 데이터를 비교하는데 순서대로 데이터가 오는지 버퍼를 만들어서 비교해보고 싶다. 

    logic            rx;
    logic            tx;
    logic      [7:0] receive_data;

    // 제약조건

    // display task
    task display(string name_s);
        $display("%t : [%s] send_data = %d, receive_data = %d", $time, name_s,
                 send_data, receive_data);
    endtask  //display

endclass  //transaction

class generator;
    transaction tr;
    mailbox #(transaction) gen2drv_mbox;
    mailbox #(transaction) gen2scb_mbox;
    event gen_next_event;

    function new(mailbox#(transaction) gen2drv_mbox,
                 mailbox#(transaction) gen2scb_mbox, event gen_next_event);
        this.gen2drv_mbox   = gen2drv_mbox;
        this.gen2scb_mbox   = gen2scb_mbox;
        this.gen_next_event = gen_next_event;
    endfunction  //new()

    task run(int run_count);

        // 통계 report
        repeat (run_count) begin
            tr = new();
            assert (tr.randomize())
            else $error("[GEN] randomize() error!! gengeration failed");
            gen2drv_mbox.put(tr);  // 랜덤값을 mailbox에 put 한다.
            gen2scb_mbox.put(tr);  // 랜덤값을 mailbox에 put 한다.
            tr.display("GEN");  // GEN 로그 출력
            @gen_next_event;  // 다음이벤트를 기다린다.
        end
    endtask  //run
endclass  //generator

class driver;
    // driver.run을 위한 parameter 선언.
    parameter TX_DELAY = 10416 * 10 * 10;
    parameter BAUD_RATE = 9600;
    parameter CLOCK_PERIOD_NS = 10;  //100MHz
    parameter BITPERCLOCK = 10416;  // 1bit per clock 1/9600 
    parameter BIT_PERIOD = BITPERCLOCK * CLOCK_PERIOD_NS; // number of clock * 10

    // for문 돌리기위해 bit_count 선언
    integer send_bit_count = 0;

    // 연결
    transaction tr;
    mailbox #(transaction) gen2drv_mbox;
    virtual uart_fifo_interface uart_fifo_if;
    event mon_next_event;


    function new(mailbox#(transaction) gen2drv_mbox,
                 virtual uart_fifo_interface uart_fifo_if,
                 event mon_next_event);
        this.gen2drv_mbox   = gen2drv_mbox;
        this.uart_fifo_if   = uart_fifo_if;
        this.mon_next_event = mon_next_event;
    endfunction  //new()

    task reset();
        uart_fifo_if.clk = 0;
        uart_fifo_if.rst = 1;
        uart_fifo_if.rx  = 1;  // IDLE 일 때 rx는 1
        repeat (2) @(posedge uart_fifo_if.clk);
        uart_fifo_if.rst = 0;
        repeat (2) @(posedge uart_fifo_if.clk);
        $display("[DRV] reset done!!");
    endtask  //reset

    task run();
        forever begin
            @(posedge uart_fifo_if.clk);  // 클럭이 오면
            gen2drv_mbox.get(tr);  // transaction에서 데이터 가져온다.
            send(tr.send_data);  // 데이터를 전송하고
            ->mon_next_event;  // monitor에게 시작하라고 한다.
        end
    endtask  //run

    // send는 우리가 인공적으로 send신호를 (uart_rx의 입력신호 rx)를 만들고, uart_rx의 출력을 받는다
    task send(input [7:0] send_data);

        begin
            // start bit
            uart_fifo_if.rx = 0;
            #(BIT_PERIOD);
            for (
                send_bit_count = 0;
                send_bit_count < 8;
                send_bit_count = send_bit_count + 1
            ) begin
                if (tr.send_data[send_bit_count]) begin
                    uart_fifo_if.rx = 1'b1;
                end else begin
                    uart_fifo_if.rx = 1'b0;
                end
                #(BIT_PERIOD);
            end
            //stop bit
            uart_fifo_if.rx = 1'b1;
            #(BIT_PERIOD);
        end
    endtask

endclass  //driver

class monitor;

    // monitor.receive을 위한 parameter 선언.
    parameter CLOCK_PERIOD_NS = 10;  //100MHz
    parameter BITPERCLOCK = 10416;  // 1bit per clock 1/9600 

    // for문 돌리기위해 bit_count 선언
    integer send_bit_count = 0;
    integer receive_bit_count = 0;

    // 연결
    transaction tr;
    generator gen;  // 추가.
    driver drv;  // 추가.
    mailbox #(transaction) mon2scb_mbox;
    virtual uart_fifo_interface uart_fifo_if;
    event mon_next_event;
    function new(mailbox#(transaction) mon2scb_mbox,
                 virtual uart_fifo_interface uart_fifo_if,
                 event mon_next_event);
        this.mon2scb_mbox   = mon2scb_mbox;
        this.uart_fifo_if   = uart_fifo_if;
        this.mon_next_event = mon_next_event;
    endfunction  //new()

    task run();
        forever begin
            @mon_next_event;  // drv가 보내주는 신호를 기다린다.
            tr = new();  //새로운 트랜잭션 생성.
            receive();  //receive 태스크 실행 ( 데이터를 받는다. )
            mon2scb_mbox.put(tr);  // 받은 데이터를 scb로 전송한다. 
            tr.display("MON");  // monitor 
        end

    endtask  //run

    // receive는 send의 출력을 입력으로 받아서 uart_rx의 출력을 만들어 send에 보낸다.
    task receive();
        begin
            tr.receive_data = 0;
            @(negedge uart_fifo_if.tx); // tx의 하강엣지를 기다린다 ( start bit 를 기다린다.)

            repeat (BITPERCLOCK / 2)
            @(posedge uart_fifo_if.clk);  // middle of start bit // 반 비트시간을 기다려서 중간값을 샘플링한다.

            // start bit pass / fail
            if (uart_fifo_if.tx) begin  // fail일 경우
                $display("Fail Start bit");
            end

            // 8개의 데이터 비트를 클럭에 맞춰 샘플링합니다.
            for (int i = 0; i < 8; i++) begin
                repeat (BITPERCLOCK) @(posedge uart_fifo_if.clk);
                tr.receive_data[i] = uart_fifo_if.tx;
            end

            //            // received data bit
            //            for (
            //                receive_bit_count = 0;
            //                receive_bit_count < 8;
            //                receive_bit_count = receive_bit_count + 1
            //            ) begin
            //                #(BIT_PERIOD);
            //                tr.receive_data[receive_bit_count] = uart_fifo_if.tx;
            //            end

            // check stop bit
            repeat (BITPERCLOCK)
            @(posedge uart_fifo_if.clk); // middle of start bit // 반 비트시간을 기다려서 중간값을 샘플링한다.
            if (!uart_fifo_if.tx) begin  // fail일 경우
                $display("Fail STOP bit");
            end

            //            #52080;  //BIT_PERIOD / 2
            //
            //            if (tr.send_data == tr.receive_data) begin
            //                $display("Pass : Data Matched");
            //                $display("send_data %2x", tr.send_data);
            //                $display("receive_data %2x", tr.receive_data);
            //            end else begin
            //                $display("Fail : Data Mismatched");
            //                $display("send_data %2x", tr.send_data);
            //                $display("receive_data %2x", tr.receive_data);
            //            end
        end
    endtask
endclass  //monitor


class scoreboard;
    // 연결
    transaction tr_expected;
    transaction tr_actual;
    mailbox #(transaction) mon2scb_mbox;
    mailbox #(transaction) gen2scb_mbox;
    event gen_next_event;

    // 통계를 위한 카운트 선언.
    int pass_count = 0;
    int fail_count = 0;
    int total_count = 0;

    // 예상 데이터를 임시 저장할 큐 선언
    logic [7:0] expected_queue[$:15];

    logic [7:0] expected_data;

    function new(mailbox#(transaction) mon2scb_mbox,
                 mailbox#(transaction) gen2scb_mbox,
                 event gen_next_event);  // driver에서 scoreboard로 이동
        this.mon2scb_mbox = mon2scb_mbox;
        this.gen2scb_mbox = gen2scb_mbox;
        this.gen_next_event = gen_next_event; // driver에서 scoreboard로 이동
    endfunction  //new()

    task run();
        fork
            // expected_data 
            forever begin
                gen2scb_mbox.get(tr_expected);  //mailbox에서 get한다.
                expected_queue.push_back(tr_expected.send_data);

            end
            // actual_data 
            forever begin
                mon2scb_mbox.get(tr_actual);  //mailbox에서 get한다.
                //            if (~tb_uart_fifo.DUT.U_UART.U_UART_TX.tx_busy_reg) begin

                // 큐에 예상 데이터가 도착할 때까지 기다립니다.
                wait(expected_queue.size() > 0);

                // 큐에서 가장 오래된 예상 데이터를 가져옵니다.
                tr_expected.send_data = expected_queue.pop_front();

                if (tr_expected.send_data == tr_actual.receive_data) begin
                    pass_count++;
                    $display(" -> PASS | send_data = %d, receive_data = %d",
                             tr_expected.send_data, tr_actual.receive_data);
                end else begin
                    fail_count++;
                    $display(" -> FAIL | send_data = %d, receive_data = %d",
                             tr_expected.send_data, tr_actual.receive_data);
                end
                //            end else begin
                //                $display("-> send_data = %d", tr.send_data);
                //            end
                total_count++;
                $display("%t : [SCB] send_data = %d, receive_data = %d", $time,
                         tr_expected.send_data,
                         tr_actual.receive_data);  // scoreboard 

                ->gen_next_event;  // driver에서 scoreboard로 이동
            end
        join_any
    endtask  //run
endclass  //scoreboard

class environment;
    generator                   gen;
    driver                      drv;
    monitor                     mon;
    scoreboard                  scb;

    mailbox #(transaction)      gen2drv_mbox;
    mailbox #(transaction)      gen2scb_mbox;
    mailbox #(transaction)      mon2scb_mbox;
    virtual uart_fifo_interface uart_fifo_if;
    event                       gen_next_event;
    event                       mon_next_event;


    function new(virtual uart_fifo_interface uart_fifo_if);
        gen2drv_mbox = new;
        gen2scb_mbox = new;
        mon2scb_mbox = new;
        gen = new(gen2drv_mbox, gen2scb_mbox, gen_next_event);
        drv = new(gen2drv_mbox, uart_fifo_if, mon_next_event);
        mon = new(mon2scb_mbox, uart_fifo_if, mon_next_event);
        scb = new(mon2scb_mbox, gen2scb_mbox, gen_next_event);

    endfunction  //new()

    task report();
        $display("===================================");
        $display("==========  test report  ==========");
        $display("===================================");
        $display("========   Total test: %4d  ", scb.total_count);
        $display("========   PASS test : %4d  ", scb.pass_count);
        $display("========   FAIL test : %4d  ", scb.fail_count);
        $display("===================================");
        $display("====== Testbench is finished ======");
        $display("===================================");
    endtask

    task reset();
        drv.reset();
    endtask  //reset

    task run();
        fork
            gen.run(100);
            drv.run();
            mon.run();
            scb.run();

        join_none
        #10;
        $display("finished");
        report();
        $stop;
    endtask  //run
endclass  //environment


module tb_uart_fifo_fail ();

    uart_fifo_interface uart_fifo_if_tb ();
    environment env;

    uart_fifo DUT (
        .clk(uart_fifo_if_tb.clk),
        .rst(uart_fifo_if_tb.rst),
        .rx (uart_fifo_if_tb.rx),
        .tx (uart_fifo_if_tb.tx)

    );

    always #5 uart_fifo_if_tb.clk = ~uart_fifo_if_tb.clk;

    initial begin
        uart_fifo_if_tb.clk = 0;
        env = new(uart_fifo_if_tb);
        env.reset();
        env.run();

    end

endmodule
