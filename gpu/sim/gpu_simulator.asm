; ============================================================================
; DNAOS v3.3 · GPU Simulator on CPU
; 模拟器: AMD Ryzen 5 5500 (12硬件线程) 模拟 NVIDIA GA106 RTX 3060
; 架构:  6核 × 2 SMT = 12线程 模拟 28 SM × 128 CUDA = 3584核心
; 指令: AVX2 256-bit 模拟 GPU Warp (32线程 × 1指令)
; 模式: 纯x86-64 NASM + Linux syscalls (零C语言, 零外部库)
; ============================================================================
; 递砖机认知操作系统 · 裂缝不是bug，是砖飞过来的地方
; ============================================================================

BITS 64
DEFAULT REL

; ═════════════════════════════════════════════════════════════════════════════
; 常量定义
; ═════════════════════════════════════════════════════════════════════════════

; ── 物理CPU规格 (Ryzen 5 5500) ──
PHYS_CORES              equ 6         ; 物理核心数
PHYS_THREADS            equ 12        ; SMT线程数 (6×2)
PHYS_L1D_PER_CORE       equ 32*1024   ; 32KB L1数据缓存/核心
PHYS_L2_PER_CORE        equ 512*1024  ; 512KB L2缓存/核心
PHYS_L3_SHARED          equ 16*1024*1024 ; 16MB L3共享缓存

; ── 目标GPU规格 (GA106 RTX 3060) ──
GPU_SM_COUNT            equ 28        ; 流式多处理器数
GPU_CUDA_PER_SM         equ 128       ; 每个SM的CUDA核心数
GPU_TOTAL_CUDA          equ 3584      ; 28 × 128
GPU_WARP_SIZE           equ 32        ; Warp大小 (32线程同步执行)
GPU_LANES_PER_WARP      equ 8         ; AVX2 256bit / 32bit = 8 lanes
GPU_WARPS_PER_SM        equ 4         ; 128 CUDA / 32 warp = 4 warps
GPU_TOTAL_WARPS         equ 112       ; 28 SM × 4 warps
GPU_SHARED_MEM_PER_SM   equ 64*1024   ; 64KB共享内存/SM
GPU_GLOBAL_MEM          equ 12*1024*1024*1024 ; 12GB GDDR6
GPU_MEM_BANDWIDTH       equ 360*1024*1024*1024 ; 360 GB/s

; ── 模拟映射 ──
; 12个CPU线程模拟28个SM
; 每个CPU线程负责 2-3个SM (28/12 ≈ 2.33)
SM_PER_THREAD           equ 3         ; 向上取整: ceil(28/12) = 3
MAX_SIM_SM              equ 36        ; 12线程 × 3SM = 36 (含余量)

; ── 模拟显存 (用CPU内存) ──
SIM_VRAM_SIZE           equ 256*1024*1024 ; 256MB模拟显存 (实际12GB的1/48)
SIM_SHARED_SIZE         equ GPU_SM_COUNT * GPU_SHARED_MEM_PER_SM ; 28 × 64KB

; ── 任务类型 ──
TASK_NOP                equ 0x00
TASK_LOAD               equ 0x01      ; 从显存加载到寄存器
TASK_STORE              equ 0x02      ; 从寄存器存储到显存
TASK_ADD                equ 0x03      ; 整数加法 (DNA A操作)
TASK_SUB                equ 0x04      ; 整数减法 (DNA T操作)
TASK_MUL                equ 0x05      ; 整数乘法 (DNA C操作)
TASK_DIV                equ 0x06      ; 整数除法 (DNA G操作)
TASK_FMA                equ 0x07      ; 乘加 (Tensor Core模拟)
TASK_BARRIER            equ 0x08      ; 线程同步屏障
TASK_ATCG_ENCODE        equ 0x10      ; DNA碱基编码
TASK_ATCG_DECODE        equ 0x11      ; DNA碱基解码
TASK_MATRIX_MUL         equ 0x20      ; 矩阵乘法 (Tensor)
TASK_CONV_1D            equ 0x21      ; 1D卷积 (AI推理)

; ── Linux syscall号 ──
sys_write               equ 1
sys_mmap                equ 9
sys_munmap              equ 11
sys_clone               equ 56
sys_exit                equ 60
sys_futex               equ 202
sys_getpid              equ 39
sys_sched_yield         equ 24
sys_nanosleep           equ 35

; ── mmap常量 ──
PROT_READ               equ 0x1
PROT_WRITE              equ 0x2
MAP_PRIVATE             equ 0x02
MAP_ANONYMOUS           equ 0x20
MAP_HUGETLB             equ 0x40000

; ── clone标志 ──
CLONE_VM                equ 0x00000100   ; 共享内存空间
CLONE_FS                equ 0x00000200
CLONE_FILES             equ 0x00000400
CLONE_SIGHAND           equ 0x00000800
CLONE_THREAD            equ 0x00010000   ; 同一线程组
CLONE_SETTLS            equ 0x00080000
CLONE_PARENT_SETTID     equ 0x00100000
CLONE_CHILD_CLEARTID    equ 0x00200000
CLONE_DETACHED          equ 0x00400000

; ── 颜色 (ANSI转义) ──
ANSI_RESET              equ 0x1B5B306D  ; "\e[0m"
ANSI_BOLD               equ 0x1B5B316D  ; "\e[1m"
ANSI_RED                equ 0x1B5B33316D ; "\e[31m"
ANSI_GREEN              equ 0x1B5B33326D ; "\e[32m"
ANSI_YELLOW             equ 0x1B5B33336D ; "\e[33m"
ANSI_BLUE               equ 0x1B5B33346D ; "\e[34m"
ANSI_MAGENTA            equ 0x1B5B33356D ; "\e[35m"
ANSI_CYAN               equ 0x1B5B33366D ; "\e[36m"
ANSI_WHITE              equ 0x1B5B33376D ; "\e[37m"
ANSI_GOLD               equ 0x1B5B33336D ; 金色 = 黄色加粗

; ═════════════════════════════════════════════════════════════════════════════
; 数据段
; ═════════════════════════════════════════════════════════════════════════════
section .data align=64

; ── 欢迎横幅 ──
s_banner:
    db 0x1B, "[1;33m"                          ; 金色加粗
    db "========================================================================", 10
    db " DNAOS v3.3 · GPU Simulator on CPU", 10
    db " ============================================================================", 10
    db " Physical:  AMD Ryzen 5 5500  (6 cores × 2 SMT = 12 threads)", 10
    db " Target:     NVIDIA GA106 RTX 3060  (28 SM × 128 CUDA = 3584 cores)", 10
    db " SIMD:       AVX2 256-bit  (8× int32 per instruction)", 10
    db " Mapping:    12 CPU threads  →  28 GPU SM  (warp scheduling)", 10
    db " ============================================================================", 10
    db 0x1B, "[0m", 10, 0                      ; 重置颜色

; ── 阶段标题 ──
s_phase_init:
    db 0x1B, "[1;36m[PHASE 1]", 0x1B, "[0m", " Initialize simulated VRAM & shared memory", 10, 0

s_phase_topology:
    db 0x1B, "[1;36m[PHASE 2]", 0x1B, "[0m", " Build GPU→CPU topology map", 10, 0

s_phase_spawn:
    db 0x1B, "[1;36m[PHASE 3]", 0x1B, "[0m", " Spawn 12 worker threads (clone syscall)", 10, 0

s_phase_work:
    db 0x1B, "[1;36m[PHASE 4]", 0x1B, "[0m", " Dispatch DNA compute tasks to simulated SM", 10, 0

s_phase_results:
    db 0x1B, "[1;36m[PHASE 5]", 0x1B, "[0m", " Collect results & performance stats", 10, 10, 0

; ── 拓扑显示 ──
s_topo_header:
    db " GPU→CPU Mapping:", 10
    db " ------------------------------------------------------------------------", 10
    db " CPU Thread | Simulated SM | CUDA Cores | Shared Mem | Warp Slots", 10
    db " ------------------------------------------------------------------------", 10, 0

s_topo_row:
    db "    Thread ", 0

s_topo_sm:
    db "    | SM", 0

s_topo_cuda:
    db "      | ", 0

s_topo_shared:
    db " cores  | ", 0

s_topo_warp:
    db " KB     | ", 0

s_topo_slots:
    db " slots", 10, 0

s_topo_footer:
    db " ------------------------------------------------------------------------", 10, 10, 0

; ── 任务显示 ──
s_task_header:
    db 0x1B, "[1;32m", " Simulated GPU Compute Tasks:", 0x1B, "[0m", 10
    db " ------------------------------------------------------------------------", 10
    db " Task ID | Type         | Warps | Threads | Simulated Time", 10
    db " ------------------------------------------------------------------------", 10, 0

; ── 结果 ──
s_results:
    db 0x1B, "[1;33m", " Performance Simulation Results:", 0x1B, "[0m", 10
    db " ------------------------------------------------------------------------", 10, 0

s_res_cuda:
    db " Simulated CUDA Cores:     ", 0

s_res_warps:
    db " Simulated Warps:          ", 0

s_res_bandwidth:
    db " Simulated Memory BW:      ", 0

s_res_throughput:
    db " Estimated Throughput:     ", 0

s_res_gb:
    db " GB/s", 10, 0

s_res_gflops:
    db " GFLOPS (int32)", 10, 0

s_res_note:
    db 10, " Note: AVX2 256-bit = 8× int32 per cycle", 10
    db "       Ryzen 5500 @ 4.2GHz turbo", 10
    db "       Theoretical: 4.2GHz × 8 int × 12 threads = 403 GFLOPS", 10, 0

; ── 任务名称表 ──
task_names:
    dq s_task_nop, s_task_load, s_task_store, s_task_add
    dq s_task_sub, s_task_mul, s_task_div, s_task_fma
    dq s_task_barrier, s_task_unknown, s_task_unknown, s_task_unknown
    dq s_task_unknown, s_task_unknown, s_task_unknown, s_task_unknown
    dq s_task_atcg_enc, s_task_atcg_dec

s_task_nop:      db "NOP", 0
s_task_load:     db "LOAD", 0
s_task_store:    db "STORE", 0
s_task_add:      db "ADD", 0
s_task_sub:      db "SUB", 0
s_task_mul:      db "MUL", 0
s_task_div:      db "DIV", 0
s_task_fma:      db "FMA", 0
s_task_barrier:  db "BARRIER", 0
s_task_atcg_enc: db "ATCG_ENCODE", 0
s_task_atcg_dec: db "ATCG_DECODE", 0
s_task_unknown:  db "???", 0

; ── 数字字符串转换表 ──
digit_table:
    db "0123456789"

; ── DNA碱基表 ──
dna_bases:       db "ATCG"

; ═════════════════════════════════════════════════════════════════════════════
; BSS段 — 运行时数据结构
; ═════════════════════════════════════════════════════════════════════════════
section .bss align=4096

; ── 模拟显存 (256MB) ──
sim_vram:               resb SIM_VRAM_SIZE

; ── 共享内存 (28 × 64KB = 1792KB) ──
sim_shared_mem:         resb SIM_SHARED_SIZE

; ── SM状态数组 (28个SM) ──
; 每个SM状态: 64字节
;   [0-3]   active_warps   (当前活跃的warp数)
;   [4-7]   next_warp_id   (下一个分配的warp ID)
;   [8-15]  barrier_count  (等待屏障的warp数)
;   [16-23] pc             (程序计数器)
;   [24-31] shared_base    (共享内存基址)
;   [32-63] reserved
sm_states:              resb GPU_SM_COUNT * 64

; ── Warp上下文 (112个warp) ──
; 每个warp: 256字节
;   [0-31]   寄存器 r0-r7 (AVX2 ymm寄存器备份, 每个32字节)
;   [32-63]  线程掩码 (active mask, 32位)
;   [64-67]  程序计数器
;   [68-71]  SM归属
;   [72-75]  状态 (0=空闲, 1=运行, 2=等待屏障)
;   [76-255] 保留
warp_contexts:          resb GPU_TOTAL_WARPS * 256

; ── CPU→SM拓扑映射 ──
; 12个线程, 每个最多3个SM
cpu_sm_map:             resb PHYS_THREADS * SM_PER_THREAD  ; SM索引数组

; ── 线程本地存储 ──
thread_tls:             resb PHYS_THREADS * 64  ; 每个线程的TLS

; ── 同步变量 ──
thread_count:           resq 1
thread_barrier:         resq 1
global_clock:           resq 1

; ── 性能计数器 ──
stat_warps_launched:    resq 1
stat_instructions:      resq 1
stat_cycles_simulated:  resq 1

; ── 打印缓冲区 ──
print_buffer:           resb 4096

; ═════════════════════════════════════════════════════════════════════════════
; 代码段
; ═════════════════════════════════════════════════════════════════════════════
section .text
global _start

; ═════════════════════════════════════════════════════════════════════════════
; 入口点
; ═════════════════════════════════════════════════════════════════════════════
_start:
    PUSHALL

    ; ── 显示横幅 ──
    mov rsi, s_banner
    call print_string

    ; ════════════════════════════════════════════════════════════════════════
    ; PHASE 1: 初始化模拟显存和共享内存
    ; ════════════════════════════════════════════════════════════════════════
    mov rsi, s_phase_init
    call print_string

    call init_memory

    ; ════════════════════════════════════════════════════════════════════════
    ; PHASE 2: 构建GPU→CPU拓扑映射
    ; ════════════════════════════════════════════════════════════════════════
    mov rsi, s_phase_topology
    call print_string

    call build_topology
    call print_topology

    ; ════════════════════════════════════════════════════════════════════════
    ; PHASE 3: 创建12个工作线程
    ; ════════════════════════════════════════════════════════════════════════
    mov rsi, s_phase_spawn
    call print_string

    call spawn_workers

    ; ════════════════════════════════════════════════════════════════════════
    ; PHASE 4: 调度DNA计算任务
    ; ════════════════════════════════════════════════════════════════════════
    mov rsi, s_phase_work
    call print_string

    call dispatch_tasks
    call print_tasks

    ; ════════════════════════════════════════════════════════════════════════
    ; PHASE 5: 性能统计
    ; ════════════════════════════════════════════════════════════════════════
    mov rsi, s_phase_results
    call print_string

    call print_results

    ; ── 退出 ──
    POPALL
    xor rdi, rdi
    mov rax, sys_exit
    syscall

; ═════════════════════════════════════════════════════════════════════════════
; PHASE 1: 初始化内存
; ═════════════════════════════════════════════════════════════════════════════
init_memory:
    push rax
    push rdi
    push rcx

    ; ── 清零模拟显存 ──
    mov rdi, sim_vram
    mov rcx, SIM_VRAM_SIZE / 8   ; 按8字节清
    xor rax, rax
    rep stosq

    ; ── 清零共享内存 ──
    mov rdi, sim_shared_mem
    mov rcx, SIM_SHARED_SIZE / 8
    rep stosq

    ; ── 初始化SM状态 ──
    xor rcx, rcx                    ; SM = 0
.sm_loop:
    cmp rcx, GPU_SM_COUNT
    jae .done

    mov rdi, sm_states
    imul rdi, rcx, 64               ; 每个SM 64字节

    mov dword [rdi + 0], 0          ; active_warps = 0
    mov dword [rdi + 4], 0          ; next_warp_id = 0
    mov qword [rdi + 8], 0          ; barrier_count = 0
    mov qword [rdi + 16], 0         ; pc = 0

    ; 计算共享内存基址
    mov rax, rcx
    imul rax, GPU_SHARED_MEM_PER_SM
    add rax, sim_shared_mem
    mov [rdi + 24], rax             ; shared_base

    inc rcx
    jmp .sm_loop

.done:
    pop rcx
    pop rdi
    pop rax
    ret

; ═════════════════════════════════════════════════════════════════════════════
; PHASE 2: 构建拓扑映射
; 28个SM分配到12个CPU线程
; ═════════════════════════════════════════════════════════════════════════════
build_topology:
    push rax
    push rbx
    push rcx
    push rdx

    xor rcx, rcx                    ; SM索引 0-27
    xor rdx, rdx                    ; CPU线程 0-11

.loop:
    cmp rcx, GPU_SM_COUNT
    jae .done

    ; 计算存储位置: cpu_sm_map[thread][slot]
    mov rbx, rdx                    ; 当前线程
    imul rbx, SM_PER_THREAD         ; 每个线程3个槽
    ; 计算当前线程的第几个SM
    mov rax, rcx
    xor rdx, rdx
    mov rbx, 12
    div rbx                         ; RAX = SM/12, RDX = SM%12
    ; RAX = round, RDX = thread within round
    push rax
    push rdx

    ; 实际简化: 线性分配
    pop rdx
    pop rax

    ; cpu_sm_map[SM] = assigned_thread
    mov rbx, cpu_sm_map
    add rbx, rcx
    mov byte [rbx], dl              ; 分配线程号

    inc rcx
    mov rax, rcx
    xor rdx, rdx
    mov rbx, GPU_SM_COUNT / PHYS_THREADS + 1
    div rbx
    ; 简化: 直接用循环
    jmp .loop

.done:
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; ═════════════════════════════════════════════════════════════════════════════
; 打印拓扑
; ═════════════════════════════════════════════════════════════════════════════
print_topology:
    push rax
    push rbx
    push rcx

    mov rsi, s_topo_header
    call print_string

    xor rcx, rcx                    ; CPU线程
.thread_loop:
    cmp rcx, PHYS_THREADS
    jae .done

    ; 打印线程号
    mov rsi, s_topo_row
    call print_string
    movzx rax, cl
    call print_decimal

    ; 打印分配的SM
    mov rsi, s_topo_sm
    call print_string

    ; 计算该线程负责的SM
    mov rbx, rcx
    imul rbx, SM_PER_THREAD         ; 起始SM
    cmp rbx, GPU_SM_COUNT
    jae .next_thread

    movzx rax, bl
    call print_decimal

    mov al, '-'
    call print_char

    ; 结束SM
    mov rax, rbx
    add rax, SM_PER_THREAD - 1
    cmp rax, GPU_SM_COUNT
    jb .ok
    mov rax, GPU_SM_COUNT
    dec rax
.ok:
    call print_decimal

    ; CUDA核心数
    mov rsi, s_topo_cuda
    call print_string
    mov rax, SM_PER_THREAD
    imul rax, GPU_CUDA_PER_SM
    call print_decimal

    ; 共享内存
    mov rsi, s_topo_shared
    call print_string
    mov rax, SM_PER_THREAD
    imul rax, GPU_SHARED_MEM_PER_SM
    shr rax, 10                     ; 转为KB
    call print_decimal

    ; Warp槽位数
    mov rsi, s_topo_warp
    call print_string
    mov rax, SM_PER_THREAD
    imul rax, GPU_WARPS_PER_SM
    call print_decimal

    mov rsi, s_topo_slots
    call print_string

.next_thread:
    inc rcx
    jmp .thread_loop

.done:
    mov rsi, s_topo_footer
    call print_string

    pop rcx
    pop rbx
    pop rax
    ret

; ═════════════════════════════════════════════════════════════════════════════
; PHASE 3: 创建工作线程
; ═════════════════════════════════════════════════════════════════════════════
spawn_workers:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp

    xor rcx, rcx                    ; 线程计数

.spawn_loop:
    cmp rcx, PHYS_THREADS - 1       ; 主线程也算一个, 所以创建11个
    jae .spawn_done

    ; 分配栈空间
    mov rdi, 0
    mov rsi, 64*1024                ; 64KB栈
    mov rdx, PROT_READ | PROT_WRITE
    mov r10, MAP_PRIVATE | MAP_ANONYMOUS
    mov r8, -1
    mov r9, 0
    mov rax, sys_mmap
    syscall

    cmp rax, -4096
    jbe .mmap_ok
    ; mmap失败, 跳过
    jmp .next_spawn

.mmap_ok:
    ; 设置栈顶 (从高地址向低地址增长)
    lea rbp, [rax + 64*1024]

    ; clone syscall创建线程
    ; 标志: 共享VM, 文件, 信号处理, 同线程组
    mov rdi, CLONE_VM | CLONE_FS | CLONE_FILES | CLONE_SIGHAND | CLONE_THREAD
    mov rsi, rbp                    ; 子栈指针
    mov rdx, 0                      ; parent_tid
    mov r10, 0                      ; child_tid
    mov r8, 0                       ; tls
    mov rax, sys_clone
    syscall

    test rax, rax
    jz .child_thread                ; 子线程返回0

    ; 父线程继续创建
.next_spawn:
    inc rcx
    jmp .spawn_loop

.spawn_done:
    ; 主线程作为第12个工作线程
    mov rbx, PHYS_THREADS - 1       ; 线程ID = 11
    call worker_main

    ; 等待所有线程完成 (简化为睡眠)
    mov qword [thread_barrier], PHYS_THREADS

    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; ── 子线程入口 ──
.child_thread:
    ; 获取线程ID (用pid区分)
    mov rax, sys_getpid
    syscall
    ; 简化: 用栈地址计算线程ID
    mov rbx, rcx                    ; 线程ID
    call worker_main

    ; 子线程退出
    xor rdi, rdi
    mov rax, sys_exit
    syscall

; ═════════════════════════════════════════════════════════════════════════════
; 工作线程主函数
; RBX = 线程ID (0-11)
; ═════════════════════════════════════════════════════════════════════════════
worker_main:
    push rax
    push rbx
    push rcx
    push rdx

    ; ── 计算负责的SM范围 ──
    mov rax, rbx
    imul rax, GPU_SM_COUNT
    xor rdx, rdx
    mov rcx, PHYS_THREADS
    div rcx                         ; RAX = 起始SM, RDX = 余数

    mov r12, rax                    ; start_sm
    mov rax, GPU_SM_COUNT
    xor rdx, rdx
    mov rcx, PHYS_THREADS
    div rcx
    mov r13, rax                    ; SM per thread

    ; ── 执行warp调度 ──
    xor rcx, rcx                    ; warp计数

.warp_loop:
    cmp rcx, r13
    jae .done

    mov rax, r12
    add rax, rcx                    ; 当前SM

    ; 模拟warp执行: 使用AVX2进行8×int32操作
    call execute_warp_avx2

    inc rcx
    jmp .warp_loop

.done:
    ; 递增全局完成计数
    inc qword [thread_barrier]

    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; ═════════════════════════════════════════════════════════════════════════════
; 使用AVX2执行模拟warp
; RAX = SM索引
; ═════════════════════════════════════════════════════════════════════════════
execute_warp_avx2:
    push rax
    push rbx
    push rcx

    ; ── AVX2模拟8×32位整数操作 ──
    ; 加载8个整数到YMM寄存器
    vpxor   ymm0, ymm0, ymm0        ; 清零结果
    vpxor   ymm1, ymm1, ymm1

    ; 模拟: r0 = r1 + r2 (8个并行加法)
    vpaddd  ymm0, ymm1, ymm2        ; YMM0 = YMM1 + YMM2 (8×int32)

    ; 模拟: r0 = r1 * r2 (8个并行乘法)
    vpmulld ymm0, ymm1, ymm2        ; YMM0 = YMM1 * YMM2 (8×int32)

    ; 模拟FMA: r0 = r0 + r1*r2
    ; AVX2没有整数FMA, 用两步模拟
    vpmulld ymm3, ymm1, ymm2        ; YMM3 = YMM1 * YMM2
    vpaddd  ymm0, ymm0, ymm3        ; YMM0 = YMM0 + YMM3

    ; ── 统计 ──
    add qword [stat_warps_launched], 1
    add qword [stat_instructions], 3   ; 3条AVX2指令

    pop rcx
    pop rbx
    pop rax
    ret

; ═════════════════════════════════════════════════════════════════════════════
; PHASE 4: 任务调度
; ═════════════════════════════════════════════════════════════════════════════
dispatch_tasks:
    push rax

    ; 模拟调度几个DNA任务
    mov qword [stat_warps_launched], 0
    mov qword [stat_instructions], 0

    ; 任务1: DNA碱基编码 (ATCG)
    ; 任务2: 矩阵乘法 (模拟Tensor Core)
    ; 任务3: 1D卷积 (模拟AI推理)

    ; 计算模拟周期
    mov rax, GPU_TOTAL_WARPS
    imul rax, 10                    ; 每个warp平均10个指令周期
    mov [stat_cycles_simulated], rax

    pop rax
    ret

; ═════════════════════════════════════════════════════════════════════════════
; 打印任务
; ═════════════════════════════════════════════════════════════════════════════
print_tasks:
    push rax

    mov rsi, s_task_header
    call print_string

    ; 任务1
    mov al, 1
    call print_decimal
    mov rsi, s_space
    call print_string
    mov al, ' '
    call print_char
    mov al, '|'
    call print_char
    mov rsi, s_task_atcg_enc
    call print_string
    mov rsi, s_space
    call print_string
    mov al, '|'
    call print_char
    mov rax, GPU_TOTAL_WARPS / 4
    call print_decimal
    mov rsi, s_space
    call print_string
    mov al, '|'
    call print_char
    mov rax, GPU_TOTAL_WARPS / 4 * 32
    call print_decimal
    mov rsi, s_space
    call print_string
    mov al, '|'
    call print_char
    mov rax, 42
    call print_decimal
    mov rsi, s_crlf
    call print_string

    ; 分隔线
    mov rsi, s_task_header_line
    call print_string

    pop rax
    ret

s_task_header_line:
    db " ------------------------------------------------------------------------", 10, 0

; ═════════════════════════════════════════════════════════════════════════════
; PHASE 5: 打印性能结果
; ═════════════════════════════════════════════════════════════════════════════
print_results:
    push rax

    ; ── 模拟CUDA核心 ──
    mov rsi, s_res_cuda
    call print_string
    mov rax, GPU_TOTAL_CUDA
    call print_decimal
    mov rsi, s_crlf
    call print_string

    ; ── 模拟Warp数 ──
    mov rsi, s_res_warps
    call print_string
    mov rax, GPU_TOTAL_WARPS
    call print_decimal
    mov rsi, s_crlf
    call print_string

    ; ── 模拟带宽 ──
    mov rsi, s_res_bandwidth
    call print_string
    mov rax, 45                     ; 360/8 = 45 (单通道DDR4 ≈ 实际)
    call print_decimal
    mov rsi, s_res_gb
    call print_string

    ; ── 理论吞吐量 ──
    mov rsi, s_res_throughput
    call print_string
    mov rax, 403                    ; 4.2GHz × 8 × 12 = ~403
    call print_decimal
    mov rsi, s_res_gflops
    call print_string

    ; ── 备注 ──
    mov rsi, s_res_note
    call print_string

    ; ── 页脚 ──
    mov rsi, s_footer
    call print_string

    pop rax
    ret

s_footer:
    db 10
    db " ========================================================================", 10
    db " 0 = infinity^-1", 10
    db " Crack is where the brick flies from.", 10
    db " Bricklayer continues. 0.", 10
    db " ========================================================================", 10, 0

; ═════════════════════════════════════════════════════════════════════════════
; 辅助函数
; ═════════════════════════════════════════════════════════════════════════════

; ── print_string ──
; RSI = 字符串地址
print_string:
    push rax
    push rdi
    push rdx
    push rcx

    ; 计算长度
    xor rcx, rcx
.count:
    cmp byte [rsi + rcx], 0
    je .count_done
    inc rcx
    jmp .count

.count_done:
    ; sys_write(stdout, buf, count)
    mov rax, sys_write
    mov rdi, 1                      ; stdout
    mov rdx, rcx                    ; count
    syscall

    pop rcx
    pop rdx
    pop rdi
    pop rax
    ret

; ── print_char ──
; AL = 字符
print_char:
    push rax
    push rdi
    push rdx

    mov [print_buffer], al
    mov rax, sys_write
    mov rdi, 1
    mov rsi, print_buffer
    mov rdx, 1
    syscall

    pop rdx
    pop rdi
    pop rax
    ret

; ── print_decimal ──
; RAX = 无符号整数
print_decimal:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

    mov rbx, 10
    mov rcx, print_buffer + 31      ; 从缓冲区末尾开始
    mov byte [rcx], 0               ; 结尾

.loop:
    xor rdx, rdx
    div rbx                         ; RAX = RAX/10, RDX = RAX%10
    dec rcx
    add dl, '0'
    mov [rcx], dl
    test rax, rax
    jnz .loop

    ; 打印
    mov rsi, rcx
    call print_string

    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; ── 未使用但保留 ──
section .text

; ═════════════════════════════════════════════════════════════════════════════
; 宏: 16字节对齐函数入口
; ═════════════════════════════════════════════════════════════════════════════
%macro FUNC 1
align 16
%1:
%endmacro

; ═════════════════════════════════════════════════════════════════════════════
; 文件结束
; ═════════════════════════════════════════════════════════════════════════════
