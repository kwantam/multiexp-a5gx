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

module mpfe_rst
    ( input     bus_clk
    , input     pll_locked
    , input     cal_success
    , input     init_done
    , input     pcie_perstn
    , input     cpu_resetn
    , input     pcie_ready

    , output    global_reset_n
    , output    mpfe_reset_n
    , output    ctrl_reset_n
    );

// for simulation, make sure we don't spend too long resetting
`ifdef MODEL_TECH
    localparam STOP_COUNT = 26'h000000f;
`else
    localparam STOP_COUNT = 26'h3ffffff;
`endif

    reg mpfe_reg[1:0];
    assign mpfe_reset_n = mpfe_reg[1];

    reg ctrl_reg[1:0];
    assign ctrl_reset_n = ctrl_reg[1];

    reg [25:0] reset_timer;
    reg pcie_perstn_sync[1:0];
    reg cpu_resetn_sync[1:0];

    wire timer_resetn = cpu_resetn_sync[1] & pcie_perstn_sync[1];

    // sync deassert for cpu_resetn
    always @(posedge bus_clk or negedge cpu_resetn) begin
        if (~cpu_resetn) begin
            cpu_resetn_sync[0] <= 0;
            cpu_resetn_sync[1] <= 0;
        end else begin
            cpu_resetn_sync[0] <= 1;
            cpu_resetn_sync[1] <= cpu_resetn_sync[0];
        end
    end

    // sync deassert for pcie_perstn
    always @(posedge bus_clk or negedge pcie_perstn) begin
        if (~pcie_perstn) begin
            pcie_perstn_sync[0] <= 0;
            pcie_perstn_sync[1] <= 0;
        end else begin
            pcie_perstn_sync[0] <= 1;
            pcie_perstn_sync[1] <= pcie_perstn_sync[0];
        end
    end

    always @(posedge bus_clk or negedge timer_resetn) begin
        if (~timer_resetn) begin
            reset_timer <= 0;
        end else if (reset_timer == STOP_COUNT) begin
            reset_timer <= STOP_COUNT;
        end else begin
            reset_timer <= reset_timer + 1'b1;
        end
    end

    assign global_reset_n = reset_timer == STOP_COUNT;

    /* mpfe reset deasserts when pll_locked and cal_success and pcie_ready */
    /* deassert synchronous to bus_clk domain */
    wire mpfe_arstn = global_reset_n & pll_locked & cal_success & pcie_ready;
    always @(posedge bus_clk or negedge mpfe_arstn) begin
        if (~mpfe_arstn) begin
            mpfe_reg[0] <= 0;
            mpfe_reg[1] <= 0;
        end else begin
            mpfe_reg[0] <= 1;
            mpfe_reg[1] <= mpfe_reg[0];
        end
    end

    wire ctrl_arstn = global_reset_n & pll_locked & cal_success & pcie_ready & init_done;
    always @(posedge bus_clk or negedge ctrl_arstn) begin
        if (~ctrl_arstn) begin
            ctrl_reg[0] <= 0;
            ctrl_reg[1] <= 0;
        end else begin
            ctrl_reg[0] <= 1;
            ctrl_reg[1] <= ctrl_reg[0];
        end
    end

endmodule
