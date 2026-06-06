; working_small.asm — 最小long mode (必须<=510字节)

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
    dd gdt + 0x7C00

gdt:
    dq 0
    dw 0xFFFF, 0, 0, 0x9A, 0xCF, 0
    dw 0xFFFF, 0, 0, 0x92, 0xCF, 0
    dw 0xFFFF, 0, 0, 0x9A, 0xAF, 0
gdt_end:

BITS 32
pm32:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, 0x90000

    mov al, '2'
    mov dx, 0x3F8
    out dx, al

    ; 页表 @ 0x7000
    mov edi, 0x7000
    mov dword [edi], 0x8003
    mov dword [edi+0x1000], 0x9003
    mov dword [edi+0x2000], 0x83
    mov dword [edi+0x2004], 0x200083

    mov eax, 0x7000
    mov cr3, eax
    mov eax, cr4
    or eax, 0x20
    mov cr4, eax
    mov ecx, 0xC0000080
    rdmsr
    or eax, 0x100
    wrmsr
    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax
    jmp 0x18:lm64

BITS 64
lm64:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov rsp, 0x1F000
    mov al, '3'
    mov dx, 0x3F8
    out dx, al
    mov al, '\r'
    out dx, al
    mov al, '\n'
    out dx, al
    cli
    hlt

times 510 - ($ - $$) db 0
dw 0xAA55
