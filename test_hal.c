/* test_hal.c - 编译+功能验证 */
#include "dna_hal.h"
#include <stdio.h>
#include <assert.h>

int main(void)
{
    printf("=== DNA HAL Test ===\n");

    /* 1. 状态查询 - 未初始化 */
    assert(dna_get_state(0) == -2);
    printf("[PASS] init state = UNINIT\n");

    /* 2. 写入三态值 */
    assert(dna_write(3, 1) == 0);   /* C-Ag+-C */
    assert(dna_get_state(3) == 1);
    printf("[PASS] write +1 OK\n");

    assert(dna_write(3, 0) == 0);   /* 中性态 */
    assert(dna_get_state(3) == 0);
    printf("[PASS] write 0 OK\n");

    assert(dna_write(3, -1) == 0);  /* T-Hg2+-T */
    assert(dna_get_state(3) == -1);
    printf("[PASS] write -1 OK\n");

    /* 3. 读取 */
    int v = dna_read(3);
    assert(v == -1);
    printf("[PASS] read back = %d\n", v);

    /* 4. 擦写次数 */
    int c = dna_get_cycles(3);
    assert(c > 0 && c <= 48);
    printf("[PASS] cycles = %d/48\n", c);

    /* 5. 擦除 */
    assert(dna_erase(3) == 0);
    assert(dna_get_state(3) == 0);
    printf("[PASS] erase OK\n");

    /* 6. 试剂预算 */
    float b = reagent_get_budget();
    assert(b >= 0.0f && b <= 1.0f);
    printf("[PASS] budget = %.4f\n", b);

    /* 7. 补充试剂 */
    reagent_refill();
    assert(reagent_get_budget() == 1.0f);
    printf("[PASS] refill OK\n");

    /* 8. 边界检查 */
    assert(dna_read(-1) == -2);
    assert(dna_read(999) == -2);
    printf("[PASS] boundary check OK\n");

    printf("\n=== All tests PASSED ===\n");
    return 0;
}
