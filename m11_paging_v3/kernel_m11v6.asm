; ============================================================================
; DNAOS v3.5 M11 v6 - 修 NASM 16-bit 段 SIB bug
;
; 关键修复:
;   - v5 撞穿原因: NASM 16-bit 段 `mov byte [si+disp8]` 编译成 SIB 编码 (mod=01 rm=100)
;     SIB 在 16-bit 段下 = [BP + DI + disp8] (跟 32-bit 段不同), 不是 [SI + disp8]
;     所以 GDT[2] byte 5 装到错位置, GDT[2] type = 0x93 (expand-down) 不是 0x92
;     expand-down 段 base = 0xFFFF0000, 不是 0, [ds:0xB8000] 寻址错 = 0xC8000 = page fault
;
;   - v6 修法: 用 32-bit 段模式 (BITS 32) 写 GDT 段, 但 pm_entry 还没切, 16-bit 段切 32-bit
;     必须先切 PE=1 + far jmp 到 32-bit 段才能 BITS 32.
;     简化: 装 GDT 时切到 32-bit 段, 设段寄存器, 切回 16-bit
;
;   - 简化 v6.1: 16-bit 段用 dword 装 (NASM 自动生成 `66 26 C7 06 ...`)
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

    ; PGD[0] = 0x00012003 (用 dword 装 4 字节)
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

    ; PGT 5 项 (dword 装 4 字节一次)
    mov dword [es:0x40], 0x00010003
    mov dword [es:0x44], 0x00011003
    mov dword [es:0x48], 0x00012003
    mov dword [es:0x240], 0x00090003
    mov dword [es:0x2E00], 0x000B8003

    mov dx, 0x3F8
    mov al, 'T'
    out dx, al

    ; GDT 装 (用 [bx+disp16] 或 [disp16] 16-bit 段模式)
    ; gdt_start 物理 = 0x10200+gdt_start_offset
    ; 但我们用 16-bit 段 ds=0x1020 写, si=offset, 寻址 [si+disp8] NASM SIB bug
    ; 改用 [bx+disp16] (16-bit 段 mod=00 rm=111 [bx+disp16]) 或直接 [disp16] (mod=00 rm=110)
    mov ax, 0x1020
    mov ds, ax

    ; 写 GDT 段 24 字节 (gdt_start 物理 0x10200+gdt_start_offset = ?)
    ; 改用 bx + disp16: bx = gdt_start_offset, [bx+0]=byte
    ; 但 k11 装好后段还没装好, 现在装 GDT 段直接写物理
    ; 简化: GDT 段 = 0x0000000000000000 (null) + 0x00CF9A000000FFFF (code) + 0x00CF92000000FFFF (data)
    ; 装到 ds:bx+offset

    ; 算 gdt_start offset
    ; 16-bit 段 ds=0x1020 段, [bx+disp16] 寻址 0x1020:bx+disp16
    ; gdt_start 物理 0x10200+gdt_start_offset
    ; bx = gdt_start_offset, disp16 = 0
    mov bx, gdt_start_offset        ; bx = gdt_start offset in k11
    mov dword [bx+0], 0x00000000    ; GDT[0] null
    mov dword [bx+4], 0x00000000
    mov dword [bx+8], 0x0000FFFF    ; GDT[1] code
    mov dword [bx+12], 0x00CF9A00
    mov dword [bx+16], 0x0000FFFF   ; GDT[2] data
    mov dword [bx+20], 0x00CF9200

    mov dx, 0x3F8
    mov al, 'G'
    out dx, al

    mov bx, gdt_desc_offset
    mov dword [bx+0], 23            ; limit
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

    ; 切 32-bit 保护模式
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
