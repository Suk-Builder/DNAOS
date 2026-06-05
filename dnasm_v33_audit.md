# v3.3 源码审计报告 — 发现的 Bug

## P0-致命 (崩溃/死循环)
1. **do_sqrt 溢出死循环** — `while(r*r<=v)` 当 v=LLONG_MAX 时 r*r 溢出为负，循环永远继续
2. **do_cleave strstr("")** — site="" 时 strstr 可能死循环
3. **do_poly strstr("")** — pr="" 时同样问题

## P1-严重 (错误输出/UB)
4. **do_copy 1<<cycles 溢出** — cycles>=31 时 signed int 移位 UB
5. **do_ligate strcat 溢出** — 拼接后可能超 MAX_LEN
6. **ADD/MUL 64位溢出 UB** — C语言有符号整数溢出是未定义行为
7. **CLAMP parser 不能用 tube** — `I->tube[1]=atoll(tok[3])` 对 "st[50]" 返回0
8. **do_anneal 默认退火** — 无温度参数时 temp=0<55，自动退火

## P2-中等 (功能缺失)
9. **COUNT/SPLIT/MIX 无 execute case** — 变成 NOP
10. **PARA 的 end 为负时 wrap 到63** — 预期应为0
11. **do_sub 负数减正数不 clamp** — st[0]=-5, st[1]=3: -5-3=-8, 但-8<0 应该clamp？实际上-8<0所以clamp到0

## P3-轻微
12. **parse_line tok[8] 数组越界** — 超过8个token时越界
13. **init_tubes malloc 不检查返回值** — 失败时 segfault
14. **prog 数组在 main 中是局部变量** — 可能栈溢出（但2MB在Linux上安全）
15. **do_prime O(N^2)** — 大N时极慢
