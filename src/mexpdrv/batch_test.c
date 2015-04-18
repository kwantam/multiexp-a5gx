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
    struct timespec tps, tpe;
    gmp_randstate_t randstate;
    gmp_randinit_default(randstate);
    gmp_randseed_ui(randstate, time(NULL));
    mpz_t tmp, p, g;
    mpz_init_set_str(p, "1619218026458484946819962773751338456396453198113136946855210864219442716543962775135683069611496995961496622914534495291118469899086347814936107199525908079372139394212530890915735261936745730729918141427781960548496059867397541588944826845193276450726480452098870156418667316921844020257490620069168050106461661928747958239", 10);
    mpz_init_set_str(g, "428700821466822934267692978879079835728058628943513747690829420627711837499111234225330033830684013299864555091333766313516808130320761164047453342262327570202560596316843440366543162713661353539376831161734017876804117912244757843793896384750486276972936354208374798718474256162935199437127342803159091099969038114697104114", 10);
    mpz_init(tmp);

    unsigned num_chunks = 8;
    unsigned num_passes = 64;
    const unsigned num_batches = 2;
    if (argc > 2) {
        num_chunks = (unsigned) abs(atoi(argv[1]));
        num_passes = (unsigned) abs(atoi(argv[2]));
    }

    const unsigned vector_length = num_chunks * MEXPDRV__C_SIZE;
    const unsigned batch_size = num_passes * MEXPDRV__N_MULTS;
    mpz_t bases[num_batches][vector_length];
    mpz_t *exps[batch_size];
    mpz_t calcs[num_batches][batch_size];

    double sw_time, hw_prep_time, hw_exec_time, hw_result_time;

    // generate random set of bases (all generators q-subgroup of Z_p)
    for(unsigned i=0; i<vector_length; i++) {
        for(unsigned j=0; j<num_batches; j++) {
            mpz_init(bases[j][i]);
            mpz_urandomb(tmp, randstate, 128);
            mpz_powm(bases[j][i], g, tmp, p);
        }
    }

    // generate random vectors of exponents
    for(unsigned i=0; i<batch_size; i++) {
        exps[i] = (mpz_t *) malloc(sizeof(mpz_t) * num_chunks * MEXPDRV__C_SIZE);
        for (unsigned j=0; j<vector_length; j++) {
            mpz_init(exps[i][j]);
            mpz_urandomb(exps[i][j], randstate, 128);
        }
    }

    clock_gettime(CLOCK_MONOTONIC, &tps);
    for(unsigned i=0; i<batch_size; i++) {
        for (unsigned k=0; k<num_batches; k++) {
            mpz_init_set_ui(calcs[k][i], 1);

            for(unsigned j=0; j<vector_length; j++) {
                mpz_powm(tmp, bases[k][j], exps[i][j], p);
                mpz_mul(calcs[k][i], calcs[k][i], tmp);
                mpz_mod(calcs[k][i], calcs[k][i], p);
            }
        }
    }
    clock_gettime(CLOCK_MONOTONIC, &tpe);
    sw_time = (double) (tpe.tv_nsec - tps.tv_nsec + 1000000000 * (tpe.tv_sec - tps.tv_sec));

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

    clock_gettime(CLOCK_MONOTONIC, &tps);
    uint32_t *ui_bases[num_batches];
    for (unsigned i=0; i<num_batches; i++) {
        ui_bases[i] = mexpdrv_prepare_bases(bases[i], vector_length, true);
    }
    uint32_t *ui_exps = mexpdrv_prepare_exps(exps, vector_length, batch_size, true);
    clock_gettime(CLOCK_MONOTONIC, &tpe);
    hw_prep_time = (double) (tpe.tv_nsec - tps.tv_nsec + 1000000000 * (tpe.tv_sec - tps.tv_sec));

    clock_gettime(CLOCK_MONOTONIC, &tps);
    uint32_t **ui_results = mexpdrv_run_batches(ui_bases, ui_exps, vector_length, batch_size, num_batches, true);
    clock_gettime(CLOCK_MONOTONIC, &tpe);
    hw_exec_time = (double) (tpe.tv_nsec - tps.tv_nsec + 1000000000 * (tpe.tv_sec - tps.tv_sec));

    clock_gettime(CLOCK_MONOTONIC, &tps);
    mpz_t **results = mexpdrv_prepare_results(ui_results, batch_size, num_batches, true);
    clock_gettime(CLOCK_MONOTONIC, &tpe);
    hw_result_time = (double) (tpe.tv_nsec - tps.tv_nsec + 1000000000 * (tpe.tv_sec - tps.tv_sec));

    for(unsigned j=0; j<num_batches; j++) {
        for(unsigned i=0; i<batch_size; i++) {
            if (mpz_cmp(results[j][i], calcs[j][i])) {
                gmp_printf("err: %Zx != %Zx\n", results[j][i], calcs[j][i]);
            }
        }
    }

    printf("%f sw\n%f hw_prep\n%f hw_exec\n%f hw_result\n\n%f hw_exec:sw speedup\n%f (hw_exec+hw_result):sw speedup\n%f (hw_prep+hw_exec+hw_result):sw speedup\n",
            sw_time, hw_prep_time, hw_exec_time, hw_result_time,
            sw_time/hw_exec_time,
            sw_time/(hw_exec_time+hw_result_time),
            sw_time/(hw_prep_time+hw_exec_time+hw_result_time));

    return 0;
}
