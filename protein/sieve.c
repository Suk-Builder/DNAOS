/* protein/sieve.c -- Prime Counting */
#include "../include/dnaos.h"

void prime_count(AVal*r, int n) {
    if(n < 2) { av_set_i64(r, 0); return; }
    int*is_prime = calloc(n+1, sizeof(int));
    for(int i = 2; i <= n; i++) is_prime[i] = 1;
    for(int i = 2; i * i <= n; i++) {
        if(is_prime[i]) {
            for(int j = i * i; j <= n; j += i) is_prime[j] = 0;
        }
    }
    int cnt = 0;
    for(int i = 2; i <= n; i++) if(is_prime[i]) cnt++;
    av_set_i64(r, cnt);
    free(is_prime);
}

void fibonacci(AVal*r, int n) {
    av_to_gmp(r);
    mpz_t a, b, t; mpz_init_set_si(a, 0); mpz_init_set_si(b, 1); mpz_init(t);
    for(int i = 0; i < n; i++) { mpz_set(t, b); mpz_add(b, b, a); mpz_set(a, t); }
    mpz_set(r->gmp, a); r->has_gmp = 1;
    if(mpz_fits_slong_p(a)) r->i64 = mpz_get_si(a);
    mpz_clear(a); mpz_clear(b); mpz_clear(t);
}

void factorial(AVal*r, int n) {
    av_to_gmp(r); mpz_set_si(r->gmp, 1);
    for(int i = 2; i <= n; i++) mpz_mul_si(r->gmp, r->gmp, i);
    if(mpz_fits_slong_p(r->gmp)) r->i64 = mpz_get_si(r->gmp);
}
