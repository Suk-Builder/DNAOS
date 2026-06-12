BITS 16
    ORG 0
    section .text align=1
entry_16:
    ptb EQU 0x11000
    mov al, 0x31
    call serial_send
    mov al, '\r'
    call serial_send
    mov al, '\n'
    call serial_send
    in al, 0x92
    or al, 2
    out 0x92, al
    cli
    lgdt [gdtr]
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp 0x08:entry_32
serial_send:
    push dx
    mov dx, 0x3fd
.wait:
    in al, dx
    test al, 0x20
    jz .wait
    mov dx, 0x3f8
    pop ax
    push ax
    out dx, al
    pop dx
    ret
gdtr:
dw gdt_end - gdt - 1
dd gdt
    ALIGN 8
gdt:
dq 0
.gdt_code:
dw 0xffff
dw 0
db 0
db 0x9a
db 0xcf
db 0
.gdt_data:
dw 0xffff
dw 0
db 0
db 0x92
db 0xcf
db 0
gdt_end:
    ALIGN 0x200
entry_32:
BITS 32
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, 0x90000
    mov al, 0x32
    call serial_send_32
    mov al, '\r'
    call serial_send_32
    mov al, '\n'
    call serial_send_32
    mov dword [ptb], (ptb + 0x1003)
    mov dword [ptb+0x1000], ptb + 0x2003
    mov dword [ptb+0x2000], 0x83
    mov dword [ptb+0x2008], 0x200083
    mov eax, ptb
    mov cr3, eax
    mov eax, cr4
    or eax, 0x20
    mov cr4, eax
    mov ecx, 0xc0000080
    rdmsr
    or eax, 0x100
    wrmsr
    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax
    push dword 8
    push dword entry_64
    retf 
BITS 64
entry_64:
    hlt
    jmp entry_64
serial_send_32:
    push edx
    mov edx, 0x3fd
.wait:
    in al, dx
    test al, 0x20
    jz .wait
    mov edx, 0x3f8
    mov ah, al
    pop eax
