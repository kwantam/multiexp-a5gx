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

module a5_multiexp  ( input             pcie_perstn
                    , input             pcie_refclk
                    , input     [3:0]   pcie_rx
                    , output    [3:0]   pcie_tx
                    , output    [3:0]   user_led
                    , output    [3:0]   extra_led
                    , output            hsma_tx_led
                    , output            hsma_rx_led

                    /*//extra i/o
                    , input  [3:0]  user_dipsw
                    , output        hsma_rx_led
                    */

                    , input     [2:0]   user_pb             // hard reset switch
                    , input             clkin_100_p         // xtal dedicated to RAM
                                                            /* memory interface i/o */
                    , output    [12:0]  ddr3_a              //       memory.mem_a
                    , output    [2:0]   ddr3_ba             //             .mem_ba
                    , output            ddr3_ck_p           //             .mem_ck
                    , output            ddr3_ck_n           //             .mem_ck_n
                    , output            ddr3_cke            //             .mem_cke
                    , output            ddr3_csn            //             .mem_cs_n
                    , output    [3:0]   ddr3_dm             //             .mem_dm
                    , output            ddr3_rasn           //             .mem_ras_n
                    , output            ddr3_casn           //             .mem_cas_n
                    , output            ddr3_wen            //             .mem_we_n
                    , output            ddr3_rstn           //             .mem_reset_n
                    , inout     [31:0]  ddr3_dq             //             .mem_dq
                    , inout     [3:0]   ddr3_dqs_p          //             .mem_dqs
                    , inout     [3:0]   ddr3_dqs_n          //             .mem_dqs_n
                    , output            ddr3_odt            //             .mem_odt
                    , input             ddr3_oct_rzq        //          oct.rzqin
                    );

    wire            bus_clk, quiesce;

    wire    [31:0]  xrdata, xwdata;
    wire            xrden, xempty, xropen, xwren, xfull, xwopen;

    wire    [31:0]  cdatao;
    wire    [11:0]  cusedw_out;
    wire            cwren;

    wire    [31:0]  cdatai;
    wire    [11:0]  cusedw_in;
    wire            crden, cempty;

    wire            pll_clk, pll_core_locked, pcie_ready, pcie_writing, ctrl_reset_n;

    assign          hsma_tx_led = ~pll_core_locked;
    assign          hsma_rx_led = ctrl_reset_n;

    localparam fifo_nwords = 2048;
    localparam fifo_widthu = $clog2(fifo_nwords);

    xillybus ixilly ( .user_r_r_rden    (xrden)     // FPGA -> HOST
                    , .user_r_r_empty   (xempty)
                    , .user_r_r_data    (xrdata)
                    , .user_r_r_eof     (1'b0)
                    , .user_r_r_open    (xropen)

                    , .user_w_w_wren    (xwren)     // HOST -> FPGA
                    , .user_w_w_full    (xfull)
                    , .user_w_w_data    (xwdata)
                    , .user_w_w_open    (xwopen)

                    , .pcie_perstn      (pcie_perstn) // general
                    , .pcie_refclk      (pcie_refclk)
                    , .pcie_rx          (pcie_rx)
                    , .bus_clk          (bus_clk)
                    , .pcie_tx          (pcie_tx)
                    , .quiesce          (quiesce)
                    , .user_led         (user_led)
                    );

    // FIFO: host -> fpga
    dcfifo #( .intended_device_family   ("Arria V")
            , .lpm_numwords             (fifo_nwords)
            , .lpm_showahead            ("OFF")
            , .lpm_type                 ("dcfifo")
            , .lpm_width                (32)
            , .lpm_widthu               (fifo_widthu)
            , .overflow_checking        ("ON")
            , .underflow_checking       ("ON")
            , .rdsync_delaypipe         (4)
            , .wrsync_delaypipe         (4)
            , .read_aclr_synch          ("OFF")
            , .write_aclr_synch         ("OFF")
            , .use_eab                  ("ON")
            , .add_ram_output_register  ("ON")
            ) f_fromhost
            ( .aclr                     (quiesce)

            , .data                     (xwdata)
            , .wrfull                   (xfull)
            , .wrreq                    (xwren)
            , .wrclk                    (bus_clk)
            , .wrusedw                  ()
            , .wrempty                  ()

            , .q                        (cdatai)
            , .rdempty                  (cempty)
            , .rdreq                    (crden)
            , .rdclk                    (pll_clk)
            , .rdusedw                  (cusedw_in[10:0])
            , .rdfull                   (cusedw_in[11])
            );

    // FIFO: fpga -> host
    dcfifo #( .intended_device_family   ("Arria V")
            , .lpm_numwords             (fifo_nwords)
            , .lpm_showahead            ("OFF")
            , .lpm_type                 ("dcfifo")
            , .lpm_width                (32)
            , .lpm_widthu               (fifo_widthu)
            , .overflow_checking        ("ON")
            , .underflow_checking       ("ON")
            , .rdsync_delaypipe         (4)
            , .wrsync_delaypipe         (4)
            , .read_aclr_synch          ("OFF")
            , .write_aclr_synch         ("OFF")
            , .use_eab                  ("ON")
            , .add_ram_output_register  ("ON")
            ) f_tohost
            ( .aclr                     (~ctrl_reset_n)

            , .data                     (cdatao)
            , .wrfull                   (cusedw_out[11])
            , .wrreq                    (cwren)
            , .wrclk                    (pll_clk)
            , .wrusedw                  (cusedw_out[10:0])
            , .wrempty                  ()

            , .q                        (xrdata)
            , .rdempty                  (xempty)
            , .rdreq                    (xrden)
            , .rdclk                    (bus_clk)
            , .rdusedw                  ()
            , .rdfull                   ()
            );

    // PLL: make core clock related to Xillybus clock
    // to minimize clock domain crossing headaches
    // (viz., synchronizer issues)
    pll_top ipll    ( .ref_clk          (bus_clk)
                    , .rst              (~pcie_perstn)
                    , .out_clk          (pll_clk)
                    , .locked           (pll_core_locked)

                    , .pcie_ready       (~quiesce)
                    , .pcie_ready_sync  (pcie_ready)

                    , .xwopen           (xwopen)
                    , .xwopen_sync      (pcie_writing)
                    );

    // And now, the actual multiexp piece.
    // If we were using partial reconfiguration, this would be the piece
    // we'd rip out and replace with something else. Sadly, I think we have
    // to upgrade to a Stratix device for that to be reasonable.
    multiexp_top   #( .fifo_widthu      (fifo_widthu)
                    , .n_mult           (16)
                    ) imexp
                    ( .clk              (pll_clk)
                    , .pcie_perstn      (pcie_perstn)
                    , .pcie_ready       (pcie_ready)
                    , .user_resetn      (user_pb[0])
                    , .pll_core_locked  (pll_core_locked)
                    , .ctrl_reset_n     (ctrl_reset_n)

                    , .fifo_datai       (cdatai)
                    , .fifo_empty       (cempty)
                    , .fifo_rden        (crden)
                    , .fifo_usedw_in    (cusedw_in)
                    , .pcie_writing     (pcie_writing)

                    , .fifo_datao       (cdatao)
                    , .fifo_wren        (cwren)
                    , .fifo_usedw_out   (cusedw_out)

                    , .status_leds      (extra_led)

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
                    );

endmodule
