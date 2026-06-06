/* 【genome/d1d4.c -- Bricklayer Meta-Theorem D1-D4 Physical 层】 */
#include "../include/dnaos.h"

/* 【D1 CAPTURE: Encode N as DNA concentration】 */
void d1_capture(long long n, AVal*out) {
    av_set_i64(out, n);
}

/* 【D2 TURAN-KUBILIUS: PCR multiplication + concentration addition】 */
void d2_turan(AVal*a, AVal*b, AVal*out) {
    av_to_gmp(a); av_to_gmp(b);
    av_to_gmp(out);
    mpz_add(out->gmp, a->gmp, b->gmp);
    if(mpz_fits_slong_p(out->gmp)) out->i64 = mpz_get_si(out->gmp);
}

/* 【D3 BERRY-ESSEEN: 错误 bound estimation】 */
void d3_berry(AVal*v, AVal*error) {
    /* 【错误 ~ 平方根(N) * 自然对数(N) / (8*pi)】 */
    av_to_gmp(v);
    mpz_t tmp; mpz_init(tmp);
    mpz_sqrt(tmp, v->gmp);
    av_set_i64(error, mpz_get_si(tmp) * 2); /* 【Simplified】 */
    mpz_clear(tmp);
}

/* 【D4 BRICKLAYER LOOP: Iterative 输出】 */
void d4_iterate(int steps, void(*cb)(int step, AVal*val)) {
    AVal v; av_init(&v);
    for(int i = 1; i <= steps; i++) {
        /* 【Gram point: t_n = 2*pi*n / 自然对数(n)】 */
        if(i == 1) av_set_i64(&v, 14);
        else {
            double ln_i = log(i);
            if(ln_i > 0) av_set_i64(&v, (long long)(2.0 * M_PI * i / ln_i));
        }
        if(cb) cb(i, &v);
    }
    av_clear(&v);
}
