; test_32com1.asm — 32位入口输出'2'然后循环

BITS 16
ORG 0x7C00

start:
    xor ax, ax
    mov ds, ax
    mov ss, ax
    mov sp, 0x7C00

    ; 输出 '1'
    mov al, '1'
    mov dx, 0x3F8
    out dx, al

    ; 加载GDT
    lgdt [gdtr]

    ; 进入保护模式
    mov eax, cr0
    or eax, 1
    mov cr0, eax

    ; 远跳
    jmp 0x08:pm32

BITS 32
pm32:
    ; 输出 '2' (32位COM1)
    mov al, '2'
    mov dx, 0x3F8
    out dx, al
    
    ; 无限循环
    jmp $

gdtr:
    dw gdt_end - gdt - 1
    dd gdt

gdt:
    dq 0
    dw 0xFFFF, 0, 0, 0x9A, 0xCF, 0
    dw 0xFFFF, 0, 0, 0x92, 0xCF, 0
gdt_end:

times 510 - ($ - $$) db 0
dw 0xAA55
