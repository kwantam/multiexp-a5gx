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

#include "mexpdrv.h"

int mexpdrv_errno;
int mexpdrv_wfd = -1;
int mexpdrv_rfd = -1;

const char *mexpdrv_errno_strings[] =
        { "No error."
        , "You must call mexpdrv_init() first."
        , "Invalid response to READ_RESULT."
        , "Invalid response to LOAD_ERAM."
        , "Invalid response to SET_ADDR."
        , "Invalid response to LOAD_TRAM."
        , "Invalid response to START_MULT."
        , "Batch size too large. Max 2^20-1."
        , "malloc() failed."
        };

int mexpdrv_rwrite(void *buf, int len) {
    if (mexpdrv_wfd < 0) {
        mexpdrv_errno = MEXPDRV_UNINIT;
        return -1;
    }

    char *wptr = buf;
    do {
        int written = write(mexpdrv_wfd, wptr, len);
        if (written < 0) {
            return written;
        }
        len -= written;
        wptr += written;
    } while (len > 0);
    return 0;
}

int mexpdrv_rread(void *buf, int len) {
    if (mexpdrv_rfd < 0) {
        mexpdrv_errno = MEXPDRV_UNINIT;
        return -1;
    }

    char *wptr = buf;
    do {
        int readlen = read(mexpdrv_rfd, wptr, len);
        if (readlen < 0) {
            return readlen;
        }
        len -= readlen;
        wptr += readlen;
    } while (len > 0);
    return 0;
}

void mexpdrv_perror(const char *s) {
    if (mexpdrv_errno == 0) {
        perror(s);
    } else {
        if (s != NULL) {
            fprintf(stderr, "%s: ", s);
        }
        fprintf(stderr, "%s\n", mexpdrv_errno_strings[mexpdrv_errno]);
    }
}

void mexpdrv_init(int rfd, int wfd) {
    mexpdrv_rfd = rfd;
    mexpdrv_wfd = wfd;
}

int mexpdrv_read_result(int addr, uint32_t *buffer) {
    uint32_t read_cmd = 0x20000000 | (addr & 0x000FFFFF);
    int status;
    if ((status = mexpdrv_rwrite(&read_cmd, 4)) < 0) {
        return status;
    }
    if ((status = mexpdrv_rread(buffer, 4*(MEXPDRV__N_WORDS+1))) < 0) {
        return status;
    }
    if ((buffer[0] & 0xF0000000) != 0x40000000) {
        mexpdrv_errno = MEXPDRV_READINVAL;
        return -1;
    }
    mexpdrv_errno = MEXPDRV_NOERR;
    return 0;
}

int mexpdrv_load_eram(int addr, int unit_sel, int load_result, uint32_t *buffer) {
    uint32_t loadres_mask = load_result ? 0x02000000 : 0;
    uint32_t unit_mask = (0x0000001F & unit_sel) << 20;
    uint32_t eload_cmd = 0x04000000 | loadres_mask | unit_mask | (0x000FFFFF & addr);
    return mexpdrv_write_interact(eload_cmd, MEXPDRV__ELOAD_RESP, MEXPDRV_ELOADINVAL, buffer, 4*MEXPDRV__E_WORDS*MEXPDRV__C_SIZE);
}

int mexpdrv_load_tram(int addr, uint32_t *buffer) {
    uint32_t ltram_cmd = 0x10000000 | (0x00007FFF & addr);
    return mexpdrv_write_interact(ltram_cmd, MEXPDRV__LTRAM_RESP, MEXPDRV_LTRAMINVAL, buffer, 8*MEXPDRV__N_WORDS);
}

int mexpdrv_write_interact(uint32_t cmd, const uint32_t expect, const unsigned errcode, uint32_t *buffer, unsigned length) {
    int status;
    if ((status = mexpdrv_rwrite(&cmd, 4)) < 0) {
        return status;
    }
    if ((status = mexpdrv_rwrite(buffer, length)) < 0) {
        return status;
    }
    if ((status = mexpdrv_expect(expect, errcode)) < 0) {
        return status;
    }
    mexpdrv_errno = MEXPDRV_NOERR;
    return 0;
}

int mexpdrv_set_addr(int addr, int unit_sel, int load_result) {
    uint32_t loadres_mask = load_result ? 0x02000000 : 0;
    uint32_t unit_mask = (0x0000001F & unit_sel) << 20;
    uint32_t saddr_cmd = 0x08000000 | loadres_mask | unit_mask | (0x000FFFFF & addr);
    return mexpdrv_simple_interact(saddr_cmd, MEXPDRV__SADDR_RESP, MEXPDRV_SADDRINVAL);
}

int mexpdrv_start_mult(void) {
    return mexpdrv_simple_interact(0x80000000, MEXPDRV__SMULT_RESP, MEXPDRV_SMULTINVAL);
}

int mexpdrv_simple_interact(uint32_t cmd, const uint32_t expect, const unsigned errcode) {
    int status;
    if ((status = mexpdrv_rwrite(&cmd, 4)) < 0) {
        return status;
    }
    if ((status = mexpdrv_expect(expect, errcode)) < 0) {
        return status;
    }
    mexpdrv_errno = MEXPDRV_NOERR;
    return 0;
}

int mexpdrv_expect(const uint32_t expect, const unsigned errcode) {
    int status;
    uint32_t response;
    if ((status = mexpdrv_rread(&response, 4)) < 0) {
        return status;
    }
    if (response != expect) {
        mexpdrv_errno = errcode;
        return -1;
    }
    mexpdrv_errno = MEXPDRV_NOERR;
    return 0;
}

unsigned mexpdrv_num_chunks(const unsigned vector_length) {
    unsigned num_chunks = vector_length / MEXPDRV__C_SIZE + (vector_length % MEXPDRV__C_SIZE ? 1 : 0);
    return num_chunks;
}

unsigned mexpdrv_num_passes(const unsigned batch_size) {
    unsigned num_passes = batch_size / MEXPDRV__N_MULTS + (batch_size % MEXPDRV__N_MULTS ? 1 : 0);
    return num_passes;
}

// takes vector_length bases, and returns a region of memory ready
// to be dumped to the device
//
// If dealloc is true, it deallocates each of the input bases when it's done with them.
//
// **NOTE** don't forget to free() the result of this function when you're done
//
// result is sizeof(uint32_t) * ceiling(vector_length/MEXPDRV__C_SIZE) * (1 + MEXPDRV__C_SIZE * (1 + 2 * MEXPDRV__N_WORDS) / 2) bytes
//
// you should write this to the device 1 "chunk" at a time, that is,
// sizeof(uint32_t) * (1 + MEXPDRV__C_SIZE * (1 + 2 * MEXPDRV__N_WORDS) / 2)
// and then make all "passes" through this chunk by sending the exponenets and then running the multiexponentiation
//
// For each chunk, the device will respond with sizeof(uint32_t) * ( 1 + MEXPDRV__C_SIZE / 2 ) bytes, which you should
// read with mexpdrv_rread().
//
// It's probably best to send one "chunk", do some work (e.g., prep your exponents), then send your first batch of exponents
// and then read the output from the device. The device has a 2048*sizeof(uint32_t) byte fifo, so you don't have to immediately
// read out the data (but the device will block if its fifo gets full!!!)
uint32_t *mexpdrv_prepare_bases(mpz_t *bases, const unsigned vector_length, const bool dealloc) {
    // we always completely fill TRAM, so round up vector_length to the next MEXPDRV__C_SIZE
    const unsigned num_chunks = mexpdrv_num_chunks(vector_length);

    // each LOAD_TRAM command has 2*N__WORDS + 1 and consumes 2 vector elements.
    // add one more at the beginning for the SET_ADDR mult0 0xFFFFF command, and assume the
    // function that dumps to the h/w will copy that word throughout the buffer as necessary
    const unsigned converted_size = MEXPDRV__LOAD_TRAM_CSIZE * num_chunks;
    uint32_t *converted = (uint32_t *) malloc(converted_size * sizeof(uint32_t));
    if (converted == NULL) {
        return NULL;
    }

    mpz_t tmp1, tmp2;
    mpz_init(tmp1);
    mpz_init(tmp2);

    for (unsigned h=0; h<num_chunks; h++) {
        converted[h*MEXPDRV__LOAD_TRAM_CSIZE] = 0x080FFFFF; // SET_ADDR mult0 0xFFFFF so we don't kill any data
        uint32_t *converted_int = &(converted[h*MEXPDRV__LOAD_TRAM_CSIZE+1]);

        for (unsigned i=0; i<MEXPDRV__C_SIZE/2; i++) {
            uint32_t taddr = i * MEXPDRV__N_WORDS;
            converted_int[i*MEXPDRV__LOAD_TRAM_SIZE] = 0x10000000 | (0x00007FFF & taddr);
            uint32_t *this_conv = &(converted_int[i*MEXPDRV__LOAD_TRAM_SIZE+1]);

            unsigned basenum = MEXPDRV__C_SIZE*h + 2*i;
            for (unsigned j=0; j<2; j++) {
                if ((basenum+j) >= vector_length) {
                    this_conv[j*MEXPDRV__N_WORDS] = 1;
                    memset(&(this_conv[j*MEXPDRV__N_WORDS+1]), 0, sizeof(uint32_t)*(MEXPDRV__N_WORDS-1));
                } else {
                    mpz_set(tmp1, bases[basenum+j]);
                    for (int k=0; k<MEXPDRV__N_WORDS; k++) {
                        mpz_mod_2exp(tmp2, tmp1, MEXPDRV__W_SIZE);
                        mpz_div_2exp(tmp1, tmp1, MEXPDRV__W_SIZE);
                        this_conv[j*MEXPDRV__N_WORDS+k] = mpz_get_ui(tmp2);
                    }
                    if (dealloc) {
                        mpz_clear(bases[basenum+j]);
                    }
                }
            }
        }
    }

    mpz_clear(tmp1);
    mpz_clear(tmp2);
    return converted;
}

// takes vector_length * batch_size exponents. batch_size must be < 2^20-1, because that's all
// the RAM we have available on the device for intermediate results. vector_length is in principle
// unlimited, but of course if you call this function you'd better have enough RAM to store the
// result!
//
// If dealloc is true, this function will deallocate the input exps as it walks through them.
//
// **NOTE** don't forget to free() the result of this function when you're done
//
// result is sizeof(uint32_t) * ceiling(batch_size / MEXPDRV__N_MULTS)
//                            * ceiling(vector_length / MEXPDRV__C_SIZE)
//                            * (1 + MEXPDRV__N_MULTS * (1 + MEXPDRV__C_SIZE * MEXPDRV__E_WORDS))
//
// you should write this to the device 1 "pass" at a time, that is,
// sizeof(uint32_t) * (1 + MEXPDRV__N_MULTS * (1 + MEXPDRV__C_SIZE * MEXPDRV__E_WORDS)) bytes
//
// After you have finished with ceiling(batch_size / MEXPDRV__N_MULTS) such passes,
// write the next chunk of bases to the device, and then write the next group of passes.
//
// After each pass, the device will respond with sizeof(uint32_t) * (1 + MEXPDRV__N_MULTS) bytes, which
// you should read with mexpdrv_rread().
//
// You can cut down on the number of syscalls by not bothering to read after each pass. The device has
// a large enough fifo for 2048 uint32_t responses, so you can get away with quite a few passes before
// you need to spend the time to read a response.
//
// (Of course, you might be conscientious about checking return values, if only the device indicated failure...)
//
// After you have finished the final pass, you should call mexpdrv_flush_readall(batch_size), which will make
// your wildest dreams come true (assuming those dreams involve the results of multiexponentiations).
//
// If your exponents aren't all ready at once, you should consider instead using mexpdrv_prepare_exps_1pass(),
// which only prepares enough input for one round of multiplication. That gives you some time to interleave
// additional computations as necessary.
uint32_t *mexpdrv_prepare_exps(mpz_t **exps, const unsigned vector_length, const unsigned batch_size, const bool dealloc) {
    // we always fill the whole exponent RAM; any excess is just 0
    const unsigned num_chunks = mexpdrv_num_chunks(vector_length);
    const unsigned num_passes = mexpdrv_num_passes(batch_size);

    // each LOAD_ERAM command has MEXPDRV__C_SIZE * MEXPDRV__E_WORDS + 1 uint32_t values
    // there are MEXPDRV__N_MULTS of these per pass, plus a START_MULT command
    // there are num_passes per chunk, and num_chunks total
    const unsigned load_eram_csize = MEXPDRV__LOAD_ERAM_PSIZE * num_passes;
    const unsigned converted_size = load_eram_csize * num_chunks;
    uint32_t *converted = (uint32_t *) malloc(converted_size * sizeof(uint32_t));
    if (converted == NULL) {
        return NULL;
    }

#ifdef MEXPDRV__FAST_EXPPREP
    // low-level bit twiddling! Be careful...
    mp_limb_t *this_elem;
    uint32_t *limb_data;
    const unsigned limbs_per_exp = MEXPDRV__E_WORDS*sizeof(uint32_t)/sizeof(mp_limb_t);
    const unsigned words_per_limb = sizeof(mp_limb_t)/sizeof(uint32_t);
#else
    // alternatively, less low-level but slower
    mpz_t tmp1, tmp2;
    mpz_init(tmp1);
    mpz_init(tmp2);
#endif

    // loop over chunks
    for (unsigned chunk=0; chunk<num_chunks; chunk++) {
        uint32_t loadres_mask = chunk ? 0x02000000 : 0; // first chunk starts with clear accumulator
        uint32_t *this_chunk = &(converted[chunk*load_eram_csize]);
        // loop over passes
        for (unsigned pass=0; pass<num_passes; pass++) {
            uint32_t *this_pass = &(this_chunk[pass*MEXPDRV__LOAD_ERAM_PSIZE]);
            uint32_t addr_base = pass * MEXPDRV__N_MULTS;
            // loop over multipliers
            for (unsigned mult=0; mult<MEXPDRV__N_MULTS; mult++) {
                uint32_t unit_mask = (0x0000001F & mult) << 20;
                uint32_t addr = 0x000FFFFF & (mult + addr_base);
                // 0x04=LOAD_ERAM ; loadres_mask depends on chunk; unit_mask depends on mult; addr depends on pass and mult
                this_pass[mult*MEXPDRV__LOAD_ERAM_SIZE] = 0x04000000 | loadres_mask | unit_mask | addr;
                uint32_t *this_mult = &(this_pass[mult*MEXPDRV__LOAD_ERAM_SIZE+1]);
                if ((pass*MEXPDRV__N_MULTS + mult) >= batch_size) {
                    // no data here; just write 0 to the exponent cache
                    memset(this_mult, 0, sizeof(uint32_t) * (MEXPDRV__LOAD_ERAM_SIZE-1));
                } else {
                    // loop over exps
                    for (unsigned elem=0; elem<MEXPDRV__C_SIZE; elem++) {
                        if ((chunk*MEXPDRV__C_SIZE+elem) >= vector_length) {
                            memset(&(this_mult[elem*MEXPDRV__E_WORDS]), 0, sizeof(uint32_t) * MEXPDRV__E_WORDS);
                        } else {
                            // loop over words of exponent
#ifdef MEXPDRV__FAST_EXPPREP
                            this_elem = exps[pass*MEXPDRV__N_MULTS+mult][chunk*MEXPDRV__C_SIZE+elem]->_mp_d;
                            for (unsigned limb=0; limb<limbs_per_exp; limb++) {
                                limb_data = (uint32_t *) &(this_elem[limb]);
                                for (unsigned wordn=0; wordn<words_per_limb; wordn++) {
                                    this_mult[elem*MEXPDRV__E_WORDS+limb*words_per_limb+wordn] = limb_data[wordn];
                                }
                            }
#else
                            mpz_set(tmp1, exps[pass*MEXPDRV__N_MULTS+mult][chunk*MEXPDRV__C_SIZE+elem]);
                            for (unsigned wordn=0; wordn<MEXPDRV__E_WORDS; wordn++) {
                                mpz_mod_2exp(tmp2, tmp1, 32);
                                mpz_div_2exp(tmp1, tmp1, 32);
                                this_mult[elem*MEXPDRV__E_WORDS+wordn] = mpz_get_ui(tmp2);
                            }
#endif
                            if (dealloc) {
                                mpz_clear(exps[pass*MEXPDRV__N_MULTS+mult][chunk*MEXPDRV__C_SIZE+elem]);
                            }
                        }
                    }
                }
            }
            // command to start the multiplication
            this_pass[MEXPDRV__LOAD_ERAM_PSIZE-1] = 0x80000000;
        }
    }

#ifndef MEXPDRV__FAST_EXPPREP
    mpz_clear(tmp1);
    mpz_clear(tmp2);
#endif
    return converted;
}

// top-level run function
// Runs a number of batches of bases against the same set of exponents (you might use this, e.g., for ElGamal, with num_batches = 2)
//
// Returns the results all packaged up as num_batches vectors of batch_size mpz_t, which it allocates.
//
// *NOTE* Don't forget to dealloc all the mpz_t with mpz_clear *and* free() the pointer itself!
//
// *NOTE* This function assumes the exponents are sized for the device (i.e., 32 bits * MEXPDRV__E_WORDS). If your exponents are bigger
// than this, you will need to preprocess the bases and exponents such that
//      g_i becomes g_{i,0} through g_{i_n}, where g_{i,j} = g_i^{2^{j*32*MEXPDRV__E_WORDS}}, and n = log2(expsize)/(32*MEXPDRV__E_WORDS)
//      e_i becomes e_{i,0} through e_{i_n}, where e_{i,j} = floor(e_i / 2^{j*32*MEXPDRV__E_WORDS}) % 2^{j*32*MEXPDRV__E_WORDS}
// ALSO, for efficiency's sake, if you have a bunch of leftover 0 bits in e_{i,n}, you should intersperse g_{i,j},g_{i+1,j} and e_{i,j},e{i+1,j} for i even
//      e_{i,0} e_{i+1,0} e_{i,1} e_{i+1,1} .. e_{i,n},e_{i+1,n}
//      g_{i,0} g_{i+1,0} g_{i,1} g_{i+1,1} .. g_{i,n},e_{i+1,n}
// This results in lots of pairs of zeros in the high-order bits of the n exponents, which are just multiplications by 1, which are optimized away
uint32_t **mexpdrv_run_batches(uint32_t **bases, uint32_t *exps, const unsigned vector_length, const unsigned batch_size, const unsigned num_batches, const bool dealloc) {
    if (batch_size > 1048575) {
        mexpdrv_errno = MEXPDRV_BATCHTOOBIG;
        return NULL;
    }

    // vector of vectors of results
    uint32_t **results = (uint32_t **) malloc(num_batches * sizeof(uint32_t *));

    const unsigned num_chunks = mexpdrv_num_chunks(vector_length);
    const unsigned num_passes = mexpdrv_num_passes(batch_size);
    const unsigned load_eram_csize = MEXPDRV__LOAD_ERAM_PSIZE * num_passes;
    const unsigned maxresponse = 1536;

    uint32_t flushresults[MEXPDRV__N_MULTS];
    for (unsigned i=0; i<MEXPDRV__N_MULTS; i++) {
        flushresults[i] = 0x080FFFFF | (i << 20);
    }

    uint32_t getresults[batch_size];
    for (unsigned i=0; i<batch_size; i++) {
        getresults[i] = 0x20000000 | i;
    }
    const unsigned results_per_request = maxresponse / MEXPDRV__READ_RSLT_RSIZE;

    uint32_t responses[maxresponse];
    unsigned respsize;

    for (unsigned batch=0; batch<num_batches; batch++) {
        results[batch] = (uint32_t *) malloc(MEXPDRV__READ_RSLT_RSIZE*batch_size*sizeof(uint32_t));
        if (results[batch] == NULL) {
            // note that I'm not deallocating previous results, so this could be messy.
            mexpdrv_errno = MEXPDRV_MALLOCFAIL;
            return NULL;
        }

        for (unsigned chunk=0; chunk<num_chunks; chunk++) {
            if (mexpdrv_rwrite(&(bases[batch][MEXPDRV__LOAD_TRAM_CSIZE*chunk]), sizeof(uint32_t)*MEXPDRV__LOAD_TRAM_CSIZE) < 0) {
                return NULL;
            }
            respsize = MEXPDRV__LOAD_TRAM_RSIZE;
            for (unsigned pass=0; pass<num_passes; pass++) {
                if ((respsize + MEXPDRV__LOAD_ERAM_RSIZE) > maxresponse) {
                    if (mexpdrv_rread(responses, sizeof(uint32_t)*respsize) < 0) {
                        return NULL;
                    }
                    respsize = 0;
                }

                if (mexpdrv_rwrite(&(exps[chunk*load_eram_csize+pass*MEXPDRV__LOAD_ERAM_PSIZE]), sizeof(uint32_t)*MEXPDRV__LOAD_ERAM_PSIZE) < 0) {
                    return NULL;
                }
                respsize += MEXPDRV__LOAD_ERAM_RSIZE;
            }
            if (mexpdrv_rread(responses, sizeof(uint32_t)*respsize) < 0) {
                return NULL;
            }
        }

        if (mexpdrv_rwrite(flushresults, sizeof(uint32_t)*MEXPDRV__N_MULTS) < 0) {
            return NULL;
        }
        if (mexpdrv_rread(responses, sizeof(uint32_t)*MEXPDRV__N_MULTS) < 0) {
            return NULL;
        }

        unsigned results_left = batch_size;
        while (results_left > 0) {
            unsigned resultnum = batch_size - results_left;
            unsigned numtoread;
            if (results_left > results_per_request) {
                numtoread = results_per_request;
            } else {
                numtoread = results_left;
            }
            if (mexpdrv_rwrite(&(getresults[resultnum]), sizeof(uint32_t)*numtoread) < 0) {
                return NULL;
            }
            if (mexpdrv_rread(&(results[batch][resultnum*MEXPDRV__READ_RSLT_RSIZE]), sizeof(uint32_t)*numtoread*MEXPDRV__READ_RSLT_RSIZE) < 0) {
                return NULL;
            }
            results_left -= numtoread;
        }

        if (dealloc) {
            free(bases[batch]);
        }
    }

    if (dealloc) {
        free(exps);
    }

    return results;
}

mpz_t **mexpdrv_prepare_results(uint32_t **raw, const unsigned batch_size, const unsigned num_batches, const bool dealloc) {
    mpz_t **results = (mpz_t **) malloc(num_batches * sizeof(mpz_t *));

    for (unsigned batch=0; batch<num_batches; batch++) {
        results[batch] = (mpz_t *) malloc(batch_size * sizeof(mpz_t));
        mpz_t *this_rslt = results[batch];
        uint32_t *this_raw = raw[batch];

        for(unsigned rnum=0; rnum<batch_size; rnum++) {
            uint32_t *this_rnum = &(this_raw[rnum*MEXPDRV__READ_RSLT_RSIZE+1]);
            mpz_init_set_ui(this_rslt[rnum], this_rnum[MEXPDRV__N_WORDS-1]);

            // progressively shift the value, adding in the next lower order word
            for (int wnum=MEXPDRV__N_WORDS-2; wnum>=0; wnum--) {
                mpz_mul_2exp(this_rslt[rnum], this_rslt[rnum], MEXPDRV__W_SIZE);
                mpz_add_ui(this_rslt[rnum], this_rslt[rnum], this_rnum[wnum]);
            }
        }

        if (dealloc) {
            free(raw[batch]);
        }
    }

    if (dealloc) {
        free(raw);
    }

    return results;
}

// takes MEXPDRV__N_MULTS * MEXPDRV__C_SIZE exponents and returns a region of memory
// ready to be dumped to the device
//
// expects **exps to be exactly a MEXPDRV__N_MULTS length array of MEXPDRV__C_SIZE exponents <=32*MEXPDRV__E_WORDS bits
// it returns an array
//
// uint32_t *addresses should contain MEXPDRV__N_MULTS addresses for the corresponding data,
// and load_result indicates whether we should load a previous result from this address. In other
// words, load_result should be 1 except the first time exponents corresponding to a particular
// address are loaded (i.e., when operating on the first "chunk" of bases)
//
// **NOTE** don't forget to free() the result of this function when you're done!
//
// result is sizeof(uint32_t) * (1 + MEXPDRV__N_MULTS * (1 + MEXPDRV__E_WORDS * MEXPDRV__C_SIZE)) bytes
//
// When you write this data to the device, it will respond with sizeof(uint32_t) * (1 + MEXPDRV__N_MULTS) bytes.
// You do not have to read these immediately; see comments above convert_bases.
uint32_t *mexpdrv_prepare_exps_1pass(mpz_t **exps, const uint32_t *addresses, const bool load_result, const bool dealloc) {
    // a "pass" is a set of multiplies done over a chunk; it takes passes * MEXPDRV__N_MULTS
    // to fully compute a chunk's worth of bases (these get padded out)

    // the pass also includes the START_MULT command
    unsigned emem_size = 1 + MEXPDRV__E_WORDS * MEXPDRV__C_SIZE;
    unsigned pass_size = 1 + MEXPDRV__N_MULTS * emem_size;
    uint32_t *converted = (uint32_t *) malloc(pass_size * sizeof(uint32_t));

    uint32_t loadres_mask = load_result ? 0x02000000 : 0;

    mpz_t tmp1, tmp2;
    mpz_init(tmp1);
    mpz_init(tmp2);

    for (unsigned i=0; i<MEXPDRV__N_MULTS; i++) {
        uint32_t unit_mask = (0x0000001F & i) << 20;
        converted[i*emem_size] = 0x04000000 | loadres_mask | unit_mask | (0x000FFFFF & addresses[i]);
        uint32_t *converted_int = &(converted[i*emem_size+1]);

        for (unsigned j=0; j<MEXPDRV__C_SIZE; j++) {
            mpz_set(tmp1, exps[i][j]);
            for (int k=0; k<MEXPDRV__E_WORDS; k++) {
                mpz_mod_2exp(tmp2, tmp1, 32);
                mpz_div_2exp(tmp1, tmp1, 32);
                converted_int[j*MEXPDRV__E_WORDS+k] = mpz_get_ui(tmp2);
            }
            if (dealloc) {
                mpz_clear(exps[i][j]);
            }
        }
    }

    // and finally the command to start the multiplication
    converted[pass_size-1] = 0x80000000;

    mpz_clear(tmp1);
    mpz_clear(tmp2);
    return 0;
}
