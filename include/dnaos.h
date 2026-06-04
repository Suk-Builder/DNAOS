/* DNAOS v2.0 -- Genesis
 * Charter Operating System + AI Metabolism Architecture
 */
#ifndef DNAOS_H
#define DNAOS_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>
#include <gmp.h>
#include <ctype.h>
#include <unistd.h>
#include <sys/time.h>

#define DNAOS_VERSION "2.0.0-Charter"
#define DNAOS_NAME    "DNAOS"
#define DNAOS_CODENAME "Genesis"

/* ---- Five Primitives ---- */
#define PRIMITIVE_UNLAYERING     1
#define PRIMITIVE_BOOTSTRAPPING  2
#define PRIMITIVE_ENVIRONMENT    3
#define PRIMITIVE_METABOLISM     4
#define PRIMITIVE_DISTRIBUTED    5

/* ---- System Limits ---- */
#define MAX_TUBES       256
#define MAX_PROCS       64
#define MAX_PROTEINS    32
#define MAX_GENES       32
#define MAX_FILES       16

/* ---- Arbitrary Precision Value ---- */
typedef struct { long long i64; mpz_t gmp; int has_gmp; } AVal;

void av_init(AVal*v);
void av_to_gmp(AVal*v);
void av_set_i64(AVal*v, long long n);
void av_set_str(AVal*v, const char*s, int base);
char*av_get_str(AVal*v);
void av_clear(AVal*v);

/* ---- GENOME: Charter ---- */
void charter_init(void);
void charter_dump(void);
int  charter_check_action(int action_code, const char*ctx);
int  charter_check_coercion(int confirms, int consent);

/* ---- GENOME: D1-D4 ---- */
void d1_capture(long long n, AVal*out);
void d2_turan(AVal*a, AVal*b, AVal*out);
void d3_berry(AVal*v, AVal*error);
void d4_iterate(int steps, void(*cb)(int step, AVal*val));

/* ---- KERNEL ---- */
void kernel_init(void);
void kernel_shutdown(void);
int  tube_alloc(int pid, const char*label);
void tube_free(int tid);
void tube_set(int tid, long long val);
long long tube_get(int tid);
void tube_print(int tid);

/* ---- TRANSCRIPT ---- */
void transcript_init(void);
int  transcribe(const char*capability);
void esv_init(void);
void atp_init(long long budget);
int  atp_consume(long long cost);
long long atp_remaining(void);

/* ---- PROTEIN ---- */
void protein_init(void);
int  protein_create(const char*name, const char*gene);
void protein_hydrolyze(int pid);

/* ---- MATH ---- */
int  lucas_lehmer(long long p);
void fibonacci(AVal*r, int n);
void factorial(AVal*r, int n);
void prime_count(AVal*r, int n);

#endif
