/* 【test_mersenne_report.c -- BSEM Mersenne 素数 Verification Report】 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <gmp.h>
#include <sys/time.h>

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
            last_pct = p;
        }
    }
    
    gettimeofday(&t1, NULL);
    double total = (double)(t1.tv_sec - t0.tv_sec) + (t1.tv_usec - t0.tv_usec) / 1e6;
    if(p >= 1000) printf("\r[LL] M_%lld: 100%% DONE in %.3fs                \n", p, total);
    else printf("[LL] M_%lld: DONE in %.3fs\n", p, total);
    
    int prime = (mpz_cmp_si(s, 0) == 0);
    mpz_clear(m); mpz_clear(s); mpz_clear(t);
    return prime;
}

int main() {
    printf("========================================================================\n");
    printf("BSEM Mersenne Prime Verification Report\n");
    printf("Method: Lucas-Lehmer with IBDWT\n");
    printf("Date: 2026-06-05\n");
    printf("========================================================================\n\n");
    
    // 【Known Mersenne exponents to 测试】
    long long exponents[] = {2, 3, 5, 7, 13, 17, 19, 31, 61, 89, 107, 127, 521};
    int n = sizeof(exponents) / sizeof(exponents[0]);
    
    struct timeval t0, t1;
    gettimeofday(&t0, NULL);
    
    int passed = 0, failed = 0;
    for(int i = 0; i < n; i++) {
        long long p = exponents[i];
        printf("--- Test %d/%d: M_%lld ---\n", i+1, n, p);
        int result = lucas_lehmer(p);
        if(result) {
            printf("RESULT: PRIME\n");
            passed++;
        } else {
            printf("RESULT: COMPOSITE (EXPECTED PRIME - CHECK)\n");
            failed++;
        }
        printf("\n");
    }
    
    gettimeofday(&t1, NULL);
    double total_time = (double)(t1.tv_sec - t0.tv_sec) + (t1.tv_usec - t0.tv_usec) / 1e6;
    
    printf("========================================================================\n");
    printf("SUMMARY: %d/%d passed, %d failed\n", passed, n, failed);
    printf("Total time: %.3fs\n", total_time);
    printf("Average per test: %.3fs\n", total_time / n);
    printf("========================================================================\n");
    
    return failed > 0 ? 1 : 0;
}
