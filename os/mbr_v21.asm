; mbr_v21.asm — read 9 sectors (k16 + k32 = 4608B = 9 sectors)
BITS 16
org 0x7C00

start:
    mov ax, 0
    mov ds, ax
    mov ss, ax
    mov sp, 0x7C00

    ; 写 'L' 到串口
    mov dx, 0x3F8
    mov al, 'L'
    out dx, al

    ; 重置软盘
    mov ah, 0x00
    mov dl, [0x7C00 + 0x80]
    test dl, dl
    jnz .d_ok
    mov dl, 0x80
.d_ok:
    int 0x13

    ; 读 9 sectors from sector 2 to 0x10000
    ; 10-retry 循环
    mov si, 10
.retry:
    push si
    mov bx, 0x1000
    mov es, bx
    xor bx, bx                ; ES:BX = 0x10000
    mov ah, 0x02
    mov al, 9                  ; 9 sectors
    mov ch, 0
    mov cl, 2                  ; sector 2
    mov dh, 0
    mov dl, [0x7C00 + 0x80]
    test dl, dl
    jnz .disk_ok
    mov dl, 0x80
.disk_ok:
    int 0x13
    pop si
    jnc .read_ok
    dec si
    jnz .retry
    ; 全失败, 写 'X' halt
    mov al, 'X'
    mov dx, 0x3F8
    out dx, al
    cli
    hlt

.read_ok:
    ; 写 '1' 表示 read_ok
    mov al, '1'
    mov dx, 0x3F8
    out dx, al

    ; 切到保护模式 (用 0x10076 的 GDT, 由 k16 设的, 在我们读的 kernel 内部)
    cli
    lgdt [gdtr]
    mov eax, cr0
    or eax, 1
    mov cr0, eax

    ; 32-bit far jmp 到 0x08:0x10100 (entry_32)
    db 0x66                    ; 32-bit 寻址前缀
    db 0xEA                    ; far jmp
    dd 0x00010100              ; 32-bit offset
    dw 0x0008                  ; CS selector

halt:
    hlt
    jmp halt

; GDTR (patched at build time with physical address of GDT in kernel)
ALIGN 4
gdtr:
    dw 0x0017                  ; limit = 0x17 = 23 (4 entries - 1)
    dd 0x00010076              ; GDT 物理地址 (patched in build_v21.sh)

times 510 - ($-start) db 0
db 0x55, 0xAA
