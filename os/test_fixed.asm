; test_fixed.asm — 修复GDT描述符（8字节）

BITS 16
ORG 0x7C00

start:
    xor ax, ax
    mov ds, ax
    mov ss, ax
    mov sp, 0x7C00

    mov al, '1'
    mov dx, 0x3F8
    out dx, al

    lgdt [gdtr]

    mov eax, cr0
    or eax, 1
    mov cr0, eax

    jmp 0x08:pm32

BITS 32
pm32:
    mov al, '2'
    mov dx, 0x3F8
    out dx, al
    jmp $

; GDT — 正确定义（每个描述符8字节）
gdtr:
    dw gdt_end - gdt - 1
    dd gdt

gdt:
    dq 0                    ; Null (8 bytes)
.code:                      ; Code 0x08 (8 bytes)
    dw 0xFFFF               ; limit 15:0
    dw 0x0000               ; base 15:0
    db 0x00                 ; base 23:16
    db 0x9A                 ; access: P=1,DPL=0,S=1,Type=Execute/Read
    db 0xCF                 ; granularity: G=1,DB=1,L=0,limit19:16=0xF
    db 0x00                 ; base 31:24
.data:                      ; Data 0x10 (8 bytes)
    dw 0xFFFF               ; limit 15:0
    dw 0x0000               ; base 15:0
    db 0x00                 ; base 23:16
    db 0x92                 ; access: P=1,DPL=0,S=1,Type=Read/Write
    db 0xCF                 ; granularity
    db 0x00                 ; base 31:24
gdt_end:

times 510 - ($ - $$) db 0
dw 0xAA55
