; ============================================================================
; DNAOS v3.5 M11 v15 — 极简, 16→32 切 + 分页 + PIT IRQ0 + VGA 写 tick
;
; 万丈高楼平地起:
;   v14 = 32-bit+分页+VGA 写 'P' (9 marker) ✓
;   v15 = + PIT IRQ0 (PIT 通道 0 100Hz, IRQ0 → INT 0x20)
;         + 装 IDT[0x20] = PIT handler
;         + 装 8259 PIC (重映射 IRQ0 → INT 0x20)
;         + 开 IRQ0 (mask 0xFE, IRQ0 enable)
;         + PIT handler 跑 VGA 写 (VGA 0xB8000 显示 tick 计数, e.g. '0' '1' '2' ...)
;
; v15 极简 (PIT 跑通 = 32-bit 段 + 分页 + PIC 重映射 + IDT 装 PIT handler + 8259 开 IRQ0):
;   1-9. (跟 v14 一样, 9 marker H K G P X 3 ! + 加 'A' = PIC 重映射装好)
;   10. 装 IDT[0x20] = PIT handler (code 段 0x0008 base 0 limit 0xFFFFF type 0x8E 中断门)
;   11. lidt
;   12. 8259 PIC 重映射 (主 IRQ0-7 → INT 0x20-0x27)
;   13. 开 IRQ0 (主 PIC mask 0xFE)
;   14. PIT 通道 0 = 100Hz (divisor 11931)
;   15. sti (开中断)
;   16. 跑 PIT handler 触发 → 'C' marker (clock tick) + VGA 写 tick 计数
;
; markers (v15):
;   H K G P X 3 ! A I S C
;   A = PIC 重映射装好
;   I = IDT 装好 (PIT handler 0x20 entry)
;   S = sti (开中断)
;   C = PIT handler 跑过 (VGA 0xB8000 显示 tick)
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
; 装 PGD[0] + PGT#0[0x10] (k11 code) + PGT#0[0xB8] (VGA)
; ----------------------------------------------------------------------------
    mov ax, 0x1100
    mov es, ax
    xor di, di
    mov cx, 0x800
    xor ax, ax
    rep stosw

    mov word [es:0], 0x2003
    mov word [es:2], 0x0001

    mov word [es:0x1040], 0x0003
    mov word [es:0x1042], 0x0001

    mov word [es:0x12E0], 0xB803
    mov word [es:0x12E2], 0x000B

    ; 装 PGT#0[0x8F] = 0x0008F003 (PM 栈 0x8F000-0x8FFFF, PIT handler push 寻址 esp-4)
    mov word [es:0x123C], 0xF003
    mov word [es:0x123E], 0x0008
    ; 装 PGT#0[0x90] = 0x00090003 (PM 栈 0x90000-0x9FFFF, PIT handler 写 0x90010)
    mov word [es:0x1240], 0x0003
    mov word [es:0x1242], 0x0009

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
    mov al, 'G'
    out dx, al

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
    mov al, '3'
    out dx, al

    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax

    mov dx, 0x3F8
    mov al, '!'
    out dx, al

; ----------------------------------------------------------------------------
; 32-bit 段 IDT 装 PIT handler (IDT[0x20] = PIT_handler)
;   IDT entry: [offset_low, selector, 0, type, offset_high]
;   type 0x8E = 中断门 (P=1 DPL=0 type=1110)
; ----------------------------------------------------------------------------
    mov edi, 0x10186           ; IDT base (32-bit 段寻址)
    ; IDT[0x20] 在 IDT 段 0x20 * 8 = 0x100 偏移
    ; PIT handler offset = 0x10000 + (pit_handler - 0x10000) = pit_handler_phys

%define PIT_HANDLER_PHYS (0x10000 + (pit_handler - 0x10000))

    mov eax, PIT_HANDLER_PHYS
    mov word [edi + 0x100 + 0], ax       ; offset_low
    mov word [edi + 0x100 + 2], 0x0008   ; selector (code 32)
    mov word [edi + 0x100 + 4], 0x8E00   ; type 0x8E (中断门) + 0
    shr eax, 16
    mov word [edi + 0x100 + 6], ax       ; offset_high

    ; idt_desc @ 0x10986 (32-bit 段寻址): base=0x10186, limit=0x7FF (256 entries)
    mov eax, 0x10186
    mov word [0x10986 + 2], ax
    shr eax, 16
    mov word [0x10986 + 4], ax
    mov word [0x10986 + 0], 0x07FF
    mov word [0x10986 + 6], 0

    lidt [0x10986]

    mov dx, 0x3F8
    mov al, 'I'                 ; I = IDT 装好
    out dx, al

; ----------------------------------------------------------------------------
; 8259 PIC 重映射 (主 IRQ0-7 → INT 0x20-0x27)
; ----------------------------------------------------------------------------
    mov al, 0x11
    out 0x20, al
    out 0xA0, al

    mov al, 0x20                ; 主 PIC: IRQ0 → INT 0x20
    out 0x21, al
    mov al, 0x28                ; 从 PIC: IRQ8 → INT 0x28
    out 0xA1, al

    mov al, 0x04                ; 主 PIC: IR2 接从 PIC
    out 0x21, al
    mov al, 0x02                ; 从 PIC: 接主 PIC IR2
    out 0xA1, al

    mov al, 0x01                ; ICW4: 8086 模式
    out 0x21, al
    out 0xA1, al

    mov al, 0xFE                ; Mask: 只开 IRQ0 (PIT)
    out 0x21, al
    mov al, 0xFF
    out 0xA1, al

    mov dx, 0x3F8
    mov al, 'A'                 ; A = PIC 装好
    out dx, al

; ----------------------------------------------------------------------------
; PIT 通道 0 = 100Hz (divisor 11931 = 0x2D87)
;   通道 0, 模式 3 (square wave), 16-bit binary = 0x36
; ----------------------------------------------------------------------------
    mov al, 0x36
    out 0x43, al
    mov al, 0x87                ; divisor low
    out 0x40, al
    mov al, 0x2D                ; divisor high
    out 0x40, al

; 开中断
    sti

    mov dx, 0x3F8
    mov al, 'S'                 ; S = sti 开中断
    out dx, al

; ----------------------------------------------------------------------------
; 32-bit 段 VGA 写 'P' (验证分页对, 跟 v14 一样)
; ----------------------------------------------------------------------------
    mov word [0xB8000], 0x0F50  ; 'P' + 0x0F white

    mov dx, 0x3F8
    mov al, 'V'
    out dx, al

; ----------------------------------------------------------------------------
; 等 PIT tick (死循环, PIT handler 会触发 VGA 写 tick)
; ----------------------------------------------------------------------------
.wait:
    hlt
    jmp .wait

; ============================================================================
; PIT handler (IRQ0, INT 0x20)
;   1. 写 EOI (0x20) 到 0x20 (主 PIC 确认)
;   2. tick_count++
;   3. VGA 0xB8000 + 4 cell 显示 '0'-'9' 循环
; ============================================================================
pit_handler:
    push eax
    push edx

    ; EOI
    mov al, 0x20
    out 0x20, al

    ; tick 计数
    mov eax, [0x90010]          ; tick_count 存 0x90010
    inc eax
    mov [0x90010], eax

    ; VGA 写 tick 数字 (0xB8000 + 4 cell, 1 字符 1 attr)
    ; 简化: 写 '0'-'9' 循环显示
    mov edx, eax
    and edx, 0xF
    add dl, '0'
    mov byte [0xB8004], dl      ; 数字字符 (ASCII)
    mov byte [0xB8005], 0x07    ; 灰字属性

    ; 写 'C' marker (PIT 跑了) 到 串口
    mov dx, 0x3F8
    mov al, 'C'
    out dx, al

    pop edx
    pop eax
    iret

; ============================================================================
; BSS
; ============================================================================
gdt_start:     times 24 db 0
gdt_desc:      times 8  db 0
idt_start:     times 2048 db 0
idt_desc:      times 8  db 0

gdt_start_offset  equ gdt_start - $$
gdt_desc_offset   equ gdt_desc - $$
