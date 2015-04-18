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

#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>
#include <inttypes.h>
#include <gmp.h>

extern int mexpdrv_errno;

#define MEXPDRV_NOERR       0
#define MEXPDRV_UNINIT      1
#define MEXPDRV_READINVAL   2
#define MEXPDRV_ELOADINVAL  3
#define MEXPDRV_SADDRINVAL  4
#define MEXPDRV_LTRAMINVAL  5
#define MEXPDRV_SMULTINVAL  6
#define MEXPDRV_BATCHTOOBIG 7
#define MEXPDRV_MALLOCFAIL  8

// These constants must actually match what's implemented on the device!
#define MEXPDRV__W_SIZE     27
#define MEXPDRV__N_WORDS    40
#define MEXPDRV__E_WORDS    4
#define MEXPDRV__C_SIZE     1024
#define MEXPDRV__N_MULTS    16
#define MEXPDRV__FIFO_SIZE  2048

// leave this undefined if you're using GMP other than 5.0.5
// unless you confirm that your version also works with the
// speed hack in mexpdrv_prepare_exps
#define MEXPDRV__FAST_EXPPREP 1

/*
#define MEXPDRV__C_SIZE     4
#define MEXPDRV__N_MULTS    4
*/

#define MEXPDRV__ELOAD_RESP 0x10000000
#define MEXPDRV__SADDR_RESP 0x20000000
#define MEXPDRV__LTRAM_RESP 0x30000000
//#define MEXPDRV__RDRES_RESP (0x40000000 | (_MEXPDRV__N_WORDS << 20))
#define MEXPDRV__FLRES_RESP 0x50000000
#define MEXPDRV__SMULT_RESP 0x60000000

#define MEXPDRV__LOAD_TRAM_SIZE  (1 + 2*MEXPDRV__N_WORDS)
#define MEXPDRV__LOAD_TRAM_CSIZE (1 + MEXPDRV__C_SIZE * MEXPDRV__LOAD_TRAM_SIZE / 2)
#define MEXPDRV__LOAD_TRAM_RSIZE (1 + MEXPDRV__C_SIZE / 2)

#define MEXPDRV__LOAD_ERAM_SIZE  (1 + MEXPDRV__C_SIZE * MEXPDRV__E_WORDS)
#define MEXPDRV__LOAD_ERAM_PSIZE (1 + MEXPDRV__N_MULTS * MEXPDRV__LOAD_ERAM_SIZE)
#define MEXPDRV__LOAD_ERAM_RSIZE (1 + MEXPDRV__N_MULTS)

#define MEXPDRV__READ_RSLT_RSIZE (1 + MEXPDRV__N_WORDS)

// returns 0 on success, -1 on error (check ERRNO for error from write())
int mexpdrv_rwrite(void *buf, int len);

// returns 0 on success, -1 on error (check ERRNO for error from write())
int mexpdrv_rread(void *buf, int len);

// prints the error as a string.
void mexpdrv_perror(const char *s);

// initialize the library, handing over wfd and rfd
void mexpdrv_init(int rfd, int wfd);

// send the READ_RESULTS command. Returns -1 on error;
int mexpdrv_read_result(int addr, uint32_t *buffer);

// load exponent. note this also flushes current contents!
int mexpdrv_load_eram(int addr, int unit_sel, int load_result, uint32_t *buffer);

// set address. note this also flushes current contents!
int mexpdrv_set_addr(int addr, int unit_sel, int load_result);

// load elements into table
int mexpdrv_load_tram(int addr, uint32_t *buffer);

// kick off multiplication
int mexpdrv_start_mult(void);

// utils
int mexpdrv_simple_interact(uint32_t cmd, const uint32_t expect, const unsigned errcode);
int mexpdrv_write_interact(uint32_t cmd, const uint32_t expect, const unsigned errcode, uint32_t *buffer, unsigned length);
int mexpdrv_expect(const uint32_t expect, const unsigned errcode);
// read a single byte, then write a whole buffer
int mexpdrv_expect_interact(uint32_t *buffer, const unsigned length, const uint32_t expect, const unsigned errcode);

unsigned mexpdrv_num_chunks(const unsigned vector_length);
unsigned mexpdrv_num_passes(const unsigned batch_size);

uint32_t *mexpdrv_prepare_bases(mpz_t *bases, const unsigned vector_length, const bool dealloc);
uint32_t *mexpdrv_prepare_exps(mpz_t **exps, const unsigned vector_length, const unsigned batch_size, const bool dealloc);
uint32_t **mexpdrv_run_batches(uint32_t **bases, uint32_t *exps, const unsigned vector_length, const unsigned batch_size, const unsigned num_batches, const bool dealloc);
mpz_t **mexpdrv_prepare_results(uint32_t **raw, const unsigned batch_size, const unsigned num_batches, const bool dealloc);

// you probably don't want to use this function
uint32_t *mexpdrv_prepare_exps_1pass(mpz_t **exps, const uint32_t *addresses, const bool load_result, const bool dealloc);

