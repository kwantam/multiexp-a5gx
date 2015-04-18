//synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2005
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

module mult_unit   #( parameter                     mult_addr   = 0
                    , parameter                     e_words     = 4
                    , parameter                     c_size      = 1024
            // vvvvvv THESE SHOULD BE LOCALPARAMS. DO NOT EDIT OR OVERRIDE vvvvvv //
                    , parameter                     ebits = $clog2(e_words)
                    , parameter                     cbits = $clog2(c_size)
                    )
                    ( input                         clk
                    , input                         ctrl_reset_n
                        
                    // dispatcher interface
                    , input     [4:0]               unit_select     
                    , input     [8:0]               g_addr
                    , input     [26:0]              g_data
                    , input                         g_rden
                    , input                         g_wren
                    , output    [26:0]              g_q
                    , input     [ebits+cbits-1:0]   e_wraddr
                    , input     [31:0]              e_data
                    , input                         e_wren
                    , input     [2:0]               command
                    , output                        idle

                    // table_control interface
                    , input     [26:0]              tdata_0
                    , input     [26:0]              tdata_1
                    , input     [26:0]              tdata_2
                    );

    wire reset = ~ctrl_reset_n;
    wire this_unit_selected = (unit_select == 5'b11111) | (unit_select == mult_addr);
    wire [2:0] command_int = this_unit_selected ? command : '0;
    reg [2:0] command_reg, command_next;
    wire command_ack;

    reg [26:0] t_data_reg, t_data_next, t_data_sel;
    wire [31:0] e_q;
    reg [1:0] exp_reg, exp_next;

    // keep track of which exponent we're in
    reg [4:0] bitnum_reg, bitnum_next;
    reg [ebits-1:0] wordnum_reg, wordnum_next;
    reg [cbits-1:0] basenum_reg, basenum_next;
    wire [cbits+ebits-1:0] e_rdaddr = {wordnum_reg,basenum_reg};

    `include "mult_commands.vh"
    localparam CMD_RSTCOUNT      = 3'b111;
    // as an incoming command, resets the count

    reg [1:0] state_reg, state_next;
    reg [5:0] count_reg, count_next;

    localparam ST_IDLE = 2'b00;
    localparam ST_MDLY = 2'b01;
    localparam ST_MULT = 2'b10;
    localparam ST_BUSY = 2'b11;

    wire inST_IDLE = state_reg == ST_IDLE;
    wire inST_MDLY = state_reg == ST_MDLY;
    wire inST_MULT = state_reg == ST_MULT;
    wire inST_BUSY = state_reg == ST_BUSY;

    wire nextST_MDLY = inST_IDLE & (command_int == CMD_BEGINMULT);

    wire last_count = count_reg == 39;

    assign idle = inST_IDLE;
    wire e_rden = nextST_MDLY | inST_MDLY;
    wire e_wren_int = e_wren & this_unit_selected;

    // mux for t_data_sel
    always_comb begin
        case (exp_reg)
            2'b01: t_data_sel = tdata_0;
            2'b10: t_data_sel = tdata_1;
            default: t_data_sel = tdata_2;
        endcase
    end

    always_comb begin
        command_next = command_reg;
        t_data_next = t_data_reg;
        exp_next = exp_reg;
        bitnum_next = bitnum_reg;
        wordnum_next = wordnum_reg;
        basenum_next = basenum_reg;
        state_next = state_reg;
        count_next = count_reg;

        case (state_reg)
            ST_IDLE: begin
                case (command_int)
                    CMD_RSTCOUNT: begin
                        count_next = '0;
                        wordnum_next = '0;
                        basenum_next = '0;
                        bitnum_next = '1;
                    end

                    CMD_BEGINSQUARE: begin
                        command_next = command;
                        state_next = ST_BUSY;
                        // when we square, that means we're on to the next "line" in the exp
                        bitnum_next = bitnum_reg - 1'b1;        // decrement bit number
                        basenum_next = '0;                      // restart on the 1st base
                        if (bitnum_reg == '0) begin             // increment wordnum if bitnum wraps
                            wordnum_next = wordnum_reg + 1'b1;
                        end
                    end

                    CMD_BEGINMULT: begin
                        state_next = ST_MDLY;
                        count_next = '1;
                        basenum_next = basenum_reg + 1'b1;
                    end

                    CMD_BEGINRAMMULT, CMD_RESETRESULT, CMD_PRELOAD, CMD_STORE: begin
                        command_next = command;
                        state_next = ST_BUSY;
                    end

                    default: state_next = ST_IDLE;
                endcase
            end

            ST_MDLY: begin
                if (count_reg == '0) begin
                    exp_next[1] = e_q[bitnum_reg];
                    if ({e_q[bitnum_reg],exp_reg[0]} == 2'b00) begin    // exponent is 0, do not multiply
                        command_next = '0;
                        count_next = '0;
                        state_next = ST_IDLE;
                    end else begin
                        command_next = CMD_BEGINMULT;
                        count_next = '1;
                        state_next = ST_MULT;
                    end
                end else begin
                    basenum_next = basenum_reg + 1'b1;
                    count_next = count_reg + 1'b1;
                    exp_next[0] = e_q[bitnum_reg];
                end
            end

            ST_MULT: begin
                t_data_next = t_data_sel;
                if (last_count) begin
                    count_next = '0;
                    command_next = CMD_INVALID;
                    state_next = ST_BUSY;
                end else begin
                    count_next = count_reg + 1'b1;
                end
            end

            ST_BUSY: begin
                command_next = '0;
                if (command_reg == '0) begin
                    // we are waiting for the multiplier to finish
                    if (command_ack) begin
                        state_next = ST_IDLE;
                    end
                end
            end
        endcase
    end

    always_ff @(posedge clk or negedge ctrl_reset_n) begin
        if (~ctrl_reset_n) begin
            command_reg     <= '0;
            t_data_reg      <= '0;
            exp_reg         <= '0;
            bitnum_reg      <= '1;
            wordnum_reg     <= '0;
            basenum_reg     <= '0;
            state_reg       <= '0;
            count_reg       <= '0;
        end else begin
            command_reg     <= command_next;
            t_data_reg      <= t_data_next;
            exp_reg         <= exp_next;
            bitnum_reg      <= bitnum_next;
            wordnum_reg     <= wordnum_next;
            basenum_reg     <= basenum_next;
            state_reg       <= state_next;
            count_reg       <= count_next;
        end
    end

    wire g_rden_a = g_rden & this_unit_selected;
    wire g_wren_a = g_wren & this_unit_selected;
    wire [31:0] g_q_a;
    assign g_q = g_q_a[26:0];
    wire [31:0] g_data_a = {5'b0,g_data};
    wire [8:0] g_addr_a = g_addr;

    wire [26:0] g_data_b;
    wire [31:0] g_q_b;
    wire [8:0] g_addr_b;
    wire g_rden_b, g_wren_b;

    // SRAM containing the exponents
    e_ram einst ( .aclr                 (reset)
                , .clock                (clk)
                , .data                 (e_data)
                , .wraddress            (e_wraddr)
                , .wren                 (e_wren_int)
                , .rdaddress            (e_rdaddr)
                , .rden                 (e_rden)
                , .q                    (e_q)
                );

    // SRAM used by the multiplier for loading/storing intermediate results
    g_ram ginst ( .aclr                 (reset)
                , .clock                (clk)
                , .address_a            (g_addr_a)
                , .data_a               (g_data_a)
                , .rden_a               (g_rden_a)
                , .wren_a               (g_wren_a)
                , .q_a                  (g_q_a)
                , .address_b            (g_addr_b)
                , .data_b               ({5'b0,g_data_b})
                , .rden_b               (g_rden_b)
                , .wren_b               (g_wren_b)
                , .q_b                  (g_q_b)
                );

    // multiplier
    modmult    #( .n_words              (40)
                , .w_width              (27)
                , .b_offset             (3)
                , .last_factor          (1)
                , .factor_1             (5)
                ) multins
                ( .m_addr               (g_addr_b)
                , .m_rden               (g_rden_b)
                , .m_wren               (g_wren_b)
                , .m_datao              (g_data_b)
                , .m_datai              (g_q_b[26:0])
                , .t_datai              (t_data_reg)
                , .aclr                 (reset)
                , .clk                  (clk)
                , .command              (command_reg)
                , .command_ack          (command_ack)
                );

endmodule
