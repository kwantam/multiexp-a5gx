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

#include <gmp.h>
#include <time.h>
#include "mexpdrv.h"

int main(int argc, char **argv) {
    (void) argc;
    (void) argv;

    gmp_randstate_t randstate;
    gmp_randinit_default(randstate);
    gmp_randseed_ui(randstate, 0);

    const unsigned FOOLEN = 249;
    const unsigned num_chunks = FOOLEN / MEXPDRV__C_SIZE + (FOOLEN % MEXPDRV__C_SIZE ? 1 : 0);

    mpz_t foo[FOOLEN];
    for (unsigned i=0; i<FOOLEN; i++) {
        mpz_init(foo[i]);
        mpz_urandomb(foo[i], randstate, 1077);
    }


    uint32_t *bases = mexpdrv_prepare_bases(foo, FOOLEN, 1);

    /*
    for(unsigned h=0; h<num_chunks; h++) {
        printf("**%x**\n", bases[h*MEXPDRV__LOAD_TRAM_CSIZE]);
        unsigned hbase = h*MEXPDRV__LOAD_TRAM_CSIZE + 1;

        for(unsigned i=0; i<MEXPDRV__C_SIZE/2; i++) {
            printf("--%x--\n", bases[hbase+i*MEXPDRV__LOAD_TRAM_SIZE]);
            unsigned ibase = hbase + i*MEXPDRV__LOAD_TRAM_SIZE + 1;

            for(unsigned j=0; j<2; j++) {
                unsigned jbase = ibase + j*MEXPDRV__N_WORDS;
                for(unsigned k=0; k<MEXPDRV__N_WORDS; k++) {
                    printf("%x\n", bases[jbase+k]);
                }
            }
            printf("----\n");
        }
        printf("****\n");
    }
    */

    unsigned converted_size = MEXPDRV__LOAD_TRAM_CSIZE * num_chunks;
    for(unsigned i=0; i<converted_size; i++) {
        printf("%x\n", bases[i]);
    }

    return 0;
}
