/* transcript.c -- DNAOS Transcription Engine
 *
 * Maps capability names → gene files (.gene contains DNAsm source).
 * Also supports direct .dna file execution.
 */
#include "../include/dnaos.h"
#include <sys/stat.h>
#include <dirent.h>

extern int dnasm_exec(const char *source, long long input, long long atp_budget, AVal *result);

static int transcript_ready = 0;

void transcript_init(void) { transcript_ready = 1; printf("[TRANSCRIPT] Engine ready\n"); }

static char *read_file(const char *path, size_t max_len) {
    FILE *fp = fopen(path, "r");
    if (!fp) return NULL;
    char *buf = malloc(max_len);
    if (!buf) { fclose(fp); return NULL; }
    size_t n = fread(buf, 1, max_len - 1, fp);
    buf[n] = 0; fclose(fp);
    return buf;
}

static char *extract_program(const char *gene_content) {
    const char *marker = "PROGRAM:";
    const char *p = strstr(gene_content, marker);
    if (!p) return NULL;
    p += strlen(marker);
    while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r') p++;
    char *prog = malloc(strlen(p) + 1);
    strcpy(prog, p);
    return prog;
}

static long long extract_atp_cost(const char *gene_content) {
    const char *marker = "ATP_COST:";
    const char *p = strstr(gene_content, marker);
    if (!p) return 100;
    p += strlen(marker);
    while (*p == ' ' || *p == '\t') p++;
    return atoll(p);
}

/* ── Execute a .dna file by absolute path ── */
int dnasm_exec_file(const char *filepath, long long input, long long atp_budget, AVal *result) {
    char *source = read_file(filepath, 65536);
    if (!source) {
        printf("[TRANSCRIPT] Cannot open file: %s\n", filepath);
        return -1;
    }
    /* Strip ; inline comments */
    char *clean = malloc(strlen(source) * 2 + 1);
    int ci = 0;
    for (int i = 0; source[i]; i++) {
        if (source[i] == ';') {
            while (source[i] && source[i] != '\n' && source[i] != '\r') i++;
            i--; continue;
        }
        clean[ci++] = source[i];
    }
    clean[ci] = 0;
    free(source);

    int rc = dnasm_exec(clean, input, atp_budget, result);
    free(clean);
    return rc;
}

/* ── Transcribe gene name → execute via VM ── */
int transcribe_and_exec(const char *capability, long long input, AVal *out_result) {
    if (!transcript_ready) transcript_init();

    printf("[TRANSCRIBE] Loading gene '%s' (input=%lld)...\n", capability, input);

    char path[256];
    snprintf(path, sizeof(path), "genome/capabilities/%s.gene", capability);
    for (char *c = path; *c; c++) if (*c >= 'A' && *c <= 'Z') *c = *c - 'A' + 'a';

    char *gene_content = read_file(path, 8192);
    if (!gene_content) {
        printf("[TRANSCRIBE] Error: gene not found: %s\n", path);
        return -1;
    }

    long long cost = extract_atp_cost(gene_content);
    if (!atp_consume(cost)) {
        printf("[TRANSCRIPT] INSUFFICIENT ATP (%lld needed, have %lld)\n",
               cost, atp_remaining());
        free(gene_content);
        return -1;
    }

    char *program = extract_program(gene_content);
    free(gene_content);
    if (!program) {
        printf("[TRANSCRIBE] Error: no PROGRAM: section in gene\n");
        return -1;
    }

    printf("[TRANSCRIBE] Executing '%s' (ATP=%lld)...\n", capability, cost);
    int rc = dnasm_exec(program, input, cost * 10, out_result);
    free(program);
    if (rc != 0) printf("[TRANSCRIBE] Execution failed: rc=%d\n", rc);
    return rc;
}

/* ── Legacy transcribe() for boot.c demo ── */
int transcribe(const char *capability) {
    if (!transcript_ready) transcript_init();
    char path[256];
    snprintf(path, sizeof(path), "genome/capabilities/%s.gene", capability);
    for (char *c = path; *c; c++) if (*c >= 'A' && *c <= 'Z') *c = *c - 'A' + 'a';
    FILE *fp = fopen(path, "r");
    if (!fp) { printf("[TRANSCRIBE] Unknown capability: %s\n", capability); return -1; }
    fclose(fp);
    char *gene_content = read_file(path, 8192);
    if (!gene_content) return -1;
    long long cost = extract_atp_cost(gene_content);
    free(gene_content);
    if (!atp_consume(cost)) { printf("[TRANSCRIPT] INSUFFICIENT ATP\n"); return -1; }
    printf("[TRANSCRIBE] Gene '%s' loaded (ATP=%lld)\n", path, cost);
    return 0;
}