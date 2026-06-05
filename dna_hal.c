/* dna_hal.c - DNA HAL simulation backend (CPU模拟层)
 * 底层映射: st[tube_id].num_val 读写
 * 后期替换: 直接对接电极驱动代码，接口不动
 */

#include "dna_hal.h"
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <stdlib.h>
#include <unistd.h>

/* ============================================================
 *  数据结构
 * ============================================================ */

typedef struct {
    int   num_val;       /* 存储的三态值: -1, 0, +1 */
    int   state;         /* 状态标记: -2=未初始化, -1/0/+1=有效 */
    int   cycles;        /* 已擦写次数（mmDNA寿命48次） */
} dna_tube_t;

typedef struct {
    float hg2plus_mg;    /* Hg²⁺累计消耗 (mg) */
    float agplus_mg;     /* Ag⁺累计消耗 (mg) */
    float edta_ml;       /* EDTA累计消耗 (ml) */
    float dna_pmol;      /* DNA链累计消耗 (pmol) */
    float budget;        /* 归一化剩余预算 0.0~1.0 */
} reagent_account_t;

/* ============================================================
 *  全局状态
 * ============================================================ */

static dna_tube_t      g_tubes[DNA_TUBE_COUNT];
static reagent_account_t g_reagent = {0.0f, 0.0f, 0.0f, 0.0f, 1.0f};
static int             g_hal_inited = 0;

/* ============================================================
 *  内部工具函数
 * ============================================================ */

/* 生成[a,b]范围内的随机整数 */
static inline int rand_range(int a, int b)
{
    return a + (rand() % (b - a + 1));
}

/* 检查tube_id合法性 */
static inline int check_id(int tube_id)
{
    return (tube_id >= 0 && tube_id < DNA_TUBE_COUNT);
}

/* 初始化全局状态（延迟初始化） */
static void hal_lazy_init(void)
{
    if (g_hal_inited) return;
    srand((unsigned)time(NULL));
    for (int i = 0; i < DNA_TUBE_COUNT; i++) {
        g_tubes[i].num_val = 0;
        g_tubes[i].state   = DNA_STATE_UNINIT;
        g_tubes[i].cycles  = 0;
    }
    g_hal_inited = 1;
}

/* 打印操作日志 */
static void log_op(const char *op, int tube_id, int val,
                   int delay_ms, float hg_mg, float ag_mg,
                   float edta_ml, int cycles)
{
    fprintf(stderr,
        "[HAL] %s tube[%d]=%d, delay=%dms, "
        "Hg2+=%.3fmg, Ag+=%.3fmg, EDTA=%.3fml, cycles=%d/%d\n",
        op, tube_id, val, delay_ms,
        hg_mg, ag_mg, edta_ml, cycles, DNA_MAX_CYCLES);
}

/* ============================================================
 *  延迟接口（模拟真实论文参数）
 * ============================================================ */

void dna_sleep_ms(int ms)
{
    struct timespec ts = {ms / 1000, (ms % 1000) * 1000000L};
    nanosleep(&ts, NULL);
}

void dna_sleep_s(int s)
{
    struct timespec ts = {s, 0};
    nanosleep(&ts, NULL);
}

void dna_sleep_min(int min)
{
    struct timespec ts = {min * 60, 0};
    nanosleep(&ts, NULL);
}

/* ============================================================
 *  存储接口
 * ============================================================ */

/* 读取tube三态值（模拟电导测量1ms延迟）
 * 后期实现: measure_conductance() -> map to tristate */
int dna_read(int tube_id)
{
    hal_lazy_init();
    if (!check_id(tube_id)) {
        fprintf(stderr, "[HAL-ERR] read: invalid tube_id=%d\n", tube_id);
        return DNA_STATE_UNINIT;
    }

    /* 模拟电导测量延迟 1ms */
    dna_sleep_ms(1);

    return g_tubes[tube_id].num_val;
}

/* 写入tube（模拟gate电压+pH切换，5-16秒延迟）
 * value: 只能为 -1, 0, +1
 * 后期实现: set_gate_voltage() + pH_switch() */
int dna_write(int tube_id, int value)
{
    hal_lazy_init();
    if (!check_id(tube_id)) {
        fprintf(stderr, "[HAL-ERR] write: invalid tube_id=%d\n", tube_id);
        return -1;
    }
    if (value != DNA_TRISTATE_NEG &&
        value != DNA_TRISTATE_ZERO &&
        value != DNA_TRISTATE_POS) {
        fprintf(stderr, "[HAL-ERR] write: invalid value=%d (must be -1/0/+1)\n", value);
        return -1;
    }
    if (g_tubes[tube_id].cycles >= DNA_MAX_CYCLES) {
        fprintf(stderr, "[HAL-ERR] write: tube[%d] exceeds max cycles %d\n",
                tube_id, DNA_MAX_CYCLES);
        return -1;
    }
    if (g_reagent.budget <= 0.0f) {
        fprintf(stderr, "[HAL-ERR] write: reagent budget depleted\n");
        return -1;
    }

    /* 计算试剂消耗（基于论文参数估算） */
    float hg_mg   = 0.0f;
    float ag_mg   = 0.0f;
    float edta_ml = 0.0f;

    switch (value) {
    case DNA_TRISTATE_NEG:  /* T-Hg2+-T 配位 */
        hg_mg = 0.01f;      /* ~0.01mg Hg²⁺ */
        break;
    case DNA_TRISTATE_POS:  /* C-Ag+-C 配位 */
        ag_mg = 0.008f;     /* ~0.008mg Ag⁺ */
        break;
    case DNA_TRISTATE_ZERO: /* 中性态，EDTA预洗 */
        edta_ml = 0.05f;
        break;
    }

    /* 写入延迟: 5-16秒（模拟金属离子配位动力学） */
    int delay_s = rand_range(5, 16);
    dna_sleep_s(delay_s);

    /* 更新tube状态 */
    g_tubes[tube_id].num_val = value;
    g_tubes[tube_id].state   = value;
    if (g_tubes[tube_id].state == DNA_STATE_UNINIT) {
        /* 首次写入 */
    }
    g_tubes[tube_id].cycles++;

    /* 扣除试剂 */
    g_reagent.hg2plus_mg += hg_mg;
    g_reagent.agplus_mg  += ag_mg;
    g_reagent.edta_ml    += edta_ml;
    g_reagent.budget     -= (hg_mg * 0.1f + ag_mg * 0.1f + edta_ml * 0.02f);
    if (g_reagent.budget < 0.0f) g_reagent.budget = 0.0f;

    /* 打印操作日志 */
    log_op("write", tube_id, value, delay_s * 1000,
           hg_mg, ag_mg, edta_ml, g_tubes[tube_id].cycles);

    return 0;
}

/* 擦除tube（模拟EDTA冲洗，重置为中性态）
 * 后期实现: EDTA_flush() */
int dna_erase(int tube_id)
{
    hal_lazy_init();
    if (!check_id(tube_id)) {
        fprintf(stderr, "[HAL-ERR] erase: invalid tube_id=%d\n", tube_id);
        return -1;
    }
    if (g_tubes[tube_id].state == DNA_STATE_UNINIT) {
        fprintf(stderr, "[HAL-WARN] erase: tube[%d] not initialized, skip\n", tube_id);
        return 0;
    }
    if (g_tubes[tube_id].cycles >= DNA_MAX_CYCLES) {
        fprintf(stderr, "[HAL-ERR] erase: tube[%d] exceeds max cycles %d\n",
                tube_id, DNA_MAX_CYCLES);
        return -1;
    }

    /* EDTA清洗消耗 */
    float edta_ml = 0.1f;

    /* 擦除延迟: 3-8秒（模拟EDTA冲洗过程） */
    int delay_s = rand_range(3, 8);
    dna_sleep_s(delay_s);

    /* 重置为中性态 */
    g_tubes[tube_id].num_val = DNA_TRISTATE_ZERO;
    g_tubes[tube_id].state   = DNA_TRISTATE_ZERO;
    g_tubes[tube_id].cycles++;

    /* 扣除试剂 */
    g_reagent.edta_ml += edta_ml;
    g_reagent.budget  -= (edta_ml * 0.02f);
    if (g_reagent.budget < 0.0f) g_reagent.budget = 0.0f;

    /* 打印操作日志 */
    log_op("erase", tube_id, 0, delay_s * 1000,
           0.0f, 0.0f, edta_ml, g_tubes[tube_id].cycles);

    return 0;
}

/* ============================================================
 *  试剂管理（开放系统ATP模型）
 * ============================================================ */

void reagent_hg2plus(float mg)
{
    hal_lazy_init();
    g_reagent.hg2plus_mg += mg;
    g_reagent.budget     -= (mg * 0.1f);
    if (g_reagent.budget < 0.0f) g_reagent.budget = 0.0f;
}

void reagent_agplus(float mg)
{
    hal_lazy_init();
    g_reagent.agplus_mg += mg;
    g_reagent.budget    -= (mg * 0.1f);
    if (g_reagent.budget < 0.0f) g_reagent.budget = 0.0f;
}

void reagent_edta(float ml)
{
    hal_lazy_init();
    g_reagent.edta_ml += ml;
    g_reagent.budget  -= (ml * 0.02f);
    if (g_reagent.budget < 0.0f) g_reagent.budget = 0.0f;
}

void reagent_dna_strand(float pmol)
{
    hal_lazy_init();
    g_reagent.dna_pmol += pmol;
    g_reagent.budget   -= (pmol * 0.001f);
    if (g_reagent.budget < 0.0f) g_reagent.budget = 0.0f;
}

float reagent_get_budget(void)
{
    hal_lazy_init();
    return g_reagent.budget;
}

void reagent_refill(void)
{
    hal_lazy_init();
    g_reagent.budget = 1.0f;
    fprintf(stderr, "[HAL] reagent_refill: budget reset to 1.0\n");
}

/* ============================================================
 *  状态查询
 * ============================================================ */

int dna_get_cycles(int tube_id)
{
    hal_lazy_init();
    if (!check_id(tube_id)) return -1;
    return g_tubes[tube_id].cycles;
}

int dna_get_state(int tube_id)
{
    hal_lazy_init();
    if (!check_id(tube_id)) return DNA_STATE_UNINIT;
    return g_tubes[tube_id].state;
}
