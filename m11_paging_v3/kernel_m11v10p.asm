; ============================================================================
; DNAOS v3.5 M11 v10' — 极简, 只验证 6 阶段
;
; 撕 v10 (撞 3 次退): PGT 装入 1024 entry 太重, 简化
;
; v10' 只装 PGD[0]=0x00012003, 其他 PGD 全 0 (BSS 0 初始化)
; 验证 CR3 + PG=1, 然后虚地址 0 触发 #PF (正确行为, 验证分页工作)
; ============================================================================

BITS 16

org 0x10000

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    mov dx, 0x3F8
    mov al, 'K'                 ; K = kernel 启动
    out dx, al

; ============================================================================
; 阶段 0 (极简): 装 PGD[0] = 0x00012003 (PGT#0 @ 0x12000)
;   PGT#0 全 0 (BSS 0 初始化) = 没映射
;   验证: 分页开后虚地址 0 触发 #PF (正确)
;
;   16-bit 段下用 es=0x1100 段 base 0x11000, 寻址 0x11000+offset
; ============================================================================
    mov ax, 0x1100
    mov es, ax
    ; 清零 PGD 段 (4KB)
    xor di, di
    mov cx, 0x800
    xor ax, ax
    rep stosw
    ; 装 PGD[0] = 0x00012003 (PGT#0 @ 0x12000, P=1 R/W=1, identity map 0-4MB)
    ;   用 2 次 mov word 装 dword (16-bit 段下 mov dword 装 dword 丢高 16)
    mov word [es:0], 0x2003     ; PGD[0] low 16
    mov word [es:2], 0x0001     ; PGD[0] high 16

; ============================================================================
; 阶段 1: A20 gate
; ============================================================================
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
    mov al, 'A'                 ; A = A20 open
    out dx, al

; ============================================================================
; 阶段 2: GDT 段装
;   gdt_start 物理 = org 0x10000 + gdt_start_offset (NASM 算)
;   GDT[1] = code 32 (0x9A)
;   GDT[2] = data 32 (0x92)
;
;   **修**: 装 GDT 段用 ds=0x1020 段 (base 0x10200, v9 已知撞过)
;          这样 bx 装 gdt_start_offset (0xFE), [ds:bx+8] = mem 0x102FE+8 = 0x10306
;          gdt_start_phys 用 0x10200+gdt_start_offset 算
; ============================================================================
    mov ax, 0x1020              ; ds = 0x1020 段 (base 0x10200)
    mov ds, ax

    mov bx, gdt_start_offset    ; bx = NASM 算的 gdt_start_offset (0xFE)

    mov dword [bx+8],  0x0000FFFF
    mov dword [bx+12], 0x00CF9A00
    mov dword [bx+16], 0x0000FFFF
    mov dword [bx+20], 0x00CF9200

    mov dx, 0x3F8
    mov al, 'G'                 ; G = GDT 装好
    out dx, al

; ============================================================================
; 阶段 3: gdt_desc + lgdt + IDT desc + lidt
;   gdt_start_phys = 0x10200 + gdt_start_offset (NASM 算 gdt_start_offset)
;   idt_start_phys = 0x10200 + idt_start_offset (NASM 算 idt_start_offset)
;
;   gdt_desc 装 base 用 NASM %define 算, 不能写死
; ============================================================================
%define GDT_START_PHYS (0x10200 + gdt_start_offset)
%define IDT_START_PHYS (0x10200 + idt_start_offset)

    mov bx, gdt_desc_offset
    mov word [bx+0], 0x0017                     ; limit 0x17
    mov word [bx+2], (GDT_START_PHYS & 0xFFFF)  ; base low 16
    mov word [bx+4], (GDT_START_PHYS >> 16)     ; base high 16

    lgdt [bx]

    mov bx, idt_desc_offset
    mov word [bx+0], 0x07FF                     ; limit 0x7FF
    mov word [bx+2], (IDT_START_PHYS & 0xFFFF)  ; base low 16
    mov word [bx+4], (IDT_START_PHYS >> 16)     ; base high 16

    lidt [bx]

    mov dx, 0x3F8
    mov al, 'D'                 ; D = desc 装好
    out dx, al

; ============================================================================
; 阶段 4: 16→32 切
; ============================================================================
    mov eax, cr0
    or eax, 1
    mov cr0, eax

    db 0x66, 0xEA               ; far jmp 32-bit
    dd pm_entry_phys
    dw 0x0008

; ============================================================================
; 32-bit PM 段
; ============================================================================
BITS 32

pm_entry_phys equ 0x10000 + (pm_entry - 0x10000)   ; = pm_entry_phys = 0x10000 + pm_entry offset

pm_entry:
    mov dx, 0x3F8
    mov al, 'P'                 ; P = PE=1
    out dx, al

; 阶段 5: 32-bit 段设
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x90000

    mov dx, 0x3F8
    mov al, 'X'                 ; X = 32-bit 段 + 栈
    out dx, al

; 阶段 6: 分页开
    mov eax, 0x11000
    mov cr3, eax

    mov dx, 0x3F8
    mov al, '3'                 ; 3 = CR3 装好
    out dx, al

    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax

    mov dx, 0x3F8
    mov al, '!'                 ; ! = PG=1
    out dx, al

; 验证 — 读 0x00000000 (IVT), PGD[0]=0x00012003 (PGT#0 全 0)
;   PGT#0[0] = 0 = 没映射, 应该 #PF (验证分页工作)
;   v10' 不接 #PF handler, 让 QEMU 抓 #PF dlog
    mov eax, [0x00000000]       ; 触发 #PF (PTE[0]=0 没映射)
    hlt

; ============================================================================
; BSS
; ============================================================================
gdt_start:     times 24 db 0
gdt_desc:      times 8  db 0
idt_start:     times 2048 db 0
idt_desc:      times 8  db 0

gdt_start_offset  equ gdt_start - $$
gdt_desc_offset   equ gdt_desc - $$
idt_start_offset  equ idt_start - $$
idt_desc_offset   equ idt_desc - $$
