# ============================================================================
# DNAOS Boot Assembly - GAS/AT&T Syntax
# ============================================================================
# Multiboot → 32-bit → long mode → kernel_main
# + GDT with TSS slot (filled at runtime by C)
# + ISR/IRQ stubs for IDT
# ============================================================================

.section .multiboot, "a", @progbits
.align 8

# Multiboot1 header (QEMU -kernel)
mb1_header:
    .long 0x1BADB002
    .long 0x00000003
    .long -(0x1BADB002 + 0x00000003) & 0xFFFFFFFF

# Multiboot2 header (GRUB)
multiboot_header:
    .long 0xE85250D6
    .long 0
    .long multiboot_header_end - multiboot_header
    .long -(0xE85250D6 + 0 + (multiboot_header_end - multiboot_header)) & 0xFFFFFFFF
    .word 5
    .word 0
    .long 20
    .long 1280
    .long 720
    .long 32
    .word 0
    .word 0
    .long 8
multiboot_header_end:

# ============================================================================
# 32-bit Entry Point
# ============================================================================
.section .text.boot, "ax", @progbits
.code32

.globl _start
.extern kernel_main

_start:
    cli

    # Save multiboot info
    movl %ebx, %edi
    movl %eax, %esi

    # Set up 32-bit stack
    movl $stack_top_32, %esp

    # Verify CPU supports long mode
    call check_multiboot
    call check_cpuid
    call check_long_mode

    # Set up page tables and enable paging
    call set_up_page_tables
    call enable_paging

    # Load 64-bit GDT and far jump to 64-bit code segment
    lgdt gdt64_pointer
    ljmp $0x08, $lm_entry

.hang32:
    hlt
    jmp .hang32

# --- Check multiboot magic ---
check_multiboot:
    cmpl $0x36D76289, %eax
    je .mb_ok
    cmpl $0x2BADB002, %eax
    je .mb_ok
    jmp .no_multiboot
.mb_ok:
    ret
.no_multiboot:
    movb $'0', %al
    jmp error

# --- Check CPUID support ---
check_cpuid:
    pushfl
    popl %eax
    movl %eax, %ecx
    xorl $(1 << 21), %eax
    pushl %eax
    popfl
    pushfl
    popl %eax
    pushl %ecx
    popfl
    cmpl %ecx, %eax
    je .no_cpuid
    ret
.no_cpuid:
    movb $'1', %al
    jmp error

# --- Check long mode support ---
check_long_mode:
    movl $0x80000000, %eax
    cpuid
    cmpl $0x80000001, %eax
    jb .no_long_mode
    movl $0x80000001, %eax
    cpuid
    testl $(1 << 29), %edx
    jz .no_long_mode
    ret
.no_long_mode:
    movb $'2', %al
    jmp error

# --- Set up page tables (identity map first 1GB) ---
set_up_page_tables:
    movl $p3_table, %eax
    orl $0x03, %eax
    movl %eax, p4_table

    movl $p2_table, %eax
    orl $0x03, %eax
    movl %eax, p3_table

    movl $0, %ecx
.map_p2:
    movl $0x200000, %eax
    mull %ecx
    orl $0x83, %eax
    movl %eax, p2_table(,%ecx,8)
    incl %ecx
    cmpl $512, %ecx
    jne .map_p2
    ret

# --- Enable paging and long mode ---
enable_paging:
    movl $p4_table, %eax
    movl %eax, %cr3

    movl %cr4, %eax
    orl $(1 << 5), %eax
    movl %eax, %cr4

    movl $0xC0000080, %ecx
    rdmsr
    orl $(1 << 8), %eax
    wrmsr

    movl %cr0, %eax
    orl $(1 << 31), %eax
    movl %eax, %cr0

    ret

# --- Error handler ---
error:
    movl $0x4F524F45, 0xB8000
    movl $0x4F3A4F52, 0xB8004
    movl $0x4F204F20, 0xB8008
    movb %al, 0xB800A
    hlt

# ============================================================================
# 64-bit Long Mode Entry
# ============================================================================
.section .text.boot, "ax", @progbits
.code64

lm_entry:
    # Load data segment registers
    xorl %eax, %eax
    movl %eax, %ds
    movl %eax, %es
    movl %eax, %fs
    movl %eax, %gs
    movl %eax, %ss

    # Set up 64-bit stack
    movl $stack_top, %esp
    movl %esp, %esp

    # Reload GDT with 64-bit base address
    lgdt gdt64_pointer(%rip)

    # Call kernel_main(magic, info) — args in rdi, rsi
    # We saved magic in esi, info in edi at _start
    # But we need them in rdi, rsi for System V ABI
    # They were saved in esi/edi before the mode switch
    # We need to pass them through the mode switch
    # Use scratch variables in .bss
    movl %esi, saved_magic(%rip)
    movl %edi, saved_info(%rip)

    # Now set up args for kernel_main
    movl saved_magic(%rip), %edi
    movl saved_info(%rip), %esi

    # Call kernel_main
    call kernel_main

.halt:
    cli
    hlt
    jmp .halt

# ============================================================================
# ISR stubs — push vector number, jump to common handler
# ============================================================================
.macro isr_stub errcode=0
    .if \errcode
        # CPU already pushed error code, just push dummy
        pushq $0
    .else
        pushq $0
    .endif
.endm

# Macro: generate ISR stub that pushes vector number
.macro MAKE_ISR vec errcode=0
isr_stub_\vec:
    .if \errcode
        # CPU pushed error code already, push vector as dummy
        # We'll rearrange in the common handler
    .else
        pushq $0           # dummy error code for uniform stack frame
    .endif
    pushq $\vec
    jmp isr_common
.endm

# CPU exception stubs (0-31)
MAKE_ISR 0
MAKE_ISR 1
MAKE_ISR 2
MAKE_ISR 3
MAKE_ISR 4
MAKE_ISR 5
MAKE_ISR 6
MAKE_ISR 7
MAKE_ISR 8,  1    # Double fault — CPU pushes error code
MAKE_ISR 9
MAKE_ISR 10, 1    # Invalid TSS
MAKE_ISR 11, 1    # Segment not present
MAKE_ISR 12, 1    # Stack segment fault
MAKE_ISR 13, 1    # General protection fault
MAKE_ISR 14, 1    # Page fault
MAKE_ISR 15
MAKE_ISR 16
MAKE_ISR 17, 1    # Alignment check
MAKE_ISR 18
MAKE_ISR 19
MAKE_ISR 20
MAKE_ISR 21
MAKE_ISR 22
MAKE_ISR 23
MAKE_ISR 24
MAKE_ISR 25
MAKE_ISR 26
MAKE_ISR 27
MAKE_ISR 28
MAKE_ISR 29
MAKE_ISR 30, 1
MAKE_ISR 31

# IRQ stubs (32-47)
MAKE_ISR 32
MAKE_ISR 33
MAKE_ISR 34
MAKE_ISR 35
MAKE_ISR 36
MAKE_ISR 37
MAKE_ISR 38
MAKE_ISR 39
MAKE_ISR 40
MAKE_ISR 41
MAKE_ISR 42
MAKE_ISR 43
MAKE_ISR 44
MAKE_ISR 45
MAKE_ISR 46
MAKE_ISR 47

# Common ISR handler — calls C function isr_handler(vec, errcode, rip, cs, rflags, rsp)
isr_common:
    # Save all general-purpose registers
    pushq %rax
    pushq %rbx
    pushq %rcx
    pushq %rdx
    pushq %rsi
    pushq %rdi
    pushq %rbp
    pushq %r8
    pushq %r9
    pushq %r10
    pushq %r11
    pushq %r12
    pushq %r13
    pushq %r14
    pushq %r15

    # Save data segment
    movw %ds, %ax
    pushq %rax

    # Load kernel data segment
    movw $0x10, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %fs
    movw %ax, %gs
    movw %ax, %ss

    # Pass pointer to saved state as argument
    movq %rsp, %rdi
    call isr_handler_c

    # Restore data segment
    popq %rax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %fs
    movw %ax, %gs
    movw %ax, %ss

    # Restore general-purpose registers
    popq %r15
    popq %r14
    popq %r13
    popq %r12
    popq %r11
    popq %r10
    popq %r9
    popq %r8
    popq %rbp
    popq %rdi
    popq %rsi
    popq %rdx
    popq %rcx
    popq %rbx
    popq %rax

    # Remove vector number and error code
    addq $16, %rsp

    iretq

# ISR stub address table — used by C code to fill IDT
.section .data, "aw", @progbits
.align 8
.globl isr_stub_table
isr_stub_table:
    .quad isr_stub_0,  isr_stub_1,  isr_stub_2,  isr_stub_3
    .quad isr_stub_4,  isr_stub_5,  isr_stub_6,  isr_stub_7
    .quad isr_stub_8,  isr_stub_9,  isr_stub_10, isr_stub_11
    .quad isr_stub_12, isr_stub_13, isr_stub_14, isr_stub_15
    .quad isr_stub_16, isr_stub_17, isr_stub_18, isr_stub_19
    .quad isr_stub_20, isr_stub_21, isr_stub_22, isr_stub_23
    .quad isr_stub_24, isr_stub_25, isr_stub_26, isr_stub_27
    .quad isr_stub_28, isr_stub_29, isr_stub_30, isr_stub_31
    .quad isr_stub_32, isr_stub_33, isr_stub_34, isr_stub_35
    .quad isr_stub_36, isr_stub_37, isr_stub_38, isr_stub_39
    .quad isr_stub_40, isr_stub_41, isr_stub_42, isr_stub_43
    .quad isr_stub_44, isr_stub_45, isr_stub_46, isr_stub_47

# ============================================================================
# GDT (in .data for writability — TSS descriptor filled at runtime)
# ============================================================================
.section .data, "aw", @progbits
.align 16

.globl gdt64
gdt64:
    .quad 0                                  # 0x00: null
    .word 0; .word 0; .byte 0                # 0x08: 64-bit code
    .byte 0x9A
    .byte 0xA0                               # L=1, D=0
    .byte 0
    .word 0; .word 0; .byte 0                # 0x10: data
    .byte 0x92
    .byte 0x00
    .byte 0
    # 0x18: TSS descriptor (16 bytes for 64-bit TSS)
    .long 0x00000068                          # limit=0x68 (104 bytes), base low=0
    .byte 0                                   # base mid=0
    .byte 0x89                                # P=1, DPL=0, TSS64 available
    .byte 0x00                                # granularity=0, base high=0
    .byte 0                                   # base upper bits 24-31
    .long 0                                   # base upper bits 32-63
    .long 0                                   # reserved (must be zero)
gdt64_end:

gdt64_pointer:
    .word gdt64_end - gdt64 - 1
    .long gdt64                              # base (low 32 bits)
    .long 0                                  # base (high 32 bits)

# ============================================================================
# BSS
# ============================================================================
.section .bss, "aw", @nobits
.align 4096

p4_table:
    .skip 4096
p3_table:
    .skip 4096
p2_table:
    .skip 4096

.align 16
.globl stack_bottom_32
stack_bottom_32:
    .skip 16384
stack_top_32:

.align 16
.globl stack_bottom
stack_bottom:
    .skip 65536
.globl stack_top
stack_top:

# Double fault stack (IST1)
.align 16
df_stack_bottom:
    .skip 8192
.globl df_stack_top
df_stack_top:

# Saved multiboot info (passed through mode switch)
.align 8
saved_magic:
    .skip 4
saved_info:
    .skip 4

# TSS (Task State Segment) — 64-bit TSS
.align 4096
.globl tss
tss:
    .skip 208                                # 26 × 8 bytes

# IDT (48 entries × 16 bytes)
.align 16
.globl idt
idt:
    .skip 48 * 16

# IDT descriptor
.align 16
.globl idt_descriptor
idt_descriptor:
    .skip 2                                  # limit
    .skip 8                                  # base
