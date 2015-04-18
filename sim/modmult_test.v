// This file is part of multiexp-a5gx.
//
// multiexp-a5gx is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.

`timescale 1ns / 1ps
module modmult_test ( );

reg clk, aclr;
reg [2:0] command;

initial begin
    clk     = '0;
    aclr    = '1;
    aclr    = #1 '0;
end

always @(clk) clk <= #4 ~clk;

localparam CMD_BEGINMULT    = 3'b010;
localparam CMD_BEGINSQUARE  = 3'b011;
localparam CMD_PRELOAD      = 3'b100;
localparam CMD_STORE        = 3'b101;

initial begin
    command = '0;
    command = #29 CMD_PRELOAD;
    command = #8 '0;
    command = #100 CMD_STORE;
    command = #8 '0;
    command = #100 CMD_BEGINMULT;
    command = #8 '0;
    repeat(5) begin
        command = #250 CMD_BEGINMULT;
        command = #8 '0;
        command = #250 CMD_BEGINSQUARE;
        command = #8 '0;
    end
end

wire [8:0] m_addr;
//reg [8:0] m_addr_d;
wire m_rden, m_wren, command_ack;
wire [26:0] m_datao;
reg [26:0] m_datai;


localparam b_offset = 4;
localparam w_width = 27;

initial begin
    m_datai <= '0;
    $srandom();
end

always @(posedge clk) m_datai <= $random() & ((m_addr[1:0] == 2'b11) ? {{(b_offset){1'b0}},{(w_width-b_offset){1'b1}}} : {(w_width){1'b1}});

/*
always @(posedge clk or posedge aclr) begin
    if (aclr) begin
        m_addr_d <= '0;
    end else begin
        m_addr_d <= m_addr;
    end
end
*/

modmult    #( .b_offset     (b_offset)
            , .last_factor  (1)
            , .factor_1     (4)
            ) imult   
            ( .m_addr       (m_addr)
            , .m_rden       (m_rden)
            , .m_wren       (m_wren)
            , .m_datao      (m_datao)
            , .m_datai      (m_datai)
            , .aclr         (aclr)
            , .clk          (clk)
            , .command      (command)
            , .command_ack  (command_ack)
            );

endmodule
