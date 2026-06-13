; ============================================================================
; DNAOS v3.5 M11 v13 — 极简, 16→32 切 + 32-bit 段 VGA 写
;
; 万丈高楼平地起 (v12 跑通 16-bit 段 VGA):
;   v13 = v12 + 16→32 切 (GDT + lgdt + far jmp) + 32-bit 段 VGA 写
;   不开分页 (推到 v14)
;
; v13 极简:
;   1. k11 entry (16-bit 段) → K
;   2. 装 GDT 段 (GDT[1] code 32 + GDT[2] data 32) → G
;   3. lgdt + CR0.PE=1 + far jmp 0x0008:pm_entry → P
;   4. 32-bit 段设 (ds=es=ss=0x10) → X
;   5. 32-bit 段 VGA 写 [0xB8000] = 0x0F50 ('P' + white) → V
;
; 已知撞过 (从 v10'/v11 沉淀):
;   - ds 段重设 (装 GDT 段用 ds=0x1020 段)
;   - gdt_desc base 用 NASM %define 算
;   - 16→32 far jmp = db 0x66, 0xEA; dd pm_entry_phys; dw 0x0008
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
; 装 GDT 段 (用 ds=0x1020 段, base 0x10200)
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
; 16→32 切 (CR0.PE=1) + far jmp
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
    mov al, 'P'                 ; P = PE=1
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
    mov al, 'X'                 ; X = 32-bit 段 + 栈
    out dx, al

; 32-bit 段 VGA 写 (虚拟地址 = 物理地址, 不开分页)
    mov word [0xB8000], 0x0F50  ; 'P' + 0x0F white

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
