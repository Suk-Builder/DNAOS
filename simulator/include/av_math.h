#ifndef AV_MATH_H
#define AV_MATH_H

#include <stdint.h>
#include <gmp.h>
#include "../nsm_backend.h"

/* ── AVal: arbitrary-precision integer (matches dnaos.h) ── */
typedef struct {
    long long i64;   /* cache for fits-in-64 values */
    mpz_t     gmp;   /* bignum storage */
    int       has_gmp;
} AVal;

void av_init(AVal *a);
void av_clear(AVal *a);
void av_set_i64(AVal *a, int64_t v);
void av_set_str(AVal *a, const char *s);
char *av_get_str(AVal *a);
void av_add(AVal *r, const AVal *a, const AVal *b);
void av_sub(AVal *r, const AVal *a, const AVal *b);
void av_mul(AVal *r, const AVal *a, const AVal *b);
void av_to_gmp(const AVal *a, mpz_t rop);

/* ── kernel stub (no-op on simulator) ── */
void kernel_init(void);
void kernel_shutdown(void);

#endif /* AV_MATH_H */