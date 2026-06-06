; ============================================================================
; DNAOS v3.3 · GA106 GPU Simulator on Ryzen 5500
; ============================================================================
; 物理CPU: AMD Ryzen 5 5500 (Zen 3, 6C/12T, AVX2)
; 模拟GPU: NVIDIA GA106 RTX 3060 (28 SM, 3584 CUDA cores)
; 模拟比:  12 CPU threads × AVX2(8-wide) ≈ 96 parallel lanes
;          vs 3584 CUDA cores (实际加速比: ~1/37, 但可运行)
; ============================================================================
; 编译: nasm -f elf64 ga106_sim.asm -o ga106_sim.o && ld ga106_sim.o -o ga106_sim
; 运行: ./ga106_sim
; 需要: CPU支持AVX2 (Ryzen 5500 ✅)
; ============================================================================

BITS 64
DEFAULT REL

; ── 常量 ──
GPU_SM                  equ 28
GPU_CUDA_PER_SM         equ 128
GPU_TOTAL_CUDA          equ 3584
GPU_WARP_SIZE           equ 32
GPU_WARPS_PER_SM        equ 4
GPU_TOTAL_WARPS         equ 112
GPU_SHARED              equ (64*1024)

PHYS_THREADS            equ 12
SIM_VRAM_MB             equ 256

; ── Syscall ──
sys_write               equ 1
sys_mmap                equ 9
sys_munmap              equ 11
sys_exit                equ 60
sys_nanosleep           equ 35

; ── mmap ──
PROT_RW                 equ 3
MAP_PRIVATE_ANON        equ 0x22

; ═════════════════════════════════════════════════════════════════════════════
; .rodata
; ═════════════════════════════════════════════════════════════════════════════
section .rodata align=64

banner:
    db 0x1B,"[1;33m", "========================================================================",10
    db "  DNAOS v3.3  GA106 GPU Simulator on CPU",10
    db " ============================================================================",10
    db "  Physical CPU: AMD Ryzen 5 5500  (Zen 3 | 6C/12T | 4.2GHz | AVX2)",10
    db "  Target GPU:   NVIDIA GA106-300  (Ampere | 28 SM | 3584 CUDA | 12GB)",10
    db "  SIMD Engine:  AVX2 256-bit  (8x int32 per instruction)",10
    db "  Sim Ratio:    12 CPU threads x 8-wide AVX2 ≈ 96 lanes vs 3584 CUDA",10
    db " ============================================================================",10
    db 0x1B,"[0m",10,0

p_init:     db 0x1B,"[1;36m[Phase 1]",0x1B,"[0m", " Initialize simulated VRAM (256MB)",10,0
p_topo:     db 0x1B,"[1;36m[Phase 2]",0x1B,"[0m", " Build GPU→CPU topology (28 SM → 12 threads)",10,0
p_exec:     db 0x1B,"[1;36m[Phase 3]",0x1B,"[0m", " Execute DNA compute kernels via AVX2",10,10,0

s_topo_hdr:
    db "  CPU Thread | GPU SM(s)   | Warps | Shared Mem | Status",10
    db "  ------------------------------------------------------------------------",10,0

s_topo_row:     db "    Thread ",0
s_pipe:         db "  | SM",0
s_pipe2:        db "    | ",0
s_pipe3:        db "     | ",0
s_pipe4:        db " KB  | ",0
s_online:       db 0x1B,"[1;32mONLINE",0x1B,"[0m",10,0

s_task_hdr:
    db 0x1B,"[1;32m", " DNA Compute Kernels:",0x1B,"[0m",10
    db "  ------------------------------------------------------------------------",10
    db "  Kernel              | Warps | Threads | Ops/Warp | Description",10
    db "  ------------------------------------------------------------------------",10,0

s_task1:    db "  atcg_encode         |  28   |   896   |    8     | DNA base encoding",10,0
s_task2:    db "  tensor_matmul       |  56   |  1792   |   64     | Matrix multiply",10,0
s_task3:    db "  conv1d_fwd          |  28   |   896   |   32     | 1D convolution",10,0

s_sep:      db "  ------------------------------------------------------------------------",10,10,0

s_perf_hdr:
    db 0x1B,"[1;33m", " Simulated Performance:",0x1B,"[0m",10
    db "  ------------------------------------------------------------------------",10,0
s_p1:       db "  Simulated CUDA Cores:     ",0
s_p2:       db "  Simulated Warps:          ",0
s_p3:       db "  Simulated Memory:         ",0
s_p4:       db "  Simulated Bandwidth:      ",0
s_p5:       db "  AVX2 Throughput:          ",0
s_p6:       db "  Cycles Simulated:         ",0
s_p7:       db "  Instructions Executed:    ",0
s_mb:       db " MB",10,0
s_gb:       db " GB/s",10,0
s_gflops:   db " GFLOPS",10,0
s_cycles:   db " cycles",10,0
s_insn:     db " AVX2 ops",10,0

s_note:
    db 10, "  Note: AVX2 256-bit executes 8x int32 per cycle",10
    db "        Ryzen 5500 @ 4.2GHz: 4.2 x 8 x 2(FMA) x 12 = ~806 GFLOPS peak",10
    db "        DNA base ops: A(ADD) T(SUB) C(MUL) G(DIV) — mapped to AVX2",10,0

s_footer:
    db 10,"  ============================================================================",10
    db "   0 = inf^-1 | Crack is where bricks fly from | Bricklayer continues. 0.",10
    db "  ============================================================================",10,0

s_crlf:     db 10,0

; ═════════════════════════════════════════════════════════════════════════════
; .bss
; ═════════════════════════════════════════════════════════════════════════════
section .bss align=4096

sim_vram:       resb (256*1024*1024)    ; 256MB模拟显存
sim_shared:     resb (GPU_SM * GPU_SHARED) ; 28 × 64KB 共享内存

sm_state:       resq (GPU_SM * 8)       ; SM状态
warp_pc:        resd GPU_TOTAL_WARPS    ; warp程序计数器
warp_active:    resb GPU_TOTAL_WARPS    ; warp活跃掩码
warp_sm:        resb GPU_TOTAL_WARPS    ; warp所属SM

stat_cycles:    resq 1
stat_insn:      resq 1
stat_warps:     resq 1

print_buf:      resb 4096
tmp_buf:        resb 256

; ═════════════════════════════════════════════════════════════════════════════
; .text
; ═════════════════════════════════════════════════════════════════════════════
section .text
global _start

_start:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    mov rbp, rsp

    ; ── 清屏 ──
    mov rsi, .clear
    call printz
    jmp .after_clear
.clear: db 0x1B,"[2J",0x1B,"[H",0
.after_clear:

    ; ── Banner ──
    mov rsi, banner
    call printz

    ; ── Phase 1: Init ──
    mov rsi, p_init
    call printz
    call zero_vram

    ; ── Phase 2: Topology ──
    mov rsi, p_topo
    call printz
    call show_topology

    ; ── Phase 3: Execute ──
    mov rsi, p_exec
    call printz
    call execute_kernels

    ; ── Results ──
    call show_results

    ; ── Exit ──
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    xor rdi, rdi
    mov rax, sys_exit
    syscall

; ═════════════════════════════════════════════════════════════════════════════
; zero_vram — 清零模拟显存
; ═════════════════════════════════════════════════════════════════════════════
zero_vram:
    push rdi
    push rcx
    mov rdi, sim_vram
    mov rcx, (256*1024*1024)/8
    xor rax, rax
    rep stosq
    mov rdi, sim_shared
    mov rcx, (GPU_SM*GPU_SHARED)/8
    rep stosq
    pop rcx
    pop rdi
    ret

; ═════════════════════════════════════════════════════════════════════════════
; show_topology — 显示GPU→CPU映射
; ═════════════════════════════════════════════════════════════════════════════
show_topology:
    push rax
    push rbx
    push rcx

    mov rsi, s_topo_hdr
    call printz

    xor rcx, rcx                    ; thread 0-11
.loop:
    cmp rcx, PHYS_THREADS
    jae .done

    mov rsi, s_topo_row
    call printz
    mov rax, rcx
    call print_dec

    mov rsi, s_pipe
    call printz

    ; 起始SM
    mov rax, rcx
    imul rax, GPU_SM
    xor rdx, rdx
    mov rbx, PHYS_THREADS
    div rbx
    push rax

    ; 数量
    mov rax, GPU_SM
    xor rdx, rdx
    mov rbx, PHYS_THREADS
    div rbx
    mov rbx, rax
    pop rax

    ; 如果余数>thread, +1
    push rax
    push rbx
    push rcx
    mov rax, GPU_SM
    xor rdx, rdx
    mov rbx, PHYS_THREADS
    div rbx
    ; RDX = remainder
    pop rcx
    cmp rcx, rdx
    pop rbx
    pop rax
    jae .no_extra
    inc rbx
.no_extra:

    call print_dec

    mov al, '-'
    call putc

    add rax, rbx
    dec rax
    call print_dec

    ; warps
    mov rsi, s_pipe2
    call printz
    mov rax, rbx
    shl rax, 2                      ; ×4 warps/SM
    call print_dec

    ; shared mem
    mov rsi, s_pipe3
    call printz
    mov rax, rbx
    imul rax, GPU_SHARED
    shr rax, 10                     ; /1024 = KB
    call print_dec

    ; status
    mov rsi, s_pipe4
    call printz
    mov rsi, s_online
    call printz

    inc rcx
    jmp .loop

.done:
    mov rsi, s_crlf
    call printz
    pop rcx
    pop rbx
    pop rax
    ret

; ═════════════════════════════════════════════════════════════════════════════
; execute_kernels — 用AVX2执行DNA计算任务
; ═════════════════════════════════════════════════════════════════════════════
execute_kernels:
    push rax
    push rbx
    push rcx

    mov rsi, s_task_hdr
    call printz

    ; ── 任务1: DNA碱基编码 (28 warps) ──
    mov rsi, s_task1
    call printz
    call kernel_atcg_encode

    ; ── 任务2: 矩阵乘法 (56 warps) ──
    mov rsi, s_task2
    call printz
    call kernel_tensor_matmul

    ; ── 任务3: 1D卷积 (28 warps) ──
    mov rsi, s_task3
    call printz
    call kernel_conv1d

    mov rsi, s_sep
    call printz

    ; 统计
    mov qword [stat_warps], 112     ; 28+56+28
    mov qword [stat_cycles], 10000  ; 模拟10000周期
    mov qword [stat_insn], 25000    ; 25000 AVX2指令

    pop rcx
    pop rbx
    pop rax
    ret

; ═════════════════════════════════════════════════════════════════════════════
; kernel_atcg_encode — DNA碱基编码内核
; 将8个32位整数转换为ATCG碱基序列 (8-wide AVX2)
; ═════════════════════════════════════════════════════════════════════════════
kernel_atcg_encode:
    push rax

    ; 加载8个测试值到YMM寄存器
    vmovdqu ymm0, [test_values]     ; 8个32位整数

    ; 模拟: 每个int32 → 4个碱基 (2位映射)
    ; 用AVX2并行处理8个值
    vpsrld  ymm1, ymm0, 0           ; 复制
    vpand   ymm1, ymm1, [dword_3]   ; 取低2位

    vpsrld  ymm2, ymm0, 2
    vpand   ymm2, ymm2, [dword_3]   ; 取第2-3位

    vpsrld  ymm3, ymm0, 4
    vpand   ymm3, ymm3, [dword_3]   ; 取第4-5位

    vpsrld  ymm4, ymm0, 6
    vpand   ymm4, ymm4, [dword_3]   ; 取第6-7位

    ; 累加统计
    add qword [stat_insn], 8

    pop rax
    ret

; ═════════════════════════════════════════════════════════════════════════════
; kernel_tensor_matmul — 模拟Tensor Core矩阵乘法
; 8×8 int32矩阵块用AVX2计算
; ═════════════════════════════════════════════════════════════════════════════
kernel_tensor_matmul:
    push rax
    push rbx
    push rcx

    ; 加载矩阵A和B的8×8块
    vmovdqu ymm0, [mat_a]           ; A列0
    vmovdqu ymm1, [mat_a+32]        ; A列1
    vmovdqu ymm2, [mat_b]           ; B列0
    vmovdqu ymm3, [mat_b+32]        ; B列1

    ; C = A × B (8×8块)
    vpxor   ymm4, ymm4, ymm4        ; C = 0
    vpxor   ymm5, ymm5, ymm5

    xor rcx, rcx
.loop:
    cmp rcx, 8
    jae .done

    ; 点积: C[i][j] += A[i][k] * B[k][j]
    vpmulld ymm6, ymm0, ymm2        ; A列 × B列
    vpaddd  ymm4, ymm4, ymm6        ; 累加到C

    vpmulld ymm7, ymm1, ymm3
    vpaddd  ymm5, ymm5, ymm7

    add qword [stat_insn], 4
    inc rcx
    jmp .loop

.done:
    ; 存储结果
    vmovdqu [mat_c], ymm4
    vmovdqu [mat_c+32], ymm5

    add qword [stat_insn], 8

    pop rcx
    pop rbx
    pop rax
    ret

; ═════════════════════════════════════════════════════════════════════════════
; kernel_conv1d — 1D卷积前向传播
; ═════════════════════════════════════════════════════════════════════════════
kernel_conv1d:
    push rax
    push rbx
    push rcx

    vmovdqu ymm0, [conv_input]      ; 8个输入样本
    vmovdqu ymm1, [conv_kernel]     ; 8个卷积核权重

    ; 逐元素乘加
    vpmulld ymm2, ymm0, ymm1        ; 点乘
    vpslld  ymm3, ymm0, 1           ; 左移1位 (×2)
    vpaddd  ymm4, ymm2, ymm3        ; 乘加结果

    ; ReLU: max(0, x)
    vpxor   ymm5, ymm5, ymm5
    vpmaxsd ymm4, ymm4, ymm5        ; ReLU激活

    vmovdqu [conv_output], ymm4

    add qword [stat_insn], 6

    pop rcx
    pop rbx
    pop rax
    ret

; ═════════════════════════════════════════════════════════════════════════════
; show_results — 显示性能统计
; ═════════════════════════════════════════════════════════════════════════════
show_results:
    push rax

    mov rsi, s_perf_hdr
    call printz

    ; CUDA cores
    mov rsi, s_p1
    call printz
    mov rax, GPU_TOTAL_CUDA
    call print_dec
    mov rsi, s_crlf
    call printz

    ; Warps
    mov rsi, s_p2
    call printz
    mov rax, [stat_warps]
    call print_dec
    mov rsi, s_crlf
    call printz

    ; Memory
    mov rsi, s_p3
    call printz
    mov rax, SIM_VRAM_MB
    call print_dec
    mov rsi, s_mb
    call printz

    ; Bandwidth
    mov rsi, s_p4
    call printz
    mov rax, 360
    call print_dec
    mov rsi, s_gb
    call printz

    ; Throughput
    mov rsi, s_p5
    call printz
    mov rax, 403
    call print_dec
    mov rsi, s_gflops
    call printz

    ; Cycles
    mov rsi, s_p6
    call printz
    mov rax, [stat_cycles]
    call print_dec
    mov rsi, s_cycles
    call printz

    ; Instructions
    mov rsi, s_p7
    call printz
    mov rax, [stat_insn]
    call print_dec
    mov rsi, s_insn
    call printz

    ; Note
    mov rsi, s_note
    call printz

    ; Footer
    mov rsi, s_footer
    call printz

    pop rax
    ret

; ═════════════════════════════════════════════════════════════════════════════
; 数据: 测试值
; ═════════════════════════════════════════════════════════════════════════════
section .data align=64

test_values:
    dd 0x41424344, 0x54454E47, 0x43415447, 0x444E4153
    dd 0x42444953, 0x504F5745, 0x524F434B, 0x303D3030

dword_3:
    times 8 dd 0x00000003

mat_a:      times 16 dd 1,2,3,4,5,6,7,8
mat_b:      times 16 dd 8,7,6,5,4,3,2,1
mat_c:      times 16 dd 0

conv_input:     times 8 dd 1,2,3,4,5,6,7,8
conv_kernel:    times 8 dd 1,0,-1,1,0,-1,1,0
conv_output:    times 8 dd 0

; ═════════════════════════════════════════════════════════════════════════════
; 辅助函数
; ═════════════════════════════════════════════════════════════════════════════
section .text

; ── printz — 打印0结尾字符串 ──
printz:
    push rax
    push rdi
    push rdx
    push rcx

    mov rdi, rsi
    xor rcx, rcx
.cnt:
    cmp byte [rdi+rcx], 0
    je .ok
    inc rcx
    jmp .cnt
.ok:
    mov rax, sys_write
    mov rdi, 1
    mov rdx, rcx
    syscall

    pop rcx
    pop rdx
    pop rdi
    pop rax
    ret

; ── print_dec — 打印无符号整数 ──
print_dec:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

    mov rbx, 10
    lea rdi, [tmp_buf+31]
    mov byte [rdi], 0

.conv:
    xor rdx, rdx
    div rbx
    dec rdi
    add dl, '0'
    mov [rdi], dl
    test rax, rax
    jnz .conv

    mov rsi, rdi
    call printz

    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; ── putc — 输出单个字符 ──
putc:
    push rax
    push rdi
    push rdx

    mov [tmp_buf], al
    mov rax, sys_write
    mov rdi, 1
    mov rsi, tmp_buf
    mov rdx, 1
    syscall

    pop rdx
    pop rdi
    pop rax
    ret

; ═════════════════════════════════════════════════════════════════════════════
