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

module multiexp_top    #( parameter                 fifo_widthu = 11
                        , parameter                 n_mult = 1
                        )
                        ( input                     clk
                        , input                     pcie_perstn
                        , input                     pcie_ready
                        , input                     user_resetn
                        , input                     pll_core_locked
                        , output                    ctrl_reset_n

                        , input     [31:0]          fifo_datai
                        , input                     fifo_empty
                        , output                    fifo_rden
                        , input     [fifo_widthu:0] fifo_usedw_in
                        , input                     pcie_writing

                        , output    [31:0]          fifo_datao
                        , output                    fifo_wren
                        , input     [fifo_widthu:0] fifo_usedw_out

                        , output    [3:0]           status_leds

                                            //  memory interface i/o (pin directly from toplevel)
                        , output    [12:0]          ddr3_a          // memory.mem_a
                        , output    [2:0]           ddr3_ba         //       .mem_ba
                        , output                    ddr3_ck_p       //       .mem_ck
                        , output                    ddr3_ck_n       //       .mem_ck_n
                        , output                    ddr3_cke        //       .mem_cke
                        , output                    ddr3_csn        //       .mem_cs_n
                        , output    [3:0]           ddr3_dm         //       .mem_dm
                        , output                    ddr3_rasn       //       .mem_ras_n
                        , output                    ddr3_casn       //       .mem_cas_n
                        , output                    ddr3_wen        //       .mem_we_n
                        , output                    ddr3_rstn       //       .mem_reset_n
                        , inout     [31:0]          ddr3_dq         //       .mem_dq
                        , inout     [3:0]           ddr3_dqs_p      //       .mem_dqs
                        , inout     [3:0]           ddr3_dqs_n      //       .mem_dqs_n
                        , output                    ddr3_odt        //       .mem_odt
                        , input                     ddr3_oct_rzq    //    oct.rzqin
                        , input                     clkin_100_p
                        );

    /* *** HOST INTERFACE COMMANDS ***
                                                MSB                              LSB
    LOAD_ERAM                                   000001 _ _____ ____________________
                                                     | |     |                    |
        command field (6'b000001) -------------------| |     |                    |
        load previous result from dram? (1 bit) -------|     |                    |
        e_ram select (5 bits) -------------------------------|                    |
        d_ram address of corresponding result (20 bits) ---------------------------

      This command should be followed by e_words * c_size words of the
      exponents in LSB->MSB order, in order corresponding to the TRAM
      values (i.e., the first exponent should correspond to TRAM address
      0, first base, the next to the TRAM address 0, second base, etc.)

      NOTE that when the load_result bit is 0, the controller will preload {'0,1'b1}
      instead of a value from RAM.

      When this command is finished, the controller responds with {4'h1,28'b0}.

    SET_ADDR                                    000010 _ _____ ____________________
                                                     | |     |                    |
        command field (6'b000001) -------------------| |     |                    |
        load previous result from dram? (1 bit) -------|     |                    |
        e_ram select (5 bits) -------------------------------|                    |
        d_ram address (20 bits) ---------------------------------------------------

      This command behaves much like LOAD_ERAM, except that it does not actually
      update the e_ram. It should be used when a multiplier does not need to be
      used in the next sequence of executions; the user should write an address
      to this multiplier such that next time its contents are written to dram
      (e.g., as the result of SET_ADDR or LOAD_ERAM) they do not overwrite a
      useful result. (One possibility is to set aside address 2^20-1 for this
      purpose.)

      When this command is finished, the controller responds with {4'h2,28'b0}.

    LOAD_TRAM                                   000100 ___________ _______________
                                                     |           |               |
        command field (6'b000010) -------------------|           |               |
        unused (11 bits) ----------------------------------------|               |
        tram start address (15 bits) --------------------------------------------|

      This command should be followed by 2 * n_words words of table values.
      The system computes the third table value and writes it to the table automatically.
      Note that alignment of the address is not checked, so the host must be
      sure to give an address correctly aligned to n_words!

      When this command is finished, the controller responds with {4'h3,28'b0}.

    READ_RESULT                                 001000 ______ ____________________
                                                     |      |                    |
        command field (6'b000100) -------------------|      |                    |
        unused (6 bits) ------------------------------------|                    |
        d_ram address of result to read (20 bits) -------------------------------|

      Reads n_words of a result out of DRAM.

      The controller responds with {4'h4,8'(n_words),address} followed by n_words of result.

    START_MULTIPLICATION                        100000 __________________________
                                                     |                          |
        command field (6'b010000) -------------------|                          |
        unused (26 bits) -------------------------------------------------------|

      A chunk of expmod batches. In other words, executes 16 * e_words * c_size
      multiplications and 32 * e_words - 1 squarings in each multiplier.

      When this command is finished, the controller responds with {4'h6,28'b0}.

    */

    // for now, these can't really be parameterized at this level.
    // Changes to allow full parameterization are pretty minor, though.
    localparam n_words = 40;
    localparam e_words = 4;
    localparam c_size = 1024;
    localparam gbits = 9;
    localparam ebits = 7;

    reg [6:0]   dcmd_reg, dcmd_next;

    wire [4:0]  d_unitsel;
    wire [8:0]  d_g_addr;
    wire        d_g_rden, d_g_wren;
    wire [26:0] d_g_data;
    wire        d_idle;
    wire d_active;

    reg [4:0]  unit_reg, unit_next;
    wire [4:0] unit_select = d_active ? d_unitsel : unit_reg;
    reg [8:0] g_addr_reg, g_addr_next;
    wire [8:0] g_addr = d_active ? d_g_addr : g_addr_reg;
    reg g_rden_reg, g_rden_next, g_wren_reg, g_wren_next;
    wire g_rden = d_active ? d_g_rden : g_rden_reg;
    wire g_wren = d_active ? d_g_wren : g_wren_reg;
    reg  [26:0] g_data_reg, g_data_next;
    wire [26:0] g_data = d_active ? d_g_data : g_data_reg;

    reg [14:0]  address_reg, address_next;

    wire [26:0] t_datai = g_data_reg;
    wire [14:0] t_wraddr = address_reg;
    reg  [2:0]  t_wren_reg, t_wren_next;
    wire [26:0] tdata_0, tdata_1, tdata_2;
    wire t_idle;
    reg  [1:0]  tcmd_reg, tcmd_next;

    wire [n_mult-1:0]   m_idle;
    reg  [2:0]          mcmd_reg, mcmd_next;

    // no tristate busses allowed inside the FPGA; we must mux
    wire [26:0] m_g_q[n_mult-1:0];
    reg  [26:0] g_q;
    always_comb begin
        if (unit_select < n_mult) begin
            g_q = m_g_q[unit_select];
        end else begin
            g_q = '0;
        end
    end

    wire [31:0] e_data, e_q;
    wire [11:0] e_addr;
    reg         e_wren_reg, e_wren_next;
    assign e_data = fifo_datai;
    assign e_addr = {~address_reg[1:0],address_reg[11:2]};
    /* e_addr explanation:

       we are getting a stream of data from the host
       0:LSB . . MSB
       1:LSB . . MSB
       ...

       What we want is to be able to scan through these like this

       MSB0 MSB1 MSB2 ... (M-1)SB0 (M-1)SB1 (M-1)SB2 ...

       So the LSB of the first word wants to go at address 3*1024
       The next byte of the 1st word wants to go at address 2*1024
       The next byte of the 1st word wants to go at address 1*1024
       Then the MSB of the 1st word wants to go at address 0*1024

       If address is counting up naturally, then it goes {'0,2'b00}, {'0,2'b01}, {'0,2b'10}, {'0,2'b11}
       If we invert the lsbits of address, then we get 11, 10, 01, 00, which are the multiples of 1024
       we want. Thus, we use the bottom two bits as the "bank select," and the top bits as the address.
       This gets us the memory layout we want for the e_rams.
    */

    reg [2:0]   state_reg, state_next;

    `include "mult_commands.vh"

    localparam ST_IDLE           = 3'b000;
    localparam ST_INTERPRET      = 3'b001;
    localparam ST_LOAD_ERAM      = 3'b010;
    localparam ST_LOAD_TRAM      = 3'b011;
    localparam ST_READ_RESULT    = 3'b100;
    localparam ST_START_MULT     = 3'b110;

    localparam CMD_LOAD_ERAM     = 6'b000001;
    localparam CMD_SET_ADDR      = 6'b000010;
    localparam CMD_LOAD_TRAM     = 6'b000100;
    localparam CMD_READ_RESULT   = 6'b001000;
    localparam CMD_START_MULT    = 6'b100000;

    localparam CMD_D_GRAM2DRAM   = 2'b10;
    localparam CMD_D_DRAM2GRAM   = 2'b11;
    localparam CMD_D_BLANKGRAM   = 2'b01;

    localparam CMD_T_START       = 2'b01;
    localparam CMD_T_RESET       = 2'b10;
    localparam CMD_T_ABORT       = 2'b11;

    localparam CMD_M_RSTCOUNT    = 3'b111;

    wire inST_IDLE              = state_reg == ST_IDLE;
    wire inST_INTERPRET         = state_reg == ST_INTERPRET;
    wire inST_LOAD_ERAM         = state_reg == ST_LOAD_ERAM;
    wire inST_LOAD_TRAM         = state_reg == ST_LOAD_TRAM;
    wire inST_READ_RESULT       = state_reg == ST_READ_RESULT;
    wire inST_START_MULT        = state_reg == ST_START_MULT;

    reg [31:0]  fifo_datao_reg, fifo_datao_next;
    reg         fifo_rden_reg, fifo_rden_next, fifo_wren_reg, fifo_wren_next;
    reg         loadprev_reg, loadprev_next;
    assign fifo_datao = fifo_datao_reg;
    assign fifo_rden = fifo_rden_reg;
    assign fifo_wren = fifo_wren_reg;
    wire [5:0] command_in = fifo_datai[31:26];
    wire fifo_full = fifo_usedw_out[fifo_widthu];

    assign d_active = (d_g_rden | d_g_wren) & ~inST_READ_RESULT;

    wire rfifo_has_40        = fifo_usedw_in > (n_words - 1);
    wire wfifo_has_space     = (fifo_usedw_out + n_words + 1) < (1 << fifo_widthu);

    wire load_eram_last     = address_reg[11:0] == {12{1'b1}};
    wire load_eram_alast    = address_reg[11:0] == {{11{1'b1}},1'b0};

    wire load_tram_tlast    = g_addr_reg[5:0] == (n_words + 1);
    wire load_tram_last     = g_addr_reg[5:0] == (n_words - 1);
    wire load_tram_aalast   = g_addr_reg[5:0] == (n_words - 3);
    wire load_tram_mstart   = g_addr_reg[5:0] == 6'd1;

    reg delay_reg, delay_next;

    wire m_idle_all     = m_idle == {n_mult{1'b1}};
    wire square_time    = address_reg[gbits-1:0] == {gbits{1'b1}};
    wire fmult_time     = g_addr_reg[ebits-1:0] == {ebits{1'b1}};

    assign status_leds = {~m_idle_all, ~inST_START_MULT, ~inST_LOAD_ERAM, ~inST_LOAD_TRAM};

    always_comb begin
        dcmd_next = dcmd_reg;
        unit_next = unit_reg;
        g_addr_next = g_addr_reg;
        g_rden_next = g_rden_reg;
        g_wren_next = g_wren_reg;
        g_data_next = g_data_reg;
        t_wren_next = t_wren_reg;
        tcmd_next = tcmd_reg;
        mcmd_next = mcmd_reg;
        e_wren_next = e_wren_reg;
        state_next = state_reg;
        address_next = address_reg;
        fifo_datao_next = fifo_datao_reg;
        fifo_rden_next = fifo_rden_reg;
        fifo_wren_next = fifo_wren_reg;
        loadprev_next = loadprev_reg;
        delay_next = '0;

        case (state_reg)
            ST_IDLE: begin
                dcmd_next = '0;
                g_addr_next = '0;
                g_rden_next = '0;
                g_wren_next = '0;
                g_data_next = '0;
                t_wren_next = '0;
                tcmd_next = '0;
                mcmd_next = '0;
                e_wren_next = '0;
                state_next = ST_IDLE;
                address_next = '0;
                fifo_datao_next = '0;
                fifo_rden_next = '1;
                fifo_wren_next = '0;
                loadprev_next = '0;
                delay_next = '0;

                if (fifo_rden_reg & ~fifo_empty) begin
                    fifo_rden_next = '0;
                    state_next = ST_INTERPRET;
                end
            end

            ST_INTERPRET: begin
                case (command_in)
                    CMD_SET_ADDR, CMD_LOAD_ERAM: begin
                        if (g_rden_reg) begin
                            g_rden_next = '0;
                            g_data_next = {7'b0,fifo_datai[19:0]};
                            g_wren_next = '1;
                        end else if (g_wren_reg) begin
                            g_data_next = {7'b0,g_q[19:0]};
                            g_addr_next = 9'd193;
                            loadprev_next = fifo_datai[25];
                            if (command_in == CMD_SET_ADDR) begin
                                address_next[14] = '1;
                            end else begin
                                address_next[14] = '0;
                            end
                            state_next = ST_LOAD_ERAM;
                        end else begin
                            unit_next = fifo_datai[24:20];
                            g_addr_next = 9'd192;
                            g_rden_next = '1;
                        end
                    end

                    CMD_LOAD_TRAM: begin
                        // spin here, waiting for fifo to be sufficiently full
                        // such that we will be able to read in everything at
                        // once
                        if (rfifo_has_40) begin
                            address_next = fifo_datai[14:0];
                            g_addr_next = 9'd64;
                            fifo_rden_next = '1;
                            unit_next = '0;
                            delay_next = '1;
                            state_next = ST_LOAD_TRAM;
                        end
                    end

                    CMD_READ_RESULT: begin
                        // block until we have space for the whole thing
                        if (wfifo_has_space) begin
                            delay_next = '1;
                            dcmd_next = {CMD_D_DRAM2GRAM,5'b11100};
                            state_next = ST_READ_RESULT;
                            fifo_datao_next = {4'h4,8'(n_words),fifo_datai[19:0]};
                            fifo_wren_next = '1;
                        end
                    end

                    CMD_START_MULT: begin
                        if (tcmd_reg == CMD_T_RESET) begin
                            tcmd_next = CMD_T_START;
                            mcmd_next = CMD_BEGINMULT;
                            delay_next = '1;
                            state_next = ST_START_MULT;
                        end else begin
                            // make sure table controller is in the correct state
                            tcmd_next = CMD_T_RESET;
                            mcmd_next = CMD_M_RSTCOUNT;
                            unit_next = 5'b11111;
                            address_next = '0;
                            g_addr_next = '0;
                            loadprev_next = '0;
                        end
                    end

                    default: begin
                        // I can't do that, Dave.
                        state_next = ST_IDLE;
                    end
                endcase
            end

            ST_START_MULT: begin
                mcmd_next = '0;
                if (tcmd_reg != CMD_T_RESET) begin
                    tcmd_next = '0;
                end

                if (fifo_wren_reg) begin
                    if (~fifo_full) begin
                        fifo_wren_next = '0;
                        state_next = ST_IDLE;
                    end
                end else if (~delay_reg & loadprev_reg & m_idle_all) begin
                    fifo_wren_next = '1;
                    fifo_datao_next = {4'h6,28'b0};
                    if (~fifo_full) begin
                        state_next = ST_IDLE;
                    end
                end else if (~delay_reg & (tcmd_reg == CMD_T_RESET) & m_idle_all) begin
                    tcmd_next = '0;
                    if (fmult_time) begin
                        loadprev_next = '1;
                        delay_next = '1;
                        mcmd_next = CMD_STORE;
                    end else begin
                        address_next = '0;
                        g_addr_next = g_addr_reg + 1'b1;
                        delay_next = '1;
                        tcmd_next = CMD_T_START;
                        mcmd_next = CMD_BEGINMULT;
                    end
                end else if (~delay_reg & m_idle_all) begin
                    if (~t_idle) begin
                        tcmd_next = CMD_T_ABORT;
                        delay_next = '1;
                    end else begin
                        delay_next = '1;
                        if (square_time) begin
                            tcmd_next = CMD_T_RESET;
                            if (fmult_time) begin
                                // we're done; chain with previously loaded result
                                mcmd_next = CMD_BEGINRAMMULT;
                            end else begin
                                // square and continue multiplying
                                mcmd_next = CMD_BEGINSQUARE;
                            end
                        end else begin
                            address_next = address_reg + 1'b1;
                            tcmd_next = CMD_T_START;
                            mcmd_next = CMD_BEGINMULT;
                        end
                    end
                end
            end

            ST_READ_RESULT: begin
                if (delay_reg) begin
                    dcmd_next = '0;
                    fifo_wren_next = '0;
                end else begin
                    if (~d_idle) begin
                        fifo_wren_next = d_g_wren;
                        fifo_datao_next = {5'b0,d_g_data};
                    end else begin
                        fifo_wren_next = '0;
                        state_next = ST_IDLE;
                    end
                end
            end

            ST_LOAD_TRAM: begin
                if (g_addr_reg[7:6] == 2'b01) begin
                    // first phase: read in g_0
                    if (delay_reg) begin
                        t_wren_next = '0;
                        g_wren_next = '0;
                    end else begin
                        g_data_next = fifo_datai[26:0];

                        if (fifo_rden_reg | g_wren_reg) begin
                            // we've gotten here, so we know that the FIFO will
                            // not be empty before we're done with this phase
                            g_wren_next = '1;
                            t_wren_next = 3'b001;

                            if (g_wren_reg) begin
                                if (load_tram_aalast) begin
                                    fifo_rden_next = '0;
                                end

                                if (load_tram_last) begin
                                    g_wren_next = '0;
                                    t_wren_next = '0;
                                end else begin
                                    g_addr_next = g_addr_reg + 1'b1;
                                    address_next = address_reg + 1'b1;
                                end
                            end

                            // as we're writing this into memory, read it into the
                            // result register
                            if (load_tram_mstart) begin
                                mcmd_next = CMD_PRELOAD;
                            end else begin
                                mcmd_next = '0;
                            end
                        end else begin
                            if (rfifo_has_40) begin
                                g_addr_next = '0;
                                address_next = address_reg - 6'd39;
                                fifo_rden_next = '1;
                                delay_next = '1;
                            end
                        end
                    end
                end else if (g_addr_reg[7:6] == 2'b00) begin
                    // second phase: read in g_1
                    if (delay_reg) begin
                        t_wren_next = '0;
                        g_wren_next = '0;
                    end else begin
                        g_data_next = fifo_datai[26:0];

                        if (fifo_rden_reg | g_wren_reg) begin
                            g_wren_next = '1;
                            t_wren_next = 3'b010;

                            if (g_wren_reg) begin
                                if (load_tram_aalast) begin
                                    fifo_rden_next = '0;
                                end

                                if (load_tram_last) begin
                                    g_wren_next = '0;
                                    t_wren_next = '0;
                                end else begin
                                    g_addr_next = g_addr_reg + 1'b1;
                                    address_next = address_reg + 1'b1;
                                end
                            end

                            // as we're writing this into memory, start
                            // multiplication
                            if (load_tram_mstart) begin
                                mcmd_next = CMD_BEGINRAMMULT;
                            end else begin
                                mcmd_next = '0;
                            end
                        end else begin
                            if (m_idle[0]) begin
                                // multiplication is finished; read out result
                                mcmd_next = CMD_STORE;
                                g_addr_next = 9'b110111110;
                                address_next = address_reg - 6'd39;
                            end
                        end
                    end
                end else if (fifo_wren_reg) begin
                    // block here until the write fifo is clear to write back
                    // the response to the host
                    if (~fifo_full) begin
                        fifo_wren_next = '0;
                        state_next = ST_IDLE;
                    end
                end else begin
                    // third phase: read multiplication result
                    g_data_next = g_q[26:0];
                    mcmd_next = '0;

                    if (~g_rden_reg & ~t_wren_reg[2]) begin
                        // allow a few cycles for the multiplier to start storing the result
                        if (load_tram_mstart) begin
                            g_addr_next = 9'd128;
                            g_rden_next = '1;
                            delay_next = '1;
                        end else begin
                            g_addr_next = g_addr_reg + 1'b1;
                        end
                    end else begin
                        g_addr_next = g_addr_reg + 1'b1;

                        if (~delay_reg) begin
                            t_wren_next = 3'b100;

                            if (t_wren_reg[2]) begin
                                if (load_tram_tlast) begin
                                    address_next = '0;
                                    t_wren_next = '0;
                                    fifo_datao_next = {4'h3,28'b0};
                                    fifo_wren_next = '1;
                                    // write back response to host
                                    if (~fifo_full) begin
                                        state_next = ST_IDLE;
                                    end
                                end else begin
                                    address_next = address_reg + 1'b1;
                                end
                            end
                        end

                        if (load_tram_last) begin
                            g_rden_next = '0;
                        end
                    end
                end
            end

            ST_LOAD_ERAM: begin
                if (g_wren_reg) begin
                    g_wren_next = '0;
                    if (~address_reg[14]) begin
                        fifo_rden_next = '1;
                    end
                    dcmd_next = {CMD_D_GRAM2DRAM,unit_reg};
                    mcmd_next = CMD_RESETRESULT;
                end else begin
                    mcmd_next = '0;
                    e_wren_next = '0;

                    if (dcmd_reg != 2'b00) begin
                        dcmd_next = '0;
                    end else if (~address_reg[12] & d_idle) begin
                        address_next[12] = 1'b1;
                        if (loadprev_reg) begin
                            dcmd_next = {CMD_D_DRAM2GRAM,unit_reg};
                            delay_next = '1;
                        end else begin
                            dcmd_next = {CMD_D_BLANKGRAM,unit_reg};
                            delay_next = '1;
                        end
                    end

                    if (~address_reg[14]) begin
                        if (~address_reg[13]) begin
                            if (e_wren_reg) begin
                                if (load_eram_last) begin
                                    address_next[13] = 1'b1;
                                    fifo_rden_next = '0;
                                    e_wren_next = '0;
                                end else begin
                                    address_next[11:0] = address_next[11:0] + 1'b1;
                                end
                            end

                            if (~fifo_empty & fifo_rden_reg) begin
                                if ( (load_eram_alast & e_wren_reg) | load_eram_last ) begin
                                    // either we're currently writing the second-last value,
                                    // or we did at some point in the past, so this is the
                                    // final time we should read from the FIFO
                                    fifo_rden_next = '0;
                                end

                                e_wren_next = '1;
                            end
                        end else begin
                            if (fifo_wren_reg) begin
                                // wait until we can write our status word to the fifo
                                if (~fifo_full) begin
                                    address_next = '0;
                                    fifo_wren_next = '0;
                                    state_next = ST_IDLE;
                                end
                            end else if (address_reg[12] & d_idle & ~delay_reg) begin
                                fifo_datao_next = {4'h1,28'b0};
                                fifo_wren_next = '1;
                                if (~fifo_full) begin
                                    address_next = '0;
                                    state_next = ST_IDLE;
                                end
                            end
                        end
                    end else begin
                        if (fifo_wren_reg) begin
                            if (~fifo_full) begin
                                address_next = '0;
                                fifo_wren_next = '0;
                                state_next = ST_IDLE;
                            end
                        end else if (address_reg[12] & d_idle & ~delay_reg) begin
                            fifo_datao_next = {4'h2,28'b0};
                            fifo_wren_next = '1;
                            if (~fifo_full) begin
                                address_next ='0;
                                state_next = ST_IDLE;
                            end
                        end
                    end
                end
            end

            default: begin
                state_next = ST_IDLE;
            end
        endcase
    end

    always_ff @(posedge clk or negedge ctrl_reset_n) begin
        if (~ctrl_reset_n) begin
            dcmd_reg        <= '0;
            unit_reg        <= '0;
            g_addr_reg      <= '0;
            g_rden_reg      <= '0;
            g_wren_reg      <= '0;
            g_data_reg      <= '0;
            t_wren_reg      <= '0;
            tcmd_reg        <= '0;
            mcmd_reg        <= '0;
            e_wren_reg      <= '0;
            state_reg       <= '0;
            address_reg     <= '0;
            fifo_datao_reg  <= '0;
            fifo_rden_reg   <= '0;
            fifo_wren_reg   <= '0;
            loadprev_reg    <= '0;
            delay_reg       <= '0;
        end else begin
            dcmd_reg        <= dcmd_next;
            unit_reg        <= unit_next;
            g_addr_reg      <= g_addr_next;
            g_rden_reg      <= g_rden_next;
            g_wren_reg      <= g_wren_next;
            g_data_reg      <= g_data_next;
            t_wren_reg      <= t_wren_next;
            tcmd_reg        <= tcmd_next;
            mcmd_reg        <= mcmd_next;
            e_wren_reg      <= e_wren_next;
            state_reg       <= state_next;
            address_reg     <= address_next;
            fifo_datao_reg  <= fifo_datao_next;
            fifo_rden_reg   <= fifo_rden_next;
            fifo_wren_reg   <= fifo_wren_next;
            loadprev_reg    <= loadprev_next;
            delay_reg       <= delay_next;
        end
    end

    dram_control idram  ( .clk              (clk)
                        , .pcie_perstn      (pcie_perstn)
                        , .pcie_ready       (pcie_ready & pll_core_locked)
                        , .user_resetn      (user_resetn)
                        , .ctrl_reset_n     (ctrl_reset_n)
                        , .command          (dcmd_reg)
                        , .g_mem_addr       ({d_unitsel, d_g_addr})
                        , .g_mem_wren       (d_g_wren)
                        , .g_mem_rden       (d_g_rden)
                        , .g_mem_datai      (d_g_data)
                        , .g_mem_datao      (g_q)
                        , .addr_direct      (fifo_datai[19:0])
                        , .ddr3_a           (ddr3_a)
                        , .ddr3_ba          (ddr3_ba)
                        , .ddr3_ck_p        (ddr3_ck_p)
                        , .ddr3_ck_n        (ddr3_ck_n)
                        , .ddr3_cke         (ddr3_cke)
                        , .ddr3_csn         (ddr3_csn)
                        , .ddr3_dm          (ddr3_dm)
                        , .ddr3_rasn        (ddr3_rasn)
                        , .ddr3_casn        (ddr3_casn)
                        , .ddr3_wen         (ddr3_wen)
                        , .ddr3_rstn        (ddr3_rstn)
                        , .ddr3_dq          (ddr3_dq)
                        , .ddr3_dqs_p       (ddr3_dqs_p)
                        , .ddr3_dqs_n       (ddr3_dqs_n)
                        , .ddr3_odt         (ddr3_odt)
                        , .ddr3_oct_rzq     (ddr3_oct_rzq)
                        , .clkin_100_p      (clkin_100_p)
                        , .idle             (d_idle)
                        );

    table_control itabl ( .clk              (clk)
                        , .ctrl_reset_n     (ctrl_reset_n)
                        , .tdatai           (t_datai)
                        , .twraddr          (t_wraddr)
                        , .twren            (t_wren_reg)
                        , .tdata_0          (tdata_0)
                        , .tdata_1          (tdata_1)
                        , .tdata_2          (tdata_2)
                        , .command          (tcmd_reg)
                        , .idle             (t_idle)
                        );

    genvar MGen;
    generate for(MGen=0; MGen<n_mult; MGen++) begin: MGenIter
        mult_unit          #( .mult_addr        (MGen)
                            ) imult     
                            ( .clk              (clk)
                            , .ctrl_reset_n     (ctrl_reset_n)
                            , .unit_select      (unit_select)
                            , .g_addr           (g_addr)
                            , .g_data           (g_data)
                            , .g_rden           (g_rden)
                            , .g_wren           (g_wren)
                            , .g_q              (m_g_q[MGen])
                            , .e_wraddr         (e_addr)
                            , .e_data           (e_data)
                            , .e_wren           (e_wren_reg)
                            , .command          (mcmd_reg)
                            , .idle             (m_idle[MGen])
                            , .tdata_0          (tdata_0)
                            , .tdata_1          (tdata_1)
                            , .tdata_2          (tdata_2)
                            );
    end
    endgenerate

endmodule
