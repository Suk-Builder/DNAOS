# DNAsm - DNA Assembly Language Specification

**DNAOS的原生编程语言。用ATCG四进制写内核。**

## 设计哲学

DNAsm不是x86汇编的简单重命名。它是四进制原生的：
- 寄存器用碱基命名（rA=Adenine, rT=Thymine, rC=Cytosine, rG=Guanine）
- 四进制指令（qand/qor/qnot/qadd）是语言的一部分
- ATCG数据可以直接嵌入代码
- 编译到x86_64机器码，裸机运行

## 寄存器映射

| DNAsm | x86_64 | 含义 |
|-------|--------|------|
| rA | rax | Adenine - 累加器/返回值 |
| rT | rcx | Thymine - 计数器 |
| rC | rdx | Cytosine - 数据 |
| rG | rbx | Guanine - 基址 |
| rS | rsi | Sugar - 源索引 |
| rP | rdi | Phosphate - 目标索引 |
| rB | rbp | Base - 基指针 |
| rK | rsp | stacK - 栈指针 |
| r0-r7 | r8-r15 | 通用寄存器 |

子寄存器：
- `rA.w` = eax, `rA.d` = ax, `rA.b` = al, `rA.h` = ah
- `r0.w` = r8d, `r0.b` = r8b

也支持x86原名（rax, eax, al等），但推荐用DNA命名。

## 指令集

### 基础指令（1:1映射到x86）

```dnasm
mov rA, 42              ; mov rax, 42
mov rA, rT              ; mov rax, rcx
add rA, rC              ; add rax, rdx
sub rA, rC              ; sub rax, rdx
and rA, rT              ; and rax, rcx
or  rA, rT              ; or  rax, rcx
xor rA, rT              ; xor rax, rcx
not rA                  ; not rax
shl rA, 4               ; shl rax, 4
shr rA, 4               ; shr rax, 4
push rA                 ; push rax
pop rA                  ; pop rax
cmp rA, rT              ; cmp rax, rcx
test rA, rT             ; test rax, rcx
lea rA, [rP+8]          ; lea rax, [rdi+8]
```

### 控制流

```dnasm
jmp label               ; 无条件跳转
jz label                ; 零跳转
jnz label               ; 非零跳转
jl label                ; 小于跳转
jg label                ; 大于跳转
call label              ; 调用函数
ret                     ; 返回
loop label              ; 循环(rT--)
```

### 系统指令

```dnasm
int 0x80                ; 中断
hlt                     ; 停机
cli                     ; 关中断
sti                     ; 开中断
nop                     ; 空操作
in al, 0x60             ; 读端口
out 0x60, al            ; 写端口
syscall                 ; 系统调用
sysret                  ; 系统返回
iretq                   ; 中断返回
lgdt [rA]               ; 加载GDT
lidt [rA]               ; 加载IDT
invlpg [rA]             ; 刷新TLB
cpuid                   ; CPU信息
rdmsr                   ; 读MSR
wrmsr                   ; 写MSR
swapgs                  ; 交换GS
rdtsc                   ; 读时间戳
```

### 四进制原生指令 ⭐

这是DNAsm的核心——x86没有的四进制操作：

```dnasm
qand rA, rT             ; 四进制AND: 每个quat位取min(a, b)
qor  rA, rT             ; 四进制OR:  每个quat位取max(a, b)
qnot rA                 ; 四进制NOT: 每个quat位取3-x
qadd rA, rT             ; 四进制ADD: 带进位的quat加法
```

四进制逻辑：
- AND = min(a, b): qand(2,3) = 2
- OR  = max(a, b): qor(2,3) = 3
- NOT = 3 - x:     qnot(1) = 2
- ADD = (a+b+carry)%4, carry = (a+b+carry)/4

### 内存操作

```dnasm
mov rA, [rP]            ; 读内存
mov rA, [rP+8]          ; 读内存+偏移
mov [rP], rA            ; 写内存
mov byte [rP], 0        ; 写字节
mov dword [rP], 0       ; 写双字
mov qword [rP], 0       ; 写四字
```

## 数据定义

```dnasm
db 0x90                 ; 字节
dw 0x1234               ; 字
dd 0x12345678           ; 双字
dq 0x123456789ABCDEF0   ; 四字
db "Hello", 0           ; 字符串
times 4096 db 0         ; 重复填充

; ATCG数据（四进制原生）
atcg "ATCGATCG"         ; 4个ATCG字符 = 1字节
; A=00, T=01, C=10, G=11
; "ATCG" = 00 01 10 11 = 0x1B
; "ATCGATCG" = 0x1B, 0xE4
```

## 段声明

```dnasm
.code                   ; 代码段 (section .text)
.data                   ; 数据段
.bss                    ; BSS段
.rodata                 ; 只读数据段
.section .text.boot     ; 自定义段
```

## 宏

```dnasm
macro save_regs
    push rA
    push rT
    push rC
    push rG
endm

macro restore_regs
    pop rG
    pop rC
    pop rT
    pop rA
endm

; 使用
save_regs
; ... do stuff ...
restore_regs
```

## 包含文件

```dnasm
include "drivers/keyboard.dna"
include "mm/pmm.dna"
```

## 完整示例：内核入口

```dnasm
; kernel.dna - DNAOS Kernel Entry Point
.code
.global kernel_main

kernel_main:
    ; Set up stack
    mov rK, stack_top
    
    ; Initialize PIC
    call pic_init
    
    ; Initialize IDT
    call idt_init
    
    ; Initialize PIT (100Hz)
    call pit_init
    
    ; Initialize keyboard
    call keyboard_init
    
    ; Initialize framebuffer
    call fb_init
    
    ; Print banner
    mov rP, banner
    call console_print
    
    ; Main loop
.loop:
    hlt
    jmp .loop

banner:
    db "DNAOS v3.5 - Quaternary Operating System", 10, 0

section .bss
stack_bottom:
    resq 8192
stack_top:
```

## 编译

```bash
# 编译为NASM源码
python3 dasm/dasm.py kernel.dna -o kernel.nasm -n

# 编译为ELF目标文件
python3 dasm/dasm.py kernel.dna -o kernel.o

# 完整构建
make iso
```

## 编译流程

```
.dna源码 → dasm.py → .nasm中间代码 → nasm → .o目标文件 → ld → dnaos.bin
```
