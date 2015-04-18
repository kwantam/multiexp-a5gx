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
module multiexp_top_sim ();

reg clk;
reg clkin_100_p;
reg pcie_perstn;
reg aclr;
reg wren_reg, flush_reg, readout_reg, restart_reg;

wire [13:0] cusedw_in, cusedw_out;
wire [31:0] cq_in, cdata_out;
reg [31:0] fifo_in;
wire crden, cempty;
wire cfull = '0;
assign cusedw_out = '0;

wire [3:0] status_leds;

initial begin
    flush_reg = '0;
    readout_reg = '0;
    clkin_100_p = '1;
    clk = '1;
    pcie_perstn = '0;
    wren_reg = '0;
    aclr = '1;

    //#1 pcie_perstn = '1;
    #1 aclr = '0;
    wren_reg = '1;

    /* TESTING LOAD_ERAM
    #1024 wren_reg = '0;
    pcie_perstn = '1;

    #16640 wren_reg = '1;
    #16640 wren_reg = '0;
    //*/

    /* TESTING SET_ADDR and LOAD_TRAM */
    #640 flush_reg = '1;
    #8 readout_reg = '1;
    #8 flush_reg = '0;
    #8 readout_reg = '0;
    restart_reg = '1;
    #8 restart_reg = '0;
    #640 flush_reg = '1;
    #8 readout_reg = '1;
    #8 flush_reg = '0;
    #8 readout_reg = '0;
    #8 wren_reg = '0; // 85 words in fifo

    #1 pcie_perstn = '1;
    //*/

    /* TESTING READ_RESULT or FLUSH_RESULTS or START_MULT
    #8 wren_reg = '0;
    pcie_perstn = '1;
    //*/

    /* 2 words in the input pipe
    #8 readout_reg = '1;
    #16 wren_reg = '0;
    //*/
end

always @(posedge clk or posedge aclr) begin
    if (aclr) begin
        /* TESTING LOAD_ERAM
        fifo_in <= 32'h04000000;
        */

        /* TESTING SET_ADDR */
        fifo_in <= 32'h10000000;
        //*/

        /* TESTING READ_RESULT
        fifo_in <= 32'h2000BEEF;
        //*/

        /* TESTING FLUSH_RESULTS
        fifo_in <= 32'h40000000;
        //*/

        /* TESTING START_MULTIPLICATION
        fifo_in <= 32'h80000000;
        //*/
    end else begin
        /*  TESTING LOAD_ERAM
        if (wren_reg) begin
            fifo_in <= fifo_in + 1'b1;
        end else begin
            fifo_in <= fifo_in;
        end
        //*/

        /*  TESTING SET_ADDR and LOAD_TRAM */
        if (restart_reg) begin
            fifo_in <= 32'h10000000;
        end else if (flush_reg & ~readout_reg) begin
            fifo_in <= 32'h08000000;
        end else if (flush_reg & readout_reg) begin
            fifo_in <= 32'h08100000;
        end else if (readout_reg) begin
            fifo_in <= 32'h80000000;
        end else if (wren_reg) begin
            fifo_in <= fifo_in + 1'b1;
        end else begin
            fifo_in <= fifo_in;
        end
        //*/

        /* TESTING READ_RESULT or FLUSH_RESULTS or START_MULT
        fifo_in <= fifo_in;
        //*/

        /*
        if (readout_reg) begin
            fifo_in <= 32'h20000000;
        end else begin
            fifo_in <= fifo_in;
        end
        */

        //fifo_in <= 32'h20000000;
    end
end

always @(clk) clk <= #4 ~clk;

always @(clkin_100_p) clkin_100_p <= #5 ~clkin_100_p;

scfifo #( .add_ram_output_register  ("ON")
        , .intended_device_family   ("Arria V")
        , .lpm_numwords             (8192)
        , .lpm_showahead            ("OFF")
        , .lpm_type                 ("scfifo")
        , .lpm_width                (32)
        , .lpm_widthu               (13)
        , .overflow_checking        ("ON")
        , .underflow_checking       ("ON")
        , .use_eab                  ("ON")
) f_di  ( .clock        (clk)       // general
        , .aclr         (aclr)

        , .q            (cq_in)
        , .rdreq        (crden)
        , .empty        (cempty)

        , .wrreq        (wren_reg)
        , .data         (fifo_in)
        , .usedw        (cusedw_in[12:0])
        , .full         (cusedw_in[13])

        , .sclr         (1'b0)
        , .almost_full  ()
        , .almost_empty ()
);

wire [12:0] ddr3_a;
wire [2:0] ddr3_ba;
wire [3:0] ddr3_dm;
wire [31:0] ddr3_dq;
wire [3:0] ddr3_dqs_p;
wire [3:0] ddr3_dqs_n;
wire ddr3_ck_p, ddr3_ck_n, ddr3_cke, ddr3_csn, ddr3_rasn, ddr3_casn, ddr3_wen, ddr3_rstn, ddr3_odt;

multiexp_top   #( .fifo_widthu          (13)
                , .n_mult               (2)
                ) imult
                ( .clk                  (clk)
                , .pcie_perstn          (pcie_perstn)
                , .pcie_ready           (1'b1)
                , .user_resetn          (1'b1)
                , .pll_core_locked      (1'b1)

                , .fifo_datai           (cq_in)
                , .fifo_empty           (cempty)
                , .fifo_rden            (crden)
                , .fifo_usedw_in        (cusedw_in)
                , .pcie_writing         (1'b1)

                , .fifo_datao           (cdata_out)
                , .fifo_wren            (cwren)
                , .fifo_usedw_out       (cusedw_out)

                , .status_leds          (status_leds)

                , .ddr3_a               (ddr3_a)
                , .ddr3_ba              (ddr3_ba)
                , .ddr3_ck_p            (ddr3_ck_p)
                , .ddr3_ck_n            (ddr3_ck_n)
                , .ddr3_cke             (ddr3_cke)
                , .ddr3_csn             (ddr3_csn)
                , .ddr3_dm              (ddr3_dm)
                , .ddr3_rasn            (ddr3_rasn)
                , .ddr3_casn            (ddr3_casn)
                , .ddr3_wen             (ddr3_wen)
                , .ddr3_rstn            (ddr3_rstn)
                , .ddr3_dq              (ddr3_dq)
                , .ddr3_dqs_p           (ddr3_dqs_p)
                , .ddr3_dqs_n           (ddr3_dqs_n)
                , .ddr3_odt             (ddr3_odt)
                , .ddr3_oct_rzq         ()
                , .clkin_100_p          (clkin_100_p)

                );

alt_mem_if_ddr3_mem_model_top_ddr3_mem_if_dm_pins_en_mem_if_dqsn_en #(
        .MEM_IF_ADDR_WIDTH            (13),
        .MEM_IF_ROW_ADDR_WIDTH        (13),
        .MEM_IF_COL_ADDR_WIDTH        (10),
        .MEM_IF_CONTROL_WIDTH         (1),
        .MEM_IF_DQS_WIDTH             (4),
        .MEM_IF_CS_WIDTH              (1),
        .MEM_IF_BANKADDR_WIDTH        (3),
        .MEM_IF_DQ_WIDTH              (32),
        .MEM_IF_CK_WIDTH              (1),
        .MEM_IF_CLK_EN_WIDTH          (1),
        .MEM_TRCD                     (8),
        .MEM_TRTP                     (4),
        .MEM_DQS_TO_CLK_CAPTURE_DELAY (450),
        .MEM_CLK_TO_DQS_CAPTURE_DELAY (100000),
        .MEM_IF_ODT_WIDTH             (1),
        .MEM_IF_LRDIMM_RM             (0),
        .MEM_MIRROR_ADDRESSING_DEC    (0),
        .MEM_REGDIMM_ENABLED          (0),
        .MEM_LRDIMM_ENABLED           (0),
        .DEVICE_DEPTH                 (1),
        .MEM_NUMBER_OF_DIMMS          (1),
        .MEM_NUMBER_OF_RANKS_PER_DIMM (1),
        .MEM_GUARANTEED_WRITE_INIT    (0),
        .MEM_VERBOSE                  (1),
        .REFRESH_BURST_VALIDATION     (0),
        .MEM_INIT_EN                  (0),
        .MEM_INIT_FILE                (""),
        .DAT_DATA_WIDTH               (32)
    ) m0 (
        .mem_a       (ddr3_a),       // memory.mem_a
        .mem_ba      (ddr3_ba),      //       .mem_ba
        .mem_ck      (ddr3_ck_p),    //       .mem_ck
        .mem_ck_n    (ddr3_ck_n),    //       .mem_ck_n
        .mem_cke     (ddr3_cke),     //       .mem_cke
        .mem_cs_n    (ddr3_csn),     //       .mem_cs_n
        .mem_dm      (ddr3_dm),      //       .mem_dm
        .mem_ras_n   (ddr3_rasn),    //       .mem_ras_n
        .mem_cas_n   (ddr3_casn),    //       .mem_cas_n
        .mem_we_n    (ddr3_wen),     //       .mem_we_n
        .mem_reset_n (ddr3_rstn),    //       .mem_reset_n
        .mem_dq      (ddr3_dq),      //       .mem_dq
        .mem_dqs     (ddr3_dqs_p),   //       .mem_dqs
        .mem_dqs_n   (ddr3_dqs_n),   //       .mem_dqs_n
        .mem_odt     (ddr3_odt)      //       .mem_odt
    );

endmodule
