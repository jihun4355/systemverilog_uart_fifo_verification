


`timescale 1ns/1ps

// ---------------- Interface ----------------
interface uart_rx_if;
    logic clk;
    logic rst;
    logic rx;
    logic baud_tick;
    logic [7:0] rx_data;
    logic rx_done;
endinterface

// ---------------- Transaction ----------------
class transaction;
    rand bit [7:0] data;       // 송신할 데이터
    bit [7:0] captured_data;   // DUT가 수신한 데이터
    bit rx_done;

    task display(string tag);
        $display("%0t [%s] data=0x%0h captured=0x%0h rx_done=%0d",
                 $time, tag, data, captured_data, rx_done);
    endtask
endclass

// ---------------- Generator ----------------
class generator;
    transaction tr;
    mailbox #(transaction) mbox_gen2drv;
    mailbox #(transaction) mbox_gen2scb;
    event ev_gen_next;
    int total_sent = 0;

    function new(mailbox #(transaction) mbox_gen2drv,
                 mailbox #(transaction) mbox_gen2scb,
                 event ev_gen_next);
        this.mbox_gen2drv = mbox_gen2drv;
        this.mbox_gen2scb = mbox_gen2scb;
        this.ev_gen_next  = ev_gen_next;
    endfunction

    task run(int n);
        for (int k=0; k<n; k++) begin
            tr = new();
            if (k>0) @(ev_gen_next);
            assert(tr.randomize()) else $error("[GEN] randomize error");
            total_sent++;
            mbox_gen2drv.put(tr);
            mbox_gen2scb.put(tr);
            tr.display("GEN");
        end
    endtask
endclass

// ---------------- Driver ----------------
class driver;
    transaction tr;
    mailbox #(transaction) mbox_gen2drv;
    virtual uart_rx_if u_if;
    event ev_mon_next;

    function new(mailbox #(transaction) mbox_gen2drv,
                 virtual uart_rx_if u_if,
                 event ev_mon_next);
        this.mbox_gen2drv = mbox_gen2drv;
        this.u_if         = u_if;
        this.ev_mon_next  = ev_mon_next;
    endfunction

    task reset();
        u_if.rst <= 1;
        u_if.rx  <= 1;
        repeat(5) @(posedge u_if.clk);
        u_if.rst <= 0;
        repeat(50) @(posedge u_if.clk);
        $display("[DRV] Reset done");
    endtask

    task send_byte(bit [7:0] d);
        int i;
        u_if.rx <= 0; repeat (16) @(posedge u_if.baud_tick);
        for (i=0; i<8; i++) begin
            u_if.rx <= d[i];
            repeat (16) @(posedge u_if.baud_tick);
        end
        u_if.rx <= 1; repeat (16) @(posedge u_if.baud_tick);
    endtask

    task run();
        forever begin
            mbox_gen2drv.get(tr);
            tr.display("DRV");
            send_byte(tr.data);

  
        end
    endtask

endclass

// ---------------- Monitor ----------------
// ---------------- Monitor ----------------
class monitor;
    transaction tr;
    mailbox #(transaction) mbox_mon2scb;
    virtual uart_rx_if u_if;

    function new(mailbox #(transaction) mbox_mon2scb,
                 virtual uart_rx_if u_if);
        this.mbox_mon2scb = mbox_mon2scb;
        this.u_if         = u_if;
    endfunction

    task run();
        forever begin
            @(posedge u_if.rx_done);  // rx_done이 1 될 때까지 기다림
            tr = new();
            tr.captured_data = u_if.rx_data;
            tr.rx_done       = 1;
            mbox_mon2scb.put(tr);
            tr.display("MON");
        end
    endtask
endclass



// ---------------- Scoreboard ----------------
// ---------------- Scoreboard ----------------
class scoreboard;
    transaction g, m;
    mailbox #(transaction) mbox_gen2scb;
    mailbox #(transaction) mbox_mon2scb;
    event ev_gen_next;

    int pass_cnt=0, fail_cnt=0, total_cnt=0;

    function new(mailbox #(transaction) mbox_gen2scb,
                 mailbox #(transaction) mbox_mon2scb,
                 event ev_gen_next);
        this.mbox_gen2scb = mbox_gen2scb;
        this.mbox_mon2scb = mbox_mon2scb;
        this.ev_gen_next  = ev_gen_next;
    endfunction

    task run();
        bit [7:0] golden_aligned;
        forever begin
            mbox_gen2scb.get(g);
            mbox_mon2scb.get(m);

            // Golden data 비트 reverse
            for (int i=0; i<8; i++)
                golden_aligned[i] = g.data[7-i];

            total_cnt++;
            if (golden_aligned == m.captured_data) begin
                pass_cnt++;
                $display("[SCB] PASS exp=0x%0h got=0x%0h",
                         golden_aligned, m.captured_data);
            end else begin
                fail_cnt++;
                $display("[SCB] FAIL exp=0x%0h got=0x%0h",
                         golden_aligned, m.captured_data);
            end

            -> ev_gen_next;
        end
    endtask
endclass



// ---------------- Environment ----------------
class environment;
    generator gen;
    driver drv;
    monitor mon;
    scoreboard scb;

    mailbox #(transaction) mbox_gen2drv, mbox_gen2scb, mbox_mon2scb;
    event ev_gen_next, ev_mon_next;
    virtual uart_rx_if u_if;

    function new(virtual uart_rx_if u_if);
        this.u_if = u_if;
        mbox_gen2drv = new();
        mbox_gen2scb = new();
        mbox_mon2scb = new();
        gen = new(mbox_gen2drv, mbox_gen2scb, ev_gen_next);
        drv = new(mbox_gen2drv, u_if, ev_mon_next);
        //mon = new(mbox_mon2scb, u_if, ev_mon_next);
        mon = new(mbox_mon2scb, u_if);
        scb = new(mbox_gen2scb, mbox_mon2scb, ev_gen_next);
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
module tb_uart_rx;
    uart_rx_if u_if();
    environment env;

    uart_rx DUT (
        .clk(u_if.clk), .rst(u_if.rst), .rx(u_if.rx),
        .baud_tick(u_if.baud_tick),
        .rx_data(u_if.rx_data), .rx_done(u_if.rx_done)
    );

    // clock
    initial begin
        u_if.clk = 0;
        forever #5 u_if.clk = ~u_if.clk;
    end

    // baud_tick (16x oversampling)
    reg [3:0] cnt;
    always @(posedge u_if.clk or posedge u_if.rst) begin
        if (u_if.rst) begin
            cnt <= 0;
            u_if.baud_tick <= 0;
        end else begin
            if (cnt == 15) begin
                cnt <= 0;
                u_if.baud_tick <= 1;
            end else begin
                cnt <= cnt + 1;
                u_if.baud_tick <= 0;
            end
        end
    end

    always @(posedge u_if.clk) begin
        if (u_if.rx_done)
            $display("%0t [DBG] rx_done=1, rx_data=0x%0h",
                     $time, u_if.rx_data);
    end

    initial begin
        env = new(u_if);
        env.reset();
        env.run(20);
    end
endmodule


























// `timescale 1ns/1ps

// // ---------------- Interface ----------------
// interface uart_rx_if;
//     logic clk;
//     logic rst;
//     logic rx;
//     logic baud_tick;
//     logic [7:0] rx_data;
//     logic rx_done;
// endinterface

// // ---------------- Transaction ----------------
// class transaction;
//     rand bit [7:0] data;
//     bit [7:0] captured_data;
//     bit rx_done;

//     task display(string tag);
//         $display("%0t [%s] data=0x%0h captured=0x%0h rx_done=%0d",
//                  $time, tag, data, captured_data, rx_done);
//     endtask
// endclass

// // ---------------- Generator ----------------
// class generator;
//     transaction tr;
//     mailbox #(transaction) mbox_gen2drv;
//     mailbox #(transaction) mbox_gen2scb;
//     event ev_gen_next;
//     int total_sent = 0;

//     function new(mailbox #(transaction) mbox_gen2drv,
//                  mailbox #(transaction) mbox_gen2scb,
//                  event ev_gen_next);
//         this.mbox_gen2drv = mbox_gen2drv;
//         this.mbox_gen2scb = mbox_gen2scb;
//         this.ev_gen_next  = ev_gen_next;
//     endfunction

//     task run(int n);
//         for (int k=0; k<n; k++) begin
//             tr = new();
//             if (k>0) @(ev_gen_next);
//             assert(tr.randomize()) else $error("[GEN] randomize error");
//             total_sent++;
//             mbox_gen2drv.put(tr);
//             mbox_gen2scb.put(tr);
//             tr.display("GEN");
//         end
//     endtask
// endclass

// // ---------------- Driver ----------------
// class driver;
//     transaction tr;
//     mailbox #(transaction) mbox_gen2drv;
//     virtual uart_rx_if u_if;
//     event ev_mon_next;

//     function new(mailbox #(transaction) mbox_gen2drv,
//                  virtual uart_rx_if u_if,
//                  event ev_mon_next);
//         this.mbox_gen2drv = mbox_gen2drv;
//         this.u_if         = u_if;
//         this.ev_mon_next  = ev_mon_next;
//     endfunction

//     task reset();
//         u_if.rst <= 1;
//         u_if.rx  <= 1;
//         repeat(5) @(posedge u_if.clk);
//         u_if.rst <= 0;
//         repeat(50) @(posedge u_if.clk);
//         $display("[DRV] Reset done");
//     endtask

//     task send_byte(bit [7:0] d);
//         int i;
//         // Start bit
//         u_if.rx <= 0;
//         repeat (24) @(posedge u_if.baud_tick); // ★ 24틱 유지

//         // Data bits (LSB-first 전송, DUT이 MSB-first로 shift하므로 문제없음)
//         for (i=0; i<8; i++) begin
//             u_if.rx <= d[i];
//             repeat (16) @(posedge u_if.baud_tick);
//         end

//         // Stop bit
//         u_if.rx <= 1;
//         repeat (16) @(posedge u_if.baud_tick);
//     endtask


//     task run();
//         forever begin
//             mbox_gen2drv.get(tr);
//             tr.display("DRV");
//             send_byte(tr.data);

  
//         end
//     endtask

// endclass


// // ---------------- Monitor ----------------
// class monitor;
//     transaction tr;
//     mailbox #(transaction) mbox_mon2scb;
//     virtual uart_rx_if u_if;

//     function new(mailbox #(transaction) mbox_mon2scb,
//                  virtual uart_rx_if u_if);
//         this.mbox_mon2scb = mbox_mon2scb;
//         this.u_if         = u_if;
//     endfunction

//     task run();
//         forever begin
//             @(posedge u_if.rx_done);
//             tr = new();
//             tr.captured_data = u_if.rx_data;
//             tr.rx_done       = 1;
//             mbox_mon2scb.put(tr);
//             tr.display("MON");
//         end
//     endtask
// endclass


// // ---------------- Scoreboard ----------------
// class scoreboard;
//     transaction g, m;
//     mailbox #(transaction) mbox_gen2scb;
//     mailbox #(transaction) mbox_mon2scb;
//     event ev_gen_next;

//     int pass_cnt=0, fail_cnt=0, total_cnt=0;

//     function new(mailbox #(transaction) mbox_gen2scb,
//                  mailbox #(transaction) mbox_mon2scb,
//                  event ev_gen_next);
//         this.mbox_gen2scb = mbox_gen2scb;
//         this.mbox_mon2scb = mbox_mon2scb;
//         this.ev_gen_next  = ev_gen_next;
//     endfunction
    
//     task run();
//         forever begin
//             mbox_gen2scb.get(g);
//             mbox_mon2scb.get(m);

//             total_cnt++;
//             if (g.data == m.captured_data) begin
//                 pass_cnt++;
//                 $display("[SCB] PASS exp=0x%0h got=0x%0h",
//                         g.data, m.captured_data);
//             end else begin
//                 fail_cnt++;
//                 $display("[SCB] FAIL exp=0x%0h got=0x%0h",
//                         g.data, m.captured_data);
//             end

//             -> ev_gen_next;
//         end
//     endtask


// endclass



// // ---------------- Environment ----------------
// class environment;
//     generator gen;
//     driver drv;
//     monitor mon;
//     scoreboard scb;

//     mailbox #(transaction) mbox_gen2drv, mbox_gen2scb, mbox_mon2scb;
//     event ev_gen_next, ev_mon_next;
//     virtual uart_rx_if u_if;

//     function new(virtual uart_rx_if u_if);
//         this.u_if = u_if;
//         mbox_gen2drv = new();
//         mbox_gen2scb = new();
//         mbox_mon2scb = new();
//         gen = new(mbox_gen2drv, mbox_gen2scb, ev_gen_next);
//         drv = new(mbox_gen2drv, u_if, ev_mon_next);
//         mon = new(mbox_mon2scb, u_if);
//         scb = new(mbox_gen2scb, mbox_mon2scb, ev_gen_next);
//     endfunction

//     task reset();
//         drv.reset();
//     endtask

//     task report();
//         $display("====================================");
//         $display("============ Test report ===========");
//         $display("==   Total sent : %4d", gen.total_sent);
//         $display("==   Checked    : %4d", scb.total_cnt);
//         $display("==   PASS       : %4d", scb.pass_cnt);
//         $display("==   FAIL       : %4d", scb.fail_cnt);
//         $display("====================================");
//     endtask

//     task run(int n=20, int timeout=1_000_000);
//         -> ev_gen_next;
//         fork
//             gen.run(n);
//             drv.run();
//             mon.run();
//             scb.run();
//         join_none

//         fork
//             begin wait (scb.total_cnt==n); end
//             begin repeat(timeout) @(posedge u_if.clk);
//                   $error("[ENV] Timeout"); end
//         join_any

//         report();
//         $stop;
//     endtask
// endclass

// // ---------------- Top TB ----------------
// module tb_uart_rx;
//     uart_rx_if u_if();
//     environment env;

//     uart_rx DUT (
//         .clk(u_if.clk), .rst(u_if.rst), .rx(u_if.rx),
//         .baud_tick(u_if.baud_tick),
//         .rx_data(u_if.rx_data), .rx_done(u_if.rx_done)
//     );

//     // clock
//     initial begin
//         u_if.clk = 0;
//         forever #5 u_if.clk = ~u_if.clk;
//     end

//     // baud_tick (16x oversampling)
//     reg [3:0] cnt;
//     always @(posedge u_if.clk or posedge u_if.rst) begin
//         if (u_if.rst) begin
//             cnt <= 0;
//             u_if.baud_tick <= 0;
//         end else begin
//             if (cnt == 15) begin
//                 cnt <= 0;
//                 u_if.baud_tick <= 1;
//             end else begin
//                 cnt <= cnt + 1;
//                 u_if.baud_tick <= 0;
//             end
//         end
//     end

//     always @(posedge u_if.clk) begin
//         if (u_if.rx_done)
//             $display("%0t [DBG] rx_done=1, rx_data=0x%0h",
//                      $time, u_if.rx_data);
//     end

//     initial begin
//         env = new(u_if);
//         env.reset();
//         env.run(20);
//     end
// endmodule
