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

module modmult #( parameter     n_words     = 4
                , parameter     w_width     = 27
                , parameter     b_offset    = 1     // bit offset of MSB for modulo reduction (see note below)
                , parameter     last_factor = 0     // how many factors are in the modulo reduction? (see note below)
                , parameter     factor_1    = 0     // factors range from 0 to 15 (represented as 4 bits internally)
                , parameter     factor_2    = 0
                , parameter     factor_3    = 0
////////////// BELOW THIS LINE SHOULD BE LOCALAPARAMS - see note ---------------vv
                , parameter     wbits       = $clog2(n_words)                   // the rest of these should be localparams
                , parameter     o_width     = 2*w_width + wbits + b_offset + 1  // but Quartus follows V2001 strictly and
                , parameter     m_width     = 2*w_width + wbits                 // does not allow localparams within the
                , parameter     nres        = 2*n_words - 1                     // ANSI style parameter list.
                , parameter     rbits       = $clog2(nres)                      // Do not override these values!!!
                )
                ( output    [8:0]           m_addr
                , output                    m_rden
                , output                    m_wren
                , output    [w_width-1:0]   m_datao
                , input     [w_width-1:0]   m_datai
                , input     [w_width-1:0]   t_datai

                , input                     aclr
                , input                     clk

                , input     [2:0]           command
                , output                    command_ack
                );

/* 

*** b_offset explanation ***

We are reducing the product mod a number of bits equal to n_words *
w_width - b_offset. The assumption is that we are reducing a Mersenne or
Crandall prime, which means that we are going to add the MSBs with some
shifts to the LSBs. So that we know where those MSBs start, we
parameterize over b_offset.

After finishing the multiplies, when we read the values out of the
multipliers, we offset the values into the higher-order registers.

When we resolve the carry bits, we simultaneously take the (w_width-
b_offset)th bit from result_reg[n_words-1] and add it into the LSB
of the result_reg[n_words] register, which makes the value stored in
result_reg[n_words-1:0] a (n_words*w_width - b_offset) bit value.

*/

/*

*** last_factor explanation ***

This block assumes that we are reducing the multiplication result mod a
Mersenne or Crandall number, that is, one of the form

2^k - n

for n small and of low Hamming weight. For example, 2^107-1 (Mersenne)
and 2^104 - 17 (Crandall) are both primes.

To reduce mod 2^107-1, note that a product of two 107-bit numbers will
be, at most 214 bits, and further that the result can be viewed as
having two words, w0 and w1, of 107 bits. In other words, the product is
w0 + 2^107*w1. But 2^107 mod 2^107-1 is 1, so the modular reduction
of 2^107*w1 is just w1, and thus the modular reduction of w0 + 2^107*w1
is just w0 + w1.

A similar argument applies to 2^104-17. Now the product is
w0 + 2^104*w1, and 2^104 mod 2^104-17 = 17, so the reduction is
w0 + 17*w1, or w0 + w1 + w1 << 4. (This is why we want n to be of low
Hamming weight.)

factor_0 is always 0. If we are reducing mod a Crandall number, then we
need to add other factors, e.g., 4 in the case above. In this case, also
be sure to change the last_factor parameter.

*/

    // last_factor can't be higher than 3; we don't have the support for it
    localparam last_factor_int = (last_factor > 3) ? 3 : last_factor;
    // '$max' not supported for synthesis even though this is all static data. BOOO.
    // add 2 bits for margin in case I've misapprehended the widest possible post-reduction carry.
    // TODO: REVISIT if there are problems with synthesis speed.
    localparam maxfact_tmp = 2 + ( (factor_3 > factor_2) ? 
                                     (factor_3 > factor_1 ?
                                       (factor_3 > 0 ? factor_3 : 0)  :
                                       (factor_1 > 0 ? factor_1 : 0)) : 
                                     (factor_2 > factor_1 ?
                                       (factor_2 > 0 ? factor_2 : 0)  :
                                       (factor_1 > 0 ? factor_1 : 0)) );
    localparam maxfactor = (maxfact_tmp < w_width) ? maxfact_tmp : w_width;
    localparam r_width = w_width + b_offset + maxfactor;
    localparam d_width = w_width + maxfactor;
    localparam h_width = w_width + wbits + b_offset + 1;

    reg     [w_width-1:0]   result_reg[n_words-1:0], result_next[n_words-1:0];
    reg     [w_width-1:0]   rshifto_reg[n_words-1:0], rshifto_next[n_words-1:0];

    reg     [w_width-1:0]   mac_y_reg[n_words-1:0], mac_y_next[n_words-1:0];
    wire    [m_width-1:0]   mult_out[n_words-1:0];
    reg     [w_width-1:0]   mac_x, mac_x_reg[n_words-1:0], mac_x_next[n_words-1:0];
    wire    [n_words-1:0]   en_accum;
    wire                    en_mac;

    reg     [o_width-1:0]   mult_o0_reg[n_words-1:0], mult_o0_next[n_words-1:0];

    reg     [h_width:0]     mult_o1h_reg[nres-2:n_words], mult_o1h_next[nres-2:n_words];
    reg     [o_width-1:0]   mult_o1h_n_reg, mult_o1h_n_next;

    reg     [w_width-1:0]   mult_o1l_reg[n_words-1:0], mult_o1l_next[n_words-1:0];

    reg     [w_width:0]     mult_o2_reg[nres-2:n_words], mult_o2_next[nres-2:n_words];
    reg     [o_width-1:0]   mult_o2_n_reg, mult_o2_n_next;

    reg     [d_width:0]     redc_reg[0:last_factor][n_words-2:0], redc_next[0:last_factor][n_words-2:0];
    reg     [o_width-1:0]   redc_n_reg[0:last_factor], redc_n_next[0:last_factor];

    reg     [w_width:0]     carry_o0_reg[n_words-2:0], carry_o0_next[n_words-2:0];
    reg     [r_width:0]     carry_o0_n_reg, carry_o0_n_next;
    reg     [w_width:0]     carry_o1_reg[n_words-2:0], carry_o1_next[n_words-2:0];
    reg     [r_width:0]     carry_o1_n_reg, carry_o1_n_next;

    /* *** MULTIPLIERS *** */
    genvar MacIter;
    generate for(MacIter=0; MacIter<n_words; MacIter++) begin: MacInst
        mac_element    #( .o_width      (m_width)
                ) mInst ( .data_y       (mac_y_reg[MacIter])
                        , .data_x       (mac_x)
                        , .result       (mult_out[MacIter])
                        , .clk          (clk)
                        , .clken_y      (en_mac)
                        , .clken_x      (en_mac)
                        , .clken_o      (en_mac)
                        , .accumulate   (en_accum[MacIter])
                        , .aclr         (aclr)
                        );
    end
    endgenerate

    /* *** CARRY TREE *** */
    wire    [n_words-1:2]   carry_gen;
    wire    [n_words-1:2]   carry_prop;
    wire    [n_words-1:2]   carry_out;
    reg     [n_words-1:2]   carry_t_reg, carry_t_next;

    generate for(MacIter=2; MacIter<n_words; MacIter++) begin: CTreeWires
        assign carry_gen[MacIter] = carry_o0_reg[MacIter-1][w_width];
        assign carry_prop[MacIter] = &(carry_o0_reg[MacIter-1][w_width-1:0]);
    end
    endgenerate

    carry_tree #( .n_words      (n_words-2)
                ) ctree_inst
                ( .g            (carry_gen[n_words-1:2])
                , .p            (carry_prop[n_words-1:2])
                , .c            (carry_out[n_words-1:2])
                );

    // How many bits could the result after carry tree extend above the "top" of result_reg[n_words-1]?
    //
    // At maximum, the value in result_reg[2*n_words-2] after multiplication and shifting
    // is 2*w_width+b_offset bits wide (because the maximum possible size of the result
    // of a multiply is 2*n_words*w_width for n_words*w_width inputs, and we shift that
    // up by b_offset). We added that to the low-order words with up to maxfactor shift.
    // So we could have as many as maxfactor+b_offset bits above w_width-1, and recall
    // that result_reg[n_words-1] is only supposed to be w_width-b_offset bits wide.
    wire [2*b_offset+maxfactor:0] reduce_detect = carry_o1_n_reg[w_width+b_offset+maxfactor:w_width-b_offset];
    wire continue_reducing = |(reduce_detect);
    // In short, if any of these bits are nonzero, we have more reduction to do.

    /* *** STATE MACHINE PARAMS *** */
    reg     [2:0]           state_reg, state_next;
    reg     [wbits-1:0]     count_reg, count_next;
    reg                     square_reg, square_next, rammult_reg, rammult_next;
    wire    last_count          = count_reg == (n_words - 1);

    `include "mult_commands.vh"

    localparam ST_IDLE          = 3'b000;
    localparam ST_PRELOAD       = 3'b001;
    localparam ST_STORE         = 3'b010;
    localparam ST_BEGINMULT     = 3'b100;
    localparam ST_SHUFFLE       = 3'b101;
    localparam ST_REDUCE        = 3'b110;
    localparam ST_CARRY         = 3'b111;

    wire    inST_IDLE           = state_reg == ST_IDLE;
    wire    inST_PRELOAD        = state_reg == ST_PRELOAD;
    wire    inST_STORE          = state_reg == ST_STORE;
    wire    inST_BEGINMULT      = state_reg == ST_BEGINMULT;
    wire    inST_SHUFFLE        = state_reg == ST_SHUFFLE;
    wire    inST_REDUCE         = state_reg == ST_REDUCE;
    wire    inST_CARRY          = state_reg == ST_CARRY;

    wire    nextST_BEGINRAMMULT = inST_IDLE & (command == CMD_BEGINRAMMULT);
    wire    nextST_BEGINMULT    = inST_IDLE & (command == CMD_BEGINMULT);
    wire    nextST_BEGINSQUARE  = inST_IDLE & (command == CMD_BEGINSQUARE);
    wire    nextST_PRELOAD      = inST_IDLE & (command == CMD_PRELOAD);
    wire    nextST_STORE        = inST_IDLE & (command == CMD_STORE);
    wire    nextST_SHUFFLE      = inST_BEGINMULT & last_count;
    wire    nextST_REDUCE       = inST_SHUFFLE & (count_reg == {'0,2'b10});
    wire    nextST_CARRY        = inST_REDUCE & (count_reg == last_factor_int);

    /* *** COMBINATIONAL CONTROL SIGNALS *** */
    assign command_ack = inST_IDLE;

    // address to read/write is determined by state_next and count_next
    // such that we are ready to go with our reads/writes immediately
    // upon entering a state
    assign m_rden = nextST_PRELOAD | inST_PRELOAD | nextST_BEGINRAMMULT | rammult_reg;
    assign m_wren = inST_STORE;
    assign m_addr = m_wren ? {'0,2'b10,count_reg} : {'0,state_next[1:0],count_next};
    assign m_datao = m_wren ? rshifto_reg[0] : '0;

    assign en_mac = nextST_BEGINMULT | inST_BEGINMULT | inST_SHUFFLE;

    /*  Timing sequence for BEGINMULT state
    cnt_next    cnt_reg     inX     inY     accum   output[0]   comment
    0           X           0       X       '0      X           ST_IDLE transitioning to ST_BEGINMULT
    1           0           d[0]    res     '1      X           ST_BEGINMULT, cnt_reg == 0
    2           1           d[1]    res<<   'b1110  0        
    3           2           d[2]    res<<   'b1101  d[0]*res  
    0           3           d[3]    res<<   'b1011  d[1]*res<<  cnt_next = 0, state_next = ST_SHUFFLE
    0           0           0       X       '0      d[2]*res<<  ST_SHUFFLE
    0           1           0       X       '0      d[3]*res<<
    */
    assign en_accum[n_words-1] = inST_BEGINMULT;
    generate for(MacIter=0; MacIter<n_words-1; MacIter++) begin: EnAccInst
        assign en_accum[MacIter] = inST_BEGINMULT & (count_reg != MacIter + 1);
    end
    endgenerate

    // as we enter ST_BEGINMULT, mac_x = 0 so that we clear the output registers
    // once in ST_BEGINMULT, choose source for X based on multiplication mode
    always_comb begin
        if (inST_BEGINMULT) begin
            if (square_reg) begin
                mac_x = mac_x_reg[0];
            end else if (rammult_reg) begin
                mac_x = m_datai;
            end else begin
                mac_x = t_datai;
            end
        end else begin
            mac_x = '0;
        end
    end

// sadly, while Altera's synthesis could handle modmult_v_reduce_step with a task, ModelSim cannot, so we use a `define instead.
`ifndef modmult_v_reduce_step
`define modmult_v_reduce_step(j,k)                                                                                          \
    generate if (last_factor_int > (``j``-1)) begin                                                                         \
        always_comb begin                                                                                                   \
            for (int i=0; i<n_words-1; i++) begin                                                                           \
                redc_next[``j``][i] = redc_reg[``j``][i];                                                                   \
            end                                                                                                             \
            redc_n_next[``j``] = redc_n_reg[``j``];                                                                         \
            if ((state_reg == ST_REDUCE) & (count_reg == ``j``)) begin                                                      \
                for(int i=0; i<n_words-2; i++) begin                                                                        \
                    redc_next[``j``][i] = redc_reg[``j``-1][i] + {mult_o2_reg[n_words+i],{``k``{1'b0}}};                    \
                end                                                                                                         \
                redc_next[``j``][n_words-2] = redc_reg[``j``-1][n_words-2] + {'0,mult_o2_n_reg[w_width-1:0],{``k``{1'b0}}}; \
                redc_n_next[``j``] = redc_n_reg[``j``-1] + {'0,mult_o2_n_reg[o_width-1:w_width],{``k``{1'b0}}};             \
            end                                                                                                             \
        end                                                                                                                 \
    end                                                                                                                     \
    endgenerate
`else //modmult_v_reduce_step
`error_multmult_v_reduce_step_macro_already_defined
`endif
`modmult_v_reduce_step(1, factor_1)
`modmult_v_reduce_step(2, factor_2)
`modmult_v_reduce_step(3, factor_3)
// careful to undef things once we're done with them
`ifdef modmult_v_reduce_step
`undef modmult_v_reduce_step
`endif //modmult_v_reduce_step

    /* *** STATE TRANSITION LOGIC *** */
    always_comb begin
        result_next = result_reg;
        rshifto_next = rshifto_reg;
        mac_y_next = mac_y_reg;
        mac_x_next = mac_x_reg;
        mult_o0_next = mult_o0_reg;
        mult_o1l_next = mult_o1l_reg;
        mult_o1h_next = mult_o1h_reg;
        mult_o1h_n_next = mult_o1h_n_reg;
        mult_o2_next = mult_o2_reg;
        mult_o2_n_next = mult_o2_n_reg;
        carry_o0_next = carry_o0_reg;
        carry_o0_n_next = carry_o0_n_reg;
        carry_o1_next = carry_o1_reg;
        carry_o1_n_next = carry_o1_n_reg;
        carry_t_next = carry_t_reg;
        state_next = state_reg;
        count_next = count_reg;
        square_next = square_reg;
        rammult_next = rammult_reg;
        for (int i=0; i<n_words-1; i++) begin
            redc_next[0][i] = redc_reg[0][i];
        end
        redc_n_next[0] = redc_n_reg[0];

        case (state_reg)
            ST_IDLE: begin
                count_next = '0;

                case (command)
                    CMD_BEGINRAMMULT, CMD_BEGINMULT, CMD_BEGINSQUARE: begin
                        for (int i=0; i<n_words; i++) begin
                            mac_y_next[i] = result_reg[i][w_width-1:0];
                        end

                        if (command == CMD_BEGINSQUARE) begin
                            square_next = '1;
                            rammult_next = '0;
                            for (int i=0; i<n_words; i++) begin
                                mac_x_next[i] = result_reg[i][w_width-1:0];
                            end
                        end else if (command == CMD_BEGINRAMMULT) begin
                            square_next = '0;
                            rammult_next = '1;
                        end else begin
                            square_next = '0;
                            rammult_next = '0;
                        end

                        state_next = ST_BEGINMULT;
                    end

                    CMD_RESETRESULT: begin
                        // reset result register to {'0,1'b1}
                        result_next[0] = {'0,1'b1};
                        for (int i=1; i<n_words; i++) begin
                            result_next[i] = '0;
                        end

                        //TODO: optimization: remember that result=1, and next time we're
                        //asked to multiply or square, we can do so quickly by copying
                        //the input to the result register or no-op, respectively.
                    end

                    CMD_STORE: begin
                        for (int i=0; i<n_words; i++) begin
                            rshifto_next[i] = result_reg[i];
                        end
                        state_next = ST_STORE;
                    end

                    CMD_PRELOAD:    state_next = ST_PRELOAD;
                    default:        state_next = ST_IDLE;
                endcase
            end

            ST_PRELOAD: begin
                for (int i=0; i<n_words; i++) begin
                    if (count_reg == i) begin
                        result_next[i][w_width-1:0] = m_datai[w_width-1:0];
                    end
                end

                if (last_count) begin     // on the last word; we're done
                    state_next = ST_IDLE;
                    count_next = '0;
                end else begin
                    count_next = count_reg + 1'b1;
                end
            end

            ST_STORE: begin
                for (int i=0; i<n_words-1; i++) begin
                    rshifto_next[i] = rshifto_reg[i+1];
                end

                if (last_count) begin
                    state_next = ST_IDLE;
                    count_next = '0;
                end else begin
                    count_next = count_reg + 1'b1;
                end
            end

            ST_BEGINMULT: begin
                // read out intermediate results as they're available, rippling carries up the chain
                if (count_reg == 2) begin
                    mult_o0_next[0] = mult_out[0];
                end
                for (int i=3; i<n_words; i++) begin
                    if (count_reg == i) begin
                        mult_o0_next[i-2] = mult_out[i-2] + {'0,mult_o0_reg[i-3][o_width-1:w_width]};
                        mult_o1l_next[i-3] = mult_o0_reg[i-3][w_width-1:0];
                    end
                end

                // cyclic shift of y input to multipliers
                for (int i=0; i<n_words; i++) begin
                    automatic int j = i-1 + (i-1 < 0 ? n_words : 0);
                    mac_y_next[i] = mac_y_reg[j];
                end

                // if we're squaring, shift the next word of the X operand into mac_x_reg[0]
                if (square_reg) begin
                    for (int i=0; i<n_words-1; i++) begin
                        mac_x_next[i] = mac_x_reg[i+1];
                    end
                end

                if (last_count) begin
                    state_next = ST_SHUFFLE;
                    square_next = '0;
                    rammult_next = '0;
                    count_next = '0;
                end else begin
                    count_next = count_reg + 1'b1;
                end
            end

            /*
                NOTE: in principle, we could save some registers by delaying the offset one cycle,
                at the cost of an additional cycle of latency.
                TODO: REVISIT if we're having trouble fitting.
            */
            ST_SHUFFLE: begin
                count_next = count_reg + 1'b1;
                case (count_reg)
                    {'0}: begin
                        // read out intermediate result, as above, doing ripples
                        mult_o0_next[n_words-2] = mult_out[n_words-2] + {'0,mult_o0_reg[n_words-3][o_width-1:w_width]};
                        mult_o1l_next[n_words-3] = mult_o0_reg[n_words-3][w_width-1:0];
                    end

                    {'0,1'b1}: begin
                        // here we finally introduce the offset implied by b_offset

                        // ripple into nwords-1 register
                        mult_o0_next[n_words-1] = {'0,mult_out[n_words-1][w_width-b_offset-1:0]} + {'0,mult_o0_reg[n_words-2][o_width-1:w_width]};
                        mult_o1l_next[n_words-2] = mult_o0_reg[n_words-2][w_width-1:0];

                        // copy from multout into high registers, resolving one round of saved carries
                        for(int i=0; i<n_words-1; i++) begin
                            automatic int j = i-1 + (i-1 < 0 ? n_words : 0);
                            if (i < n_words - 2) begin
                                // offset the mult_out into the high registers
                                mult_o1h_next[i+n_words] = {'0,mult_out[i][w_width-b_offset-1:0],{(b_offset){1'b0}}} + {'0,mult_out[j][m_width-1:w_width-b_offset]};
                            end else begin
                                // highest mult_out is a doubleword, so we don't mask its high bits
                                mult_o1h_n_next = {'0,mult_out[i],{(b_offset){1'b0}}} + {'0,mult_out[j][m_width-1:w_width-b_offset]};
                            end
                        end
                    end

                    {'0,2'b10}: begin
                        // mult_o2_reg[n_words-1] is only w_width-b_offset large. We carry everything else up
                        mult_o1l_next[n_words-1] = {'0,mult_o0_reg[n_words-1][w_width-b_offset-1:0]};
                        mult_o2_next[n_words] = {'0,mult_o1h_reg[n_words][w_width-1:0]} + {'0,mult_o0_reg[n_words-1][h_width:w_width-b_offset]};
                        for(int i=n_words+1; i<nres-1; i++) begin
                            // TODO: REVISIT this optimization; can we add in fewer bits?
                            // In the previous step, we added numbers of w_width-b_offset and (m_width-(w_width-b_offset)) bits.
                            // m_width = 2*w_width + wbits, so we have a sum of (w_width - b_offset) + (w_width + wbits + b_offset)
                            // Max width is thus w_width + wbits + b_offset + 1.
                            // here we are adding one more bit than this, which should certainly be sufficient
                            mult_o2_next[i] = {'0,mult_o1h_reg[i][w_width-1:0]} + {'0,mult_o1h_reg[i-1][h_width:w_width]};
                        end
                        // the most significant word is actually a double word, so do not mask it
                        mult_o2_n_next = mult_o1h_n_reg + {'0,mult_o1h_reg[nres-2][h_width:w_width]};
                        // now we just have to resolve the possible carry-outs with a carry tree (after reducing)
                        // (carry propagate is result[w_width-1:0]=='1, carry generate is result[w_width]==1'b1
                        
                        // at this point, the carries have been completely propagated to the higher-order words
                        // this means we are safe to start the modulo reduction (though be careful because the
                        // high words can still have carries in the (w_width+1)th bit position. That's OK---
                        // we'll resolve those during the modular reduction
                        // NOTE that this approach means that we don't have to bother with the carry tree until
                        // the very very end. This is pretty sweet.
                        state_next = ST_REDUCE;
                        count_next = '0;
                    end

                    default: begin
                        // something wrong here; give up
                        state_next = ST_IDLE;
                        count_next = '0;
                    end
                endcase
            end


            ST_REDUCE: begin
                if (count_reg == last_factor_int) begin
                    state_next = ST_CARRY;
                    count_next = '0;
                end else begin
                    count_next = count_reg + 1'b1;
                end

                /* there is danger of overflow here fi result[n_words+i] has excess carry bits or factor is too big */
                if (count_reg == 0) begin
                    for(int i=0; i<n_words-2; i++) begin
                        redc_next[0][i] = mult_o1l_reg[i] + mult_o2_reg[n_words+i];
                    end
                    /* special cases: split lower and upper half of the nres'th register */
                    redc_next[0][n_words-2] = mult_o1l_reg[n_words-2] + {'0,mult_o2_n_reg[w_width-1:0]};
                    redc_n_next[0] = mult_o1l_reg[n_words-1] + {'0,mult_o2_n_reg[o_width-1:w_width]};
                end
            end

            ST_CARRY: begin
                count_next = count_reg + 1'b1;

                case (count_reg)
                    {'0,2'b00}: begin
                        // carry width in redc is maxfactor (already includes 2-bit safety margin, see above)
                        carry_o0_next[0] = {'0,redc_reg[last_factor_int][0][w_width-1:0]};
                        for(int i=1; i<n_words-1; i++) begin
                            carry_o0_next[i] = {'0,redc_reg[last_factor_int][i][w_width-1:0]} + {'0,redc_reg[last_factor_int][i-1][d_width:w_width]};
                        end
                        carry_o0_n_next = redc_n_reg[last_factor_int] + {'0,redc_reg[last_factor_int][n_words-2][d_width:w_width]};
                    end

                    {'0,2'b01}: begin
                        carry_t_next = carry_out;
                    end

                    {'0,2'b10}: begin
                        // since maxfactor <= w_width (enforced above)
                        // we know that at this point we have at most 1 bit of carry
                        // so it's time for the carry tree!
                        carry_o1_next[0] = carry_o0_reg[0];
                        carry_o1_next[1] = carry_o0_reg[1] & {w_width{1'b1}};
                        for(int i=2; i<n_words-1; i++) begin
                            carry_o1_next[i] = (carry_o0_reg[i] + {'0,carry_t_reg[i]}) & {w_width{1'b1}};
                        end
                        carry_o1_n_next = carry_o0_n_reg + {'0,carry_t_reg[n_words-1]};
                    end

                    {'0,2'b11}: begin
                        // clear out high-order result registers
                        for(int i=n_words+1; i<nres-1; i++) begin
                            mult_o2_next[i] = '0;
                        end
                        mult_o2_n_next = '0;

                        // any remaining carry coming out of the top of the register gets moved to mult_o2_reg[n_words]
                        mult_o2_next[n_words] = {'0,reduce_detect};
                        mult_o1l_next[n_words-1] = {'0,carry_o1_n_reg[w_width-b_offset-1:0]};

                        // write result registers in case we're done
                        result_next[n_words-1] = {'0,carry_o1_n_reg[w_width-b_offset-1:0]};
                        for(int i=0; i<n_words-1; i++) begin
                            result_next[i] = carry_o1_reg[i][w_width-1:0];
                            mult_o1l_next[i] = carry_o1_reg[i][w_width-1:0];
                        end


                        // Now we detect whether to do another reduction step or not.
                        if (continue_reducing) begin
                            state_next = ST_REDUCE;
                        end else begin
                            state_next = ST_IDLE;
                        end
                        count_next = '0;
                    end

                    default: begin
                        // something wrong here; give up
                        state_next = ST_IDLE;
                        count_next = '0;
                    end
                endcase
            end

            default: begin
                // something wrong here; give up
                state_next = ST_IDLE;
            end
        endcase
    end

    /* *** FLIP-FLOPS *** */
    always_ff @(posedge clk or posedge aclr) begin
        if (aclr) begin
            state_reg               <= '0;
            count_reg               <= '0;
            rammult_reg             <= '0;
            result_reg              <= '{default:0};
            rshifto_reg             <= '{default:0};
            square_reg              <= '0;
            mac_y_reg               <= '{default:0};
            mac_x_reg               <= '{default:0};
            mult_o0_reg             <= '{default:0};
            mult_o1l_reg            <= '{default:0};
            mult_o1h_reg            <= '{default:0};
            mult_o1h_n_reg          <= '0;
            mult_o2_reg             <= '{default:0};
            mult_o2_n_reg           <= '0;
            redc_reg                <= '{default:0};
            redc_n_reg              <= '{default:0};
            carry_o0_reg            <= '{default:0};
            carry_o0_n_reg          <= '0;
            carry_o1_reg            <= '{default:0};
            carry_o1_n_reg          <= '0;
            carry_t_reg             <= '0;
        end else begin
            state_reg               <= state_next;
            count_reg               <= count_next;
            rammult_reg             <= rammult_next;
            result_reg              <= result_next;
            rshifto_reg             <= rshifto_next;
            square_reg              <= square_next;
            mac_y_reg               <= mac_y_next;
            mac_x_reg               <= mac_x_next;
            mult_o0_reg             <= mult_o0_next;
            mult_o1l_reg            <= mult_o1l_next;
            mult_o1h_reg            <= mult_o1h_next;
            mult_o1h_n_reg          <= mult_o1h_n_next;
            mult_o2_reg             <= mult_o2_next;
            mult_o2_n_reg           <= mult_o2_n_next;
            redc_reg                <= redc_next;
            redc_n_reg              <= redc_n_next;
            carry_o0_reg            <= carry_o0_next;
            carry_o0_n_reg          <= carry_o0_n_next;
            carry_o1_reg            <= carry_o1_next;
            carry_o1_n_reg          <= carry_o1_n_next;
            carry_t_reg             <= carry_t_next;
        end
    end

endmodule
