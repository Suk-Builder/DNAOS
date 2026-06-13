; ============================================================================
; DNAOS v3.5 M11 v14 — 极简, 16→32 切 + 分页开 + VGA 写
;
; 万丈高楼平地起:
;   v12 = 16-bit 段 VGA 写 (3 marker HKV) ✓
;   v13 = + 16→32 切 (6 marker HKGPXV) ✓
;   v14 = + 分页开 (目标 8 marker HKGPX3!V, VGA 写在分页下也成功)
;
; v14 极简分页:
;   1. k11 entry (16-bit 段) → K
;   2. 装 PGD[0] = 0x00012003 (PGT#0 @ 0x12000) + PGT#0[0x10] = 0x00010003 (k11 code)
;                            + PGT#0[0xB8] = 0x000B8003 (VGA 0xB8000)
;      **修**: 0xB8000 PTE 索引 = 0xB8 (不是 0x380), 0xB8 & 0x3FF = 0xB8
;      (我之前 v11 算错说 0x380, 实际 0xB8 < 0x3FF, & 后不变)
;   3. 装 GDT 段 (用 ds=0x1020 段) → G
;   4. 16→32 切 (CR0.PE=1) + far jmp → P
;   5. 32-bit 段设 → X
;   6. CR3 = 0x11000 → 3
;   7. PG = 1 → !
;   8. 32-bit 段 VGA 写 (分页寻址) → V
;
; 16-bit 段装 PGT#0[0x10] @ 0x12040 (es=0x1100 段 base 0x11000, [es:0x1040])
; 16-bit 段装 PGT#0[0xB8] @ 0x122E0 ([es:0x12E0])
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

; ----------------------------------------------------------------------------
; 装 PGD[0] + PGT#0[0x10] (k11 code) + PGT#0[0x380] (VGA)
; ----------------------------------------------------------------------------
    mov ax, 0x1100
    mov es, ax
    xor di, di
    mov cx, 0x800
    xor ax, ax
    rep stosw                   ; PGD 段清零

    ; 装 PGD[0] = 0x00012003
    mov word [es:0], 0x2003
    mov word [es:2], 0x0001

    ; 装 PGT#0[0x10] = 0x00010003 (k11 code @ mem 0x10000)
    mov word [es:0x1040], 0x0003
    mov word [es:0x1042], 0x0001

    ; 装 PGT#0[0xB8] = 0x000B8003 (VGA 0xB8000)
    mov word [es:0x12E0], 0xB803
    mov word [es:0x12E2], 0x000B

; ----------------------------------------------------------------------------
; 装 GDT 段 (用 ds=0x1020 段)
; ----------------------------------------------------------------------------
    mov ax, 0x1020
    mov ds, ax

    mov bx, gdt_start_offset
    mov dword [bx+8],  0x0000FFFF
    mov dword [bx+12], 0x00CF9A00
    mov dword [bx+16], 0x0000FFFF
    mov dword [bx+20], 0x00CF9200

    mov dx, 0x3F8
    mov al, 'G'                 ; G = GDT 装好
    out dx, al

; ----------------------------------------------------------------------------
; 装 gdt_desc + lgdt
; ----------------------------------------------------------------------------
%define GDT_START_PHYS (0x10200 + gdt_start_offset)

    mov bx, gdt_desc_offset
    mov word [bx+0], 0x0017
    mov word [bx+2], (GDT_START_PHYS & 0xFFFF)
    mov word [bx+4], (GDT_START_PHYS >> 16)

    lgdt [bx]

; ----------------------------------------------------------------------------
; 16→32 切
; ----------------------------------------------------------------------------
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

; 32-bit 段设
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

; 分页开
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

; 32-bit 段 VGA 写 (分页寻址 0xB8000 → PGD[0] → PGT#0[0x380] = 0x000B8003 → 0xB8000 物理)
    mov word [0xB8000], 0x0F50

    mov dx, 0x3F8
    mov al, 'V'                 ; V = VGA 写完
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
