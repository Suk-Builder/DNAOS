/* dnasm_exec.c -- DNAOS DNAsm Virtual Machine Executor
 *
 * Genome → Transcript → Protein execution chain.
 * Loads DNAsm source, parses to bytecode, executes, returns AVal result.
 *
 * Energy model: each instruction costs 1 ATP unit.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <math.h>
#include <stdint.h>
#include <gmp.h>
#include "../include/dnaos.h"

#define MAX_PROG     512
#define MAX_LABELS   128
#define REG_COUNT     128
#define MAX_CALL_STACK 32

enum {
    OP_HALT=0, OP_NOP, OP_NUM, OP_ADD, OP_SUB, OP_MUL, OP_DIV,
    OP_PRINT, OP_LOAD, OP_STORE, OP_READ,
    OP_JMP, OP_JZ, OP_JNZ, OP_JE, OP_JNE,
    OP_JLT, OP_JGE, OP_JGT, OP_JLE, OP_CMP,
    OP_CALL, OP_RET, OP_LABEL,
    OP_PARA, OP_REDUCE_SUM, OP_REDUCE_MAX, OP_DOT, OP_MAD,
    OP_LERP, OP_CLAMP, OP_SIN, OP_COS, OP_FMA, OP_SYNC,
    OP_SLEEP, OP_POW, OP_SQRT, OP_GCD, OP_LN,
    OP_FIB, OP_PRIME, OP_FACT, OP_INC,
    N_OPS
};

static const char *op_names[N_OPS] = {
    "HALT","NOP","NUM","ADD","SUB","MUL","DIV","PRINT","LOAD","STORE",
    "READ","JMP","JZ","JNZ","JE","JNE","JLT","JGE","JGT","JLE","CMP",
    "CALL","RET","LABEL","PARA","REDUCE_SUM","REDUCE_MAX","DOT","MAD",
    "LERP","CLAMP","SIN","COS","FMA","SYNC","SLEEP","POW","SQRT","GCD",
    "LN","FIB","PRIME","FACT","INC"
};

typedef struct { int op; long long imm; int ra, rb; char label[32]; } Inst;
typedef struct { char name[32]; int addr; } LabelMap;

/* ── Parse one line of DNAsm source ── */
static int parse_line(const char *line, Inst *out) {
    memset(out, 0, sizeof(*out));
    char buf[256]; strncpy(buf, line, 255); buf[255] = 0;
    char *save = NULL;
    char *tok[16]; int nt = 0;
    char *p = buf;
    while (nt < 16 && *p) {
        while (*p==' '||*p=='\t') p++;
        if (!*p||*p=='#'||*p=='\n') break;
        tok[nt++] = p;
        while (*p&&*p!=' '&&*p!='\t'&&*p!='\n') p++;
        if (!*p) break;
        *p++ = 0;
    }
    if (nt == 0) { out->op = OP_NOP; return 1; }
    for (char *c = tok[0]; *c; c++) *c = (*c>='a'&&*c<='z')?*c-'a'+'A':*c;
    int op = -1;
    for (int i = 0; i < N_OPS; i++) { if (strcmp(tok[0], op_names[i])==0) { op=i; break; } }
    if (op == -1) { out->op = OP_NOP; return 1; }
    out->op = op;
    if (op == OP_NUM || op == OP_LOAD || op == OP_STORE || op == OP_READ) {
        if (nt > 1) out->ra = (tok[1][0]=='r'||tok[1][0]=='R') ? atoi(tok[1]+1) : -1;
        if (nt > 2) out->rb = (tok[2][0]=='r'||tok[2][0]=='R') ? atoi(tok[2]+1) : -1;
    } else if (op == OP_ADD || op == OP_SUB || op == OP_MUL || op == OP_DIV ||
               op == OP_CMP || op == OP_DOT || op == OP_MAD || op == OP_LERP) {
        if (nt > 1) out->ra = (tok[1][0]=='r'||tok[1][0]=='R') ? atoi(tok[1]+1) : -1;
        if (nt > 2) out->rb = (tok[2][0]=='r'||tok[2][0]=='R') ? atoi(tok[2]+1) : -1;
    } else if (op == OP_JMP || op == OP_JZ || op == OP_JNZ || op == OP_JE ||
               op == OP_JNE || op == OP_JLT || op == OP_JGE ||
               op == OP_JGT || op == OP_JLE || op == OP_CALL) {
        if (nt > 1) { char *lbl = tok[1]; if (lbl[0]=='@') lbl++; strncpy(out->label, lbl, 31); }
    } else if (op == OP_LABEL) {
        if (nt > 1) { char *lbl = tok[1]; if (lbl[0]=='@') lbl++; strncpy(out->label, lbl, 31); }
    } else if (op == OP_INC) {
        if (nt > 1) out->ra = (tok[1][0]=='r'||tok[1][0]=='R') ? atoi(tok[1]+1) : -1;
    }
    (void)save;
    return 1;
}

static int build_labels(Inst *prog, int n, LabelMap *L, int *nL) {
    *nL = 0;
    for (int i = 0; i < n; i++) if (prog[i].op == OP_LABEL)
        if (*nL < MAX_LABELS) { strcpy(L[*nL].name, prog[i].label); L[*nL++].addr = i; }
}
static int resolve(LabelMap *L, int nL, const char *n) {
    for (int i = 0; i < nL; i++) if (strcmp(L[i].name, n)==0) return L[i].addr;
    return -1;
}

/* ── VM State ── */
typedef struct {
    AVal r[REG_COUNT];
    int cs[MAX_CALL_STACK]; int cs_t;
    int pc;
    long long atp_budget, atp_spent;
    long long input_n;
    AVal output;
    int halted;
} VM;

static void vm_init(VM *v, long long inp, long long atp) {
    memset(v, 0, sizeof(*v));
    for (int i = 0; i < REG_COUNT; i++) av_init(&v->r[i]);
    av_init(&v->output);
    v->input_n = inp; v->atp_budget = atp; v->halted = 0; v->cs_t = 0; v->pc = 0;
}

static void vm_free(VM *v) {
    for (int i = 0; i < REG_COUNT; i++) av_clear(&v->r[i]);
    av_clear(&v->output);
}

static long long atp_cost(int op) {
    switch(op) {
        case OP_MUL: case OP_DIV: case OP_POW: case OP_SQRT:
        case OP_FIB: case OP_PRIME: case OP_FACT: return 5;
        case OP_SIN: case OP_COS: case OP_LN: case OP_GCD: return 4;
        default: return 1;
    }
}

/* ── Execute one instruction ── */
static int exec_inst(Inst *I, VM *v, LabelMap *L, int nL) {
    if (v->atp_spent + atp_cost(I->op) > v->atp_budget) { v->halted = 1; return 0; }
    v->atp_spent += atp_cost(I->op);
    int ra = I->ra, rb = I->rb;

    switch(I->op) {
        case OP_HALT: v->halted = 1; return 0;

        case OP_NOP: break;

        case OP_NUM: {
            if (ra >= 0 && ra < REG_COUNT) { av_init(&v->r[ra]); av_set_i64(&v->r[ra], I->imm); }
            break;
        }

        case OP_LOAD: {
            if (ra >= 0 && ra < REG_COUNT) { av_init(&v->r[ra]); av_set_i64(&v->r[ra], v->input_n); }
            break;
        }

        case OP_STORE: {
            int dest = ra, src = rb;
            if (dest >= 0 && dest < REG_COUNT && src >= 0 && src < REG_COUNT) {
                av_clear(&v->r[dest]); av_init(&v->r[dest]);
                mpz_set(v->r[dest].gmp, v->r[src].gmp);
            }
            break;
        }

        case OP_INC: {
            if (ra >= 0 && ra < REG_COUNT) mpz_add_ui(v->r[ra].gmp, v->r[ra].gmp, 1);
            break;
        }

        case OP_ADD: {
            if (ra>=0&&ra<REG_COUNT&&rb>=0&&rb<REG_COUNT) mpz_add(v->r[ra].gmp, v->r[ra].gmp, v->r[rb].gmp);
            break;
        }

        case OP_SUB: {
            if (ra>=0&&ra<REG_COUNT&&rb>=0&&rb<REG_COUNT) mpz_sub(v->r[ra].gmp, v->r[ra].gmp, v->r[rb].gmp);
            break;
        }

        case OP_CMP: {
            if (ra>=0&&ra<REG_COUNT&&rb>=0&&rb<REG_COUNT) {
                int cmp = mpz_cmp(v->r[ra].gmp, v->r[rb].gmp);
                av_init(&v->r[15]); av_set_i64(&v->r[15], (cmp<0)?-1:(cmp>0)?1:0);
            }
            break;
        }

        case OP_PRINT: {
            if (ra>=0&&ra<REG_COUNT) {
                char *s = av_get_str(&v->r[ra]);
                printf("  [DNAVM] r%d = %s\n", ra, s);
                free(s);
                av_clear(&v->output); av_init(&v->output);
                mpz_set(v->output.gmp, v->r[ra].gmp);
            }
            break;
        }

        case OP_JMP: {
            int a = resolve(L, nL, I->label);
            if (a >= 0) v->pc = a - 1;
            break;
        }

        case OP_JZ: {
            int cmp = mpz_get_si(v->r[15].gmp);
            if (cmp == 0) { int a = resolve(L, nL, I->label); if (a >= 0) v->pc = a - 1; }
            break;
        }

        case OP_JNZ: {
            int cmp = mpz_get_si(v->r[15].gmp);
            if (cmp != 0) { int a = resolve(L, nL, I->label); if (a >= 0) v->pc = a - 1; }
            break;
        }

        case OP_JGT: {
            int cmp = mpz_get_si(v->r[15].gmp);
            if (cmp > 0) { int a = resolve(L, nL, I->label); if (a >= 0) v->pc = a - 1; }
            break;
        }

        case OP_JGE: {
            int cmp = mpz_get_si(v->r[15].gmp);
            if (cmp >= 0) { int a = resolve(L, nL, I->label); if (a >= 0) v->pc = a - 1; }
            break;
        }

        case OP_JLT: {
            int cmp = mpz_get_si(v->r[15].gmp);
            if (cmp < 0) { int a = resolve(L, nL, I->label); if (a >= 0) v->pc = a - 1; }
            break;
        }

        case OP_JLE: {
            int cmp = mpz_get_si(v->r[15].gmp);
            if (cmp <= 0) { int a = resolve(L, nL, I->label); if (a >= 0) v->pc = a - 1; }
            break;
        }

        case OP_CALL: {
            int a = resolve(L, nL, I->label);
            if (a >= 0 && v->cs_t < MAX_CALL_STACK) v->cs[v->cs_t++] = v->pc;
            if (a >= 0) v->pc = a - 1;
            break;
        }

        case OP_RET: {
            if (v->cs_t > 0) v->pc = v->cs[--v->cs_t] - 1;
            break;
        }

        case OP_FIB: {
            int r_src = ra, r_dst = rb;
            if (r_src>=0&&r_src<REG_COUNT&&r_dst>=0&&r_dst<REG_COUNT) {
                int n = (int)mpz_get_si(v->r[r_src].gmp);
                av_init(&v->r[r_dst]);
                if (n <= 1) { av_set_i64(&v->r[r_dst], n); }
                else {
                    mpz_t a, b, t;
                    mpz_init_set_si(a, 0); mpz_init_set_si(b, 1); mpz_init(t);
                    for (int i = 0; i < n; i++) { mpz_set(t, b); mpz_add(b, b, a); mpz_set(a, t); }
                    mpz_set(v->r[r_dst].gmp, a);
                    mpz_clear(a); mpz_clear(b); mpz_clear(t);
                }
            }
            break;
        }

        case OP_POW: {
            if (ra>=0&&ra<REG_COUNT&&rb>=0&&rb<REG_COUNT) {
                double res = pow(mpz_get_d(v->r[ra].gmp), mpz_get_d(v->r[rb].gmp));
                av_clear(&v->r[ra]); av_init(&v->r[ra]); mpz_set_d(v->r[ra].gmp, res);
            }
            break;
        }

        default: break;
    }
    return 1;
}

/* ── Parse source string into instruction array ── */
static int parse_source(const char *src, Inst *prog, int max_prog) {
    int n = 0;
    const char *p = src;
    while (n < max_prog && *p) {
        while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r') p++;
        if (!*p || *p == '#') { if (!*p) break; p++; continue; }
        const char *e = p;
        while (*e && *e != '\n' && *e != '\r') e++;
        int len = e - p;
        if (len > 0 && len < 255) {
            char buf[256]; strncpy(buf, p, len); buf[len] = 0;
            char *cmt = strchr(buf, '#'); if (cmt) *cmt = 0;
            int tail = strlen(buf) - 1;
            while (tail >= 0 && (buf[tail]==' '||buf[tail]=='\t')) buf[tail--] = 0;
            if (strlen(buf) > 0) parse_line(buf, &prog[n++]);
        }
        p = e;
        if (*p) p++;
    }
    return n;
}

/* ── Main entry point ── */
int dnasm_exec(const char *source, long long input, long long atp_budget, AVal *result) {
    Inst prog[MAX_PROG];
    int n_prog = parse_source(source, prog, MAX_PROG);
    if (n_prog == 0) { printf("[DNAVM] Error: empty program\n"); return -1; }

    LabelMap labels[MAX_LABELS]; int n_labels;
    build_labels(prog, n_prog, labels, &n_labels);

    VM vm; vm_init(&vm, input, atp_budget);
    int step = 0;
    while (!vm.halted && vm.pc < n_prog) {
        exec_inst(&prog[vm.pc], &vm, labels, n_labels);
        vm.pc++;
        step++;
        if (step > 10000) { printf("[DNAVM] Error: infinite loop detected (>10000 steps)\n"); break; }
    }

    if (result) { av_init(result); mpz_set(result->gmp, vm.output.gmp); }
    printf("  [DNAVM] ATP spent: %lld / %lld, steps: %d\n", vm.atp_spent, atp_budget, step);
    vm_free(&vm);
    return 0;
}