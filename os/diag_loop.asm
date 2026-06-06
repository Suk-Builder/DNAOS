; diag_loop.asm — 32位入口无限循环，检查EIP
; 16位输出'1'，远跳32位，32位入口立即无限循环

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

    cli
    lgdt [gdtr]
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp 0x08:pm32

ALIGN 4
gdtr:
    dw gdt_end - gdt - 1
    dd gdt

gdt:
    dq 0
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 0x9A
    db 0xCF
    db 0x00
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 0x92
    db 0xCF
    db 0x00
gdt_end:

BITS 32
pm32:
    jmp $    ; 32位入口立即无限循环

times 510 - ($ - $$) db 0
dw 0xAA55
