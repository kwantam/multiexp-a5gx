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

    const unsigned ks = 5;
    const unsigned kc = 7;
    const unsigned num_chunks = kc / MEXPDRV__C_SIZE + (kc % MEXPDRV__C_SIZE ? 1 : 0);
    const unsigned num_passes = ks / MEXPDRV__N_MULTS + (ks % MEXPDRV__N_MULTS ? 1 : 0);

    mpz_t *foo[ks];
    for (unsigned i=0; i<ks; i++) {
        foo[i] = (mpz_t *) malloc(kc * sizeof(mpz_t));
        for (unsigned j=0; j<kc; j++) {
            mpz_init(foo[i][j]);
            mpz_urandomb(foo[i][j], randstate, 128);
        }
    }

    uint32_t *exps = mexpdrv_prepare_exps(foo, kc, ks, 1);

    unsigned converted_size = MEXPDRV__LOAD_ERAM_PSIZE * num_passes * num_chunks;
    for(unsigned i=0; i<converted_size; i++) {
        printf("%x\n", exps[i]);
    }

    return 0;
}
