#include "nsm_backend.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>

/* ============================================================
 * NSM Backend: Software-emulated memristor crossbar array
 * DNAOS 2.0 - Neural State Machine physical layer
 * ============================================================ */

/* ---------- tunable device parameters ---------- */
static const float TYP_PW_NS   = 5.0f;     /* typical pulse width  (ns)   */
static const float TYP_AMP_V   = 1.0f;     /* typical pulse amplitude (V) */
static const float STDP_TAU_MS = 20.0f;    /* STDP time constant (ms)     */
static const float BASE_DELTA  = 0.01f;    /* 1% of (G_max-G_min) per typ pulse */

/* ---------- energy accounting (shared, see note) ---------- */
static float g_total_energy_pj = 0.0f;

/* ---------- internal helpers ---------- */

/* Clamp x to [lo, hi] */
static inline float clamp(float x, float lo, float hi)
{
    return (x < lo) ? lo : ((x > hi) ? hi : x);
}

/* Normalised pulse factor: how strongly a pulse differs from the typical one */
static inline float pulse_factor(float pw_ns, float amp_v)
{
    return (amp_v / TYP_AMP_V) * (pw_ns / TYP_PW_NS);
}

/* Add energy for one pulsing event: E = V^2 * G * t   [J]  */
static inline void acc_energy(float amp_v, float g_siemens, float pw_ns)
{
    float t_s = pw_ns * 1e-9f;               /* ns → s */
    float e_j = amp_v * amp_v * g_siemens * t_s;
    g_total_energy_pj += e_j * 1e12f;        /* J → pJ */
}

/* ---------- API implementation ---------- */

void nsm_init(MemristorArray* arr)
{
    if (!arr) return;

    arr->G_min     = 1e-6f;      /* 1  μS */
    arr->G_max     = 1e-4f;      /* 100 μS */
    arr->max_cycles = 1000000;   /* 1 M cycles */

    memset(arr->V, 0, sizeof(arr->V));
    memset(arr->I, 0, sizeof(arr->I));
    memset(arr->cycles, 0, sizeof(arr->cycles));

    float range = arr->G_max - arr->G_min;
    for (int r = 0; r < NSM_ROWS; ++r)
        for (int c = 0; c < NSM_COLS; ++c)
            arr->G[r][c] = arr->G_min + ((float)rand() / (float)RAND_MAX) * range;

    g_total_energy_pj = 0.0f;
}

/* SET: potentiation (LTP) — increase conductance */
void nsm_set(MemristorArray* arr, int row, int col, float pw, float amp)
{
    if (!arr || row < 0 || row >= NSM_ROWS || col < 0 || col >= NSM_COLS)
        return;
    if (arr->cycles[row][col] >= arr->max_cycles)
        return;

    float g_old = arr->G[row][col];
    float dG    = pulse_factor(pw, amp) * BASE_DELTA * (arr->G_max - arr->G_min);

    /* non-linear device model: ΔG proportional to remaining head-room */
    float g_new = g_old + dG * (1.0f - g_old / arr->G_max);
    arr->G[row][col] = clamp(g_new, arr->G_min, arr->G_max);
    arr->cycles[row][col]++;

    acc_energy(amp, g_old, pw);   /* use pre-pulse G as approximation */
}

/* RESET: depression (LTD) — decrease conductance */
void nsm_reset(MemristorArray* arr, int row, int col, float pw, float amp)
{
    if (!arr || row < 0 || row >= NSM_ROWS || col < 0 || col >= NSM_COLS)
        return;
    if (arr->cycles[row][col] >= arr->max_cycles)
        return;

    float g_old = arr->G[row][col];
    float dG    = pulse_factor(pw, amp) * BASE_DELTA * (arr->G_max - arr->G_min);

    /* non-linear device model: ΔG proportional to how far above floor */
    float g_new = g_old - dG * (g_old / arr->G_min);
    arr->G[row][col] = clamp(g_new, arr->G_min, arr->G_max);
    arr->cycles[row][col]++;

    acc_energy(amp, g_old, pw);
}

/* READ: non-destructive read of a single cell */
float nsm_read(MemristorArray* arr, int row, int col)
{
    if (!arr || row < 0 || row >= NSM_ROWS || col < 0 || col >= NSM_COLS)
        return 0.0f;
    return arr->G[row][col];
}

/* VMM: vector-matrix multiply  I_j = Σ_i G_ij × V_i
 * Result written to arr->I in micro-amperes (μA).                */
void nsm_vmm(MemristorArray* arr)
{
    if (!arr) return;

    for (int c = 0; c < NSM_COLS; ++c) {
        float sum_a = 0.0f;                     /* accumulator in amperes */
        for (int r = 0; r < NSM_ROWS; ++r)
            sum_a += arr->G[r][c] * arr->V[r];  /* S × V = A */
        arr->I[c] = sum_a * 1e6f;               /* A → μA */
    }
}

/* STDP: spike-timing-dependent plasticity */
void nsm_stdp(MemristorArray* arr, int pre_row, int post_col,
              float pre_t, float post_t)
{
    if (!arr || pre_row < 0 || pre_row >= NSM_ROWS
             || post_col < 0 || post_col >= NSM_COLS)
        return;
    if (arr->cycles[pre_row][post_col] >= arr->max_cycles)
        return;

    float dt   = post_t - pre_t;                /* ms */
    float abs_dt = fabsf(dt);
    float A    = 0.1f * (arr->G_max - arr->G_min);
    float dG   = A * expf(-abs_dt / STDP_TAU_MS);

    float g_old = arr->G[pre_row][post_col];
    float g_new;

    if (dt > 0.0f) {
        /* post after pre  →  LTP  →  SET */
        g_new = g_old + dG * (1.0f - g_old / arr->G_max);
    } else if (dt < 0.0f) {
        /* post before pre →  LTD  →  RESET */
        g_new = g_old - dG * (g_old / arr->G_min);
    } else {
        /* dt == 0: no change (coincident firing) */
        return;
    }

    arr->G[pre_row][post_col] = clamp(g_new, arr->G_min, arr->G_max);
    arr->cycles[pre_row][post_col]++;

    /* approximate energy: use typical pulse parameters for STDP event */
    acc_energy(TYP_AMP_V, g_old, TYP_PW_NS);
}

/* Chemical modulation via ionic liquid / neurotransmitter analogy */
void nsm_chem_mod(MemristorArray* arr, int chem_type, float intensity)
{
    if (!arr || intensity < 0.0f || intensity > 1.0f)
        return;

    switch (chem_type) {
        case 0: {  /* dopamine — boost toward G_max (enhanced LTP) */
            float factor = intensity * 0.1f;
            for (int r = 0; r < NSM_ROWS; ++r)
                for (int c = 0; c < NSM_COLS; ++c) {
                    float g = arr->G[r][c];
                    arr->G[r][c] = clamp(g + (arr->G_max - g) * factor,
                                         arr->G_min, arr->G_max);
                }
            break;
        }
        case 1: {  /* glutamate — standard transmitter, no-op */
            break;
        }
        case 2: {  /* serotonin — global scaling (excitability tuning) */
            float scale = 1.0f - intensity * 0.5f;
            for (int r = 0; r < NSM_ROWS; ++r)
                for (int c = 0; c < NSM_COLS; ++c)
                    arr->G[r][c] = clamp(arr->G[r][c] * scale,
                                         arr->G_min, arr->G_max);
            break;
        }
        default:
            break;
    }
}

/* Return endurance cycles consumed for a cell */
int nsm_get_cycles(MemristorArray* arr, int row, int col)
{
    if (!arr || row < 0 || row >= NSM_ROWS || col < 0 || col >= NSM_COLS)
        return -1;
    return arr->cycles[row][col];
}

/* Return total accumulated energy in pico-joules */
float nsm_get_energy_pj(MemristorArray* arr)
{
    (void)arr;   /* reserved for per-instance accounting in future HW */
    return g_total_energy_pj;
}
