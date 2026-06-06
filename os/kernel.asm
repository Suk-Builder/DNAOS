; ============================================================================
; DNAOS v3.4 — Kernel (64KB)
; 功能: 16→32→64位模式切换, COM1串口, VGA, 键盘输入
; 加载地址: 0x1000:0x0000 = 物理 0x10000
; ============================================================================

BITS 16
ORG 0x0000                  ; 相对段0x1000的偏移

section .text align=1

; ═══════════════════════════════════════════════════════════════════════════
; 16-bit Entry @ 0x0000 (物理 0x10000)
; ═══════════════════════════════════════════════════════════════════════════
entry_16:
    ; COM1输出 '1\r\n' (确认16位代码运行)
    mov al, '1'
    call serial_send
    mov al, '\r'
    call serial_send
    mov al, '\n'
    call serial_send

    ; Enable A20 (fast gate method)
    in al, 0x92
    or al, 0x02
    out 0x92, al

    ; 关中断
    cli

    ; 加载GDT
    lgdt [gdtr]

    ; 进入保护模式 (CR0.PE = 1)
    mov eax, cr0
    or eax, 1
    mov cr0, eax

    ; 远跳32位 (16位编码的32位far jmp)
    jmp 0x08:entry_32

; ── 16位辅助函数 ──
serial_send:                ; al = 字符
    push dx
    mov dx, 0x3FD           ; LSR
.wait:
    in al, dx
    test al, 0x20
    jz .wait
    mov dx, 0x3F8           ; TX
    pop ax                  ; 恢复al中的字符
    push ax
    out dx, al
    pop dx
    ret

; ── GDT ──
gdtr:
    dw gdt_end - gdt - 1    ; limit
    dd gdt                  ; base (线性地址 = 0x10000 + gdt偏移)

ALIGN 8
gdt:
    ; Null descriptor
    dq 0
.gdt_code:                  ; 0x08 — 32/64位代码段
    dw 0xFFFF               ; limit 15:0
    dw 0x0000               ; base 15:0
    db 0x00                 ; base 23:16
    db 0x9A                 ; P=1, DPL=0, S=1, Type=Execute/Read
    db 0xCF                 ; G=1, DB=1, L=0, limit 19:16=0xF
    db 0x00                 ; base 31:24
.gdt_data:                  ; 0x10 — 数据段
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 0x92                 ; P=1, DPL=0, S=1, Type=Read/Write
    db 0xCF
    db 0x00
gdt_end:

; ═══════════════════════════════════════════════════════════════════════════
; 32-bit Entry @ entry_32 (ORG + 0x200 = 物理 0x10200)
; ═══════════════════════════════════════════════════════════════════════════
ALIGN 512
entry_32:
    BITS 32
    ; 加载数据段选择子
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, 0x00090000     ; 32位栈

    ; COM1输出 '2\r\n' (确认32位代码运行)
    mov al, '2'
    call serial_send_32
    mov al, '\r'
    call serial_send_32
    mov al, '\n'
    call serial_send_32

    ; 设置页表 (identity map 0-4MB, 2MB大页)
    ; PML4 @ ptb, PDPT @ ptb+0x1000, PD @ ptb+0x2000
    mov dword [ptb],       (ptb + 0x1000) | 0x03
    mov dword [ptb+0x1000], (ptb + 0x2000) | 0x03
    mov dword [ptb+0x2000], 0x00000083     ; 0-2MB, PS=1, P=1, R/W=1
    mov dword [ptb+0x2008], 0x00200083     ; 2-4MB

    ; CR3 = 页表基址
    mov eax, ptb
    mov cr3, eax

    ; CR4.PAE = 1
    mov eax, cr4
    or eax, 0x20            ; PAE bit
    mov cr4, eax

    ; EFER.LME = 1 (MSR 0xC0000080, bit 8)
    mov ecx, 0xC0000080
    rdmsr
    or eax, 0x100           ; LME bit 8
    wrmsr

    ; CR0.PG = 1 (PE=1 already → 长模式)
    mov eax, cr0
    or eax, 0x80000000      ; PG bit
    mov cr0, eax

    ; 远跳64位 (兼容模式下用retf trick)
    push dword 0x08         ; CS selector
    push dword entry_64     ; EIP
    retf

; ── 32位辅助函数 ──
serial_send_32:             ; al = 字符
    push edx
    mov edx, 0x3FD
.wait:
    in al, dx
    test al, 0x20
    jz .wait
    mov edx, 0x3F8
    mov ah, al
    pop eax                 ; 恢复al到ah，但al已经被覆盖了...

; 等等，这个有问题。让我换一种写法。
