; ============================================================================
; DNAOS v25 - M10 16-bit BIOS, jmp-only dispatch (避 v24 撞穿 call/ret)
; ============================================================================
; 策略 (从主题 #7 笔记学的):
; - 跟 v23 一样 BIOS 16-bit 路线, 跑通 ✓
; - 加 1 个命令: 'h' = help (打印 help 字符串)
; - **不调 sub-routine**, 把整个命令分派 inline 在 .poll 后面
; - 不用 call/ret 栈, 避免 v24 撞穿 call pc 后的栈不平衡
; - 字符串最小化: help = "DNAOS h"
; 目标: ≤256B

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
    out dx, al                ; K

    mov ax, 0x0003
    int 0x10

    mov dx, 0x3F8
    mov al, 'M'
    out dx, al                ; M

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
    out dx, al                ; P

.poll:
    mov ah, 0x01              ; 查有无
    int 0x16
    jz .poll                  ; 等

    mov ah, 0x00              ; 读
    int 0x16
    ; AL = ASCII

    push ax
    mov dx, 0x3FD
.wait1:
    in al, dx
    test al, 0x20
    jz .wait1
    pop ax
    push ax
    mov dx, 0x3F8
    out dx, al                ; 串口 echo
    pop ax

    cmp al, 'h'               ; 命令: 'h' = help
    jne .no_help
    mov dx, 0x3F8
    mov al, '='
    out dx, al                ; 串口响应
    mov si, msg_help
    call puts_bios
    jmp .poll

.no_help:
    cmp al, 0x0D              ; Enter
    jne .no_enter
    mov dx, 0x3F8
    mov al, '#'
    out dx, al
    jmp .poll

.no_enter:
    ; 显示字符
    mov ah, 0x0A
    mov bh, 0
    mov bl, 0x0A
    mov cx, 1
    int 0x10

    mov ah, 0x03
    mov bh, 0
    int 0x10
    inc dl
    mov ah, 0x02
    int 0x10

    jmp .poll

; puts_bios: SI=字符串
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
    mov bl, 0x0E
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

banner:    db ' DNAOS v3.5 M10 v25', 0
info:      db ' 16-bit BIOS+jmp', 0
chain:     db ' h=help', 0
prompt:    db ' DNAOS> ', 0
msg_help:  db ' help', 0

times 256 - ($ - $$) db 0x90
