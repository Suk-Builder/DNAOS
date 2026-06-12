[BITS 32]
org 0x0000

; DNAOS entry_32 (32-bit protected mode)
; Loaded at file offset 0x100 within the kernel (physical 0x10100 when kernel is at 0x10000)

entry_32:
    mov ax, 0x10           ; data segment selector
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, 0x00090000    ; set up a stack in high memory

    mov al, '6'
    mov dx, 0x3F8
    out dx, al

    mov al, '7'
    mov dx, 0x3F8
    out dx, al

    mov al, '8'
    mov dx, 0x3F8
    out dx, al

    mov al, 'P'
    mov dx, 0x3F8
    out dx, al

.halt:
    hlt
    jmp .halt

; Pad to 0x100 (256 bytes) so kernel files align
times 0x100 - ($ - $$) db 0x90
