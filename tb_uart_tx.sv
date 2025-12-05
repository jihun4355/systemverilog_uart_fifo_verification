// `timescale 1ns / 1ps

// interface uart_tx_interface;
//     logic clk;
//     logic rst;
//     logic baud_tick;
//     logic start_trig;
//     logic [7:0] tx_data;
//     logic tx_busy;
//     // logic done;
//     logic tx;
// endinterface


// class transaction;
//     rand logic [7:0] tx_data;
//     rand logic       start_trig;
//     logic [7:0]      tx_bits;   // tx 라인에서 샘플한 8비트(LSB-first)
//     constraint tx_start_c { start_trig == 1; }

//     task display(string name_s);
//         $display("%0t,[%s] : start_trig=%0d, tx_data=0x%0h, tx_bits=0x%0h",
//                  $time, name_s, start_trig, tx_data, tx_bits);
//     endtask
// endclass


// class generator;
//     transaction tr;
//     mailbox #(transaction) gen2drv_mbox;
//     event gen_next_event;
//     int   total_repeat = 0;

//     function new(mailbox#(transaction) gen2drv_mbox, event gen_next_event);
//         this.gen2drv_mbox   = gen2drv_mbox;
//         this.gen_next_event = gen_next_event;
//     endfunction

//     task run(int run_count);
//         for (int k = 0; k < run_count; k++) begin
//             total_repeat++;
//             tr = new();
//             if (k > 0) @(gen_next_event); // 다음 트랜잭션 허가 대기
//             assert(tr.randomize()) else $error("[GEN] randomize() error!");
//             gen2drv_mbox.put(tr);
//             tr.display("GEN");
//         end
//     endtask
// endclass


// class driver;
//     transaction tr;
//     mailbox #(transaction) gen2drv_mbox;
//     virtual uart_tx_interface uart_if;
//     event mon_next_event;

//     function new(mailbox#(transaction) gen2drv_mbox,
//                  virtual uart_tx_interface uart_if,
//                  event mon_next_event);
//         this.gen2drv_mbox   = gen2drv_mbox;
//         this.uart_if        = uart_if;
//         this.mon_next_event = mon_next_event;
//     endfunction

//     task reset();
//         uart_if.rst      = 1;
//         uart_if.start_trig = 0;
//         uart_if.tx_data  = 0;
//         repeat(2) @(posedge uart_if.clk);
//         uart_if.rst = 0;
//         repeat(2) @(posedge uart_if.clk);
//         $display("[DRV] Reset done!");
//     endtask

//     task run();
//         forever begin
//             gen2drv_mbox.get(tr);
//             while (uart_if.tx_busy) @(posedge uart_if.clk);

//             uart_if.start_trig <= tr.start_trig; // 1클럭 펄스
//             uart_if.tx_data  <= tr.tx_data;
//             tr.display("DRV");
//             @(posedge uart_if.clk);
//             uart_if.start_trig <= 1'b0;

//             // DUT busy 상승을 모니터에 알림
//             @(posedge uart_if.tx_busy);
//             -> mon_next_event;
//         end
//     endtask
// endclass


// // =========================
// // MONITOR (OSR=16: b_tick 16번 = 1비트)
// //  - 스타트 검출 → 다음 b_tick 정렬 → 반비트 이동(8틱)
// //  - 이후 매 비트마다 16틱을 건너뛴 뒤 중앙에서 샘플
// // =========================
// class monitor;
//     transaction tr;
//     mailbox #(transaction) mon2scb_mbox;
//     virtual uart_tx_interface uart_if;
//     event mon_next_event;

//     localparam int OSR = 16; // 오버샘플 비율

//     function new(mailbox#(transaction) mon2scb_mbox,
//                  virtual uart_tx_interface uart_if,
//                  event mon_next_event);
//         this.mon2scb_mbox   = mon2scb_mbox;
//         this.uart_if        = uart_if;
//         this.mon_next_event = mon_next_event;
//     endfunction

//     task run();
//         logic [7:0] d;
//         int i;
//         forever begin
//             @(mon_next_event);

//             // 비교 대상 값 스냅샷
//             tr          = new();
//             tr.start_trig = uart_if.start_trig;
//             tr.tx_data  = uart_if.tx_data;

//             // Start LOW 정렬(이미 0이면 대기 생략)
//             if (uart_if.tx == 1'b1) @(negedge uart_if.tx);

//             // b_tick 그리드에 정렬
//             @(posedge uart_if.baud_tick);

//             // start 비트 중앙까지 반비트(8틱)
//             repeat (OSR/2) @(posedge uart_if.baud_tick);
//             if (uart_if.tx !== 1'b0)
//                 $display("[MON] Start bit not LOW at %0t", $time);

//             // 데이터 0의 중앙으로 1비트(16틱) 더 이동
//             repeat (OSR) @(posedge uart_if.baud_tick);

//             // 8비트 LSB-first 수집: 매 비트마다 16틱 간격
//             d = '0;
//             for (i = 0; i < 8; i++) begin
//                 d[i] = uart_if.tx;                // 비트 중앙에서 샘플
//                 if (i != 7) repeat (OSR) @(posedge uart_if.baud_tick);
//             end

//             // stop 비트 중앙 확인
//             repeat (OSR) @(posedge uart_if.baud_tick);
//             if (uart_if.tx !== 1'b1)
//                 $display("[MON] Stop bit not HIGH at %0t", $time);

//             tr.tx_bits = d;       // ★ tx에서 모은 8비트만 사용
//             tr.display("MON");

//             @(posedge uart_if.clk);
//             mon2scb_mbox.put(tr);
//         end
//     endtask
// endclass


// class scoreboard;
//     transaction tr;
//     mailbox #(transaction) mon2scb_mbox;
//     event gen_next_event;

//     int match_cnt    = 0;
//     int mismatch_cnt = 0;
//     int total_cnt    = 0;

//     function new(mailbox#(transaction) mon2scb_mbox, event gen_next_event);
//         this.mon2scb_mbox   = mon2scb_mbox;
//         this.gen_next_event = gen_next_event;
//     endfunction

//     task run();
//         int i;
//         bit all_match;

//         forever begin
//             mon2scb_mbox.get(tr);

//             // 비트 단위(LSB-first) 비교: tx에서 모은 비트 == tx_data의 각 비트
//             all_match = 1'b1;
//             for (i = 0; i < 8; i++) begin
//                 if (tr.tx_bits[i] != tr.tx_data[i]) begin
//                     all_match = 1'b0;
//                     $display("[SCB] BIT MISMATCH @bit%0d: exp=%0b act=%0b",
//                              i, tr.tx_data[i], tr.tx_bits[i]);
//                 end
//             end

//             total_cnt++;
//             if (all_match) begin
//                 match_cnt++;
//                 $display("[SCB] PASS  (tx bits == tx_data)  exp=0x%0h act(bits)=0x%0h",
//                          tr.tx_data, tr.tx_bits);
//             end else begin
//                 mismatch_cnt++;
//                 $display("[SCB] FAIL  (tx bits != tx_data)  exp=0x%0h act(bits)=0x%0h",
//                          tr.tx_data, tr.tx_bits);
//             end
//             $display("--------------------");

//             -> gen_next_event; // 다음 트랜잭션 허용
//         end
//     endtask
// endclass

// class environment;
//     mailbox #(transaction) gen2drv_mbox;
//     mailbox #(transaction) mon2scb_mbox;
//     event gen_next_event;
//     event mon_next_event;

//     generator  gen;
//     driver     drv;
//     monitor    mon;
//     scoreboard scb;

//     virtual uart_tx_interface uart_if; // 타임아웃용

//     function new(virtual uart_tx_interface uart_if);
//         this.uart_if = uart_if;
//         gen2drv_mbox = new();
//         mon2scb_mbox = new();
//         gen = new(gen2drv_mbox, gen_next_event);
//         drv = new(gen2drv_mbox, uart_if, mon_next_event);
//         mon = new(mon2scb_mbox, uart_if, mon_next_event);
//         scb = new(mon2scb_mbox, gen_next_event);
//     endfunction

//     task reset();
//         drv.reset();
//     endtask

//     task report();
//         $display("====================================");
//         $display("============ Test report ===========");
//         $display("====================================");
//         $display("==          Total sent: %4d   ==", gen.total_repeat);
//         $display("== Total checked pairs: %4d   ==", scb.total_cnt);
//         $display("==         Pass(Match): %4d   ==", scb.match_cnt);
//         $display("==      Fail(Mismatch): %4d   ==", scb.mismatch_cnt);
//         $display("====================================");
//         $display("========= Testbench done ==========");
//     endtask

//     task run(int run_count = 50, int timeout_cycles = 1_000_000);
//         -> gen_next_event; // 첫 트랜잭션 시작

//         fork
//             gen.run(run_count);
//             drv.run();
//             mon.run();
//             scb.run();
//         join_none

//         fork
//             begin : wait_done
//                 wait (scb.total_cnt == run_count);
//             end
//             begin : timeout_guard
//                 repeat (timeout_cycles) @(posedge uart_if.clk);
//                 $error("[ENV] Timeout: expected %0d frames, got %0d",
//                        run_count, scb.total_cnt);
//             end
//         join_any

//         report();
//         $stop;
//     endtask
// endclass

// module tb_uart_tx;
//     uart_tx_interface uart_if_tb();
//     environment env;

//     // 100MHz 클럭
//     localparam int CLK_PERIOD = 10;
//     initial begin
//         uart_if_tb.clk = 1'b0;
//         forever #(CLK_PERIOD/2) uart_if_tb.clk = ~uart_if_tb.clk;
//     end

//     // b_tick 생성 (16배 분주: 비트 경계마다 1펄스)
//     reg [$clog2(16)-1:0] baud_cnt = '0;
//     always @(posedge uart_if_tb.clk or posedge uart_if_tb.rst) begin
//         if (uart_if_tb.rst) begin
//             uart_if_tb.baud_tick <= 1'b0;
//             baud_cnt          <= '0;
//         end else begin
//             if (baud_cnt == 15) begin
//                 uart_if_tb.baud_tick <= 1'b1;
//                 baud_cnt          <= '0;
//             end else begin
//                 uart_if_tb.baud_tick <= 1'b0;
//                 baud_cnt          <= baud_cnt + 1'b1;
//             end
//         end
//     end

//     // DUT 인스턴스 (외부 RTL 필요)
//     uart_tx DUT (
//         .clk     (uart_if_tb.clk),
//         .rst     (uart_if_tb.rst),
//         .baud_tick  (uart_if_tb.baud_tick), //b_tick - > baud_tick
//         .start_trig(uart_if_tb.start_trig), // tx_start -> start_trig
//         .tx_data (uart_if_tb.tx_data),
//         .tx_busy    (uart_if_tb.tx_busy),  //busy ->tx_busy
//         // .done    (uart_if_tb.done),
//         .tx      (uart_if_tb.tx)
//     );

//     initial begin
//         env = new(uart_if_tb);
//         env.reset();
//         env.run(50); // 3 프레임 검증
//     end
// endmodule











`timescale 1ns/1ps

// ---------------- Interface ----------------
interface uart_tx_if;
    logic clk;
    logic rst;
    logic baud_tick;
    logic start_trig;
    logic [7:0] tx_data;
    logic tx_busy;
    logic tx;
endinterface

// ---------------- Transaction ----------------
class transaction;
    rand logic [7:0] tx_data;
    rand logic       start_trig;
    logic [7:0]      captured_bits;   // 모니터에서 수집한 비트열
    constraint c_start { start_trig == 1; }

    task display(string tag);
        $display("%0t [%s] : start=%0d, tx_data=0x%0h, captured=0x%0h",
                 $time, tag, start_trig, tx_data, captured_bits);
    endtask
endclass

// ---------------- Generator ----------------
class generator;
    transaction tr;
    mailbox #(transaction) mbox_gen2drv;
    event ev_gen_next;
    int total_sent = 0;

    function new(mailbox#(transaction) mbox_gen2drv, event ev_gen_next);
        this.mbox_gen2drv = mbox_gen2drv;
        this.ev_gen_next  = ev_gen_next;
    endfunction

    task run(int n);
        for (int k=0; k<n; k++) begin
            tr = new();
            if (k>0) @(ev_gen_next);
            assert(tr.randomize()) else $error("[GEN] randomize error");
            total_sent++;
            mbox_gen2drv.put(tr);
            tr.display("GEN");
        end
    endtask
endclass

// ---------------- Driver ----------------
class driver;
    transaction tr;
    mailbox #(transaction) mbox_gen2drv;
    virtual uart_tx_if u_if;
    event ev_mon_next;

    function new(mailbox#(transaction) mbox_gen2drv,
                 virtual uart_tx_if u_if,
                 event ev_mon_next);
        this.mbox_gen2drv = mbox_gen2drv;
        this.u_if         = u_if;
        this.ev_mon_next  = ev_mon_next;
    endfunction

    task reset();
        u_if.rst        = 1;
        u_if.start_trig = 0;
        u_if.tx_data    = 0;
        repeat(2) @(posedge u_if.clk);
        u_if.rst = 0;
        repeat(2) @(posedge u_if.clk);
        $display("[DRV] Reset done");
    endtask

    task run();
        forever begin
            mbox_gen2drv.get(tr);
            while (u_if.tx_busy) @(posedge u_if.clk);

            u_if.start_trig <= tr.start_trig;
            u_if.tx_data    <= tr.tx_data;
            tr.display("DRV");
            @(posedge u_if.clk);
            u_if.start_trig <= 1'b0;

            @(posedge u_if.tx_busy);
            -> ev_mon_next;
        end
    endtask
endclass

// ---------------- Monitor ----------------
class monitor;
    transaction tr;
    mailbox #(transaction) mbox_mon2scb;
    virtual uart_tx_if u_if;
    event ev_mon_next;

    localparam int OSR = 16; // oversampling

    function new(mailbox#(transaction) mbox_mon2scb,
                 virtual uart_tx_if u_if,
                 event ev_mon_next);
        this.mbox_mon2scb = mbox_mon2scb;
        this.u_if         = u_if;
        this.ev_mon_next  = ev_mon_next;
    endfunction

    task run();
        logic [7:0] d;
        int i;
        forever begin
            @(ev_mon_next);

            tr = new();
            tr.start_trig = u_if.start_trig;
            tr.tx_data    = u_if.tx_data;

            if (u_if.tx == 1'b1) @(negedge u_if.tx);
            @(posedge u_if.baud_tick);

            repeat (OSR/2) @(posedge u_if.baud_tick);
            if (u_if.tx !== 0) $display("[MON] Start not LOW at %0t", $time);

            repeat (OSR) @(posedge u_if.baud_tick);

            d = '0;
            for (i=0; i<8; i++) begin
                d[i] = u_if.tx;
                if (i!=7) repeat (OSR) @(posedge u_if.baud_tick);
            end

            repeat (OSR) @(posedge u_if.baud_tick);
            if (u_if.tx !== 1) $display("[MON] Stop not HIGH at %0t", $time);

            tr.captured_bits = d;
            tr.display("MON");

            @(posedge u_if.clk);
            mbox_mon2scb.put(tr);
        end
    endtask
endclass

// ---------------- Scoreboard ----------------
class scoreboard;
    transaction tr;
    mailbox #(transaction) mbox_mon2scb;
    event ev_gen_next;

    int pass_cnt=0, fail_cnt=0, total_cnt=0;

    function new(mailbox#(transaction) mbox_mon2scb, event ev_gen_next);
        this.mbox_mon2scb = mbox_mon2scb;
        this.ev_gen_next  = ev_gen_next;
    endfunction

    task run();
        int i;
        bit all_match;
        forever begin
            mbox_mon2scb.get(tr);

            all_match = 1;
            for (i=0; i<8; i++) begin
                if (tr.captured_bits[i] != tr.tx_data[i]) begin
                    all_match = 0;
                    $display("[SCB] BIT MISMATCH @%0d exp=%0b got=%0b",
                             i, tr.tx_data[i], tr.captured_bits[i]);
                end
            end

            total_cnt++;
            if (all_match) begin
                pass_cnt++;
                $display("[SCB] PASS exp=0x%0h got=0x%0h",
                         tr.tx_data, tr.captured_bits);
            end else begin
                fail_cnt++;
                $display("[SCB] FAIL exp=0x%0h got=0x%0h",
                         tr.tx_data, tr.captured_bits);
            end
            $display("--------------------");

            -> ev_gen_next;
        end
    endtask
endclass

// ---------------- Environment ----------------
class environment;
    mailbox #(transaction) mbox_gen2drv;
    mailbox #(transaction) mbox_mon2scb;
    event ev_gen_next, ev_mon_next;

    generator  gen;
    driver     drv;
    monitor    mon;
    scoreboard scb;

    virtual uart_tx_if u_if;

    function new(virtual uart_tx_if u_if);
        this.u_if = u_if;
        mbox_gen2drv = new();
        mbox_mon2scb = new();
        gen = new(mbox_gen2drv, ev_gen_next);
        drv = new(mbox_gen2drv, u_if, ev_mon_next);
        mon = new(mbox_mon2scb, u_if, ev_mon_next);
        scb = new(mbox_mon2scb, ev_gen_next);
    endfunction

    task reset();
        drv.reset();
    endtask

    task report();
        $display("====================================");
        $display("============ Test report ===========");
        $display("==   Total sent : %4d", gen.total_sent);
        $display("==   Checked    : %4d", scb.total_cnt);
        $display("==   PASS       : %4d", scb.pass_cnt);
        $display("==   FAIL       : %4d", scb.fail_cnt);
        $display("====================================");
    endtask

    task run(int n=20, int timeout=1_000_000);
        -> ev_gen_next;
        fork
            gen.run(n);
            drv.run();
            mon.run();
            scb.run();
        join_none

        fork
            begin wait (scb.total_cnt==n); end
            begin repeat(timeout) @(posedge u_if.clk);
                  $error("[ENV] Timeout"); end
        join_any

        report();
        $stop;
    endtask
endclass

// ---------------- Top TB ----------------
module tb_uart_tx;
    uart_tx_if u_if();
    environment env;

    localparam int CLK_PERIOD = 10;
    initial begin
        u_if.clk = 0;
        forever #(CLK_PERIOD/2) u_if.clk = ~u_if.clk;
    end

    // baud tick (16x oversampling)
    reg [3:0] baud_cnt = 0;
    always @(posedge u_if.clk or posedge u_if.rst) begin
        if (u_if.rst) begin
            baud_cnt     <= 0;
            u_if.baud_tick <= 0;
        end else begin
            if (baud_cnt==15) begin
                baud_cnt     <= 0;
                u_if.baud_tick <= 1;
            end else begin
                baud_cnt     <= baud_cnt+1;
                u_if.baud_tick <= 0;
            end
        end
    end

    // DUT
    uart_tx DUT (
        .clk       (u_if.clk),
        .rst       (u_if.rst),
        .baud_tick (u_if.baud_tick),
        .start_trig(u_if.start_trig),
        .tx_data   (u_if.tx_data),
        .tx_busy   (u_if.tx_busy),
        .tx        (u_if.tx)
    );

    initial begin
        env = new(u_if);
        env.reset();
        env.run(20);
    end
endmodule
