/* av_math.c — DNAOS NSM backend: AVal big-integer math + kernel stubs
 * Uses GMP for arbitrary-precision arithmetic.
 */
#include "include/av_math.h"
#include <stdio.h>
#include <string.h>

/* ── AVal ── */
void av_init(AVal *a) {
    a->i64 = 0;
    mpz_init(a->gmp);
    a->has_gmp = 1;
}

void av_clear(AVal *a) {
    if (a->has_gmp) mpz_clear(a->gmp);
    a->has_gmp = 0;
}

void av_set_i64(AVal *a, int64_t v) {
    a->i64 = v;
    mpz_set_si(a->gmp, v);
}

void av_set_str(AVal *a, const char *s) {
    mpz_set_str(a->gmp, s, 10);
}

char *av_get_str(AVal *a) {
    return mpz_get_str(NULL, 10, a->gmp);
}

void av_add(AVal *r, const AVal *a, const AVal *b) {
    mpz_add(r->gmp, a->gmp, b->gmp);
}

void av_sub(AVal *r, const AVal *a, const AVal *b) {
    mpz_sub(r->gmp, a->gmp, b->gmp);
}

void av_mul(AVal *r, const AVal *a, const AVal *b) {
    mpz_mul(r->gmp, a->gmp, b->gmp);
}

void av_to_gmp(const AVal *a, mpz_t rop) {
    mpz_set(rop, a->gmp);
}

/* ── Kernel stubs ── */
void kernel_init(void) {}
void kernel_shutdown(void) {}