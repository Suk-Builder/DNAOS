/* 【引导.c -- DNAOS v2.0 Genesis 引导】 */
#include "include/dnaos.h"

int main(int argc, char**argv) {
    (void)argc; (void)argv;
    struct timeval tv0, tv1;
    gettimeofday(&tv0, NULL);

    printf("========================================================================\n");
    printf("   DNAOS v%s -- %s\n", DNAOS_VERSION, DNAOS_CODENAME);
    printf("   Charter Operating System + AI Metabolism\n");
    printf("   Architecture: Genome -> Transcript -> Protein (cyclic)\n");
    printf("========================================================================\n\n");

    /* 【1. GENOME: Charter】 */
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
    atp_init(10000000000LL); /* 【10 billion ATP】 */

    /* 【4. PROTEIN】 */
    printf("[PROTEIN] Initializing protein pool...\n");
    protein_init();

    /* 【5. Demonstrate: Transcribe Mersenne verification protein】 */
    printf("\n=== DEMONSTRATION ===\n\n");
    printf("[ACTION] TRANSCRIBE MERSENNE -> ATP check -> Load gene...\n");
    int mersenne = transcribe("MERSENNE");
    if(mersenne < 0) {
        printf("[FALLBACK] Direct LL execution (no transcription needed)\n");
    }

    /* 【6. Verify known Mersenne primes (direct C execution)】 */
    printf("\n[MATH] Verifying known Mersenne primes (LL test)...\n");
    int known[] = {2, 3, 5, 7, 13, 17, 19, 31, 61, 89, 107, 127};
    int n_known = sizeof(known) / sizeof(known[0]);

    for(int i = 0; i < n_known; i++) {
        int p = known[i];
        int is_prime = lucas_lehmer(p);
        printf("  M_%-3d = %s\n", p, is_prime ? "*** 素数 ***" : "合数");
    }

    /* 【7. Prime counting (direct C execution)】 */
    printf("\n[MATH] Prime counting (direct C)...\n");
    AVal pi; av_init(&pi);
    prime_count(&pi, 100);    printf("  pi(100)    = %s\n", av_get_str(&pi));
    prime_count(&pi, 1000);   printf("  pi(1000)   = %s\n", av_get_str(&pi));
    prime_count(&pi, 10000);  printf("  pi(10000)  = %s\n", av_get_str(&pi));
    prime_count(&pi, 100000); printf("  pi(100000) = %s\n", av_get_str(&pi));

    /* 【8. Fibonacci via genome→transcript→protein chain (DNAsm VM)】 */
    printf("\n[MATH] Fibonacci via genome->transcript->protein (DNAsm VM)...\n");
    printf("  [Chain: gene file -> transcript compiles -> protein executes VM]\n\n");
    AVal fib_result; av_init(&fib_result);
    int test_n[] = {0, 1, 5, 10, 20};
    for (int ti = 0; ti < 5; ti++) {
        int n = test_n[ti];
        av_clear(&fib_result);
        av_init(&fib_result);
        printf("  [DNAVM] Fib(%d):\n", n);
        int rc = transcribe_and_exec("fibonacci", n, &fib_result);
        if (rc == 0) {
            char *s = av_get_str(&fib_result);
            printf("  [RESULT] Fib(%d) = %s\n", n, s);
            free(s);
        } else {
            printf("  [RESULT] Fib(%d) = (execution failed)\n", n);
        }
    }

    av_clear(&fib_result);
    av_clear(&pi);

    /* 【9. Hydrolyze】 */
    printf("\n[PROTEIN] HYDROLYZE Mersenne protein...\n");
    protein_hydrolyze(0);

    /* 【10. Check ATP】 */
    printf("\n[ATP] Remaining: %lld / 10000000000\n", atp_remaining());

    /* 【11. D1-D4 demonstration】 */
    printf("\n[D1-D4] Bricklayer Meta-Theorem demonstration:\n");
    printf("  Gram point approximation for first 10 zeros:\n");
    for(int n = 1; n <= 10; n++) {
        double ln_n = log(n > 1 ? n : 1);
        double t_n = (n == 1) ? 14.13 : (2.0 * M_PI * n / ln_n);
        printf("    t_%d ~ %.2f\n", n, t_n);
    }

    /* 【12. Shutdown】 */
    printf("\n[SHUTDOWN] DNAOS halting...\n");
    kernel_shutdown();

    gettimeofday(&tv1, NULL);
    double total = (tv1.tv_sec - tv0.tv_sec) + (tv1.tv_usec - tv0.tv_usec) / 1e6;
    printf("\n=== DONE ===\nTime: %.3fs\n", total);
    printf("0\n");
    return 0;
}