; DNAOS v3.5 MBR v35 (修 BPB + 装多 head 扇区)
BITS 16
ORG 0x7C00

    jmp short start
    nop

; BPB (BIOS Parameter Block) - 1.44MB 标准
OEMName:        db "DNAOS   "
BytesPerSec:    dw 512
SecPerClus:     db 1
RsvdSecCnt:     dw 1
NumFATs:        db 2
RootEntCnt:     dw 224
TotSec16:       dw 2880         ; 1.44MB = 2880 扇区
Media:          db 0xF8
FATSz16:        dw 9            ; FAT 9 扇区
SecPerTrk:      dw 18           ; 1.44MB 18 扇区/道
NumHeads:       dw 2            ; 1.44MB 2 头
HiddSec:        dd 0
TotSec32:       dd 0
DrvNum:         db 0x80
Reserved1:      db 0
BootSig:        db 0x29
VolID:          dd 0x4F414E44
VolLab:         db "DNAOS v3.5  "
FilSysType:     db "FAT12   "

start:
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    mov [BootDrive], dl

    mov si, msg_boot
    call print_serial

    ; 装多 head 扇区: head 0 装 17 扇区 (sector 2-18) 到 0x10000+, 然后 head 1 装 18 扇区 (sector 1-18 head 1) 到 0x10000+17*512=0x10800
    ; head 0 装
    mov ah, 0x02
    mov al, 17
    mov ch, 0
    mov cl, 2                 ; LBA 1
    mov dh, 0                 ; head 0
    mov dl, [BootDrive]
    mov bx, 0x1000
    mov es, bx
    xor bx, bx
    int 0x13
    jc disk_error

    ; head 1 装
    mov ah, 0x02
    mov al, 18
    mov ch, 0
    mov cl, 1                 ; head 1 起点 sector 1 (CHS head=1, sector=1)
    mov dh, 1                 ; head 1
    mov dl, [BootDrive]
    mov bx, 0x1080            ; 装到 0x10800 (head 0 装完 17 扇区, = 0x10000+0x2200)
    mov es, bx
    xor bx, bx
    int 0x13
    jc disk_error

    ; 串口 'H' (head 1 装 OK)
    mov dx, 0x3F8
    mov al, 'H'
    out dx, al

    jmp 0x1020:0x0000     ; 跳到 k12a 起点 (sector 3 @ 0x10200)

disk_error:
    mov si, msg_err
    call print_serial
    jmp $

print_serial:
    push ax
    push bx
.loop:
    lodsb
    test al, al
    jz .done
    mov dx, 0x3FD
.wait:
    in al, dx
    test al, 0x20
    jz .wait
    mov dx, 0x3F8
    out dx, al
    jmp .loop
.done:
    pop bx
    pop ax
    ret

msg_boot:   db "\r\nDNAOS v3.5 MBR v35\r\n", 0
msg_err:    db "Disk error!\r\n", 0
BootDrive:  db 0

times 510 - ($ - $$) db 0
dw 0xAA55
