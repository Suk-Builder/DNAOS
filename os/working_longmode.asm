; working_longmode.asm — 已知工作的long mode切换
; 来源: OSDev Wiki "Setting Up Long Mode"
; 编译: nasm -f bin working_longmode.asm -o working_longmode.bin

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

    ; 启用A20
    in al, 0x92
    or al, 2
    out 0x92, al

    ; 关中断
    cli

    ; 加载GDT
    lgdt [gdtr]

    ; 进入保护模式
    mov eax, cr0
    or eax, 1
    mov cr0, eax

    ; 远跳到32位
    jmp 0x08:protected_mode

ALIGN 4
gdtr:
    dw gdt_end - gdt - 1
    dd gdt

gdt:
    dq 0                    ; Null
    dw 0xFFFF, 0, 0, 0x9A, 0xCF, 0  ; Code 32-bit 0x08
    dw 0xFFFF, 0, 0, 0x92, 0xCF, 0  ; Data 0x10
    dw 0xFFFF, 0, 0, 0x9A, 0xAF, 0  ; Code 64-bit 0x18
gdt_end:

BITS 32
protected_mode:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, 0x90000

    ; 输出 '2'
    mov al, '2'
    mov dx, 0x3F8
    out dx, al

    ; 设置页表 (identity map 0-4MB) — 页表放在0x7000-0x7FFF
    mov edi, 0x7000
    mov dword [edi], 0x7000 + 0x1000 + 3  ; PML4[0] -> PDPT
    mov dword [edi+0x1000], 0x7000 + 0x2000 + 3  ; PDPT[0] -> PD
    mov dword [edi+0x2000], 0x83      ; 0-2MB, PS=1
    mov dword [edi+0x2004], 0x200083  ; 2-4MB

    ; CR3
    mov eax, 0x7000
    mov cr3, eax

    ; PAE
    mov eax, cr4
    or eax, 0x20
    mov cr4, eax

    ; EFER.LME
    mov ecx, 0xC0000080
    rdmsr
    or eax, 0x100
    wrmsr

    ; 开启分页
    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax

    ; 远跳到64位
    jmp 0x18:long_mode

BITS 64
long_mode:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov rsp, 0x1F000

    ; 输出 '3'
    mov al, '3'
    mov dx, 0x3F8
    out dx, al

    ; 输出 \r\n
    mov al, '\r'
    out dx, al
    mov al, '\n'
    out dx, al

    cli
    hlt

times 510 - ($ - $$) db 0
dw 0xAA55
