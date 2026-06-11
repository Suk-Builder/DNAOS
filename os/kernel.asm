; ============================================================================
; DNAOS v3.5 — Kernel
; 功能: 32位保护模式Shell, BIOS键盘输入, VGA文本输出
; 加载地址: 0x10000 (物理), 入口 entry_32 (kernel+0x200)
; ============================================================================

BITS 16
ORG 0x0000

section .text align=1

; ═══════════════════════════════════════════════════════════════════════════
; 16-bit Entry @ entry_16 (物理 0x10000)
; ═══════════════════════════════════════════════════════════════════════════
entry_16:
    ptb EQU 0x11000

    ; 输出 '1' 确认16位代码运行
    mov al, '1'
    db 0x9A, 0x7E, 0x00, 0x08, 0x00  ; far call serial_send (0x08:0x007E)
    mov al, '\r'
    db 0x9A, 0x7E, 0x00, 0x08, 0x00
    mov al, '\n'
    db 0x9A, 0x7E, 0x00, 0x08, 0x00

    ; Enable A20
    in al, 0x92
    or al, 0x02
    out 0x92, al

    cli

    ; Load GDT (kernel GDT at 0x10048)
    lgdt [gdtr]

    ; CR0.PE = 1 → Protected Mode
    mov eax, cr0
    or eax, 1
    mov cr0, eax

    ; Far jump to entry_32 (selector 0x08, offset = entry_32 - kernel_base)
    ; With CS.base=0x00010000: target = 0x00010000 + 0x0200 = 0x10200
    jmp 0x08:entry_32

; ── 16位串口发送 (BIOS INT 10h 方式) ──
serial_send:                ; al = 字符
    push dx
    mov ah, 0x0E            ; BIOS teletype output
    int 0x10
    pop dx
    ret

; ═══════════════════════════════════════════════════════════════════════════
; GDT — 扁平模型，base=0x00010000 (kernel load address)
;   Selector 0x08: Code  — base=0x00010000, limit=8MB
;   Selector 0x10: Data  — base=0x00010000, limit=8MB
; ═══════════════════════════════════════════════════════════════════════════
gdtr:
    dw gdt_end - gdt - 1
    db 0x48, 0x00, 0x01, 0x00  ; base = 0x00010048 (physical GDT addr)

ALIGN 8
gdt:
    dq 0
.gdt_code:                  ; 0x08 — code segment
    dw 0x07FF               ; limit 15:0 = 2047
    dw 0x0000               ; base 15:0 = 0x0000
    db 0x00                 ; base 23:16 = 0x00
    db 0x9A                 ; P=1, DPL=0, Type=Execute/Read
    db 0x00C0               ; G=1, DB=1, limit 19:16=0xF
    db 0x01                 ; base 31:24 = 0x01 → base=0x00010000
.gdt_data:                  ; 0x10 — data segment
    dw 0x07FF
    dw 0x0000
    db 0x00
    db 0x92                 ; P=1, DPL=0, Type=Read/Write
    db 0x00C0
    db 0x01                 ; base 31:24 = 0x01 → base=0x00010000
gdt_end:

; ═══════════════════════════════════════════════════════════════════════════
; 32-bit Entry @ entry_32 (kernel+0x200 = physical 0x10200)
; 执行: 设置段寄存器 → 打印欢迎 → 运行Shell
; ═══════════════════════════════════════════════════════════════════════════
ALIGN 512
entry_32:
    BITS 32

    ; 设置扁平段寄存器
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, 0x00090000     ; 栈顶

    ; 输出 '\r\n' 确认进入32位模式
    mov al, '\r'
    call serial_send_32
    mov al, '\n'
    call serial_send_32

    ; 打印欢迎信息
    push entry_32_msg
    call print_string_32
    add esp, 4

    ; 输出提示符
    push prompt_msg
    call print_string_32
    add esp, 4

    ; ═══ Shell 主循环 ═══
shell_loop:
    ; 读取键盘字符 (INT 16h AH=00h → AL=ASCII)
    xor ah, ah
    int 0x16
    ; AL = ASCII, AH = 扫描码

    ; 忽略控制字符 (< 0x20，除了 CR/LF/BS)
    cmp al, 0x08             ; Backspace
    je .backspace
    cmp al, 0x0D             ; Enter
    je .enter
    cmp al, 0x00             ; 扫描码扩展 (方向键等)
    je shell_loop
    cmp al, 0x1B             ; ESC
    je .enter
    cmp al, 0x20
    jb shell_loop            ; 忽略 < 0x20

    ; 显示字符
    push eax                ; 保存 AX
    movzx eax, al
    call putchar_32
    pop eax

    ; 存入输入缓冲
    push edi
    mov edi, input_buf
    add edi, [buf_len]
    mov byte [edi], al
    inc dword [buf_len]
    pop edi

    jmp shell_loop

.backspace:
    cmp dword [buf_len], 0
    je shell_loop
    dec dword [buf_len]
    mov al, '\b'
    call putchar_32
    mov al, ' '
    call putchar_32
    mov al, '\b'
    call putchar_32
    jmp shell_loop

.enter:
    mov al, '\r'
    call putchar_32
    mov al, '\n'
    call putchar_32

    ; 处理命令
    push input_buf
    call process_command_32
    add esp, 4

    ; 清空缓冲区
    mov dword [buf_len], 0

    ; 打印提示符
    push prompt_msg
    call print_string_32
    add esp, 4

    jmp shell_loop

; ═══════════════════════════════════════════════════════════════════════════
; 32位辅助函数
; ═══════════════════════════════════════════════════════════════════════════

; 串口发送 (直接I/O)
serial_send_32:
    push ebx
    mov bl, al               ; 保存字符
.wait:
    in al, dx
    test al, 0x20
    jz .wait
    mov al, bl
    mov dx, 0x3F8
    out dx, al
    pop ebx
    ret

; 显示字符 AL
putchar_32:
    push eax
    movzx eax, al
    mov ah, 0x0E
    int 0x10
    pop eax
    ret

; 打印以NULL结尾的字符串 (指针在栈上)
print_string_32:
    push ebp
    mov ebp, esp
    push esi
    mov esi, [ebp+8]         ; 字符串指针
.loop:
    lodsb
    test al, al
    jz .done
    push eax
    movzx eax, al
    mov ah, 0x0E
    int 0x10
    pop eax
    jmp .loop
.done:
    pop esi
    pop ebp
    ret

; 处理命令 (指针在栈上)
process_command_32:
    push ebp
    mov ebp, esp
    push edi
    push esi
    mov esi, [ebp+8]         ; 命令字符串
    mov edi, cmd_help
    mov ecx, 4
    repe cmpsb
    jne .not_help
    push help_msg
    call print_string_32
    add esp, 4
    jmp .done_cmd
.not_help:
    mov esi, [ebp+8]
    mov edi, cmd_reboot
    mov ecx, 6
    repe cmpsb
    jne .not_reboot
    ; 软重启
    mov al, 'R'
    call putchar_32
    mov al, '\r'
    call putchar_32
    mov al, '\n'
    call putchar_32
    ; 使用 BIOS reset
    mov ax, 0xFFFF
    jmp ax
.not_reboot:
    mov esi, [ebp+8]
    mov edi, cmd_version
    mov ecx, 3
    repe cmpsb
    jne .not_version
    push version_msg
    call print_string_32
    add esp, 4
    jmp .done_cmd
.not_version:
    ; 未知命令
    push unknown_msg
    call print_string_32
    add esp, 4
.done_cmd:
    pop esi
    pop edi
    pop ebp
    ret

; ═══════════════════════════════════════════════════════════════════════════
; 数据
; ═══════════════════════════════════════════════════════════════════════════
entry_32_msg:
    db 'DNAOS v3.5 - 32-bit Protected Mode', 0

prompt_msg:
    db 'DNAOS> ', 0

help_msg:
    db 'Commands: help  version  reboot', 0

version_msg:
    db 'DNAOS v3.5 kernel - (c) 2026 Builder-System', 0

unknown_msg:
    db 'Unknown command. Type "help" for commands.', 0

cmd_help:
    db 'help'
cmd_reboot:
    db 'reboot'
cmd_version:
    db 'ver'

; 输入缓冲区
input_buf:
    times 64 db 0
buf_len:
    dd 0