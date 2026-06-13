; ============================================================================
; DNAOS v3.5 M11 v12 — 极简, 16-bit 段, 不开分页, 直接 VGA 写
;
; 万丈高楼平地起 (白桦 06-13 命令):
;   先搭最小框架, 验证 VGA 写成功, 再加 16→32 + 分页
;
; v12 极简 (1 个功能: 写 0xB8000 = 0x0F50 'P' + white):
;   1. k11 entry (16-bit 段, cs=0x1000, ds=0x1020 段 base 0x10200)
;   2. 写 0x0F50 到 0xB8000 (用 ds=0xB800 段 base 0xB8000, [ds:0] = 0x0F50)
;   3. 验证 (QEMU 抓 mem 0xB8000 = 0x50 0x0F little-endian)
;   4. hlt
;
; 16-bit 段寻址 ds=0xB800 段 base 0xB8000, [ds:0] = mem 0xB8000
; mov word [0xB8000], 0x0F50 (16-bit 段下, NASM 编译 = mov word [ds:0], 0x0F50)
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

; ----------------------------------------------------------------------------
; VGA 写 (16-bit 段, 不开分页, 虚拟地址 = 物理地址)
;   ds=0xB800 段 base 0xB8000, [ds:0] = mem 0xB8000
;   写 0x0F50 ('P' + white attr) 到 0xB8000
; ----------------------------------------------------------------------------
    mov ax, 0xB800
    mov ds, ax                  ; ds = 0xB800 段 (VGA 显存)
    mov word [0], 0x0F50        ; [ds:0] = 0x0F50 ('P' + 0x0F white)

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
