; ============================================================================
; DNAOS v3.5 M11 v9 - 照 hello386 + Linux 0.01 boot.s 经验
;
; 关键修复 (v8 撞 6 次后):
;   1. 开 A20 gate (hello386 经验) — 也许 A20 没开 PM 段跑死
;   2. 用 32-bit 段栈 esp=0x90000 (MercuryOS 经验)
;   3. 简化 GDT 描述符 (hello386 经验) — 不用 BSS 段装
;
; v9 测试: 装 A20 + 跑 PM 段 + hlt
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

    ; --- A20 gate enable (hello386 经验) ---
    wait_a20_1:
        in al, 0x64
        test al, 2
        jnz wait_a20_1
        mov al, 0xd1
        out 0x64, al
    wait_a20_2:
        in al, 0x64
        test al, 2
        jnz wait_a20_2
        mov al, 0xdf
        out 0x60, al

    mov dx, 0x3F8
    mov al, 'A'
    out dx, al

    ; PGD @ 0x11000
    ; PGD @ 0x11000 — 修: 0xB8000 需要 PGT#2 (0xB80 PTE 索引越界 PGT#0)
    ; 装 PGD[0] (PGT#0 0x12000) + PGD[2] (PGT#2 0x14000)
    mov ax, 0x1100
    mov es, ax
    xor di, di
    mov cx, 0x800
    xor ax, ax
    rep stosw
    mov dword [es:0], 0x00012023    ; PGD[0] = PGT#0 0x12000 (P=1, R/W=1)
    mov dword [es:8], 0x00014023    ; PGD[2] = PGT#2 0x14000 (P=1, R/W=1)

    mov dx, 0x3F8
    mov al, 'G'
    out dx, al

    ; PGT#0 @ 0x12000 (PTE 0x00-0x3FF, 物理 0-0x3FF000)
    mov ax, 0x1200
    mov es, ax
    xor di, di
    mov cx, 0x800
    xor ax, ax
    rep stosw
    mov dword [es:0x40], 0x00010003    ; PGT#0[0x10] = frame 0x10
    mov dword [es:0x44], 0x00011003    ; PGT#0[0x11] = frame 0x11
    mov dword [es:0x48], 0x00012003    ; PGT#0[0x12] = frame 0x12
    mov dword [es:0x240], 0x00090003   ; PGT#0[0x90] = frame 0x90

    ; PGT#2 @ 0x14000 (PTE 0x200-0x3FF, 物理 0x80000-0xFFF000)
    ; 修: 装 PGT#2 段用 es=0x1100 段 (base 0x11000) 寻址 mem 0x14000+ ([es:0x3000])
    ; 用 mov word 装 dword 0x000B8003 (16-bit 段下 mov dword 装 word 装错)
    mov ax, 0x1100
    mov es, ax
    ; 清零 PGT#2 段 0x400 words = 0x800 字节 (0x14000-0x147FF), 用 [es:0x3000]
    mov di, 0x3000
    mov cx, 0x400
    xor ax, ax
    rep stosw
    ; 装 PGT#2[0x180] = 0x000B8003 用 2 次 mov word (low 16 + high 16)
    mov word [es:0x3600], 0xB803     ; PGT#2[0x180] low 16 = 0xB803 (mem 0x14600-0x14601)
    mov word [es:0x3602], 0x000B     ; PGT#2[0x180] high 16 = 0x000B (mem 0x14602-0x14603)

    mov dx, 0x3F8
    mov al, 'T'
    out dx, al

    ; GDT 装 (用 hello386 经验: 直接 dd 装 8 字节, 不用 [bx+disp16])
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

    ; gdt_desc 装 (用 mov eax 装 32-bit base!)
    mov bx, gdt_desc_offset
    mov word [bx+0], 23
    mov eax, gdt_start_phys
    mov word [bx+2], ax
    shr eax, 16
    mov word [bx+4], ax
    mov byte [bx+6], 0
    lgdt [bx]

    ; IDT 装
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

    ; --- 切 32-bit 段 (照 hello386 经验) ---
    mov eax, cr0
    or eax, 1
    mov cr0, eax

    mov dx, 0x3F8
    mov al, 'P'
    out dx, al

    jmp dword 0x08:pm_entry_phys

BITS 32
pm_entry:
    ; --- PM 段初始化 (照 hello386 经验) ---
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

    ; --- CR3 + PG=1 (照 v8 经验) ---
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

    ; --- VGA 写 (照 hello386 经验) ---
    mov edi, 0xB8000
    mov word [edi], 0x0F50        ; 'P' + 0x0F (白字)

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

; 关键: k11 16-bit 段设 ds=0x1020 (base 0x10200), 装 GDT 段到 [ds:bx] = mem 0x10200+bx
; 之前 v8/v9 用 0x10200 算 gdt_start_phys 对了 (装 GDT 段到 [ds:bx] = mem 0x10200+bx)
; 但 pm_entry_phys 算 0x10200+offset 错! pm_entry 实际物理 = 0x10000+offset (k11 装 mem 0x10000, 16-bit 段 cs=0x1000 段 base 0x10000)
; 修法: pm_entry_phys = 0x10000 + (pm_entry - $$)
gdt_start_phys equ 0x10200 + (gdt_start - $$)
idt_start_phys equ 0x10200 + (idt_start - $$)
pm_entry_phys equ 0x10000 + (pm_entry - $$)
gdt_start_offset equ gdt_start - $$
gdt_desc_offset equ gdt_desc - $$
idt_start_offset equ idt_start - $$
idt_desc_offset equ idt_desc - $$
