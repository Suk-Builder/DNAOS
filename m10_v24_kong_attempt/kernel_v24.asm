; DNAOS v24 - 极简 2 命令
BITS 16
ORG 0x0000

SERIAL equ 0x3F8
LSR    equ 0x3FD
PROW   equ 24
PCOL   equ 8
BSZ    equ 24
AG     equ 0x0A
AC     equ 0x09

start:
    xor ax,ax
    mov ds,ax
    mov es,ax
    mov ss,ax
    mov sp,0x7C00
    mov al,'K'
    call pc
    mov ax,0x0003
    int 0x10
    mov al,'M'
    call pc

    mov si,banner
    mov dh,0
    mov bl,AG
    call pl
    mov si,info
    mov dh,2
    mov bl,AG
    call pl
    mov si,prompt
    mov dh,PROW
    mov bl,AC
    call pl
    mov al,'P'
    call pc

ml:
    mov ah,0x02
    mov bh,0
    mov dh,PROW
    mov dl,PCOL
    int 0x10
    mov di,buf
    xor cx,cx
rc:
    mov ah,0x00
    int 0x16
    push ax
    call pc
    pop ax
    cmp al,0x0D
    je cmd
    cmp cx,BSZ-1
    jae rc
    mov [di],al
    inc di
    inc cx
    mov ah,0x0A
    mov bh,0
    mov bl,AG
    mov cx,1
    int 0x10
    mov ah,0x03
    int 0x10
    inc dl
    mov ah,0x02
    int 0x10
    jmp rc
cmd:
    mov byte [di],0
    mov al,0x0A
    call pc
    mov si,buf
    mov di,th
    call sc
    jc do_help
    mov si,buf
    mov di,tv
    call sc
    jc do_ver
    mov si,buf
    call pl2
    jmp ml
do_help:
    mov si,mh
    call pl2
    jmp ml
do_ver:
    mov si,mv
    call pl2
    jmp ml

pc:
    push ax
    push dx
    mov dx,LSR
.w:
    in al,dx
    test al,0x20
    jz .w
    pop dx
    push dx
    mov dx,SERIAL
    out dx,al
    pop dx
    pop ax
    ret
pl:
    push ax
    push bx
    push dx
    mov ah,0x02
    mov bh,0
    mov dl,0
    int 0x10
    push bx
.l:
    lodsb
    test al,al
    jz .d
    mov ah,0x0A
    mov bh,0
    pop bx
    push bx
    mov cx,1
    int 0x10
    mov ah,0x03
    int 0x10
    inc dl
    mov ah,0x02
    int 0x10
    jmp .l
.d:
    pop bx
    pop dx
    pop bx
    pop ax
    ret
pl2:
    push ax
    push bx
    push dx
    mov ah,0x03
    int 0x10
    mov dh,[cr]
    mov dl,0
    mov ah,0x02
    int 0x10
.l2:
    lodsb
    test al,al
    jz .d2
    mov ah,0x0A
    mov bh,0
    mov bl,AG
    mov cx,1
    int 0x10
    mov ah,0x03
    int 0x10
    inc dl
    mov ah,0x02
    int 0x10
    jmp .l2
.d2:
    mov al,[cr]
    inc al
    cmp al,PROW
    jb .o
    xor al,al
.o:
    mov [cr],al
    pop dx
    pop bx
    pop ax
    ret
sc:
    push si
    push di
.c:
    lodsb
    mov ah,[di]
    inc di
    cmp al,ah
    jne .n
    test al,al
    jnz .c
    pop di
    pop si
    stc
    ret
.n:
    pop di
    pop si
    clc
    ret

banner:    db ' DNAOS v3.5 M10 v24',0
info:      db ' help ver',0
prompt:    db ' DNAOS> ',0
th:        db 'help',0
tv:        db 'ver',0
mh:        db 'help ver',0
mv:        db 'v24 16-bit',0
cr:        db 0
buf:       times BSZ db 0

times 512 - ($-$$) db 0x90
