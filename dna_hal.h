/* dna_hal.h - DNA Hardware Abstraction Layer for DNAOS
 * DNA存算一体伪HAL接口层
 * 模拟微流控芯片ASU mmDNA电极阵列，9bp DNA三态金属离子配位存储
 */

#ifndef DNA_HAL_H
#define DNA_HAL_H

#include <stdint.h>

/* --- 系统常量 --- */
#define DNA_TUBE_COUNT      256     /* 电极阵列tube数量 */
#define DNA_MAX_CYCLES      48      /* mmDNA擦写寿命上限 */
#define DNA_TRISTATE_NEG    (-1)    /* T-Hg2+-T 配位态 */
#define DNA_TRISTATE_ZERO   0       /* 未配位/中性态 */
#define DNA_TRISTATE_POS    1       /* C-Ag+-C 配位态 */
#define DNA_STATE_UNINIT    (-2)    /* 未初始化 */

/* --- 存储接口 --- */
int  dna_read(int tube_id);              /* 读取tube三态值（后期=measure_conductance） */
int  dna_write(int tube_id, int value);  /* 写入tube（后期=set_gate_voltage + pH切换） */
int  dna_erase(int tube_id);             /* 擦除tube（后期=EDTA冲洗） */

/* --- 延迟模拟（论文参数） --- */
void dna_sleep_ms(int ms);               /* 毫秒级延迟（模拟电导测量1ms） */
void dna_sleep_s(int s);                 /* 秒级延迟（模拟写入5-16s） */
void dna_sleep_min(int min);             /* 分钟级延迟（模拟TCR 30min） */

/* --- 试剂管理（开放系统ATP模型） --- */
void  reagent_hg2plus(float mg);         /* 消耗Hg²⁺离子（mg） */
void  reagent_agplus(float mg);          /* 消耗Ag⁺离子（mg） */
void  reagent_edta(float ml);            /* 消耗EDTA清洗液（ml） */
void  reagent_dna_strand(float pmol);    /* 消耗新DNA链（pmol） */
float reagent_get_budget(void);          /* 查询剩余试剂预算（归一化0.0~1.0） */
void  reagent_refill(void);              /* 换液/补充试剂 */

/* --- 状态查询 --- */
int dna_get_cycles(int tube_id);         /* 查询tube擦写次数（mmDNA寿命48次） */
int dna_get_state(int tube_id);          /* 查询tube三态: -1/0/+1, -2=未初始化 */

#endif /* DNA_HAL_H */
