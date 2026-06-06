/* 【dnasm_v32_gmp.c -- DNAsm v3.2 with GMP big integer tubes】 */
/* 【Every 试管 stores an arbitrary-precision integer via GMP mpz_t】 */
/* 【No 64-bit 限制. M_1279 (386 digits) runs natively.】 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <math.h>
#include <gmp.h>

#define NTUBES 64
#define MAX_SEQ 2048
#define MAX_LABELS 256

typedef struct {
    char name[64];
    char seq[MAX_SEQ];
    int seq_len;
    mpz_t v;           /* 【GMP big integer -- THE 试管 值】 */
} Tube;

static Tube st[NTUBES];
static int pc_stack[64], sp = 0;
static int debug = 0;

/* 【---- 操作码 table ----】 */
typedef enum {
    OP_UNZIP=0, OP_HYB, OP_DISPL, OP_CLEAVE, OP_LIGATE,
    OP_POLY, OP_MELT, OP_ANNEAL, OP_FIND, OP_COUNT, OP_SPLIT, OP_MIX,
    OP_COPY, OP_BURN, OP_READ, OP_LOAD, OP_TEMP,
    OP_NUM, OP_ADD, OP_PRINT, OP_SUB, OP_MUL, OP_DIV, OP_MOD,
    OP_FIB, OP_PRIME, OP_FACT, OP_POW, OP_SQRT, OP_GCD, OP_LN,
    OP_PARA, OP_REDUCE_SUM, OP_REDUCE_MAX, OP_DOT, OP_MAD, OP_LERP,
    OP_CLAMP, OP_SIN, OP_COS, OP_FMA, OP_SYNC,
    OP_LABEL, OP_JMP, OP_JZ, OP_JNZ, OP_JE, OP_JNE, OP_JGE, OP_JLE,
    OP_CMP, OP_CALL, OP_RET, OP_HALT,
    N_OPS
} Opcode;

static const char*op_names[N_OPS+1] = {
    "UNZIP","HYB","DISPL","CLEAVE","LIGATE",
    "POLY","MELT","ANNEAL","FIND","COUNT","SPLIT","MIX",
    "COPY","BURN","READ","LOAD","TEMP",
    "NUM","ADD","PRINT","SUB","MUL","DIV","MOD",
    "FIB","PRIME","FACT","POW","SQRT","GCD","LN",
    "PARA","REDUCE_SUM","REDUCE_MAX","DOT","MAD","LERP",
    "CLAMP","SIN","COS","FMA","SYNC",
    "LABEL","JMP","JZ","JNZ","JE","JNE","JGE","JLE",
    "CMP","CALL","RET","HALT",
    NULL
};

static int find_op(const char*s) {
    for(int i=0; i<N_OPS; i++)
        if(op_names[i] && strcasecmp(s, op_names[i])==0) return i;
    return -1;
}

/* 【---- 标签 table ----】 */
static struct { char name[64]; int addr; } labels[MAX_LABELS];
static int n_labels = 0;

static int find_label(const char*name) {
    for(int i=0; i<n_labels; i++)
        if(strcmp(labels[i].name, name)==0) return labels[i].addr;
    return -1;
}

/* 【---- parser ----】 */
static int parse_reg(const char*s) {
    if(s[0]=='s' && s[1]=='t' && s[2]=='[') return atoi(s+3);
    return atoi(s);
}

/* ---- 主函数 ---- */
int main(int argc, char**argv) {
    if(argc<2) { printf("Usage: %s <program.dna> [debug]\n", argv[0]); return 1; }
    if(argc>2 && atoi(argv[2])) debug=1;

    /* 【初始化 GMP tubes】 */
    for(int i=0; i<NTUBES; i++) mpz_init(st[i].v);

    /* 读取 程序 */
    char** prog = NULL;
    int n_lines = 0, cap = 0;
    FILE*f = fopen(argv[1], "r");
    if(!f) { perror(argv[1]); return 1; }
    char line[1024];
    while(fgets(line, sizeof(line), f)) {
        if(n_lines>=cap) { cap = cap?cap*2:256; prog = realloc(prog, cap*sizeof(char*)); }
        prog[n_lines] = strdup(line);
        char*c = strchr(prog[n_lines], '#');
        if(!c) c = strchr(prog[n_lines], ';');
        if(c) *c = '\0';
        n_lines++;
    }
    fclose(f);

    /* 【pass 1: collect labels】 */
    for(int i=0; i<n_lines; i++) {
        char* p = strdup(prog[i]);
        char* tok = strtok(p, " \t\n");
        if(!tok) { free(p); continue; }
        int op = find_op(tok);
        if(op==OP_LABEL) {
            char* name = strtok(NULL, " \t\n");
            if(name && n_labels<MAX_LABELS) {
                strncpy(labels[n_labels].name, name, 63);
                labels[n_labels].addr = i; n_labels++;
            }
        }
        free(p);
    }

    /* 【pass 2: 执行】 */
    int pc = 0;
    while(pc < n_lines) {
        char* p = strdup(prog[pc]);
        char* tok = strtok(p, " \t\n");
        if(!tok) { free(p); pc++; continue; }
        int op = find_op(tok);

        char *t1 = strtok(NULL, " \t\n,");
        char *t2 = strtok(NULL, " \t\n,");
        char *t3 = strtok(NULL, " \t\n,");

        switch(op) {
        case OP_NUM: {
            int dst = parse_reg(t1);
            if(t2 && (t2[0]=='-' || isdigit(t2[0]))) mpz_set_str(st[dst].v, t2, 10);
            break;
        }
        case OP_ADD: {
            int dst = parse_reg(t1), src = parse_reg(t2);
            mpz_add(st[dst].v, st[dst].v, st[src].v); break;
        }
        case OP_SUB: {
            int dst = parse_reg(t1), src = parse_reg(t2);
            mpz_sub(st[dst].v, st[dst].v, st[src].v); break;
        }
        case OP_MUL: {
            int dst = parse_reg(t1), src = parse_reg(t2);
            mpz_mul(st[dst].v, st[dst].v, st[src].v); break;
        }
        case OP_DIV: {
            int dst = parse_reg(t1), src = parse_reg(t2);
            if(mpz_cmp_si(st[src].v, 0)!=0) mpz_tdiv_q(st[dst].v, st[dst].v, st[src].v);
            break;
        }
        case OP_MOD: {
            int dst = parse_reg(t1), src = parse_reg(t2);
            if(mpz_cmp_si(st[src].v, 0)!=0) mpz_tdiv_r(st[dst].v, st[dst].v, st[src].v);
            break;
        }
        case OP_SQRT: {
            int dst = parse_reg(t1);
            mpz_sqrt(st[dst].v, st[dst].v); break;
        }
        case OP_POW: {
            int dst = parse_reg(t1), src = parse_reg(t2);
            mpz_pow_ui(st[dst].v, st[dst].v, mpz_get_ui(st[src].v)); break;
        }
        case OP_CMP: {
            int dst = parse_reg(t1), src = parse_reg(t2);
            mpz_set_si(st[dst].v, mpz_cmp(st[dst].v, st[src].v)); break;
        }
        case OP_PRINT: {
            int dst = parse_reg(t1);
            gmp_printf("[st[%02d]] = %Zd\n", dst, st[dst].v); break;
        }
        case OP_LABEL: break;
        case OP_JMP: {
            int a = find_label(t1); if(a>=0) { pc=a; free(p); continue; }
            break;
        }
        case OP_JZ: {
            int dst = parse_reg(t1);
            if(mpz_cmp_si(st[dst].v, 0)==0) {
                int a = find_label(t2); if(a>=0) { pc=a; free(p); continue; }
            }
            break;
        }
        case OP_JNZ: {
            int dst = parse_reg(t1);
            if(mpz_cmp_si(st[dst].v, 0)!=0) {
                int a = find_label(t2); if(a>=0) { pc=a; free(p); continue; }
            }
            break;
        }
        case OP_JE: {
            int d = parse_reg(t1), s = parse_reg(t2);
            if(mpz_cmp(st[d].v, st[s].v)==0) {
                int a = find_label(t3); if(a>=0) { pc=a; free(p); continue; }
            }
            break;
        }
        case OP_JNE: {
            int d = parse_reg(t1), s = parse_reg(t2);
            if(mpz_cmp(st[d].v, st[s].v)!=0) {
                int a = find_label(t3); if(a>=0) { pc=a; free(p); continue; }
            }
            break;
        }
        case OP_JGE: {
            int dst = parse_reg(t1);
            if(mpz_cmp_si(st[dst].v, 0)>=0) {
                int a = find_label(t2); if(a>=0) { pc=a; free(p); continue; }
            }
            break;
        }
        case OP_JLE: {
            int dst = parse_reg(t1);
            if(mpz_cmp_si(st[dst].v, 0)<=0) {
                int a = find_label(t2); if(a>=0) { pc=a; free(p); continue; }
            }
            break;
        }
        case OP_CALL: { pc_stack[sp++] = pc; break; }
        case OP_RET: {
            if(sp>0) { pc = pc_stack[--sp] + 1; free(p); continue; }
            break;
        }
        case OP_HALT: { free(p); goto done; }
        default: break;
        }
        free(p); pc++;
    }
done:
    for(int i=0; i<n_lines; i++) free(prog[i]);
    free(prog);
    for(int i=0; i<NTUBES; i++) mpz_clear(st[i].v);
    return 0;
}
