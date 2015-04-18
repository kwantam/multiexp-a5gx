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

module mac_element #( parameter y_width = 27
                    , parameter x_width = 27
                    , parameter o_width = 64
                   )( input     [y_width-1:0]   data_y
                    , input     [x_width-1:0]   data_x
                    , output    [o_width-1:0]   result
                    , input                     clk
                    , input                     clken_y
                    , input                     clken_x
                    , input                     clken_o
                    , input                     accumulate
                    , input                     aclr
                    );

    arriav_mac #( .ax_width             (x_width)
                , .ay_scan_in_width     (y_width)
                , .az_width             (0)
                , .bx_width             (0)
                , .by_width             (0)
                , .bz_width             (0)
                , .load_const_value     (0)
                , .scan_out_width       (0)
                , .result_a_width       (o_width)
                , .result_b_width       (1)
                , .operation_mode       ("M27X27")
                , .mode_sub_location    (0)
                , .operand_source_max   ("input")
                , .operand_source_may   ("input")
                , .operand_source_mbx   ("input")
                , .operand_source_mby   ("input")
                , .preadder_subtract_a  ("false")
                , .preadder_subtract_b  ("false")
                , .signed_max           ("false")
                , .signed_may           ("false")
                , .signed_mbx           ("false")
                , .signed_mby           ("false")
                , .ay_use_scan_in       ("false")
                , .by_use_scan_in       ("false")
                , .delay_scan_out_ay    ("false")
                , .delay_scan_out_by    ("false")
                , .use_chainadder       ("false")
                , .enable_double_accum  ("false")
                , .coef_a_0             (0)
                , .coef_a_1             (0)
                , .coef_a_2             (0)
                , .coef_a_3             (0)
                , .coef_a_4             (0)
                , .coef_a_5             (0)
                , .coef_a_6             (0)
                , .coef_a_7             (0)
                , .coef_b_0             (0)
                , .coef_b_1             (0)
                , .coef_b_2             (0)
                , .coef_b_3             (0)
                , .coef_b_4             (0)
                , .coef_b_5             (0)
                , .coef_b_6             (0)
                , .coef_b_7             (0)
                , .ax_clock             ("0")
                , .ay_scan_in_clock     ("1")
                , .az_clock             ("none")
                , .bx_clock             ("none")
                , .by_clock             ("none")
                , .bz_clock             ("none")
                , .coef_sel_a_clock     ("none")
                , .coef_sel_b_clock     ("none")
                , .sub_clock            ("none")
                , .negate_clock         ("none")
                , .accumulate_clock     ("2")
                , .load_const_clock     ("none")
                , .output_clock         ("2")
    ) imac      ( .ax                   (data_x)
                , .ay                   (data_y)
                , .az                   ()
                , .coefsela             ()
                , .bx                   ()
                , .by                   ()
                , .bz                   ()
                , .coefselb             ()
                , .scanin               ()
                , .chainin              ()
                , .loadconst            (1'b0)
                , .accumulate           (accumulate)
                , .negate               (1'b0)
                , .sub                  (1'b0)
                , .clk                  ({3{clk}})
                , .ena                  ({clken_o,clken_y,clken_x})
                , .aclr                 ({2{aclr}})
                , .resulta              (result)
                , .resultb              ()
                , .scanout              ()
                , .chainout             ()
                , .dftout               ()
                );

endmodule
