; ============================================================================
; DNAOS v12a - FAT12 read 简化: 不用 INT 13h, 直接用 mbr 装好的内存
; ============================================================================
; mbr 已经把 sector 1-128 装到 0x10000+, 所以:
;   sector 1 @ 0x10000 (kernel, 1024B = 2 sectors, 0x10000-0x103FF)
;   sector 3 @ 0x10400 (FAT #1)
;   sector 12 @ 0x11800 (FAT #2)
;   sector 21 @ 0x12900 (Root Dir, 14 sectors = 0x12900-0x14BFF)
;   sector 35 @ 0x15800 (Data cluster 2, README.TXT)
;
; 直接从 0x12900 找 README.TXT entry, 拿 cluster, 跟 FAT, dump 0x15800 内容
; 16-bit BIOS 路线, 不切 32-bit
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

    ; 找 README.TXT @ 0x12400 (mbr 装好的 root dir: sector 19 @ 0x10000+18*512)
    mov ax, 0x1240
    mov es, ax
    xor di, di

.find:
    mov si, target_name
    mov cx, 11
    push di
    mov si, target_name
    repe cmpsb
    pop di
    je .found
    add di, 32
    cmp di, 14*512
    jb .find
    jmp .not_found

.found:
    ; 拿 cluster (offset 0x1A) 跟 size
    mov ax, es
    mov ds, ax
    mov si, di
    add si, 0x1A
    lodsw
    mov [cluster], ax
    mov si, di
    add si, 0x1C
    lodsw
    mov [file_size], ax
    lodsw
    mov [file_size+2], ax

    ; dump 0x13C00 (sector 35 = 0x10000 + 34*512) 内容到串口
    mov ax, 0x13C0
    mov ds, ax
    xor si, si
    mov cx, 100                ; dump 100B (跟 readme 大小一致)
.dump:
    lodsb
    test al, al
    jz .done
    push cx
    mov dx, 0x3FD
.duw:
    in al, dx
    test al, 0x20
    jz .duw
    mov dx, 0x3F8
    out dx, al
    pop cx
    loop .dump

.done:
    mov dx, 0x3F8
    mov al, 'O'                 ; OK
    out dx, al

    ; 恢复 ds
    xor ax, ax
    mov ds, ax
    jmp .poll

.not_found:
    mov dx, 0x3F8
    mov al, '?'
    out dx, al
    xor ax, ax
    mov ds, ax
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

banner:    db ' v12a FAT12', 0
info:      db ' 16-bit', 0
chain:     db ' r=read README', 0
prompt:    db ' DNAOS> ', 0
target_name: db 'README  TXT'
cluster:  dw 0
file_size: dd 0

times 1024 - ($ - $$) db 0x90
