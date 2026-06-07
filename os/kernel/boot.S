/*
 * ============================================================================
 * DNAOS Kernel - Boot Assembly (Extended)
 * ============================================================================
 * 
 * Multiboot2 entry → GDT → Long mode → kernel_main()
 * + ISR/IRQ stubs for IDT
 * + Context switch for scheduler
 * + Syscall entry
 * ============================================================================
 */

.section ".text.boot"

.global _start

/* ============================================================================
 * Multiboot2 Header
 * ============================================================================
 */
.section ".multiboot"
.align 8
multiboot_header:
    .long   0xE85250D6              /* Magic */
    .long   0                       /* Architecture: i386 */
    .long   multiboot_header_end - multiboot_header
    .long   -(0xE85250D6 + 0 + (multiboot_header_end - multiboot_header))  /* Checksum */
    
    /* Framebuffer tag */
    .word   5                       /* Type: framebuffer */
    .word   0                       /* Flags */
    .long   20                      /* Size */
    .long   1280                    /* Width */
    .long   720                     /* Height */
    .long   32                      /* Depth */
    
    /* End tag */
    .word   0                       /* Type */
    .word   0                       /* Flags */
    .long   8                       /* Size */
multiboot_header_end:

/* ============================================================================
 * Entry Point
 * ============================================================================
 */
.section ".text"
.code32

_start:
    /* Save multiboot info */
    movl    %eax, %esi              /* Magic */
    movl    %ebx, %edi              /* MBI pointer */
    
    /* Disable interrupts */
    cli
    
    /* Set up stack */
    movl    $stack_top, %esp
    
    /* Check for multiboot2 */
    cmpl    $0x36D76289, %esi
    jne     .halt
    
    /* ========================================================================
     * Set up page tables (identity map first 4GB using 2MB pages)
     * ========================================================================
     */
    /* Clear PML4 */
    movl    $pml4, %eax
    movl    $0, %ecx
    movl    $1024, %edx
.clear_pml4:
    movl    %ecx, (%eax)
    addl    $4, %eax
    decl    %edx
    jnz     .clear_pml4
    
    /* Clear PDPT */
    movl    $pdpt, %eax
    movl    $0, %ecx
    movl    $1024, %edx
.clear_pdpt:
    movl    %ecx, (%eax)
    addl    $4, %eax
    decl    %edx
    jnz     .clear_pdpt
    
    /* PML4[0] → PDPT */
    movl    $pdpt, %eax
    orl     $0x03, %eax             /* Present + Writable */
    movl    %eax, pml4
    
    /* PDPT[0] → PD0 (0-1GB) */
    movl    $pd0, %eax
    orl     $0x03, %eax
    movl    %eax, pdpt
    
    /* PDPT[1] → PD1 (1-2GB) */
    movl    $pd1, %eax
    orl     $0x03, %eax
    movl    %eax, pdpt + 8
    
    /* PDPT[2] → PD2 (2-3GB) */
    movl    $pd2, %eax
    orl     $0x03, %eax
    movl    %eax, pdpt + 16
    
    /* PDPT[3] → PD3 (3-4GB) */
    movl    $pd3, %eax
    orl     $0x03, %eax
    movl    %eax, pdpt + 24
    
    /* Fill PD0-PD3 with 2MB pages */
    /* Each PD has 512 entries, each mapping 2MB = 1GB total */
    movl    $0x83, %eax             /* Present + Writable + Page Size (2MB) */
    movl    $pd0, %ebx
    movl    $2048, %ecx             /* 512 * 4 PDs */
.fill_pd:
    movl    %eax, (%ebx)
    addl    $0x00200000, %eax       /* Next 2MB */
    addl    $8, %ebx
    decl    %ecx
    jnz     .fill_pd
    
    /* Enable PAE */
    movl    %cr4, %eax
    orl     $0x20, %eax             /* PAE bit */
    movl    %eax, %cr4
    
    /* Load PML4 into CR3 */
    movl    $pml4, %eax
    movl    %eax, %cr3
    
    /* Enable long mode (set EFER.LME) */
    movl    $0xC0000080, %ecx       /* EFER MSR */
    rdmsr
    orl     $0x100, %eax            /* LME bit */
    wrmsr
    
    /* Enable paging */
    movl    %cr0, %eax
    orl     $0x80000000, %eax       /* PG bit */
    movl    %eax, %cr0
    
    /* Load 64-bit GDT */
    lgdt    gdt64_pointer
    
    /* Far jump to 64-bit code */
    ljmpl   $0x08, $long_mode_entry

.halt:
    hlt
    jmp     .halt

/* ============================================================================
 * 64-bit Entry
 * ============================================================================
 */
.code64
long_mode_entry:
    /* Set up segment registers */
    movl    $0x10, %eax
    movl    %eax, %ds
    movl    %eax, %es
    movl    %eax, %fs
    movl    %eax, %gs
    movl    %eax, %ss
    
    /* Set up 64-bit stack */
    movq    $stack_top, %rsp
    
    /* Call kernel_main(magic, mbi) */
    movl    %esi, %edi              /* First arg: magic */
    movl    %r8d, %esi              /* Second arg: mbi (saved earlier) */
    /* Actually, we need to pass the saved values properly */
    /* rdi = magic, rsi = mbi */
    
    call    kernel_main
    
    /* Should never return */
    cli
.halt64:
    hlt
    jmp     .halt64

/* ============================================================================
 * GDT (64-bit)
 * ============================================================================
 */
.align 16
gdt64:
    .quad   0                       /* Null */
    .quad   0x00209A0000000000      /* Code: 64-bit, exec, read */
    .quad   0x0000920000000000      /* Data: 64-bit, write */
    .quad   0x0020FA0000000000      /* User code: 64-bit, DPL=3 */
    .quad   0x0000F20000000000      /* User data: 64-bit, DPL=3 */
gdt64_end:

gdt64_pointer:
    .word   gdt64_end - gdt64 - 1
    .quad   gdt64

/* ============================================================================
 * ISR/IRQ Stubs
 * ============================================================================
 */
.macro ISR_NOERR n
isr\n:
    pushq   $0                      /* Dummy error code */
    pushq   $\n                     /* Interrupt number */
    jmp     isr_common
.endm

.macro ISR_ERR n
isr\n:
    pushq   $\n                     /* Error code already pushed */
    jmp     isr_common
.endm

.macro IRQ n, irq_num
irq\n:
    pushq   $0
    pushq   $\irq_num
    jmp     irq_common
.endm

isr_common:
    /* Save all registers */
    pushq   %rax
    pushq   %rbx
    pushq   %rcx
    pushq   %rdx
    pushq   %rsi
    pushq   %rdi
    pushq   %rbp
    pushq   %r8
    pushq   %r9
    pushq   %r10
    pushq   %r11
    pushq   %r12
    pushq   %r13
    pushq   %r14
    pushq   %r15
    
    /* Call C handler */
    movq    120(%rsp), %rdi         /* Interrupt number */
    call    isr_handler
    
    /* Restore registers */
    popq    %r15
    popq    %r14
    popq    %r13
    popq    %r12
    popq    %r11
    popq    %r10
    popq    %r9
    popq    %r8
    popq    %rbp
    popq    %rdi
    popq    %rsi
    popq    %rdx
    popq    %rcx
    popq    %rbx
    popq    %rax
    
    addq    $16, %rsp               /* Remove error code + int number */
    iretq

irq_common:
    pushq   %rax
    pushq   %rbx
    pushq   %rcx
    pushq   %rdx
    pushq   %rsi
    pushq   %rdi
    pushq   %rbp
    pushq   %r8
    pushq   %r9
    pushq   %r10
    pushq   %r11
    pushq   %r12
    pushq   %r13
    pushq   %r14
    pushq   %r15
    
    movq    120(%rsp), %rdi
    call    irq_handler
    
    popq    %r15
    popq    %r14
    popq    %r13
    popq    %r12
    popq    %r11
    popq    %r10
    popq    %r9
    popq    %r8
    popq    %rbp
    popq    %rdi
    popq    %rsi
    popq    %rdx
    popq    %rcx
    popq    %rbx
    popq    %rax
    
    addq    $16, %rsp
    iretq

/* CPU Exception ISRs */
ISR_NOERR 0     /* Divide by zero */
ISR_NOERR 1     /* Debug */
ISR_NOERR 2     /* NMI */
ISR_NOERR 3     /* Breakpoint */
ISR_NOERR 4     /* Overflow */
ISR_NOERR 5     /* Bound range */
ISR_NOERR 6     /* Invalid opcode */
ISR_NOERR 7     /* Device not available */
ISR_ERR   8     /* Double fault */
ISR_NOERR 9     /* Coprocessor */
ISR_ERR   10    /* Invalid TSS */
ISR_ERR   11    /* Segment not present */
ISR_ERR   12    /* Stack segment fault */
ISR_ERR   13    /* General protection fault */
ISR_ERR   14    /* Page fault */

/* Hardware IRQs (remapped to 32-47) */
IRQ 0,  32      /* PIT Timer */
IRQ 1,  33      /* Keyboard */
IRQ 2,  34      /* Cascade */
IRQ 3,  35
IRQ 4,  36
IRQ 5,  37
IRQ 6,  38
IRQ 7,  39
IRQ 8,  40      /* RTC */
IRQ 9,  41
IRQ 10, 42
IRQ 11, 43
IRQ 12, 44      /* Mouse */
IRQ 13, 45
IRQ 14, 46      /* Primary ATA */
IRQ 15, 47      /* Secondary ATA */

/* ============================================================================
 * Context Switch (for scheduler)
 * ============================================================================
 */
.global context_switch
context_switch:
    /* Save old context */
    pushq   %r15
    pushq   %r14
    pushq   %r13
    pushq   %r12
    pushq   %r11
    pushq   %r10
    pushq   %r9
    pushq   %r8
    pushq   %rdi
    pushq   %rsi
    pushq   %rbp
    pushq   %rdx
    pushq   %rcx
    pushq   %rbx
    pushq   %rax
    
    /* Save old RSP to old_ctx */
    movq    %rdi, %rax
    movq    %rsp, (%rax)
    
    /* Load new CR3 (page tables) */
    movq    %rdx, %cr3
    
    /* Load new RSP from new_ctx */
    movq    %rsi, %rsp
    
    /* Restore new context */
    popq    %rax
    popq    %rbx
    popq    %rcx
    popq    %rdx
    popq    %rbp
    popq    %rsi
    popq    %rdi
    popq    %r8
    popq    %r9
    popq    %r10
    popq    %r11
    popq    %r12
    popq    %r13
    popq    %r14
    popq    %r15
    
    iretq

/* ============================================================================
 * Syscall Entry (SYSCALL instruction)
 * ============================================================================
 */
.global syscall_entry
syscall_entry:
    /* Swap GS (kernel GS base) */
    swapgs
    
    /* Save user RSP */
    movq    %rsp, %gs:0            /* Save to per-CPU area */
    movq    %gs:8, %rsp            /* Load kernel stack */
    
    /* Save user registers */
    pushq   %rcx                    /* Return RIP */
    pushq   %r11                    /* RFLAGS */
    pushq   %rbx
    pushq   %rbp
    pushq   %r12
    pushq   %r13
    pushq   %r14
    pushq   %r15
    
    /* Call syscall handler */
    movq    %rax, %rdi              /* Syscall number */
    movq    %rdi, %rsi              /* arg1 */
    movq    %rsi, %rdx              /* arg2 */
    movq    %rdx, %rcx              /* arg3 */
    movq    %r10, %r8               /* arg4 */
    movq    %r8,  %r9               /* arg5 */
    call    syscall_handler
    
    /* Restore registers */
    popq    %r15
    popq    %r14
    popq    %r13
    popq    %r12
    popq    %rbp
    popq    %rbx
    popq    %r11
    popq    %rcx
    
    /* Restore user RSP */
    movq    %rsp, %gs:8
    movq    %gs:0, %rsp
    
    swapgs
    sysretq

/* ============================================================================
 * Data
 * ============================================================================
 */
.section ".bss"
.align 4096

pml4:   .skip 4096
pdpt:   .skip 4096
pd0:    .skip 4096
pd1:    .skip 4096
pd2:    .skip 4096
pd3:    .skip 4096

.align 16
stack_bottom:
    .skip   65536
stack_top:
