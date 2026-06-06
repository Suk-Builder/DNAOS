; test_vga.asm — 用VGA写入确认32位代码执行
; 编译: nasm -f bin test_vga.asm -o test_vga.bin

BITS 16
ORG 0x7C00

start:
    xor ax, ax
    mov ds, ax
    mov ss, ax
    mov sp, 0x7C00

    ; 清屏: 用空格+黑底填VGA
    mov ax, 0xB800
    mov es, ax
    xor di, di
    mov cx, 2000
    mov ax, 0x0720
    rep stosw

    ; 在VGA(0,0)写 '1' (16位确认)
    mov byte [es:0], '1'
    mov byte [es:1], 0x0E  ; 黄色

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
    ; 加载数据段
    mov ax, 0x10
    mov ds, ax
    mov es, ax

    ; 在VGA(1,0)写 '2' (32位确认)
    mov ebx, 0xB8000
    mov byte [ebx+2], '2'
    mov byte [ebx+3], 0x0E  ; 黄色

    ; halt
    cli
    hlt

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
