; ============================================================================
; DNAOS Boot Assembly (Rewritten)
; ============================================================================
; Reference: Phil Opp blog_os (first_edition_post_3)
;            OSDev wiki - Setting Up Long Mode, Creating a 64-bit kernel
;
; Structural fixes applied:
;   1. GDT in .data (writable) — can fill TSS descriptor at runtime
;   2. Correct order: lgdt → far jump → set segments → fill TSS → ltr → lidt
;   3. TSS descriptor written to correct GDT address (using rel + known offset)
;   4. Minimal IDT initialized with exception handlers + double fault IST1
;   5. Page tables in .bss (no overlap with kernel at 0x100000)
;   6. TSS offsets fixed: RSP0 at +0x04, IST1 at +0x24
;   7. ISR common: push rax instead of push ax for 64-bit stack alignment
; ============================================================================

; ============================================================================
; Multiboot Headers (must be in first 8KB of OS image)
; ============================================================================
section .multiboot

; Multiboot1 header (for QEMU -kernel direct boot)
align 4
mb1_header:
    dd 0x1BADB002                                        ; magic
    dd 0x00000003                                        ; flags: align + meminfo
    dd -(0x1BADB002 + 0x00000003) & 0xFFFFFFFF          ; checksum

; Multiboot2 header (for GRUB)
align 8
multiboot_header:
    dd 0xE85250D6                                        ; magic
    dd 0                                                 ; architecture: 0 = i386
    dd multiboot_header_end - multiboot_header           ; header length
    dd -(0xE85250D6 + 0 + (multiboot_header_end - multiboot_header)) & 0xFFFFFFFF
    ; Framebuffer tag (type 5)
    dw 5                                                 ; type = framebuffer
    dw 0                                                 ; flags
    dd 20                                                ; size
    dd 1280                                              ; width
    dd 720                                               ; height
    dd 32                                                ; depth
    ; End tag
    dw 0
    dw 0
    dd 8
multiboot_header_end:

; ============================================================================
; 32-bit Entry Point
; ============================================================================
; GRUB loads us in 32-bit protected mode with flat segments.
; We stay in GRUB's code segment until paging is enabled, then far-jump
; to our 64-bit code segment. (Reference: Phil Opp blog_os)
; ============================================================================
section .text.boot
bits 32

global _start
extern kernel_main

_start:
    cli

    ; Save multiboot info
    ; eax = multiboot magic, ebx = multiboot info pointer
    mov edi, ebx                           ; preserve across function calls
    mov esi, eax

    ; Set up 32-bit stack
    mov esp, stack_top_32

    ; Verify CPU supports long mode
    call check_multiboot
    call check_cpuid
    call check_long_mode

    ; Set up page tables and enable paging
    call set_up_page_tables
    call enable_paging

    ; Load 64-bit GDT and far jump to 64-bit code segment
    ; After paging is enabled, we're in compatibility mode.
    ; Far jump to a 64-bit code segment transitions to full long mode.
    lgdt [gdt64.pointer]
    jmp gdt64.code:lm_entry

.hang:
    hlt
    jmp .hang

; --- Check multiboot magic ---
check_multiboot:
    cmp eax, 0x36D76289
    jne .no_multiboot
    ret
.no_multiboot:
    mov al, "0"
    jmp error

; --- Check CPUID support ---
check_cpuid:
    pushfd
    pop eax
    mov ecx, eax
    xor eax, 1 << 21
    push eax
    popfd
    pushfd
    pop eax
    push ecx
    popfd
    cmp eax, ecx
    je .no_cpuid
    ret
.no_cpuid:
    mov al, "1"
    jmp error

; --- Check long mode support ---
check_long_mode:
    mov eax, 0x80000000
    cpuid
    cmp eax, 0x80000001
    jb .no_long_mode
    mov eax, 0x80000001
    cpuid
    test edx, 1 << 29                     ; LM bit
    jz .no_long_mode
    ret
.no_long_mode:
    mov al, "2"
    jmp error

; --- Set up page tables (identity map first 1GB) ---
; Reference: Phil Opp blog_os
; Page tables are in .bss, zeroed by GRUB (Multiboot spec requires .bss = 0)
set_up_page_tables:
    ; P4[0] → P3
    mov eax, p3_table
    or eax, 0x03                          ; present + writable
    mov [p4_table], eax

    ; P3[0] → P2
    mov eax, p2_table
    or eax, 0x03                          ; present + writable
    mov [p3_table], eax

    ; P2 entries: 512 × 2MB huge pages = 1GB identity mapping
    mov ecx, 0
.map_p2:
    mov eax, 0x200000                     ; 2MB per page
    mul ecx                               ; start address = 2MB * ecx
    or eax, 0x83                          ; present + writable + huge (2MB page)
    mov [p2_table + ecx * 8], eax
    inc ecx
    cmp ecx, 512
    jne .map_p2
    ret

; --- Enable paging and long mode ---
; Reference: Phil Opp blog_os
enable_paging:
    ; Load P4 (PML4) into CR3
    mov eax, p4_table
    mov cr3, eax

    ; Enable PAE (CR4 bit 5)
    mov eax, cr4
    or eax, 1 << 5
    mov cr4, eax

    ; Enable long mode (EFER.LME bit 8)
    mov ecx, 0xC0000080                   ; EFER MSR
    rdmsr
    or eax, 1 << 8
    wrmsr

    ; Enable paging (CR0.PG bit 31)
    mov eax, cr0
    or eax, 1 << 31
    mov cr0, eax

    ret

; --- Error handler (prints ERR: code to VGA text buffer) ---
error:
    mov dword [0xB8000], 0x4F524F45       ; "ER"
    mov dword [0xB8004], 0x4F3A4F52       ; "R:"
    mov dword [0xB8008], 0x4F204F20       ; "  "
    mov byte  [0xB800A], al
    hlt

; ============================================================================
; 64-bit Long Mode Entry
; ============================================================================
section .text.boot
bits 64

lm_entry:
    ; Load data segment registers
    ; In 64-bit long mode at CPL=0, null selector (0) is valid for DS/ES/FS/GS/SS
    mov ax, 0
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    ; Set up 64-bit stack
    mov rsp, stack_top

    ; Reload GDT with 64-bit base address
    lgdt [rel gdt64.pointer]

    ; --- Fill TSS descriptor in GDT ---
    ; TSS descriptor is at offset 0x28 in GDT (in .data, writable)
    ; 64-bit TSS descriptor layout (16 bytes):
    ;   +0:  limit low (2 bytes)
    ;   +2:  base bits 0-15 (2 bytes)
    ;   +4:  base bits 16-23 (1 byte)
    ;   +5:  access byte (1 byte) = 0x89 (present, 64-bit TSS)
    ;   +6:  flags + limit high (1 byte)
    ;   +7:  base bits 24-31 (1 byte)
    ;   +8:  base bits 32-63 (4 bytes)
    ;   +12: reserved (4 bytes)
    lea rax, [rel tss]
    mov word  [rel gdt64 + 0x28 + 2], ax          ; base bits 0-15
    shr rax, 16
    mov byte  [rel gdt64 + 0x28 + 4], al          ; base bits 16-23
    shr rax, 8
    mov byte  [rel gdt64 + 0x28 + 7], al          ; base bits 24-31
    shr rax, 8
    mov dword [rel gdt64 + 0x28 + 8], eax         ; base bits 32-63

    ; --- Set up TSS ---
    ; 64-bit TSS layout:
    ;   +0x00: Reserved (4 bytes)
    ;   +0x04: RSP0 (8 bytes) — kernel stack for ring 3 → 0
    ;   +0x0C: RSP1 (8 bytes)
    ;   +0x14: RSP2 (8 bytes)
    ;   +0x1C: Reserved (8 bytes)
    ;   +0x24: IST1 (8 bytes) — for double fault handler
    ;   +0x2C: IST2-IST7...
    lea rax, [rel stack_top]
    mov [rel tss + 0x04], rax              ; RSP0

    lea rax, [rel df_stack_top]
    mov [rel tss + 0x24], rax              ; IST1 (double fault)

    ; Load task register (AFTER GDT loaded and TSS descriptor filled)
    mov ax, 0x28
    ltr ax

    ; --- Set up IDT ---
    call setup_idt

    ; Call kernel_main
    ; rdi = multiboot info pointer (preserved from 32-bit entry)
    call kernel_main

    ; Should not return
.halt:
    cli
    hlt
    jmp .halt

; ============================================================================
; IDT Setup
; ============================================================================
section .text
bits 64

; Fill a single IDT entry
; Input: rdi = IDT entry address, rax = handler offset, dx = selector,
;        cl = IST, ch = type attributes
fill_idt_entry:
    mov word  [rdi], ax                   ; offset bits 0-15
    mov word  [rdi + 2], dx               ; selector
    mov byte  [rdi + 4], cl               ; IST
    mov byte  [rdi + 5], ch               ; type attributes
    shr rax, 16
    mov word  [rdi + 6], ax               ; offset bits 16-31
    shr rax, 16
    mov dword [rdi + 8], eax              ; offset bits 32-63
    mov dword [rdi + 12], 0               ; reserved
    ret

; Set up IDT with exception handlers
setup_idt:
    push rax
    push rbx
    push rcx
    push rdx
    push rdi
    push rsi

    ; Fill ISR entries (0-31)
    lea rbx, [rel isr_stub_table]
    lea rdi, [rel idt]
    mov dx, 0x08                          ; kernel code selector
    mov ch, 0x8E                          ; interrupt gate, present, DPL=0

    mov esi, 0
.isr_loop:
    mov rax, [rbx + rsi * 8]             ; handler address
    ; IST: use IST1 for double fault (ISR 8)
    mov cl, 0
    cmp esi, 8
    jne .isr_no_ist
    mov cl, 1                             ; IST1 for double fault
.isr_no_ist:
    call fill_idt_entry
    add rdi, 16
    inc esi
    cmp esi, 32
    jb .isr_loop

    ; Fill IRQ entries (32-47)
    lea rbx, [rel irq_stub_table]
    mov cl, 0                             ; no IST for IRQs
    mov esi, 0
.irq_loop:
    mov rax, [rbx + rsi * 8]
    call fill_idt_entry
    add rdi, 16
    inc esi
    cmp esi, 16
    jb .irq_loop

    ; Fill IDT descriptor and load
    mov word [rel idt_descriptor], 48 * 16 - 1   ; limit (48 entries)
    lea rax, [rel idt]
    mov [rel idt_descriptor + 2], rax             ; base

    lidt [rel idt_descriptor]

    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; ============================================================================
; ISR Stubs (CPU Exceptions 0-31)
; ============================================================================
section .text
bits 64

%macro ISR_NOERR 1
isr_stub_%1:
    push 0                                ; dummy error code
    push %1                               ; interrupt number
    jmp isr_common
%endmacro

%macro ISR_ERR 1
isr_stub_%1:
    ; Error code already pushed by CPU
    push %1                               ; interrupt number
    jmp isr_common
%endmacro

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
    ; Save all general-purpose registers
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

    ; Save data segment (8-byte push for proper stack alignment)
    xor rax, rax
    mov ax, ds
    push rax

    ; Load kernel data segment
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    ; Call C handler
    ; Stack layout at this point:
    ;   [rsp + 0*8]:  DS value (8 bytes)
    ;   [rsp + 1*8]:  r15
    ;   [rsp + 2*8]:  r14
    ;   ...
    ;   [rsp + 15*8]: rax
    ;   [rsp + 16*8]: interrupt number (pushed by ISR stub)
    ;   [rsp + 17*8]: error code (pushed by ISR stub or CPU)
    mov rdi, [rsp + 16*8]                ; interrupt number
    mov rsi, [rsp + 17*8]                ; error code

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

    ; Restore data segment
    pop rax
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
section .text
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

    xor rax, rax
    mov ax, ds
    push rax

    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    ; Call IRQ handler
    mov rdi, [rsp + 16*8]                ; IRQ number
    extern irq_handler
    call irq_handler

    ; Send EOI to PIC
    mov al, 0x20
    out 0x20, al
    cmp rdi, 40
    jl .no_slave_eoi
    out 0xA0, al
.no_slave_eoi:

    pop rax
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
section .text
bits 64

global context_switch
; rdi = old process stack pointer (pointer to save)
; rsi = new process stack pointer (value to load)
context_switch:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov [rdi], rsp
    mov rsp, rsi
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
section .text
bits 64

global syscall_entry
syscall_entry:
    swapgs
    mov gs:0, rsp
    mov rsp, gs:8                         ; Kernel stack
    push rcx                              ; Return RIP
    push r11                              ; Saved RFLAGS
    push rax                              ; Syscall number
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    mov rcx, r10                          ; r10 → rcx for C calling convention
    extern syscall_handler
    call syscall_handler
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    pop rax                               ; Return value
    pop r11                               ; RFLAGS
    pop rcx                               ; Return RIP
    mov rsp, gs:0
    swapgs
    sysretq

; ============================================================================
; I/O Port Helpers (called from DNAsm code)
; ============================================================================
section .text
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
; CR Register Access
; ============================================================================
section .text
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
; GDT (in .data for writability — TSS descriptor filled at runtime)
; ============================================================================
section .data
align 16

gdt64:
.null: equ $ - gdt64
    dq 0                                  ; null descriptor
.code: equ $ - gdt64
    ; 64-bit code segment: L=1, D=0, executable/read, DPL=0
    dw 0                                  ; limit low (ignored in long mode)
    dw 0                                  ; base low
    db 0                                  ; base mid
    db 10011010b                          ; access: P=1, DPL=00, S=1, Type=execute/read
    db 00100000b                          ; flags: L=1, D=0, G=0
    db 0                                  ; base high
.data_seg: equ $ - gdt64
    ; Data segment: writable, DPL=0
    dw 0
    dw 0
    db 0
    db 10010010b                          ; access: P=1, DPL=00, S=1, Type=read/write
    db 00000000b                          ; flags: L=0, D=0, G=0
    db 0
.user_code: equ $ - gdt64
    ; User 64-bit code segment: L=1, D=0, executable/read, DPL=3
    dw 0
    dw 0
    db 0
    db 11111010b                          ; access: P=1, DPL=11, S=1, Type=execute/read
    db 00100000b                          ; flags: L=1, D=0
    db 0
.user_data: equ $ - gdt64
    ; User data segment: writable, DPL=3
    dw 0
    dw 0
    db 0
    db 11110010b                          ; access: P=1, DPL=11, S=1, Type=read/write
    db 00000000b
    db 0
.tss: equ $ - gdt64
    ; TSS descriptor (16 bytes, base filled at runtime)
    dw 0x0067                             ; limit = 103 (minimum 64-bit TSS size - 1)
    dw 0                                  ; base bits 0-15 (filled at runtime)
    db 0                                  ; base bits 16-23 (filled at runtime)
    db 0x89                               ; access: P=1, DPL=00, Type=64-bit TSS available
    db 0                                  ; flags + limit high
    db 0                                  ; base bits 24-31 (filled at runtime)
    dd 0                                  ; base bits 32-63 (filled at runtime)
    dd 0                                  ; reserved
.end:

; GDT pointer (works for both 32-bit and 64-bit lgdt)
; In 32-bit mode, lgdt reads 6 bytes (2 limit + 4 base)
; In 64-bit mode, lgdt reads 10 bytes (2 limit + 8 base)
; Using dq for base works because x86 is little-endian
.pointer:
    dw gdt64.end - gdt64 - 1              ; limit
    dq gdt64                              ; base address

; ISR stub table (addresses of ISR handlers for IDT setup)
align 8
isr_stub_table:
    %assign i 0
    %rep 32
        dq isr_stub_%+i
    %assign i i+1
    %endrep

; IRQ stub table
align 8
irq_stub_table:
    %assign i 0
    %rep 16
        dq irq_stub_%+i
    %assign i i+1
    %endrep

; ============================================================================
; BSS
; ============================================================================
section .bss
align 4096

; Page tables (in .bss, zeroed by GRUB per Multiboot spec)
p4_table:
    resb 4096
p3_table:
    resb 4096
p2_table:
    resb 4096

; 32-bit stack (used before long mode)
align 16
stack_bottom_32:
    resb 16384
stack_top_32:

; 64-bit kernel stack
align 16
stack_bottom:
    resb 65536
stack_top:

; Double fault stack (IST1)
align 16
df_stack_bottom:
    resb 8192
df_stack_top:

; TSS (Task State Segment)
; 64-bit TSS minimum size = 104 bytes (0x68)
; We allocate 208 bytes (26 × 8) for IST1-7 support
align 4096
tss:
    resq 26

; IDT (Interrupt Descriptor Table)
; 256 entries × 16 bytes = 4096 bytes
align 16
idt:
    resq 256 * 2

; IDT descriptor (2 bytes limit + 8 bytes base = 10 bytes)
align 16
idt_descriptor:
    resw 1                                ; limit
    resq 1                                ; base
