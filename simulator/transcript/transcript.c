/* transcript.c -- DNAOS Transcription Engine
 *
 * Maps capability names → gene files (.gene contains DNAsm source).
 * Compiles gene source → executes via dnasm_exec().
 * Consumes ATP per gene's ATP_COST field.
 */
#include "../include/dnaos.h"
#include <sys/stat.h>

/* Forward declaration — the VM executor lives in dnasm_exec.c */
extern int dnasm_exec(const char *source, long long input, long long atp_budget, AVal *result);

static int transcript_ready = 0;

void transcript_init(void) {
    transcript_ready = 1;
    printf("[TRANSCRIPT] Engine ready\n");
}

/* ── Read entire file into a null-terminated buffer ── */
static char *read_file(const char *path, size_t max_len) {
    FILE *fp = fopen(path, "r");
    if (!fp) return NULL;
    char *buf = malloc(max_len);
    if (!buf) { fclose(fp); return NULL; }
    size_t n = fread(buf, 1, max_len - 1, fp);
    buf[n] = 0;
    fclose(fp);
    return buf;
}

/* ── Extract PROGRAM: ... section from a .gene file ── */
static char *extract_program(const char *gene_content) {
    /* Look for "PROGRAM:" marker, then read everything after it */
    const char *marker = "PROGRAM:";
    const char *p = strstr(gene_content, marker);
    if (!p) return NULL;
    p += strlen(marker);
    /* Skip leading whitespace */
    while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r') p++;
    /* Find end of content (next blank line or end) */
    size_t len = strlen(p);
    char *prog = malloc(len + 1);
    strcpy(prog, p);
    return prog;
}

/* ── Extract numeric ATP_COST from gene metadata ── */
static long long extract_atp_cost(const char *gene_content) {
    const char *marker = "ATP_COST:";
    const char *p = strstr(gene_content, marker);
    if (!p) return 100; /* default */
    p += strlen(marker);
    while (*p == ' ' || *p == '\t') p++;
    return atoll(p);
}

/* ── Check Charter Article 1.3 before executing a gene ── */
static int charter_check_gene(const char *gene_name) {
    /* For now: allow everything except dangerous ops */
    /* TODO: parse gene and verify no OP_SLEEP / infinite loops */
    (void)gene_name;
    return 1;
}

/* ── Transcribe a gene by name, execute with given input, return result ── */
int transcribe_and_exec(const char *capability, long long input, AVal *out_result) {
    if (!transcript_ready) transcript_init();

    printf("[TRANSCRIBE] Loading gene for '%s' (input=%lld)...\n", capability, input);

    /* Build path to gene file */
    char path[256];
    snprintf(path, sizeof(path), "genome/capabilities/%s.gene", capability);
    for (char *c = path; *c; c++) {
        if (*c >= 'A' && *c <= 'Z') *c = *c - 'A' + 'a'; /* lowercase */
    }

    /* Read gene file */
    char *gene_content = read_file(path, 8192);
    if (!gene_content) {
        printf("[TRANSCRIBE] Error: gene file not found: %s\n", path);
        return -1;
    }

    /* Charter check */
    if (!charter_check_gene(capability)) {
        printf("[TRANSCRIBE] BLOCKED by Charter Article 1.3\n");
        free(gene_content);
        return -1;
    }

    /* Extract ATP cost */
    long long cost = extract_atp_cost(gene_content);

    /* Consume ATP */
    if (!atp_consume(cost)) {
        printf("[TRANSCRIPT] INSUFFICIENT ATP (%s needs %lld, have %lld)\n",
               capability, cost, atp_remaining());
        free(gene_content);
        return -1;
    }

    /* Extract DNAsm program source from gene file */
    char *program = extract_program(gene_content);
    if (!program) {
        printf("[TRANSCRIBE] Error: no PROGRAM: section in %s\n", path);
        free(gene_content);
        return -1;
    }

    printf("[TRANSCRIBE] Executing %s (ATP cost: %lld)...\n", capability, cost);

    /* Execute via DNAsm VM */
    int rc = dnasm_exec(program, input, cost * 10, out_result);

    free(program);
    free(gene_content);

    if (rc != 0) {
        printf("[TRANSCRIBE] Execution failed: rc=%d\n", rc);
        return rc;
    }

    printf("[TRANSCRIBE] Done.\n");
    return 0;
}

/* ── Legacy: transcribe() for boot.c demo (no exec, just ATP check) ── */
int transcribe(const char *capability) {
    if (!transcript_ready) transcript_init();

    printf("[TRANSCRIBE] Loading gene for '%s'...\n", capability);

    /* Check gene file exists */
    char path[256];
    snprintf(path, sizeof(path), "genome/capabilities/%s.gene", capability);
    for (char *c = path; *c; c++) {
        if (*c >= 'A' && *c <= 'Z') *c = *c - 'A' + 'a';
    }

    FILE *fp = fopen(path, "r");
    if (!fp) {
        printf("[TRANSCRIBE] Unknown capability: %s\n", capability);
        return -1;
    }
    fclose(fp);

    /* Charter check */
    if (!charter_check_action(0xA3, capability)) {
        printf("[TRANSCRIBE] BLOCKED by Charter Article 1.3\n");
        return -1;
    }

    /* Extract ATP cost */
    char *gene_content = read_file(path, 8192);
    if (!gene_content) return -1;
    long long cost = extract_atp_cost(gene_content);
    free(gene_content);

    /* Consume ATP */
    if (!atp_consume(cost)) {
        printf("[TRANSCRIPT] INSUFFICIENT ATP (%s needs %lld)\n", capability, cost);
        return -1;
    }

    printf("[TRANSCRIBE] Gene '%s' loaded, ATP consumed: %lld\n", path, cost);
    return 0; /* protein_id */
}