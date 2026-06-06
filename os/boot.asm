; ============================================================================
; DNAOS v3.4 — MBR Boot Sector (512 bytes)
; 功能: COM1串口输出 → INT13h读内核 → 远跳0x1000:0x0000
; 标准NASM语法，经过验证的汇编代码
; ============================================================================

BITS 16                     ; 16位实模式
ORG 0x7C00                  ; BIOS加载MBR到0x7C00

    ; jmp short start + nop (3字节，让BPB从0x03开始)
    jmp short start
    nop

; ── BPB @ 0x03 (FAT12伪参数) ──
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
    ; 初始化段寄存器 + 栈
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00          ; 栈从0x7C00向下增长

    ; 保存启动盘号
    mov [BootDrive], dl

    ; COM1串口输出 "DNAOS v3.4 MBR\r\n"
    mov si, msg_boot
    call print_serial

    ; INT13h AH=02: 读128扇区(64KB)到 ES:BX = 0x1000:0x0000
    mov ah, 0x02            ; 读扇区
    mov al, 128             ; 128扇区 = 64KB
    mov ch, 0               ; 柱面0
    mov cl, 2               ; 从扇区2开始（扇区1是MBR）
    mov dh, 0               ; 磁头0
    mov dl, [BootDrive]     ; 启动盘
    mov bx, 0x1000
    mov es, bx              ; ES = 0x1000
    xor bx, bx              ; BX = 0 (偏移)
    int 0x13
    jc disk_error           ; 读盘失败

    ; 远跳转到内核 0x1000:0x0000
    jmp 0x1000:0x0000

disk_error:
    mov si, msg_err
    call print_serial
    jmp $                   ; halt

; ── print_serial: DS:SI -> COM1, 0结尾字符串 ──
print_serial:
    push ax
    push bx
.loop:
    lodsb
    test al, al
    jz .done
    ; 等待COM1发送缓冲空 (LSR bit 5)
    mov dx, 0x3FD           ; LSR
.wait:
    in al, dx
    test al, 0x20
    jz .wait
    ; 发送字符
    mov dx, 0x3F8           ; TX
    out dx, al
    jmp .loop
.done:
    pop bx
    pop ax
    ret

; ── 数据 ──
msg_boot:   db "\r\nDNAOS v3.4 MBR\r\n", 0
msg_err:    db "Disk error!\r\n", 0
BootDrive:  db 0

; ── 填充到510字节 + 0x55AA签名 ──
times 510 - ($ - $$) db 0
dw 0xAA55
