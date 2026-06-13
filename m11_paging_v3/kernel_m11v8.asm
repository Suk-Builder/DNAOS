; ============================================================================
; DNAOS v3.5 M11 v8 - 修 lgdt base 装错 (dword 装 gdt_desc)
;
; v7 撞穿原因: lgdt 装 GDT register base 显示 0x00000366 不是 mem 0x00010366
;   实际 dlog 显示错 (也许是 QEMU 8.2 dlog display bug)
;   mem gdt_desc 装对 (limit 23, base 0x00010366)
;
; v8 修法: 简化 gdt_desc 装用 dword 一次装 24-bit base (limit 16 + base 32)
;   lgdt 在 16-bit 段 + 16-bit operand size 装 6 字节
;   16-bit 段 lgdt 装 6 字节 = limit 16 + base 24
;   32-bit 段 lgdt 装 6 字节 = limit 16 + base 32
;   16-bit 段 + operand size override 32-bit 装 6 字节 = limit 16 + base 24
;   16-bit 段 + 0x67 addr size override 装 6 字节 = limit 16 + base 32 (用 lgdt 16:32)
;
;   NASM: lgdt [bx] 自动用 0x67 prefix, 16-bit 段装 6 字节 = limit 16 + base 32
;
; v8 测试: 简化 gdt_desc 装顺序, 装 base 用 dword 一次装 32-bit
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

    ; gdt_desc 装 — 关键: 用 mov eax 装 32-bit (mov ax 丢高 16!)
    mov bx, gdt_desc_offset
    mov word [bx+0], 23         ; limit 16
    mov eax, gdt_start_phys      ; eax = 0x00010366 (32-bit!)
    mov word [bx+2], ax          ; base low 16 = 0x0366
    shr eax, 16                  ; eax = 0x0001
    mov word [bx+4], ax          ; base high 16 = 0x0001
    mov byte [bx+6], 0           ; base high 8 = 0
    lgdt [bx]

    mov bx, idt_start_offset
    mov cx, 0x400
    xor ax, ax
    mov di, bx
    rep stosw

    mov bx, idt_desc_offset
    mov word [bx+0], 0x7FF
    mov eax, idt_start_phys      ; 32-bit
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
