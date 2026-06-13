; ============================================================================
; DNAOS v3.5 M11 v8.1 - 修 mov ax (丢高 16-bit) bug
;
; v8 撞穿原因: k11 16-bit 段 `mov ax, gdt_start_phys` (0x00010366) 编译
;   = `mov ax, 0x0366` (low 16), eax 高 16 没改 = 0
;   shr eax, 16 = 0, gdt_desc base high 16 = 0
;   gdt_desc base = 0x00000066_0366 = 0x00000366 (不是 0x00010366)
;   lgdt 装 GDT register base = 0x00000366 (BIOS 区), 不是 k11 GDT 段 0x10366
;   far jmp 跳 GDT[1] 0x0008 = 0x00000366 + 8 = 0x0000036E (BIOS 区) = #GP error=0x0008
;
; v8.1 修法: 用 mov eax, gdt_start_phys 装 32-bit
;   eax = 0x00010366 ✓
;   shr eax, 16 = 0x0001 ✓
;   gdt_desc base = 0x00_010366 = 0x00010366 ✓
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

    mov ax, 0x1020
    mov ds, ax

    mov bx, gdt_start_offset
    mov dword [bx+0], 0x00000000
    mov dword [bx+4], 0x00000000
    mov dword [bx+8], 0x0000FFFF
    mov dword [bx+12], 0x00CF9A00
    mov dword [bx+16], 0x0000FFFF
    mov dword [bx+20], 0x00CF9200

    mov dx, 0x3F8
    mov al, 'G'
    out dx, al

    mov bx, gdt_desc_offset
    mov word [bx+0], 23
    mov eax, gdt_start_phys       ; eax = 0x00010366
    mov word [bx+2], ax           ; base low 16 = 0x0366
    shr eax, 16                   ; eax = 0x0001
    mov word [bx+4], ax           ; base high 16 = 0x0001
    mov byte [bx+6], 0
    lgdt [bx]

    mov bx, idt_start_offset
    mov cx, 0x400
    xor ax, ax
    mov di, bx
    rep stosw

    mov bx, idt_desc_offset
    mov word [bx+0], 0x7FF
    mov eax, idt_start_phys
    mov word [bx+2], ax
    shr eax, 16
    mov word [bx+4], ax
    mov byte [bx+6], 0
    lidt [bx]

    mov dx, 0x3F8
    mov al, 'D'
    out dx, al

    mov eax, cr0
    or eax, 1
    mov cr0, eax

    mov dx, 0x3F8
    mov al, 'P'
    out dx, al

    jmp dword 0x08:pm_entry_phys

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
