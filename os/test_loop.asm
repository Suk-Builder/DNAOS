; test_loop.asm — 32位入口写无限循环，用-d cpu检查EIP

BITS 16
ORG 0x7C00

start:
    xor ax, ax
    mov ds, ax
    mov ss, ax
    mov sp, 0x7C00

    ; 输出 '1' 到COM1
    mov al, '1'
    mov dx, 0x3F8
    out dx, al

    ; 加载GDT
    lgdt [gdtr]

    ; 进入保护模式
    mov eax, cr0
    or eax, 1
    mov cr0, eax

    ; 远跳到32位
    jmp 0x08:pm32

BITS 32
pm32:
    ; 32位入口: 直接无限循环
    jmp $

; GDT
ALIGN 8
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
