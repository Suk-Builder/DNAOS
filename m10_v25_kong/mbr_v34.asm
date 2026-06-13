; DNAOS v3.4 MBR (本地版)
BITS 16
ORG 0x7C00

    jmp short start
    nop

OEMName:        db "DNAOS   "
BytesPerSec:    dw 512
SecPerClus:     db 1
RsvdSecCnt:     dw 1
NumFATs:        db 2
RootEntCnt:     dw 224
TotSec16:       dw 128
Media:          db 0xF8
FATSz16:        dw 1
SecPerTrk:      dw 32
NumHeads:       dw 64
HiddSec:        dd 0
TotSec32:       dd 0
DrvNum:         db 0x80
Reserved1:      db 0
BootSig:        db 0x29
VolID:          dd 0x4F414E44
VolLab:         db "DNAOS v3.4  "
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

    mov ah, 0x02
    mov al, 128
    mov ch, 0
    mov cl, 2
    mov dh, 0
    mov dl, [BootDrive]
    mov bx, 0x1000
    mov es, bx
    xor bx, bx
    int 0x13
    jc disk_error

    jmp 0x1000:0x0000

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

msg_boot:   db "\r\nDNAOS v3.4 MBR\r\n", 0
msg_err:    db "Disk error!\r\n", 0
BootDrive:  db 0

times 510 - ($ - $$) db 0
dw 0xAA55
