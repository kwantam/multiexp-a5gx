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

module dram_control
                   #( parameter         n_words = 40
                    , parameter         w_width = 27
            // vvvvvv THESE SHOULD BE LOCALPARAMS. DO NOT EDIT OR OVERRIDE vvvvvv //
                    , parameter         wbits = $clog2(n_words)
                    )
                    ( input             clk
                    , input             pcie_perstn
                    , input             pcie_ready
                    , input             user_resetn
                    , output            ctrl_reset_n

                    , input     [6:0]   command

                    , output    [13:0]  g_mem_addr
                    , output            g_mem_wren
                    , output            g_mem_rden
                    , output    [w_width-1:0]   g_mem_datai
                    , input     [w_width-1:0]   g_mem_datao

                    , input     [25-wbits:0]    addr_direct

                    //  memory interface i/o (pin directly from toplevel)
                    , output    [12:0]  ddr3_a          // memory.mem_a
                    , output    [2:0]   ddr3_ba         //       .mem_ba
                    , output            ddr3_ck_p       //       .mem_ck
                    , output            ddr3_ck_n       //       .mem_ck_n
                    , output            ddr3_cke        //       .mem_cke
                    , output            ddr3_csn        //       .mem_cs_n
                    , output    [3:0]   ddr3_dm         //       .mem_dm
                    , output            ddr3_rasn       //       .mem_ras_n
                    , output            ddr3_casn       //       .mem_cas_n
                    , output            ddr3_wen        //       .mem_we_n
                    , output            ddr3_rstn       //       .mem_reset_n
                    , inout     [31:0]  ddr3_dq         //       .mem_dq
                    , inout     [3:0]   ddr3_dqs_p      //       .mem_dqs
                    , inout     [3:0]   ddr3_dqs_n      //       .mem_dqs_n
                    , output            ddr3_odt        //       .mem_odt
                    , input             ddr3_oct_rzq    //    oct.rzqin
                    , input             clkin_100_p

                    , output            idle
                    );

    localparam fifodepth = 1 << wbits;

    wire mem_ready, mrdata_valid, pll_locked, cal_success, mpfe_reset_n, global_reset_n, init_done, mrden, mwren;
    wire [31:0] mrdata, mwdata;
    reg [w_width-1:0] gdata_reg, gdata_next;
    assign mwdata[31:w_width] = '0;
    assign g_mem_datai = gdata_reg;

    reg [1:0] state_reg, state_next;

    localparam ST_IDLE   = 2'b00;
    localparam ST_ADDR   = 2'b01;
    localparam ST_READ   = 2'b10;
    localparam ST_WRITE  = 2'b11;

    wire inST_IDLE  = state_reg == ST_IDLE;
    wire inST_ADDR  = state_reg == ST_ADDR;     // get addr from g_mem
    wire inST_READ  = state_reg == ST_READ;     // read from g_mem into RAM
    wire inST_WRITE = state_reg == ST_WRITE;    // write from RAM into g_mem

    reg [wbits-1:0] count_reg, count_next;
    wire last_count = count_reg == (n_words - 1);
    wire count_is_3 = count_reg == {{(wbits-2){1'b0}},2'b11};

    localparam SEG_ADDR      = 2'b11;
    localparam SEG_PRELOAD   = 2'b00;
    localparam SEG_STORE     = 2'b10;

    reg [1:0] saddr_reg, saddr_next;
    reg [5:0] command_reg, command_next;
    assign g_mem_addr = {command_reg[4:0],{(7-wbits){1'b0}},saddr_reg,count_reg};

    reg grden_reg, grden_next, gwren_reg, gwren_next;
    assign g_mem_wren = gwren_reg;
    assign g_mem_rden = grden_reg;

    wire empty;
    assign mwren = inST_READ;
    wire rdreq = (inST_READ & mem_ready) | (inST_ADDR & count_is_3);
    reg wrreq_reg, wrreq_next;

    reg mrden_reg, mrden_next;
    reg begin_reg, begin_next;
    reg [25-wbits:0] maddr_reg, maddr_next;
    wire [25:0] maddr = {maddr_reg,{(wbits){1'b0}}};

    assign idle = inST_IDLE;

    // illegal unit address (28) indicates we should read address directly from dispatch
    wire do_direct_write = &command[6:2];

    always_comb begin
        command_next = command_reg;
        state_next = state_reg;
        count_next = count_reg;
        saddr_next = saddr_reg;
        grden_next = grden_reg;
        gwren_next = '0;
        gdata_next = gdata_reg;
        mrden_next = mrden_reg;
        begin_next = '0;
        maddr_next = maddr_reg;
        wrreq_next = wrreq_reg;

        case (state_reg)
            ST_IDLE: begin
                if (do_direct_write) begin
                    command_next = {6'b111100};
                    maddr_next = addr_direct;
                    state_next = ST_WRITE;
                    count_next = '0;
                    mrden_next = '1;
                    begin_next = '1;
                end else if (command[6]) begin
                    state_next = ST_ADDR;
                    command_next = command[5:0];
                    grden_next = '1;
                    // address 0 if writing (to preload area), address 1 if reading (from store area)
                    count_next = {{(wbits-1){1'b0}},~command[5]};
                    // 11 segment stores addresses
                    saddr_next = SEG_ADDR;
                end else if (command[5]) begin
                    // going into ST_WRITE with command_reg[5] == 0 enables "clear" action
                    command_next = {1'b0,command[4:0]};
                    count_next = '0;
                    saddr_next = SEG_PRELOAD;
                    state_next = ST_WRITE;
                end
            end

            /** READING ** gmem -> dram (~command_reg[5])
                state   saddr_reg   saddr_next  grden_reg   grden_next  count_reg   count_next  wrreq_reg   wrreq_next  g_mem_datao
                IDLE    00          11          0           1           0           1           X           0           X
                ADDR    11          10          1           "           1           0           0           "           X
                ADDR    10          "           "           "           0           1           "           1           maddr_next
                ADDR    "           "           "           "           1           2           1           "           data[0] -> fifo
                ADDR    "           "           "           "           2           3           "           "           data[1] -> fifo  (fifo pre-read)
                READ    "           "           "           "           3           4           "                       data[2] -> fifo
                READ    "           "           "           "           4..         5..                                 data[3..] -> fifo
                READ    "           0           "           0           n_words-1   0                                   data[n_words-2] -> fifo
                READ    0           0           0           0           0           "                                   data[n_words-1] -> fifo
                transition back to ST_IDLE once gfifo_empty;

            *** WRITING ** dram -> gmem (command_reg[5])
                state   saddr_reg   saddr_next  grden_reg   grden_next  count_reg   count_next  g_mem_datao
                IDLE    00          11          0           1           0           0           X
                ADDR    11          00          1           0           "           "           X
                ADDR    00          "           0           "           "           0           maddr_next
                WRITE   "           "           "           "           0           "           X
                wait for mem_ready -> turn off mrden
                when mrdata_valid, indicate wren and save data to registers
                when wren is active, a write is happening; increment counter. If we're on the last count, done.
            */
            ST_ADDR: begin
                if (saddr_reg == SEG_ADDR) begin
                    count_next = '0;
                    if (~command_reg[5]) begin
                        // segment 2 if reading from STORE area
                        saddr_next = SEG_STORE;
                    end else begin
                        // segment 1 if writing to PRELOAD area
                        saddr_next = SEG_PRELOAD;
                        grden_next = '0;
                    end
                end else if (~wrreq_reg) begin
                    maddr_next = g_mem_datao[25-wbits:0];
                    if (~command_reg[5]) begin
                        wrreq_next = '1;
                        count_next = count_reg + 1'b1;
                    end else begin
                        state_next = ST_WRITE;
                        count_next = '0;
                        mrden_next = '1;
                        begin_next = '1;
                    end
                end else begin
                    count_next = count_reg + 1'b1;
                    if (count_is_3) begin
                        state_next = ST_READ;
                        begin_next = '1;
                    end
                end
            end

            // FROM gmem TO dram
            ST_READ: begin
                if (grden_reg) begin
                    if (last_count) begin
                        grden_next = '0;
                        count_next = '0;
                    end else begin
                        count_next = count_reg + 1'b1;
                    end
                end else begin
                    wrreq_next = '0;

                    if (mem_ready & empty) begin
                        state_next = ST_IDLE;
                    end
                end
            end

            // FROM dram TO gmem
            ST_WRITE: begin
                if (command_reg[5]) begin
                    if (mrden_reg) begin
                        if (mem_ready) begin
                            mrden_next = 1'b0;
                        end
                    end else begin
                        // this is relying on the DRAM controller to deassert
                        // data_valid after the transfer is finished. This
                        // seems to be true in practice.
                        if (mrdata_valid) begin
                            gdata_next = mrdata[w_width-1:0];
                            gwren_next = '1;
                        end

                        if (gwren_reg) begin
                            if (last_count) begin
                                state_next = ST_IDLE;
                                count_next = '0;
                            end else begin
                                count_next = count_reg + 1'b1;
                            end
                        end
                    end
                end else begin
                    // set the PRELOAD register to {'0,1'b1};
                    if (gwren_reg) begin
                        if (last_count) begin
                            state_next = ST_IDLE;
                            count_next = '0;
                        end else begin
                            gdata_next = '0;
                            gwren_next = '1;
                            count_next = count_reg + 1'b1;
                        end
                    end else begin
                        gdata_next = {{(w_width-1){1'b0}},1'b1};
                        gwren_next = '1;
                        count_next = '0;
                    end
                end
            end
        endcase
    end

    always_ff @(posedge clk or negedge ctrl_reset_n) begin
        if (~ctrl_reset_n) begin
            command_reg     <= '0;
            state_reg       <= '0;
            count_reg       <= '0;
            saddr_reg       <= '0;
            grden_reg       <= '0;
            gwren_reg       <= '0;
            gdata_reg       <= '0;
            mrden_reg       <= '0;
            begin_reg       <= '0;
            maddr_reg       <= '0;
            wrreq_reg       <= '0;
        end else begin
            command_reg     <= command_next;
            state_reg       <= state_next;
            count_reg       <= count_next;
            saddr_reg       <= saddr_next;
            grden_reg       <= grden_next;
            gwren_reg       <= gwren_next;
            gdata_reg       <= gdata_next;
            mrden_reg       <= mrden_next;
            begin_reg       <= begin_next;
            maddr_reg       <= maddr_next;
            wrreq_reg       <= wrreq_next;
        end
    end

    scfifo         #( .add_ram_output_register      ("ON")
                    , .intended_device_family       ("Arria V")
                    , .lpm_numwords                 (fifodepth)
                    , .lpm_showahead                ("OFF")
                    , .lpm_type                     ("scfifo")
                    , .lpm_width                    (w_width)
                    , .lpm_widthu                   (wbits)
                    , .overflow_checking            ("ON")
                    , .underflow_checking           ("ON")
                    , .use_eab                      ("ON")
                    ) gfifo
                    ( .clock                        (clk)
                    , .aclr                         (~ctrl_reset_n)
                    , .sclr                         (inST_IDLE)

                    , .q                            (mwdata[w_width-1:0])
                    , .rdreq                        (rdreq)
                    , .empty                        (empty)

                    , .data                         (g_mem_datao)
                    , .wrreq                        (wrreq_reg)

                    , .full                         ()
                    , .usedw                        ()
                    , .almost_full                  ()
                    , .almost_empty                 ()
                    );

    mpfe_rst rstins ( .bus_clk                      (clk)
                    , .pll_locked                   (pll_locked)
                    , .cal_success                  (cal_success)
                    , .init_done                    (init_done)
                    , .pcie_perstn                  (pcie_perstn)
                    , .pcie_ready                   (pcie_ready)
                    , .cpu_resetn                   (user_resetn)
                    , .global_reset_n               (global_reset_n)
                    , .mpfe_reset_n                 (mpfe_reset_n)
                    , .ctrl_reset_n                 (ctrl_reset_n)
                    );

    ddr3_x32 ddrins ( .pll_ref_clk                  (clkin_100_p)
                    , .global_reset_n               (global_reset_n)
                    , .soft_reset_n                 (pll_locked)
                    , .mem_a                        (ddr3_a)
                    , .mem_ba                       (ddr3_ba)
                    , .mem_ck                       (ddr3_ck_p)
                    , .mem_ck_n                     (ddr3_ck_n)
                    , .mem_cke                      (ddr3_cke)
                    , .mem_cs_n                     (ddr3_csn)
                    , .mem_dm                       (ddr3_dm)
                    , .mem_ras_n                    (ddr3_rasn)
                    , .mem_cas_n                    (ddr3_casn)
                    , .mem_we_n                     (ddr3_wen)
                    , .mem_reset_n                  (ddr3_rstn)
                    , .mem_dq                       (ddr3_dq)
                    , .mem_dqs                      (ddr3_dqs_p)
                    , .mem_dqs_n                    (ddr3_dqs_n)
                    , .mem_odt                      (ddr3_odt)
                    , .oct_rzqin                    (ddr3_oct_rzq)
                    , .avl_ready_0                  (mem_ready)
                    , .avl_burstbegin_0             (begin_reg)
                    , .avl_addr_0                   (maddr)
                    , .avl_rdata_valid_0            (mrdata_valid)
                    , .avl_rdata_0                  (mrdata)
                    , .avl_wdata_0                  (mwdata)
                    , .avl_read_req_0               (mrden_reg)
                    , .avl_write_req_0              (mwren)
                    , .avl_size_0                   (n_words)
                    , .avl_be_0                     (4'b1111)
                    , .mp_cmd_clk_0_clk             (clk)
                    , .mp_cmd_reset_n_0_reset_n     (mpfe_reset_n)
                    , .mp_rfifo_clk_0_clk           (clk)
                    , .mp_rfifo_reset_n_0_reset_n   (mpfe_reset_n)
                    , .mp_wfifo_clk_0_clk           (clk)
                    , .mp_wfifo_reset_n_0_reset_n   (mpfe_reset_n)
                    , .afi_clk                      ()
                    , .afi_half_clk                 ()
                    , .afi_phy_clk                  ()
                    , .afi_reset_n                  ()
                    , .afi_reset_export_n           ()
                    , .local_init_done              (init_done)
                    , .local_cal_success            (cal_success)
                    , .local_cal_fail               ()
                    , .pll_mem_clk                  ()
                    , .pll_write_clk                ()
                    , .pll_locked                   (pll_locked)
                    , .pll_write_clk_pre_phy_clk    ()
                    , .pll_addr_cmd_clk             ()
                    , .pll_avl_clk                  ()
                    , .pll_config_clk               ()
                    , .pll_mem_phy_clk              ()
                    , .pll_avl_phy_clk              ()
                    );

endmodule
