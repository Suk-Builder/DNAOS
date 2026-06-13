; ============================================================================
; DNAOS v3.5 M11 v7 - 简化 GDT 装 (避开 NASM SIB bug), retf 跳 32-bit
;
; v6 改进:
;   - 用 [bx+disp16] 装 GDT 段 (mod=00 rm=111, 16-bit 段下 [bx+disp16])
;   - GDT[2] type 0x92 (expand-up, 不是 0x93 expand-down) ✓
;   - GDT 装对但 far jmp #GP
; v7 简化:
;   - 用 retf 跳 32-bit 段 (push offset; retf) — 跟 far jmp 等价
;   - 或者 GDT base 用绝对地址 0 (base 0) 验证
; ============================================================================

BITS 16

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    mov dx, 0x3F8
    mov al, 'K'
    out dx, al

    ; PGD @ 0x11000
    mov ax, 0x1100
    mov es, ax
    xor di, di
    mov cx, 0x800
    xor ax, ax
    rep stosw

    mov dword [es:0], 0x00012003

    mov dx, 0x3F8
    mov al, 'G'
    out dx, al

    ; PGT @ 0x12000
    mov ax, 0x1200
    mov es, ax
    xor di, di
    mov cx, 0x800
    xor ax, ax
    rep stosw

    mov dword [es:0x40], 0x00010003
    mov dword [es:0x44], 0x00011003
    mov dword [es:0x48], 0x00012003
    mov dword [es:0x240], 0x00090003
    mov dword [es:0x2E00], 0x000B8003

    mov dx, 0x3F8
    mov al, 'T'
    out dx, al

    ; GDT 用 [bx+disp16] 装 (mod=00 rm=111, 不需要 SIB)
    mov ax, 0x1020
    mov ds, ax

    mov bx, gdt_start_offset
    mov dword [bx+0], 0x00000000    ; GDT[0] null
    mov dword [bx+4], 0x00000000
    mov dword [bx+8], 0x0000FFFF    ; GDT[1] code
    mov dword [bx+12], 0x00CF9A00
    mov dword [bx+16], 0x0000FFFF   ; GDT[2] data
    mov dword [bx+20], 0x00CF9200

    mov bx, gdt_desc_offset
    mov dword [bx+0], 23
    mov ax, gdt_start_phys
    mov word [bx+2], ax
    shr eax, 16
    mov word [bx+4], ax
    mov byte [bx+6], 0
    lgdt [bx]

    mov bx, idt_start_offset
    mov cx, 0x400
    xor ax, ax
    mov di, bx
    rep stosw

    mov bx, idt_desc_offset
    mov dword [bx+0], 0x7FF
    mov ax, idt_start_phys
    mov word [bx+2], ax
    shr eax, 16
    mov word [bx+4], ax
    mov byte [bx+6], 0
    lidt [bx]

    mov dx, 0x3F8
    mov al, 'D'
    out dx, al

    ; 切 32-bit
    mov eax, cr0
    or eax, 1
    mov cr0, eax

    mov dx, 0x3F8
    mov al, 'P'
    out dx, al

    ; retf 跳 32-bit 段 (push 32-bit offset; retf)
    ; 32-bit retf = pop EIP, pop CS
    ; 简化: push 0x08 (CS), push 0x00010319 (EIP) ; retfd
    mov ax, 0x0008
    push ax
    mov ax, 0x0319
    push ax
    db 0x66            ; operand size override
    retf               ; retfd (32-bit offset, 16-bit segment)

BITS 32
pm_entry:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x90000

    mov dx, 0x3F8
    mov al, 'X'
    out dx, al

    mov eax, 0x11000
    mov cr3, eax

    mov dx, 0x3F8
    mov al, '3'
    out dx, al

    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax

    mov dx, 0x3F8
    mov al, '!'
    out dx, al

    mov edi, 0xB8000
    mov word [edi], 0x0F50

    mov dx, 0x3F8
    mov al, 'V'
    out dx, al

    hlt

gdt_start:
    times 24 db 0
gdt_desc:
    times 8 db 0
idt_start:
    times 2048 db 0
idt_desc:
    times 8 db 0

gdt_start_phys equ 0x10200 + (gdt_start - $$)
idt_start_phys equ 0x10200 + (idt_start - $$)
pm_entry_phys equ 0x10200 + (pm_entry - $$)
gdt_start_offset equ gdt_start - $$
gdt_desc_offset equ gdt_desc - $$
idt_start_offset equ idt_start - $$
idt_desc_offset equ idt_desc - $$
