#ifndef NSM_BACKEND_H
#define NSM_BACKEND_H

#define NSM_ROWS 64
#define NSM_COLS 64

// 忆阻器交叉阵列
typedef struct {
    float G[NSM_ROWS][NSM_COLS];      // 电导矩阵 (μS)
    float V[NSM_ROWS];                 // 输入电压 (V)
    float I[NSM_COLS];                 // 输出电流 (μA)
    float G_min, G_max;                // 电导范围
    int cycles[NSM_ROWS][NSM_COLS];    // 擦写次数
    int max_cycles;                    // 寿命上限
} MemristorArray;

// 初始化
void nsm_init(MemristorArray* arr);

// SET操作：增强电导（模拟LTP）
// pulse_width_ns: 脉冲宽度（纳秒）
// pulse_amp_V: 脉冲幅度（伏特）
void nsm_set(MemristorArray* arr, int row, int col, float pw, float amp);

// RESET操作：减弱电导（模拟LTD）
void nsm_reset(MemristorArray* arr, int row, int col, float pw, float amp);

// READ操作：读取电导
float nsm_read(MemristorArray* arr, int row, int col);

// VMM：向量矩阵乘法（忆阻器核心计算）
// I = G^T × V（利用欧姆定律+基尔霍夫定律）
void nsm_vmm(MemristorArray* arr);

// STDP：脉冲时间依赖可塑性
// pre_time: 前突触放电时间（ms）
// post_time: 后突触放电时间（ms）
// 【Δt = post - pre > 0 → LTP（设置）】
// 【Δt = post - pre < 0 → LTD（重置）】
void nsm_stdp(MemristorArray* arr, int pre_row, int post_col,
              float pre_t, float post_t);

// 模拟离子液体化学调制（多巴胺/谷氨酸）
// chem_type: 0=多巴胺(增强LTP), 1=谷氨酸(标准递质), 2=血清素(调节)
// intensity: 0.0~1.0 浓度
void nsm_chem_mod(MemristorArray* arr, int chem_type, float intensity);

// 获取统计信息
int nsm_get_cycles(MemristorArray* arr, int row, int col);
float nsm_get_energy_pj(MemristorArray* arr);  // 累计能耗(pJ)

#endif
