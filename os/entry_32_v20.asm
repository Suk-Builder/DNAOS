[BITS 32]
org 0x0000

; DNAOS entry_32 v20 - M9 VGA splash
; Print 3 lines of VGA text, then halt

VGA_BUF  equ 0xB8000
VGA_COLS equ 80

entry_32:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, 0x00090000

    mov al, '6'
    mov dx, 0x3F8
    out dx, al

    ; Clear 80*25 cells with spaces
    mov edi, VGA_BUF
    mov ecx, 2000
    mov ax, 0x0920          ; ' ' green-on-black
clear:
    mov [edi], ax
    add edi, 2
    dec ecx
    jnz clear

    mov al, '7'
    mov dx, 0x3F8
    out dx, al

    ; Row 0: banner (yellow)
    mov esi, banner
    mov edi, VGA_BUF
    mov ah, 0x0E
    call puts

    mov al, '8'
    mov dx, 0x3F8
    out dx, al

    ; Row 2: info (green)
    mov esi, info
    mov edi, VGA_BUF + (2 * VGA_COLS)
    mov ah, 0x0A
    call puts

    mov al, 'P'
    mov dx, 0x3F8
    out dx, al

    ; Row 4: chain (green)
    mov esi, chain
    mov edi, VGA_BUF + (4 * VGA_COLS)
    mov ah, 0x0A
    call puts

    ; Row 24: prompt (cyan)
    mov esi, prompt
    mov edi, VGA_BUF + (24 * VGA_COLS)
    mov ah, 0x09
    call puts

    jmp halt

puts:
ploop:
    lodsb
    test al, al
    jz pdone
    mov [edi], ax
    add edi, 2
    jmp ploop
pdone:
    ret

halt:
    hlt
    jmp halt

banner:  db ' DNAOS v3.5 M9', 0
info:    db ' 640K PM 32 GDT3', 0
chain:   db ' MBR->16->32->VGA', 0
prompt:  db ' DNAOS> ', 0

times 0x100 - ($ - $$) db 0x90
