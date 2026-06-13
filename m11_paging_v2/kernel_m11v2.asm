; ============================================================================
; DNAOS v3.5 M11 v2 - 16-bit BIOS 32-bit 切 + 4KB 分页 (k11)
; 路线 (从 m8 笔记学):
;   1. 16-bit 段: 装 PGD/PGT, 装 GDT, 设 CR0.PE=1, far jmp 32-bit
;   2. 32-bit 段: 设 CR3=PGD, 设 CR0.PG=1, 写 VGA 验证
;
; 内存布局:
;   0x10000-0x103FF: k11 (sector 2-3, 物理 0x10200 起)
;   0x11000-0x11FFF: PGD (4KB, 1024 项, 每项 4B)
;   0x12000-0x12FFF: PGT (4KB, 1024 项, 每项 4B)
;
; 简化: identity map 0x00000-0xFFFFF, 但 PGT 只填 4 项:
;   PGT[0]    = frame 0x00000  (低 4KB, BIOS/IVT)
;   PGT[0x10] = frame 0x10000  (k11 32-bit 段)
;   PGT[0x11] = frame 0x11000  (PGD @ 0x11000, 给 CR3 用)
;   PGT[0x12] = frame 0x12000  (PGT 自己)
;   PGT[0xB80] = frame 0xB8000 (VGA 显存)
;
; PGD[0] = 0x12003 (指向 PGT @ 0x12000)
; ============================================================================

BITS 16

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    ; 串口 'K' (kernel 启动)
    mov dx, 0x3F8
    mov al, 'K'
    out dx, al

    ; ============== 装 PGD @ 0x11000 (4KB) ==============
    mov ax, 0x1100
    mov es, ax
    xor di, di
    mov cx, 0x800        ; 4KB / 2 = 2048 word
    xor ax, ax
    rep stosw            ; PGD 全 0

    ; 装 PGD[0] = 0x12003 (PGT @ 0x12000, P=1 R/W=1)
    ; 32-bit PGD[0] = 0x00012003 = low word 0x2003 + high word 0x0001
    mov word [es:0], 0x2003
    mov word [es:2], 0x0001

    ; 串口 'G' (PGD 装好)
    mov dx, 0x3F8
    mov al, 'G'
    out dx, al

    ; ============== 装 PGT @ 0x12000 (4KB) ==============
    mov ax, 0x1200
    mov es, ax
    xor di, di
    mov cx, 0x800        ; 4KB
    xor ax, ax
    rep stosw            ; PGT 全 0

    ; PGT[0] = 0x00003 (frame 0x00000, P=1 R/W=1)
    mov word [es:0], 0x0003
    mov word [es:2], 0x0000

    ; PGT[0x10] = 0x10003 (frame 0x10000, k11 自己)
    mov word [es:0x40], 0x0003
    mov word [es:0x42], 0x0001

    ; PGT[0x11] = 0x11003 (frame 0x11000, PGD)
    mov word [es:0x44], 0x1003
    mov word [es:0x46], 0x0001

    ; PGT[0x12] = 0x12003 (frame 0x12000, PGT 自己)
    mov word [es:0x48], 0x2003
    mov word [es:0x4A], 0x0001

    ; PGT[0xB80] = 0xB8003 (frame 0xB8000, VGA)
    mov word [es:0x2E00], 0x8003
    mov word [es:0x2E02], 0x000B

    ; 串口 'T' (PGT 装好)
    mov dx, 0x3F8
    mov al, 'T'
    out dx, al

    ; ============== 装 GDT (扁平) ==============
    mov ax, 0x1020
    mov ds, ax           ; ds = k11 段

    mov si, gdt_start
    ; GDT[0] null
    mov word [si], 0
    mov word [si+2], 0
    mov word [si+4], 0
    mov word [si+6], 0
    ; GDT[1] code 4GB flat (base=0)
    mov word [si+8], 0xFFFF
    mov word [si+10], 0x0000
    mov byte [si+12], 0x00
    mov byte [si+13], 0x9A
    mov byte [si+14], 0xCF
    mov byte [si+15], 0x00
    ; GDT[2] data 4GB flat
    mov word [si+16], 0xFFFF
    mov word [si+18], 0x0000
    mov byte [si+20], 0x00
    mov byte [si+21], 0x92
    mov byte [si+22], 0xCF
    mov byte [si+23], 0x00

    ; lgdt [gdt_desc]
    mov si, gdt_desc
    ; gdt_desc: 6 bytes limit(16) base(32)
    ; gdt_start 物理 = 0x10000 + (gdt_start - 0x10200) = 0x10000 + offset_in_k11
    ; 用 NASM 自动算:  gdt_start_phys = 0x10000 + (gdt_start - $$)
    ; 简化: gdt_start 紧跟 far jmp 后, 估计偏移 0x300
    ; 让我用绝对地址: gdt_start @ 0x10000 + (label - $$)
    mov word [si], 23
    mov eax, gdt_start_phys
    mov word [si+2], ax         ; base low 16
    shr eax, 16
    mov word [si+4], ax         ; base mid 16 (high 16 of 32-bit)
    mov byte [si+6], 0          ; base high 8

    lgdt [si]

    ; 装 IDT (空表, 256 项 * 8B = 2KB)
    mov ax, 0x1020
    mov ds, ax
    mov si, idt_start
    mov cx, 0x400        ; 2KB / 4B
    xor ax, ax
    rep stosw            ; IDT 全 0 (空描述符)

    mov si, idt_desc
    mov word [si], 0x7FF       ; limit = 2047 (256 * 8 - 1)
    mov eax, idt_start_phys
    mov word [si+2], ax
    shr eax, 16
    mov word [si+4], ax
    mov byte [si+6], 0
    lidt [si]

    ; 串口 'D' (GDT 装好 + lgdt + IDT 装好)
    mov dx, 0x3F8
    mov al, 'D'
    out dx, al

    ; ============== 切 32-bit (PE=1) ==============
    mov eax, cr0
    or eax, 1
    mov cr0, eax

    ; 串口 'P' (PE=1)
    mov dx, 0x3F8
    mov al, 'P'
    out dx, al

    ; far jmp 0x08:0x00010346 (32-bit code at 0x10346 = 0x10200 + pm_entry offset 0x146)
    ; 用 dword 强制 32-bit 偏移 (16-bit 段默认 16-bit far jmp)
    jmp dword 0x08:0x00010346

BITS 32
pm_entry:
    ; 32-bit 段
    ; 立即串口 'X' (进 32-bit 了)
    mov dx, 0x3F8
    mov al, 'X'
    out dx, al

    ; ============== 开分页 (PG=1) ==============
    ; 设 CR3 = 0x11000 (PGD)
    mov eax, 0x11000
    mov cr3, eax

    ; 串口 '3' (CR3 设好)
    mov dx, 0x3F8
    mov al, '3'
    out dx, al

    ; CR0 |= 0x80000000
    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax

    ; 串口 '!' (PG=1, 分页开!)
    mov dx, 0x3F8
    mov al, '!'
    out dx, al

    ; 写 VGA 'P' (32-bit kernel 跑通 + 分页开)
    mov edi, 0xB8000
    mov word [edi], 0x0F50

    ; 串口 'W' (VGA 写完前, 验证未 page fault)
    mov dx, 0x3F8
    mov al, 'W'
    out dx, al

    ; 串口 'V' (VGA 写完)
    mov dx, 0x3F8
    mov al, 'V'
    out dx, al

    hlt

    ; ============== 开分页 (PG=1) ==============
    ; 设 CR3 = 0x11000 (PGD)
    mov eax, 0x11000
    mov cr3, eax

    ; 串口 '3' (CR3 设好)
    mov dx, 0x3F8
    mov al, '3'
    out dx, al

    ; CR0 |= 0x80000000
    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax

    ; 串口 '!' (PG=1)
    mov dx, 0x3F8
    mov al, '!'
    out dx, al

    ; 写 VGA 'P'
    mov edi, 0xB8000
    mov word [edi], 0x0F50

    ; 串口 'V' (VGA 写完)
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

; gdt_start 物理地址 = 0x10000 + (gdt_start - k11 起点) = 0x10000 + offset
; k11 起点 = 0x10200, gdt_start = ?
; 让 NASM 算
gdt_start_phys equ 0x10200 + (gdt_start - $$)
idt_start_phys equ 0x10200 + (idt_start - $$)
