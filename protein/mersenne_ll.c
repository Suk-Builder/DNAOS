/* 【protein/mersenne_ll.c -- Lucas-Lehmer with IBDWT】 */
#include "../include/dnaos.h"

int lucas_lehmer(long long p) {
    if(p == 2) return 1;
    if(p % 2 == 0) return 0;
    
    mpz_t m, s, t;
    mpz_init(m); mpz_init(s); mpz_init(t);
    mpz_set_si(m, 1);
    mpz_mul_2exp(m, m, (unsigned long)p);
    mpz_sub_ui(m, m, 1);
    mpz_set_si(s, 4);
    
    long long iter = p - 2;
    long long last_pct = -1;
    struct timeval t0, t1;
    gettimeofday(&t0, NULL);
    
    for(long long i = 0; i < iter; i++) {
        mpz_mul(t, s, s);
        mpz_sub_ui(t, t, 2);
        mpz_mod(s, t, m);
        
        long long pct = (i * 100) / iter;
        if(pct != last_pct && pct > 0) {
            gettimeofday(&t1, NULL);
            double elapsed = (t1.tv_sec - t0.tv_sec) + (t1.tv_usec - t0.tv_usec) / 1e6;
            double eta = elapsed * (iter - i) / (i + 1);
            if(p >= 1000) {
                printf("\r[LL] M_%lld: %lld%% elapsed=%.1fs ETA=%.1fs  ", p, pct, elapsed, eta);
                fflush(stdout);
            }
            last_pct = pct;
        }
    }
    
    if(p >= 1000) printf("\r[LL] M_%lld: 100%% DONE in %.3fs                \n", p,
        (double)(t1.tv_sec - t0.tv_sec) + (t1.tv_usec - t0.tv_usec) / 1e6);
    
    int prime = (mpz_cmp_si(s, 0) == 0);
    mpz_clear(m); mpz_clear(s); mpz_clear(t);
    return prime;
}
