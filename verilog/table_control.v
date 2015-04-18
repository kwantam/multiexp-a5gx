// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2005
//
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

module table_control   #( parameter         n_words = 40
                        )
                        ( input             clk
                        , input             ctrl_reset_n

                        , input     [26:0]  tdatai          // dispatch intf to tables
                        , input     [14:0]  twraddr
                        , input     [2:0]   twren

                        , output    [26:0]  tdata_0
                        , output    [26:0]  tdata_1
                        , output    [26:0]  tdata_2

                        , input     [1:0]   command

                        , output            idle
                        );

    localparam wbits = $clog2(n_words);

    wire    [26:0]  tdatao [2:0];
    assign tdata_0 = tdatao[0];
    assign tdata_1 = tdatao[1];
    assign tdata_2 = tdatao[2];

    reg [14:0]      trdaddr_reg, trdaddr_next;
    reg             trden_reg, trden_next;
    reg [wbits-1:0] count_reg, count_next;
    reg             state_reg, state_next;

    localparam   ST_IDLE = 1'b0;
    localparam   ST_STRM = 1'b1;

    wire    inST_IDLE = state_reg == ST_IDLE;
    wire    inST_STRM = state_reg == ST_STRM;

    localparam   CMD_START = 2'b01;
    localparam   CMD_RESET = 2'b10;
    localparam   CMD_ABORT = 2'b11;

    wire gotCMD_ABORT = command == CMD_ABORT;

    wire [14:0] trdaddr = trdaddr_reg + {{(15-wbits){1'b0}},count_reg};
    wire last_count = count_reg == (n_words - 1);

    assign idle = inST_IDLE;

    always_comb begin
        trdaddr_next = trdaddr_reg;
        trden_next = trden_reg;
        count_next = count_reg;
        state_next = state_reg;

        case (state_reg)
            ST_IDLE: begin
                if (~trden_reg) begin
                    case (command)
                        CMD_RESET: begin
                            trdaddr_next = '0;
                            trden_next = '0;
                            count_next = '0;
                        end 
                        
                        CMD_START: begin
                            trden_next = '1;
                            count_next = '0;
                        end

                        default: state_next = ST_IDLE;
                    endcase
                end else begin
                    state_next = ST_STRM;
                    count_next = count_reg + 1'b1;
                end
            end

            ST_STRM: begin
                if (last_count | gotCMD_ABORT) begin
                    trden_next = '0;
                    count_next = '0;
                    trdaddr_next = trdaddr_reg + n_words;
                    state_next = ST_IDLE;
                end else begin
                    count_next = count_reg + 1'b1;
                end
            end
        endcase
    end

    always_ff @(posedge clk or negedge ctrl_reset_n) begin
        if (~ctrl_reset_n) begin
            trdaddr_reg     <= '0;
            trden_reg       <= '0;
            count_reg       <= '0;
            state_reg       <= '0;
        end else begin
            trdaddr_reg     <= trdaddr_next;
            trden_reg       <= trden_next;
            count_reg       <= count_next;
            state_reg       <= state_next;
        end
    end

    genvar TGen;
    generate for(TGen=0; TGen<3; TGen++) begin: TGenInst
        t_ram ramins( .aclr         (~ctrl_reset_n)
                    , .clock        (clk)
                    , .data         (tdatai)
                    , .wraddress    (twraddr)
                    , .wren         (twren[TGen])
                    , .rden         (trden_reg)
                    , .rdaddress    (trdaddr)
                    , .q            (tdatao[TGen])
                    );
    end
    endgenerate

endmodule
