/* 【引导.c -- DNAOS v2.0 Genesis 引导】 */
#include "include/dnaos.h"
#include <dirent.h>

/* ── External VM executor (transcript.c provides this) ── */
extern int dnasm_exec_file(const char *path, long long input, long long atp, AVal *result);

/* ── Run all bench/*.dna programs ── */
static void run_bench_all(void) {
    printf("\n========================================================================\n");
    printf("   DNAOS v%s -- BENCHMARK SUITE\n", DNAOS_VERSION);
    printf("========================================================================\n\n");

    const char *bench_dirs[] = {
        "../bench",
        "../../bench",
        "bench",
        NULL
    };

    char bench_path[512] = "";
    for (int i = 0; bench_dirs[i]; i++) {
        DIR *d = opendir(bench_dirs[i]);
        if (d) { strcpy(bench_path, bench_dirs[i]); closedir(d); break; }
    }
    if (!bench_path[0]) {
        printf("[BENCH] Error: bench/ directory not found\n");
        return;
    }
    printf("[BENCH] Using: %s/\n\n", bench_path);

    struct bench_prog { char name[128]; int lines; long long atp; int pass; };
    struct bench_prog programs[32];
    int n_prog = 0;

    /* Collect programs */
    DIR *dir = opendir(bench_path);
    if (!dir) { printf("[BENCH] Cannot open: %s\n", bench_path); return; }
    struct dirent *entry;
    while ((entry = readdir(dir)) && n_prog < 32) {
        if (strstr(entry->d_name, ".dna")) {
            char full[512];
            snprintf(full, sizeof(full), "%s/%s", bench_path, entry->d_name);
            FILE *f = fopen(full, "r");
            if (!f) continue;
            int lines = 0; char buf[256];
            while (fgets(buf, sizeof(buf), f)) lines++;
            fclose(f);

            strncpy(programs[n_prog].name, entry->d_name, 127);
            programs[n_prog].lines = lines;
            /* ATP budget based on program size */
            if (lines < 150)   programs[n_prog].atp = 100000;
            else if (lines < 400) programs[n_prog].atp = 500000;
            else if (lines < 1000) programs[n_prog].atp = 2000000;
            else                    programs[n_prog].atp = 5000000;
            programs[n_prog].pass = -1; /* -1=not run, 0=fail, 1=pass */
            n_prog++;
        }
    }
    closedir(dir);

    printf("[BENCH] Found %d programs\n\n", n_prog);

    /* Execute each program */
    int passed = 0;
    for (int i = 0; i < n_prog; i++) {
        char full[512];
        snprintf(full, sizeof(full), "%s/%s", bench_path, programs[i].name);
        printf("=== [%s] (%d lines, ATP=%lld) ===\n",
               programs[i].name, programs[i].lines, programs[i].atp);

        AVal result; av_init(&result);
        int rc = dnasm_exec_file(full, 0, programs[i].atp, &result);
        programs[i].pass = (rc == 0) ? 1 : 0;
        if (programs[i].pass) passed++;
        av_clear(&result);

        printf("\n");
    }

    /* Summary table */
    printf("========================================================================\n");
    printf("   BENCHMARK SUMMARY (%d / %d passed)\n", passed, n_prog);
    printf("========================================================================\n");
    printf("  %-45s %8s %6s %s\n", "Program", "Lines", "ATP", "Status");
    printf("  %-45s %8s %6s %s\n", "--------", "-----", "---", "------");
    for (int i = 0; i < n_prog; i++) {
        printf("  %-45s %8d %6lld %s\n",
               programs[i].name,
               programs[i].lines,
               programs[i].atp,
               programs[i].pass == 1 ? "✅ PASS" :
               programs[i].pass == 0 ? "❌ FAIL" : "⚠️  SKIP");
    }
    printf("\n  Remaining ATP: %lld / 10000000000\n", atp_remaining());
}

int main(int argc, char**argv) {
    (void)argc; (void)argv;
    struct timeval tv0, tv1;
    gettimeofday(&tv0, NULL);

    /* Check for bench mode */
    if (argc > 1 && strcmp(argv[1], "bench") == 0) {
        charter_init();
        transcript_init();
        esv_init();
        atp_init(10000000000LL);
        protein_init();
        run_bench_all();
        printf("\n=== BENCH DONE ===\n");
        return 0;
    }

    printf("========================================================================\n");
    printf("   DNAOS v%s -- %s\n", DNAOS_VERSION, DNAOS_CODENAME);
    printf("   Charter Operating System + AI Metabolism\n");
    printf("   Architecture: Genome -> Transcript -> Protein (cyclic)\n");
    printf("========================================================================\n\n");

    /* 【1. GENOME】 */
    printf("[GENOME] Loading Charter into ROM...\n");
    charter_init();
    charter_dump();

    /* 【2. KERNEL】 */
    printf("[KERNEL] Booting microkernel...\n");
    kernel_init();

    /* 【3. TRANSCRIPT】 */
    printf("[TRANSCRIPT] Initializing transcription engine...\n");
    transcript_init();
    esv_init();
    atp_init(10000000000LL);

    /* 【4. PROTEIN】 */
    printf("[PROTEIN] Initializing protein pool...\n");
    protein_init();

    /* 【5. Transcribe Mersenne protein】 */
    printf("\n=== DEMONSTRATION ===\n\n");
    printf("[ACTION] TRANSCRIBE MERSENNE -> ATP check -> Load gene...\n");
    transcribe("MERSENNE");

    /* 【6. Mersenne primes (direct C)】 */
    printf("\n[MATH] Verifying known Mersenne primes...\n");
    int known[] = {2,3,5,7,13,17,19,31,61,89,107,127};
    for (int i = 0; i < 12; i++) {
        int p = known[i];
        int is_prime = lucas_lehmer(p);
        printf("  M_%-3d = %s\n", p, is_prime ? "素数" : "合数");
    }

    /* 【7. Prime counting】 */
    printf("\n[MATH] Prime counting...\n");
    AVal pi; av_init(&pi);
    prime_count(&pi, 100);   printf("  pi(100)    = %s\n", av_get_str(&pi));
    prime_count(&pi, 1000);  printf("  pi(1000)   = %s\n", av_get_str(&pi));
    prime_count(&pi, 10000); printf("  pi(10000)  = %s\n", av_get_str(&pi));
    av_clear(&pi);

    /* 【8. Fibonacci (genome->transcript->protein chain)】 */
    printf("\n[MATH] Fibonacci via genome->transcript->protein...\n");
    AVal fib_result; av_init(&fib_result);
    int test_n[] = {0, 1, 5, 10, 20};
    for (int ti = 0; ti < 5; ti++) {
        int n = test_n[ti];
        av_clear(&fib_result); av_init(&fib_result);
        int rc = transcribe_and_exec("fibonacci", n, &fib_result);
        if (rc == 0) {
            char *s = av_get_str(&fib_result);
            printf("  [RESULT] Fib(%d) = %s\n", n, s);
            free(s);
        } else {
            printf("  [RESULT] Fib(%d) = (failed)\n", n);
        }
    }
    av_clear(&fib_result);

    /* 【9. ATP check】 */
    printf("\n[ATP] Remaining: %lld / 10000000000\n", atp_remaining());

    /* 【10. D1-D4】 */
    printf("\n[D1-D4] Bricklayer Meta-Theorem:\n");
    for (int n = 1; n <= 10; n++) {
        double t_n = (n == 1) ? 14.13 : (2.0 * M_PI * n / log(n > 1 ? n : 1));
        printf("    t_%d ~ %.2f\n", n, t_n);
    }

    /* 【11. Shutdown】 */
    printf("\n[SHUTDOWN] DNAOS halting...\n");
    kernel_shutdown();

    gettimeofday(&tv1, NULL);
    double total = (tv1.tv_sec - tv0.tv_sec) + (tv1.tv_usec - tv0.tv_usec) / 1e6;
    printf("\n=== DONE ===\nTime: %.3fs\n", total);
    printf("0\n");
    return 0;
}