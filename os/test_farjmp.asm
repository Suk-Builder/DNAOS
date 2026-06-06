; test_farjmp.asm — 最小远跳测试
; 编译: nasm -f bin test_farjmp.asm -o test_farjmp.bin
; 测试: qemu-system-x86_64 -drive format=raw,file=test_farjmp.bin -m 128 -display none -serial stdio

BITS 16
ORG 0x7C00

start:
    xor ax, ax
    mov ds, ax
    mov ss, ax
    mov sp, 0x7C00

    ; 输出 '1' 到COM1 (确认16位运行)
    mov al, '1'
    call serial_out

    ; 加载GDT
    lgdt [gdtr]

    ; 进入保护模式
    mov eax, cr0
    or eax, 1
    mov cr0, eax

    ; 远跳到32位代码
    jmp 0x08:pm32

BITS 32
pm32:
    ; 加载数据段
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, 0x90000

    ; 输出 '2' 到COM1 (确认32位运行)
    mov al, '2'
    call serial_out32

    ; 输出 \r\n
    mov al, '\r'
    call serial_out32
    mov al, '\n'
    call serial_out32

    ; halt
    cli
    hlt

BITS 16
serial_out:        ; al = char, 16位模式
    push dx
    mov dx, 0x3F8
    out dx, al
    pop dx
    ret

BITS 32
serial_out32:      ; al = char, 32位模式
    push edx
    mov edx, 0x3F8
    out dx, al
    pop edx
    ret

; GDT
ALIGN 8
gdtr:
    dw gdt_end - gdt - 1
    dd gdt

gdt:
    dq 0                    ; Null
    dw 0xFFFF, 0, 0, 0x9A, 0xCF, 0  ; Code 0x08
    dw 0xFFFF, 0, 0, 0x92, 0xCF, 0  ; Data 0x10
gdt_end:

; 填充到510字节 + 签名
times 510 - ($ - $$) db 0
dw 0xAA55
