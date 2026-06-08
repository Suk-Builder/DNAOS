; ============================================================================
; DNAOS - Boot Assembly (Complete)
; ============================================================================
; Multiboot2 entry → GDT → Long mode → kernel_main()
; + ISR/IRQ stubs for IDT
; + Context switch for scheduler
; + SYSCALL/SYSRET entry
; + TSS setup
; ============================================================================

section ".text.boot"

global _start
extern kernel_main

; ============================================================================
; Multiboot2 Header
; ============================================================================
section ".multiboot"
align 8
multiboot_header:
    dd 0xE85250D6              ; Magic
    dd 0                       ; Architecture: i386
    dd multiboot_header_end - multiboot_header
    dd -(0xE85250D6 + 0 + (multiboot_header_end - multiboot_header))  ; Checksum
    
    ; Framebuffer tag (type 5)
    dw 5                       ; Type = framebuffer
    dw 0                       ; Flags
    dd 20                      ; Size
    dd 1280                    ; Width
    dd 720                     ; Height
    dd 32                      ; Depth (bits per pixel)
    
    ; End tag
    dw 0                       ; Type
    dw 0                       ; Flags
    dd 8                       ; Size
multiboot_header_end:

; ============================================================================
; GDT (Global Descriptor Table)
; ============================================================================
section ".rodata"
align 16
gdt_start:
    ; Null descriptor
    dq 0
    
    ; Kernel code segment (0x08)
    dw 0xFFFF, 0x0000
    db 0x00, 0x9A, 0x20, 0x00
    
    ; Kernel data segment (0x10)
    dw 0xFFFF, 0x0000
    db 0x00, 0x92, 0x20, 0x00
    
    ; User code segment (0x18)
    dw 0xFFFF, 0x0000
    db 0x00, 0xFA, 0x20, 0x00
    
    ; User data segment (0x20)
    dw 0xFFFF, 0x0000
    db 0x00, 0xF2, 0x20, 0x00
    
    ; TSS segment (0x28) - filled at runtime
    dq 0, 0
gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dq gdt_start

; ============================================================================
; TSS (Task State Segment)
; ============================================================================
section ".bss"
align 4096
tss:
    resq 26                    ; 26 × 8 bytes = 208 bytes (64-bit TSS)

; ============================================================================
; IDT (Interrupt Descriptor Table)
; ============================================================================
section ".rodata"
align 16

; ISR stub table (addresses of ISR handlers)
isr_stub_table:
    %assign i 0
    %rep 32
        dq isr_stub_%+i
    %assign i i+1
    %endrep

; IRQ stub table
irq_stub_table:
    %assign i 0
    %rep 16
        dq irq_stub_%+i
    %assign i i+1
    %endrep

; ============================================================================
; Entry Point
; ============================================================================
section ".text.boot"
bits 32

_start:
    ; Disable interrupts
    cli
    
    ; Save multiboot info
    mov edi, ebx              ; Multiboot2 info pointer
    mov esi, eax              ; Multiboot2 magic
    
    ; Check multiboot2 magic
    cmp eax, 0x36D76289
    jne .hang
    
    ; Set up stack
    mov esp, stack_top_32
    
    ; Load GDT
    lgdt [gdt_descriptor_32]
    
    ; Switch to protected mode (should already be in PM from GRUB)
    
    ; Far jump to load new CS
    jmp 0x08:.pm_entry

.pm_entry:
    ; Load data segments
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    
    ; Set up page tables for long mode
    ; PML4 at 0x100000 (1MB)
    mov edi, 0x100000
    xor eax, eax
    mov ecx, 4096 / 4
    rep stosd                 ; Clear PML4
    
    ; PDPT at 0x101000
    mov edi, 0x101000
    xor eax, eax
    mov ecx, 4096 / 4
    rep stosd                 ; Clear PDPT
    
    ; PD at 0x102000
    mov edi, 0x102000
    xor eax, eax
    mov ecx, 4096 / 4
    rep stosd                 ; Clear PD
    
    ; Set up PML4[0] → PDPT
    mov dword [0x100000], 0x101003  ; Present + Writable
    
    ; Set up PDPT[0] → PD
    mov dword [0x101000], 0x102003  ; Present + Writable
    
    ; Set up PD entries (2MB pages, identity map first 4GB)
    mov edi, 0x102000
    mov eax, 0x83            ; Present + Writable + Page Size (2MB)
    mov ecx, 512             ; 512 × 2MB = 1GB
    
.map_pd:
    mov [edi], eax
    add eax, 0x200000        ; Next 2MB
    add edi, 8
    dec ecx
    jnz .map_pd
    
    ; Second PD for 1-2GB
    mov edi, 0x103000
    xor eax, eax
    mov ecx, 4096 / 4
    rep stosd
    
    mov edi, 0x103000
    mov eax, 0x40000083      ; Start at 1GB
    mov ecx, 512
    
.map_pd2:
    mov [edi], eax
    add eax, 0x200000
    add edi, 8
    dec ecx
    jnz .map_pd2
    
    ; Set up PDPT[1] → PD2
    mov dword [0x101008], 0x103003
    
    ; Enable PAE (CR4.PAE = bit 5)
    mov eax, cr4
    or eax, (1 << 5)
    mov cr4, eax
    
    ; Load PML4 into CR3
    mov eax, 0x100000
    mov cr3, eax
    
    ; Enable long mode (EFER.LME = bit 8)
    mov ecx, 0xC0000080      ; EFER MSR
    rdmsr
    or eax, (1 << 8)
    wrmsr
    
    ; Enable paging (CR0.PG = bit 31)
    mov eax, cr0
    or eax, (1 << 31)
    mov cr0, eax
    
    ; Far jump to 64-bit code
    jmp 0x08:lm_entry

.hang:
    hlt
    jmp .hang

; 32-bit GDT descriptor
gdt_descriptor_32:
    dw gdt_end - gdt_start - 1
    dd gdt_start

; 32-bit stack
section ".bss"
align 16
stack_bottom_32:
    resb 16384
stack_top_32:

; ============================================================================
; 64-bit Long Mode Entry
; ============================================================================
section ".text.boot"
bits 64

lm_entry:
    ; Load 64-bit data segments
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    
    ; Set up 64-bit stack
    mov rsp, stack_top
    
    ; Set up TSS
    lea rax, [rel tss]
    mov [gdt_start + 0x28], ax
    mov word [gdt_start + 0x28 + 2], 0
    mov byte [gdt_start + 0x28 + 4], 0x89  ; Present, 64-bit TSS
    mov byte [gdt_start + 0x28 + 5], 0
    mov word [gdt_start + 0x28 + 6], 0
    shr rax, 16
    mov [gdt_start + 0x28 + 2], ax
    shr rax, 8
    mov [gdt_start + 0x28 + 4], al
    shr rax, 8
    mov [gdt_start + 0x28 + 7], al
    
    ; TSS IST1 for double fault
    lea rax, [rel df_stack_top]
    mov [tss + 4], rax       ; IST1
    
    ; TSS RSP0 for kernel stack
    lea rax, [rel stack_top]
    mov [tss + 1], rax       ; RSP0
    
    ; Load task register
    mov ax, 0x28
    ltr ax
    
    ; Reload GDT (64-bit version)
    lgdt [rel gdt_descriptor]
    
    ; Call kernel main
    ; rdi = multiboot2 info pointer (saved from 32-bit)
    call kernel_main
    
    ; Should not return
.halt:
    cli
    hlt
    jmp .halt

; ============================================================================
; ISR Stubs (CPU Exceptions 0-31)
; ============================================================================
section ".text"
bits 64

; Macro for ISR without error code
%macro ISR_NOERR 1
isr_stub_%1:
    push 0                   ; Dummy error code
    push %1                  ; Interrupt number
    jmp isr_common
%endmacro

; Macro for ISR with error code
%macro ISR_ERR 1
isr_stub_%1:
    ; Error code already pushed by CPU
    push %1                  ; Interrupt number
    jmp isr_common
%endmacro

; CPU exception handlers
ISR_NOERR 0    ; Divide by zero
ISR_NOERR 1    ; Debug
ISR_NOERR 2    ; NMI
ISR_NOERR 3    ; Breakpoint
ISR_NOERR 4    ; Overflow
ISR_NOERR 5    ; Bound range
ISR_NOERR 6    ; Invalid opcode
ISR_NOERR 7    ; Device not available
ISR_ERR   8    ; Double fault (has error code)
ISR_NOERR 9    ; Coprocessor segment overrun
ISR_ERR   10   ; Invalid TSS
ISR_ERR   11   ; Segment not present
ISR_ERR   12   ; Stack segment fault
ISR_ERR   13   ; General protection fault
ISR_ERR   14   ; Page fault
ISR_NOERR 15   ; Reserved
ISR_NOERR 16   ; x87 FPU error
ISR_ERR   17   ; Alignment check
ISR_NOERR 18   ; Machine check
ISR_NOERR 19   ; SIMD floating point
ISR_NOERR 20   ; Virtualization
ISR_NOERR 21   ; Control protection
ISR_NOERR 22   ; Reserved
ISR_NOERR 23   ; Reserved
ISR_NOERR 24   ; Reserved
ISR_NOERR 25   ; Reserved
ISR_NOERR 26   ; Reserved
ISR_NOERR 27   ; Reserved
ISR_NOERR 28   ; Hypervisor injection
ISR_ERR   29   ; VMM communication
ISR_ERR   30   ; Security
ISR_NOERR 31   ; Reserved

; Common ISR handler
isr_common:
    ; Save all registers
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
    
    ; Save data segments
    mov ax, ds
    push ax
    
    ; Load kernel data segment
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    
    ; Call C handler
    ; rdi = interrupt number (from stack)
    ; rsi = error code
    mov rdi, [rsp + 15*8 + 8]   ; Int number
    mov rsi, [rsp + 15*8 + 16]  ; Error code
    
    ; If page fault, get CR2
    cmp rdi, 14
    jne .not_pf
    mov rdx, cr2
    jmp .call_handler
.not_pf:
    xor rdx, rdx
    
.call_handler:
    extern isr_handler
    call isr_handler
    
    ; Restore data segments
    pop ax
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    
    ; Restore registers
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    
    ; Remove error code and interrupt number
    add rsp, 16
    
    iretq

; ============================================================================
; IRQ Stubs (32-47)
; ============================================================================
section ".text"
bits 64

%macro IRQ_STUB 1
irq_stub_%1:
    push 0
    push %1 + 32
    jmp irq_common
%endmacro

IRQ_STUB 0     ; IRQ0  - PIT Timer
IRQ_STUB 1     ; IRQ1  - Keyboard
IRQ_STUB 2     ; IRQ2  - Cascade
IRQ_STUB 3     ; IRQ3  - COM2
IRQ_STUB 4     ; IRQ4  - COM1
IRQ_STUB 5     ; IRQ5  - LPT2
IRQ_STUB 6     ; IRQ6  - Floppy
IRQ_STUB 7     ; IRQ7  - LPT1
IRQ_STUB 8     ; IRQ8  - RTC
IRQ_STUB 9     ; IRQ9  - Free
IRQ_STUB 10    ; IRQ10 - Free
IRQ_STUB 11    ; IRQ11 - Free
IRQ_STUB 12    ; IRQ12 - Mouse
IRQ_STUB 13    ; IRQ13 - FPU
IRQ_STUB 14    ; IRQ14 - Primary ATA
IRQ_STUB 15    ; IRQ15 - Secondary ATA

; Common IRQ handler
irq_common:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
    
    mov ax, ds
    push ax
    
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    
    ; Call IRQ handler
    mov rdi, [rsp + 15*8 + 8]   ; IRQ number
    extern irq_handler
    call irq_handler
    
    ; Send EOI to PIC
    mov al, 0x20
    out 0x20, al
    cmp rdi, 40                  ; If IRQ >= 8, also EOI slave
    jl .no_slave_eoi
    out 0xA0, al
.no_slave_eoi:
    
    pop ax
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    
    add rsp, 16
    iretq

; ============================================================================
; Context Switch (Scheduler)
; ============================================================================
section ".text"
bits 64

global context_switch
; rdi = old process stack pointer (pointer to save)
; rsi = new process stack pointer (value to load)

context_switch:
    ; Save old process registers
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    
    ; Save old RSP
    mov [rdi], rsp
    
    ; Load new RSP
    mov rsp, rsi
    
    ; Restore new process registers
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    
    ret

; ============================================================================
; SYSCALL/SYSRET Entry
; ============================================================================
section ".text"
bits 64

global syscall_entry
syscall_entry:
    ; Swap GS to kernel GS base
    swapgs
    
    ; Save user RSP
    mov gs:0, rsp
    mov rsp, gs:8              ; Kernel stack
    
    ; Save user registers
    push rcx                   ; Return RIP
    push r11                   ; Saved RFLAGS
    push rax                   ; Syscall number
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    
    ; Call syscall handler
    ; rdi = syscall number (already in rdi from user)
    ; rsi, rdx, r10, r8, r9 = arguments
    mov rcx, r10               ; r10 → rcx for C calling convention
    extern syscall_handler
    call syscall_handler
    
    ; Restore registers
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    pop rax                    ; Return value
    pop r11                    ; RFLAGS
    pop rcx                    ; Return RIP
    
    ; Restore user RSP
    mov rsp, gs:0
    swapgs
    
    sysretq

; ============================================================================
; I/O Port Helpers (called from DNAsm code)
; ============================================================================
section ".text"
bits 64

global outb_func
global inb_func
global outw_func
global inw_func
global outl_func
global inl_func
global io_wait_func

outb_func:
    mov dx, di
    mov al, sil
    out dx, al
    ret

inb_func:
    mov dx, di
    in al, dx
    ret

outw_func:
    mov dx, di
    mov ax, si
    out dx, ax
    ret

inw_func:
    mov dx, di
    in ax, dx
    ret

outl_func:
    mov dx, di
    mov eax, esi
    out dx, eax
    ret

inl_func:
    mov dx, di
    in eax, dx
    ret

io_wait_func:
    mov dx, 0x80
    mov al, 0
    out dx, al
    ret

; ============================================================================
; CR register access
; ============================================================================
section ".text"
bits 64

global read_cr2
global read_cr3
global write_cr3
global invlpg_func

read_cr2:
    mov rax, cr2
    ret

read_cr3:
    mov rax, cr3
    ret

write_cr3:
    mov cr3, rdi
    ret

invlpg_func:
    invlpg [rdi]
    ret

; ============================================================================
; BSS
; ============================================================================
section ".bss"
align 4096

; Page tables (already set up, but reserve space)
; pml4: resq 512
; pdpt: resq 512
; pd:   resq 512

; Kernel stack
align 16
stack_bottom:
    resb 65536
stack_top:

; Double fault stack (IST1)
align 16
df_stack_bottom:
    resb 8192
df_stack_top:

; IDT storage
align 16
idt:
    resq 256 * 2              ; 256 entries × 16 bytes

idt_descriptor:
    resw 1                    ; Limit
    resq 1                    ; Base
