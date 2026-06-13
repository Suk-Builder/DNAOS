; ============================================================================
; DNAOS v3.5 M11 v16 — 极简, 16→32 切 + 分页 + PIT IRQ0 + PS/2 IRQ1 键盘
;
; 万丈高楼平地起:
;   v15 = + PIT IRQ0 (100Hz 时钟) ✓
;   v16 = + PS/2 IRQ1 (键盘, 0x60 读 scancode, handler 写 'K' + scancode)
;
; v16 极简:
;   1-15. (跟 v15 一样, v15 跑通 9+800 marker)
;   16. 装 IDT[0x21] = PS2 handler
;   17. 8259 开 IRQ0 + IRQ1 (mask 0xFC)
;   18. PIT handler (IRQ0) + PS2 handler (IRQ1) 各自跑
;   19. PS2 handler 读 0x60 scancode, 写 'K' + scancode 到串口
;
; markers (v16):
;   H K G P X 3 ! I A S V + C (PIT) + K (PS2) per scancode
;   (v15 marker 还在, 加 PS2 handler)
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
; 装 PGD[0] + PGT#0[0x10] + PGT#0[0xB8] + PGT#0[0x8F] + PGT#0[0x90]
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

    mov word [es:0x123C], 0xF003
    mov word [es:0x123E], 0x0008
    mov word [es:0x1240], 0x0003
    mov word [es:0x1242], 0x0009

; ----------------------------------------------------------------------------
; 装 GDT 段
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
; 32-bit 段 IDT 装 PIT handler (INT 0x20) + PS2 handler (INT 0x21)
; ----------------------------------------------------------------------------
    mov edi, 0x10186

%define PIT_HANDLER_PHYS  (0x10000 + (pit_handler  - 0x10000))
%define PS2_HANDLER_PHYS  (0x10000 + (ps2_handler  - 0x10000))

    ; IDT[0x20] = PIT handler
    mov eax, PIT_HANDLER_PHYS
    mov word [edi + 0x100 + 0], ax
    mov word [edi + 0x100 + 2], 0x0008
    mov word [edi + 0x100 + 4], 0x8E00
    shr eax, 16
    mov word [edi + 0x100 + 6], ax

    ; IDT[0x21] = PS2 handler
    mov eax, PS2_HANDLER_PHYS
    mov word [edi + 0x108 + 0], ax
    mov word [edi + 0x108 + 2], 0x0008
    mov word [edi + 0x108 + 4], 0x8E00
    shr eax, 16
    mov word [edi + 0x108 + 6], ax

    ; idt_desc @ 0x10986
    mov eax, 0x10186
    mov word [0x10986 + 2], ax
    shr eax, 16
    mov word [0x10986 + 4], ax
    mov word [0x10986 + 0], 0x07FF
    mov word [0x10986 + 6], 0

    lidt [0x10986]

    mov dx, 0x3F8
    mov al, 'I'
    out dx, al

; ----------------------------------------------------------------------------
; 8259 PIC 重映射
; ----------------------------------------------------------------------------
    mov al, 0x11
    out 0x20, al
    out 0xA0, al

    mov al, 0x20
    out 0x21, al
    mov al, 0x28
    out 0xA1, al

    mov al, 0x04
    out 0x21, al
    mov al, 0x02
    out 0xA1, al

    mov al, 0x01
    out 0x21, al
    out 0xA1, al

    mov al, 0xFC                ; Mask: 开 IRQ0 (PIT) + IRQ1 (PS/2)
    out 0x21, al
    mov al, 0xFF
    out 0xA1, al

    mov dx, 0x3F8
    mov al, 'A'
    out dx, al

; ----------------------------------------------------------------------------
; PIT 通道 0 = 100Hz
; ----------------------------------------------------------------------------
    mov al, 0x36
    out 0x43, al
    mov al, 0x87
    out 0x40, al
    mov al, 0x2D
    out 0x40, al

; 开中断
    sti

    mov dx, 0x3F8
    mov al, 'S'
    out dx, al

; ----------------------------------------------------------------------------
; 32-bit 段 VGA 写 'P' (验证分页对)
; ----------------------------------------------------------------------------
    mov word [0xB8000], 0x0F50

    mov dx, 0x3F8
    mov al, 'V'
    out dx, al

; ----------------------------------------------------------------------------
; 等 PIT/PS2 tick
; ----------------------------------------------------------------------------
.wait:
    hlt
    jmp .wait

; ============================================================================
; PIT handler (IRQ0, INT 0x20)
; ============================================================================
pit_handler:
    push eax
    push edx

    mov al, 0x20
    out 0x20, al

    mov eax, [0x90010]
    inc eax
    mov [0x90010], eax

    mov edx, eax
    and edx, 0xF
    add dl, '0'
    mov byte [0xB8004], dl
    mov byte [0xB8005], 0x07

    mov dx, 0x3F8
    mov al, 'C'
    out dx, al

    pop edx
    pop eax
    iret

; ============================================================================
; PS/2 键盘 handler (IRQ1, INT 0x21)
;   1. 读 0x60 端口 (scancode)
;   2. 写 EOI (0x20) 到 0x20
;   3. 写 'K' + scancode 高 4 位 (hex) 到串口
; ============================================================================
ps2_handler:
    push eax
    push edx

    ; 读 0x60 scancode
    in al, 0x60
    mov ah, al                  ; 备份 scancode

    ; EOI
    mov al, 0x20
    out 0x20, al

    ; 写 'K' marker
    mov dx, 0x3F8
    mov al, 'K'
    out dx, al

    ; 写 scancode 高 4 位 (hex digit)
    mov al, ah
    shr al, 4
    cmp al, 10
    jb .ps2_hex1
    add al, 'a' - 10
    jmp .ps2_hex1_out
.ps2_hex1:
    add al, '0'
.ps2_hex1_out:
    mov dx, 0x3F8
    out dx, al

    ; 写 scancode 低 4 位 (hex digit)
    mov al, ah
    and al, 0xF
    cmp al, 10
    jb .ps2_hex2
    add al, 'a' - 10
    jmp .ps2_hex2_out
.ps2_hex2:
    add al, '0'
.ps2_hex2_out:
    mov dx, 0x3F8
    out dx, al

    ; 空格分隔
    mov al, ' '
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
