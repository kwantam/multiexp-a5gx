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

module carry_tree  #( parameter     n_words     = 4
                   )( input     [n_words-1:0]   g
                    , input     [n_words-1:0]   p
                    , output    [n_words-1:0]   c
                    );

    localparam  n_leaves    = 1 << $clog2(n_words);
    localparam  n_levels    = 2*$clog2(n_words);

    reg     [n_leaves-1:0]  g_int[n_levels-1:0];
    reg     [n_leaves-1:0]  p_int[n_levels-1:0];

    genvar CIter;
    generate
        if (n_words < 3) begin
            assign c[0] = g[0];
            if (n_words == 2) begin
                assign c[1] = g[1] | (g[0] & p[1]);
            end
        end else begin
            for(CIter=0; CIter<n_words; CIter++) begin: CAssign
                assign c[CIter] = g_int[n_levels-1][CIter];
            end
        end
    endgenerate

   always_comb begin
       if (n_words < 3) begin
           g_int = '{default:0};
           p_int = '{default:0};
       end else begin
           for(int i=0; i<n_leaves; i++) begin
               if (i < n_words) begin
                   g_int[0][i] = g[i];
                   p_int[0][i] = p[i];
               end else begin
                   g_int[0][i] = 1'b0;
                   p_int[0][i] = 1'b0;
               end
           end

           for(int CStep=1; CStep<n_leaves; CStep*=2) begin
               automatic int CLevel = $clog2(CStep) + 1;
               automatic int CBot = CStep - 1;
               automatic int CTop = CBot + CStep;
               for(int CIter=0; CIter<n_leaves; CIter++) begin
                   if (CIter != CTop) begin
                       g_int[CLevel][CIter] = g_int[CLevel-1][CIter];
                       p_int[CLevel][CIter] = p_int[CLevel-1][CIter];
                   end else begin
                       g_int[CLevel][CIter] = g_int[CLevel-1][CIter] | (g_int[CLevel-1][CBot] & p_int[CLevel-1][CIter]);
                       p_int[CLevel][CIter] = p_int[CLevel-1][CIter] & p_int[CLevel-1][CBot];
                       CBot += CStep;
                       CTop += CStep;
                   end
               end
           end

           for(int CStep=n_leaves/2; CStep>1; CStep/=2) begin
               automatic int CLevel = 2 * $clog2(n_leaves) - $clog2(CStep);
               automatic int CBot = CStep - 1;
               automatic int CTop = CBot + CStep/2;
               for(int CIter=0; CIter<n_leaves; CIter++) begin
                   if (CIter != CTop) begin
                       g_int[CLevel][CIter] = g_int[CLevel-1][CIter];
                       p_int[CLevel][CIter] = p_int[CLevel-1][CIter];
                   end else begin
                       g_int[CLevel][CIter] = g_int[CLevel-1][CIter] | (g_int[CLevel-1][CBot] & p_int[CLevel-1][CIter]);
                       p_int[CLevel][CIter] = p_int[CLevel-1][CIter] & p_int[CLevel-1][CBot];
                       CBot += CStep;
                       CTop += CStep;
                   end
               end
           end
       end
   end


endmodule
