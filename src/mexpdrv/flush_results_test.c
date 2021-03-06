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

#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdio.h>
#include <time.h>
#include <gmp.h>

#include "mexpdrv.h"

// 26-bit address space
#define MEMSIZE (1 << 20)
#define RDDEV "/dev/xillybus_r"
#define WRDEV "/dev/xillybus_w"

int main(int argc, char **argv) {
    (void) argc;
    (void) argv;

    srand(time(NULL));

    uint32_t readresp[MEXPDRV__N_WORDS + 1] = {0,};
    int w_fd = open(WRDEV, O_WRONLY);
    if (w_fd < 0) {
        perror("Could not open wfd");
        exit(-1);
    }

    int r_fd = open(RDDEV, O_RDONLY);
    if (r_fd < 0) {
        perror("Could not open rfd");
        exit(-1);
    }

    mexpdrv_init(r_fd, w_fd);

    gmp_randstate_t randstate;
    mpz_t l, r, lr, tmp, p;
    gmp_randinit_default(randstate);
    gmp_randseed_ui(randstate, time(NULL));
    mpz_init(l);
    mpz_init(r);
    mpz_init(tmp);
    mpz_init(lr);
    mpz_init(p);
    mpz_urandomb(l, randstate, 1077);
    mpz_urandomb(r, randstate, 1077);

    mpz_set_str(p, "1619218026458484946819962773751338456396453198113136946855210864219442716543962775135683069611496995961496622914534495291118469899086347814936107199525908079372139394212530890915735261936745730729918141427781960548496059867397541588944826845193276450726480452098870156418667316921844020257490620069168050106461661928747958239", 10);
    mpz_mul(tmp, l, r);
    mpz_mod(lr, tmp, p);
    mpz_powm_ui(lr, lr, 512, p);
    mpz_powm_ui(lr, lr, 65536, p);
    mpz_powm_ui(lr, lr, 65536, p);
    mpz_powm_ui(lr, lr, 65536, p);
    mpz_powm_ui(lr, lr, 65536, p);
    mpz_powm_ui(lr, lr, 65536, p);
    mpz_powm_ui(lr, lr, 65536, p);

    uint32_t tramvals[2*MEXPDRV__N_WORDS] = {0,};
    uint32_t result_expect [MEXPDRV__N_WORDS] = {0,};

    for (int i=0; i<40; i++) {
        mpz_mod_2exp(tmp, l, 27);
        mpz_div_2exp(l, l, 27);
        tramvals[i] = mpz_get_ui(tmp);

        mpz_mod_2exp(tmp, r, 27);
        mpz_div_2exp(r, r, 27);
        tramvals[40+i] = mpz_get_ui(tmp);

        mpz_mod_2exp(tmp, lr, 27);
        mpz_div_2exp(lr, lr, 27);
        result_expect[i] = mpz_get_ui(tmp);
    }

    for (int i=0; i<MEXPDRV__C_SIZE/2; i++) {
        mexpdrv_load_tram(40*i, tramvals);
    }

    uint32_t eramvals1[MEXPDRV__E_WORDS*MEXPDRV__C_SIZE] = {0,};
    for (int i=0; i<MEXPDRV__C_SIZE; i++) {
        eramvals1[MEXPDRV__E_WORDS*i+3] = 1;
    }

    uint32_t maddrs[MEXPDRV__N_MULTS];
    for (unsigned i=0; i<MEXPDRV__N_MULTS; i++) {
        maddrs[i] = rand() & 0x000FFFFF;
        if (mexpdrv_load_eram(maddrs[i], i, 0, eramvals1) < 0) {
            mexpdrv_perror("Load eram failed");
            exit(-1);
        }
    }

    if (mexpdrv_start_mult() < 0) {
        mexpdrv_perror("Multiply failed");
        exit(-1);
    }

    for (unsigned i=0; i<MEXPDRV__N_MULTS; i++) {
        if (mexpdrv_set_addr(maddrs[i], i, 0) < 0) {
            mexpdrv_perror("Set address failed");
            exit(-1);
        }
        if (mexpdrv_read_result(maddrs[i], readresp) < 0) {
            mexpdrv_perror("Read failed");
            exit(-1);
        }

        printf("**%x**\n", readresp[0]);
        for (unsigned j=1; j<MEXPDRV__N_WORDS+1; j++) {
            printf("%8.8x %8.8x %s\n", readresp[j], result_expect[j-1], readresp[j] == result_expect[j-1] ? "" : "!!!!");
        }
        printf("\n");
    }

    return 0;
}
