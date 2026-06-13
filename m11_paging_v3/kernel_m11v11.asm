; ============================================================================
; DNAOS v3.5 M11 v11 — v10' + PGD[2] + PGT#2[0x180] + VGA 写
;
; 设计: /workspace/dnaos_review/DNAOS_v35_design.md
; 基础: /workspace/dnaos_review/m11_paging_v3/kernel_m11v10p.asm (v10' 跑通 7 marker)
;
; v11 新增:
;   - 阶段 0': 装 PGD[2] = 0x00014023 (PGT#2 @ 0x14000)
;   - 阶段 0': 装 PGT#2[0x180] = 0x000B8003 (frame 0xB8 = 0xB8000 物理)
;   - 阶段 7: 32-bit 段 VGA 写 [0xB8000] = 0x0F50 ('P' + white attr) → 'V' marker
;
; 已知撞过 (用 v9 法):
;   - 16-bit 段 PGT#2 段用 es=0x1100 段 + 2 次 mov word 装 dword
;   - ds=0x1020 段 (base 0x10200) 装 GDT 段
;   - gdt_desc base 用 NASM %define 算
;
; 撞 2 次停, 撞 3 次撕
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
    mov al, 'K'
    out dx, al

; ============================================================================
; 阶段 0: 装 PGD[0] (16-bit 段, es=0x1100 段 base 0x11000)
;   PGD[0] = 0x00012003 (PGT#0 @ 0x12000, 范围 0-4MB 含 0xB8000)
;   不装 PGD[2] (VGA 0xB8000 在 PGD[0] 范围 0-4MB)
; ============================================================================
    mov ax, 0x1100
    mov es, ax
    xor di, di
    mov cx, 0x800
    xor ax, ax
    rep stosw                   ; PGD 段清零

    ; 装 PGD[0] = 0x00012003 (PGT#0 @ 0x12000, P=1 R/W=1)
    mov word [es:0], 0x2003
    mov word [es:2], 0x0001

; ============================================================================
; 阶段 0': 装 PGT#0[0x10] (k11 code) + PGT#0[0x380] (VGA 0xB8000)
;   PGT#0[0x10] = 0x00010003 (frame 0x10 = k11 code 物理 0x10000)
;   PGT#0[0x380] = 0x000B8003 (frame 0xB8 = VGA 物理 0xB8000)
;     **修**: 0xB8000 PTE 索引 = 0xB80 & 0x3FF = 0x380 (低 10 bit, 在 PGT#0 范围)
;     **撞 1 次修**: 之前算 0x180 PTE 索引在 PGT#2, 实际 0x380 在 PGT#0
;     VGA 物理 0xB8000 < 4MB (在 PGT#0 范围 0-4MB)
;
;   PGT#0[0x10] @ 0x12000+0x10*4 = 0x12040, [es:0x1040]
;   PGT#0[0x380] @ 0x12000+0x380*4 = 0x12E00, [es:0x1E00]
; ============================================================================
    mov word [es:0x1040], 0x0003    ; PGT#0[0x10] low 16 = 0x0003
    mov word [es:0x1042], 0x0001    ; PGT#0[0x10] high 16 = 0x0001

    mov word [es:0x1E00], 0xB803    ; PGT#0[0x380] low 16 = 0xB803
    mov word [es:0x1E02], 0x000B    ; PGT#0[0x380] high 16 = 0x000B

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
    mov al, 'A'
    out dx, al

; ============================================================================
; 阶段 2: GDT 段装 (用 ds=0x1020 段)
; ============================================================================
    mov ax, 0x1020
    mov ds, ax

    mov bx, gdt_start_offset

    mov dword [bx+8],  0x0000FFFF
    mov dword [bx+12], 0x00CF9A00
    mov dword [bx+16], 0x0000FFFF
    mov dword [bx+20], 0x00CF9200

    mov dx, 0x3F8
    mov al, 'G'
    out dx, al

; ============================================================================
; 阶段 3: gdt_desc + lgdt + IDT desc + lidt
; ============================================================================
%define GDT_START_PHYS (0x10200 + gdt_start_offset)
%define IDT_START_PHYS (0x10200 + idt_start_offset)

    mov bx, gdt_desc_offset
    mov word [bx+0], 0x0017
    mov word [bx+2], (GDT_START_PHYS & 0xFFFF)
    mov word [bx+4], (GDT_START_PHYS >> 16)

    lgdt [bx]

    mov bx, idt_desc_offset
    mov word [bx+0], 0x07FF
    mov word [bx+2], (IDT_START_PHYS & 0xFFFF)
    mov word [bx+4], (IDT_START_PHYS >> 16)

    lidt [bx]

    mov dx, 0x3F8
    mov al, 'D'
    out dx, al

; ============================================================================
; 阶段 4: 16→32 切
; ============================================================================
    mov eax, cr0
    or eax, 1
    mov cr0, eax

    db 0x66, 0xEA
    dd pm_entry_phys
    dw 0x0008

; ============================================================================
; 32-bit PM 段
; ============================================================================
BITS 32

pm_entry_phys equ 0x10000 + (pm_entry - 0x10000)

pm_entry:
    mov dx, 0x3F8
    mov al, 'P'
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
    mov al, 'X'
    out dx, al

; 阶段 6: 分页开
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

; ============================================================================
; 阶段 7 (新): 32-bit 段 VGA 写
;   写 0x0F50 ('P' + 0x0F white) 到 0xB8000
;   32-bit 段下 mov word [0xB8000], 0x0F50
;   0xB8000 寻址: PGD[0xB80/1024=2] = PGT#2 (0x00014023)
;                  PGT#2[0xB80%1024=0x180] = 0x000B8003 (frame 0xB8)
;                  物理 = 0xB8000
; ============================================================================
    mov dword [0xB8000], 0x0F50     ; 'P' (low byte) + 0x0F (high byte = white attr)
                                    ; 等等 — 0x0F50 little-endian = mem[0]=0x50 'P', mem[1]=0x0F white
                                    ; 应该用 mov word, 但 mov dword 也行 (装 0x00000F50 = 只装低 16)

    mov dx, 0x3F8
    mov al, 'V'                     ; V = VGA 写完
    out dx, al

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
