; ============================================================================
; DNAOS v23 - M10 16-bit BIOS 重写路线 (简化版)
; ============================================================================

BITS 16
ORG 0x0000

start:
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    mov dx, 0x3F8
    mov al, 'K'
    out dx, al                ; K = kernel 启动

    ; BIOS INT 10h AH=00 80x25 文本模式
    mov ax, 0x0003
    int 0x10

    mov dx, 0x3F8
    mov al, 'M'
    out dx, al                ; M = 模式设好

    ; 画 4 行 (用 BIOS INT 10h 0Ah 写 + 02h 设光标)
    mov si, banner
    mov dh, 0
    call puts_bios

    mov si, info
    mov dh, 2
    call puts_bios

    mov si, chain
    mov dh, 4
    call puts_bios

    mov si, prompt
    mov dh, 24
    call puts_bios

    mov dx, 0x3F8
    mov al, 'P'
    out dx, al                ; P = polling 准备

.poll:
    mov ah, 0x01
    int 0x16
    jz .poll

    mov ah, 0x00
    int 0x16
    ; AL = ASCII, AH = scan code

    push ax
    mov dx, 0x3FD
.wait1:
    in al, dx
    test al, 0x20
    jz .wait1
    pop ax
    push ax
    mov dx, 0x3F8
    out dx, al
    pop ax

    mov ah, 0x0A               ; BIOS 写字符 (光标不动)
    mov bh, 0
    mov bl, 0x0A
    mov cx, 1
    int 0x10

    mov ah, 0x03               ; 读光标位置
    mov bh, 0
    int 0x10
    inc dl                     ; col + 1
    mov ah, 0x02
    int 0x10

    jmp .poll

; puts_bios: SI = 字符串, DH = row
puts_bios:
    push ax
    push bx
    push dx

    mov ah, 0x02
    mov bh, 0
    mov dl, 0
    int 0x10
.puts:
    lodsb
    test al, al
    jz .done
    mov ah, 0x0A
    mov bh, 0
    mov bl, 0x0E               ; yellow default
    mov cx, 1
    int 0x10
    mov ah, 0x03
    int 0x10
    inc dl
    mov ah, 0x02
    int 0x10
    jmp .puts
.done:
    pop dx
    pop bx
    pop ax
    ret

banner:    db ' DNAOS v3.5 M10', 0
info:      db ' 16-bit BIOS route', 0
chain:     db ' MBR->16->PS2 BIOS', 0
prompt:    db ' DNAOS> ', 0

times 256 - ($ - $$) db 0x90
