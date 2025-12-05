`timescale 1ns / 1ps

interface uart_fifo_interface;
    logic clk;
    logic rst;
    logic rx;
    logic tx;
    logic [7:0] expected_data;  // send_data 전송용. //input 이자 output
endinterface  //uart_fifo_interface

class transaction;

    // 랜덤값 부여
    rand logic [7:0] send_data;

    // scoreboard 로직 선언. // 지금은 특정 시간의 데이터를 추출해서 데이터를 비교하는데 순서대로 데이터가 오는지 버퍼를 만들어서 비교해보고 싶다. 
    logic            rx;
    logic            tx;
    logic      [7:0] expected_data;
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
    event gen_next_event;

    function new(mailbox#(transaction) gen2drv_mbox, event gen_next_event);
        this.gen2drv_mbox   = gen2drv_mbox;
        this.gen_next_event = gen_next_event;
    endfunction  //new()

    task run(int run_count);
        repeat (run_count) begin
            tr = new();
            assert (tr.randomize())
            else $error("[GEN] randomize() error!! gengeration failed");
            gen2drv_mbox.put(tr);  // 랜덤값을 mailbox에 put 한다.
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
        uart_fifo_if.rx = 1;  // IDLE 일 때 rx는 1
        uart_fifo_if.expected_data = 0;
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


    task send(input [7:0] send_data);

        begin
            // start bit
            uart_fifo_if.rx = 0;
            uart_fifo_if.expected_data = tr.send_data;   // 인터페이스 안에 expected_data에 send_data 저장.
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
    // monitor.reveive를 위한 parameter 선언.
    parameter TX_DELAY = 10416 * 10 * 10;
    parameter BAUD_RATE = 9600;
    parameter CLOCK_PERIOD_NS = 10;  //100MHz
    parameter BITPERCLOCK = 10416;  // 1bit per clock 1/9600 
    parameter BIT_PERIOD = BITPERCLOCK * CLOCK_PERIOD_NS; // number of clock * 10
    parameter HALF_PERIOD = 5;
    parameter HALF_BIT_PERIOD = BITPERCLOCK * HALF_PERIOD;

    // for문 돌리기위해 bit_count 선언
    integer receive_bit_count = 0;

    transaction tr;
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
            @mon_next_event;
            tr    = new();
            tr.tx = uart_fifo_if.tx;
            tr.rx = uart_fifo_if.rx;
            tr.expected_data = uart_fifo_if.expected_data;
            receive();
            mon2scb_mbox.put(tr);
            tr.display("MON");  // monitor 
        end
    endtask  //run

    // receive는 tx와 tx_busy를 받아서 receive_data로 만든다.
    task receive();
        begin
            tr.receive_data = 0;
            //@(negedge uart_fifo_if.tx);
            // middle of start bit
            #(HALF_BIT_PERIOD);  // #104160 /2 

            // start bit pass / fail
            if (uart_fifo_if.tx) begin  // fail일 경우
                $display("Fail Start bit");
            end

            // received data bit
            for (
                receive_bit_count = 0;
                receive_bit_count < 8;
                receive_bit_count = receive_bit_count + 1
            ) begin
                #(BIT_PERIOD);
                tr.receive_data[receive_bit_count] = uart_fifo_if.tx;
            end

            // check stop bit
            #(BIT_PERIOD);
            if (!uart_fifo_if.tx) begin  // fail일 경우
                $display("Fail STOP bit");
            end
            #(HALF_BIT_PERIOD);
            $display("%t : tx = %d, receive_bit_count = %d, receive_data = %b",
                     $time, uart_fifo_if.tx, receive_bit_count,
                     tr.receive_data);

        end
    endtask

endclass  //monitor


class scoreboard;

    transaction tr;
    mailbox #(transaction) mon2scb_mbox;
    event gen_next_event;

    // 통계
    int total_count = 0;
    int pass_count = 0;
    int fail_count = 0;

    function new(mailbox#(transaction) mon2scb_mbox,
                 event gen_next_event);  // driver에서 scoreboard로 이동
        this.mon2scb_mbox = mon2scb_mbox;
        this.gen_next_event = gen_next_event; // driver에서 scoreboard로 이동
    endfunction  //new()

    task report();
        $display("===================================");
        $display("==========  test report  ==========");
        $display("===================================");
        $display("========   Total test: %4d  ", total_count);
        $display("========   PASS test : %4d  ", pass_count);
        $display("========   FAIL test : %4d  ", fail_count);
        $display("===================================");
        $display("====== Testbench is finished ======");
        $display("===================================");
    endtask

    task run();
        forever begin
            // pass fail decision.
            mon2scb_mbox.get(tr);  //mailbox에서 get한다.
            tr.display("SCB");  // scoreboard display
            if (tr.expected_data == tr.receive_data) begin
                pass_count++;
                $display("Pass : Data Matched, Pass count : %d", pass_count);
                $display("expected_data %b", tr.expected_data);
                $display("receive_data %b", tr.receive_data);
            end else begin
                fail_count++;
                $display("Fail : Data Mismatched, Fail count : %d", fail_count);
                $display("expected_data %b", tr.expected_data);
                $display("receive_data %b", tr.receive_data);
            end
            ->gen_next_event;  // driver에서 scoreboard로 이동
            total_count++;
        end
    endtask  //run

endclass  //scoreboard

class environment;
    generator                   gen;
    driver                      drv;
    monitor                     mon;
    scoreboard                  scb;

    mailbox #(transaction)      gen2drv_mbox;
    mailbox #(transaction)      mon2scb_mbox;
    virtual uart_fifo_interface uart_fifo_if;
    event                       gen_next_event;
    event                       mon_next_event;


    function new(virtual uart_fifo_interface uart_fifo_if);
        gen2drv_mbox = new;
        mon2scb_mbox = new;
        gen = new(gen2drv_mbox, gen_next_event);
        drv = new(gen2drv_mbox, uart_fifo_if, mon_next_event);
        mon = new(mon2scb_mbox, uart_fifo_if, mon_next_event);
        scb = new(mon2scb_mbox, gen_next_event);

    endfunction  //new()


    task reset();
        drv.reset();
    endtask  //reset

    task run();
        fork
            gen.run(100);
            drv.run();
            mon.run();
            scb.run();
        join_any
        #10;
        $display("finished");
           scb.report();
        $stop;
    endtask  //run
endclass  //environment


module tb_uart_fifo ();

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
