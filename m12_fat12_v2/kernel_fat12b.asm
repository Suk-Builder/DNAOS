; ============================================================================
; DNAOS v12b - FAT12 read 简化: hardcode cluster=2, 0x10A00 = sector 19
; ============================================================================
; 简化: 不找文件名, 直接读 sector 19 (root dir) 第一个 entry, 取 cluster
; 然後 cluster 2 = sector 33, 读 0x10A00+0x400-0x10BFF (in mem)
; 等等, 33-1=32, 32*512=0x4000, 0x10000+0x4000=0x12600
; 但 mbr 装 head 1 sector 19-36 (LBA 18-35) 到 0x12600-0x147FF
; sector 33 (LBA 32) = 0x12600+(32-18)*512 = 0x12600+14*512=0x12600+0x1C00=0x12600
; ============================================================================

BITS 16
ORG 0x0000

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    mov dx, 0x3F8
    mov al, 'K'
    out dx, al

    mov ax, 0x0003
    int 0x10

    mov dx, 0x3F8
    mov al, 'M'
    out dx, al

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
    out dx, al

.poll:
    mov ah, 0x01
    int 0x16
    jz .poll

    mov ah, 0x00
    int 0x16

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

    cmp al, 'r'
    jne .poll

    mov dx, 0x3F8
    mov al, '!'
    out dx, al

    ; 简化: 读 root dir @ 0x10800 (mbr 装 head 1 sector 1 = LBA 18 = sector 19)
    mov ax, 0x1080
    mov ds, ax
    mov si, 0x1A           ; cluster 偏移
    lodsw
    mov [cluster], ax       ; cluster=2
    mov si, 0x1C
    lodsw
    mov [file_size], ax
    lodsw
    mov [file_size+2], ax

    ; 串口 'C' (cluster 拿到)
    mov dx, 0x3F8
    mov al, 'C'
    out dx, al

    ; dump 0x12600 (sector 33) 内容 100B
    mov ax, 0x1260
    mov ds, ax

    ; 串口 'Z' (dump start)
    mov dx, 0x3F8
    mov al, 'Z'
    out dx, al
    mov cx, 20                 ; 试 20 字节

    ; 串口 'D' (dump start)
    mov dx, 0x3F8
    mov al, 'D'
    out dx, al

.dump:
    lodsb                     ; al = byte from 0x12600
    push ax                   ; 保存字符
    mov dx, 0x3FD
.duw:
    in al, dx
    test al, 0x20
    jz .duw
    pop ax
    mov dx, 0x3F8
    out dx, al                ; 串口输出字符
    loop .dump

.done:
    mov dx, 0x3F8
    mov al, 'O'
    out dx, al

    xor ax, ax
    mov ds, ax
    jmp .poll

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

banner:    db ' v12b', 0
info:      db ' 16-bit', 0
chain:     db ' r=read', 0
prompt:    db ' DNAOS> ', 0
cluster:  dw 0
file_size: dd 0

times 1024 - ($ - $$) db 0x90
