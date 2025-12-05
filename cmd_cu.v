`timescale 1ns / 1ps

module cmd_cu (
    input clk,
    input rst,
    input rx_done,
    input [7:0] rx_data,
    output Btn_R_trig,
    output Btn_L_trig,
    output Btn_U_trig
);

    reg btn_r_trig_reg, btn_r_trig_next;
    reg btn_l_trig_reg, btn_l_trig_next;
    reg btn_u_trig_reg, btn_u_trig_next;


    assign Btn_R_trig = btn_r_trig_reg;
    assign Btn_L_trig = btn_l_trig_reg;
    assign Btn_U_trig = btn_u_trig_reg;

    always @(posedge clk, posedge rst) begin
        if (rst) begin
            btn_r_trig_reg <= 0;
            btn_l_trig_reg <= 0;
            btn_u_trig_reg <= 0;
        end else begin
            btn_r_trig_reg <= btn_r_trig_next;
            btn_l_trig_reg <= btn_l_trig_next;
            btn_u_trig_reg <= btn_u_trig_next;
        end
    end

    always @(*) begin
        btn_r_trig_next = 0;
        btn_l_trig_next = 0;
        btn_u_trig_next = 0;
        if (rx_done) begin
            case (rx_data)
                8'h52: begin  //R
                    btn_r_trig_next = 1'b1;
                end
                8'h4C: begin //L
                    btn_l_trig_next = 1'b1;
                end
                8'h55: begin //U
                    btn_u_trig_next = 1'b1;
                end
            endcase
        end
    end
endmodule
