/* kernel/kernel.c -- DNAOS Microkernel */
#include "../include/dnaos.h"

static struct { int used, owner; AVal val; char label[32]; } tubes[MAX_TUBES];
static int next_pid = 1;

void av_init(AVal*v) { v->i64 = 0; v->has_gmp = 0; }
void av_to_gmp(AVal*v) { if(!v->has_gmp) { mpz_init(v->gmp); v->has_gmp = 1; } }
void av_set_i64(AVal*v, long long n) { v->i64 = n; }
void av_set_str(AVal*v, const char*s, int base) { av_to_gmp(v); mpz_set_str(v->gmp, s, base); }
char*av_get_str(AVal*v) {
    static char buf[2000000];
    if(v->has_gmp) gmp_snprintf(buf, sizeof(buf), "%Zd", v->gmp);
    else snprintf(buf, sizeof(buf), "%lld", v->i64);
    return buf;
}
void av_clear(AVal*v) { if(v->has_gmp) mpz_clear(v->gmp); }

void kernel_init(void) {
    for(int i = 0; i < MAX_TUBES; i++) {
        tubes[i].used = 0; tubes[i].owner = -1;
        av_init(&tubes[i].val);
    }
    printf("[KERNEL] %d tubes, %d procs initialized\n", MAX_TUBES, MAX_PROCS);
}

void kernel_shutdown(void) {
    for(int i = 0; i < MAX_TUBES; i++) if(tubes[i].used) tube_free(i);
    printf("[KERNEL] Shutdown complete\n");
}

int tube_alloc(int pid, const char*label) {
    for(int i = 0; i < MAX_TUBES; i++) {
        if(!tubes[i].used) {
            tubes[i].used = 1; tubes[i].owner = pid;
            av_init(&tubes[i].val);
            strncpy(tubes[i].label, label ? label : "anon", 31);
            return i;
        }
    }
    return -1;
}

void tube_free(int tid) {
    if(tid < 0 || tid >= MAX_TUBES) return;
    av_clear(&tubes[tid].val); av_init(&tubes[tid].val);
    tubes[tid].used = 0; tubes[tid].owner = -1;
}

void tube_set(int tid, long long val) {
    if(tid < 0 || tid >= MAX_TUBES) return;
    av_set_i64(&tubes[tid].val, val);
}

long long tube_get(int tid) {
    if(tid < 0 || tid >= MAX_TUBES) return 0;
    return tubes[tid].val.i64;
}

void tube_print(int tid) {
    if(tid < 0 || tid >= MAX_TUBES) return;
    printf("  [st[%02d]] = %s\n", tid, av_get_str(&tubes[tid].val));
}
