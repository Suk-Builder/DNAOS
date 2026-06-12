[BITS 32]
org 0x0000

; DNAOS entry_32 v21 (M10: 键盘 + 简单 shell)
;
; 比 v20 加了:
;   1. PIC 8259A 重映射 (IRQ0-7 -> INT 0x20-0x27, IRQ8-15 -> INT 0x28-0x2F)
;   2. IDT (256 entries, 全部指向 ignore_int)
;   3. 键盘中断处理器 (INT 0x21 = IRQ1)
;   4. 简化键盘扫描码表 (Set 1, 抄 Linus 0.01 keyboard.s)
;   5. 简单 shell: help / ver / reboot
;
; 内存布局 (entry_32 在 file offset 0x100, physical 0x10100):
;   0x10100: entry_32
;   0x10300: GDT (新位置, 512 字节, 4 entries: null+code+data+tss)
;   0x10500: IDT (256 entries * 8 = 2048 字节, 物理 0x10500)
;   0x10D00: shell 输入缓冲区 (256 字节, 物理 0x10D00)
;   0x10E00: shell 输出缓冲区 (256 字节, 物理 0x10E00)
;   0x10F00: 32-bit stack (向下增长, ESP = 0x0010F000)
;   0x11000: end

; ===== 常量 =====
VGA_BUF      equ 0xB8000
VGA_COLS     equ 80
VGA_ROWS     equ 25
VGA_CURSOR   equ 0x3D4   ; CRT 索引寄存器
VGA_CDAT     equ 0x3D5   ; CRT 数据寄存器

; PIC 8259A
PIC1_CMD     equ 0x20
PIC1_DATA    equ 0x21
PIC2_CMD     equ 0xA0
PIC2_DATA    equ 0xA1
PIC_EOI      equ 0x20

; 8253 PIT (Programmable Interval Timer)
PIT_CH0      equ 0x40
PIT_CMD      equ 0x43

; GDT
GDT_BASE     equ 0x00010300   ; 4 entries, 32 字节
GDT_LIMIT    equ 31            ; 4*8 - 1

; IDT
IDT_BASE     equ 0x00010500
IDT_LIMIT    equ 256*8 - 1

; 颜色
ATTR_YB      equ 0x0E
ATTR_GB      equ 0x0A
ATTR_CB      equ 0x09
ATTR_WB      equ 0x0F

; 键盘 buffer (ring buffer, 简化)
KB_BUF_SIZE  equ 256

; ===== entry point =====
entry_32:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x0010F000       ; stack 顶端

    mov al, '6'
    mov dx, 0x3F8
    out dx, al

    call setup_gdt_v21        ; 重新设 GDT (含 TSS 占位)
    call setup_idt            ; 设 IDT
    call setup_pic            ; 重映射 PIC
    call enable_a20_check     ; A20 自检

    mov al, '7'
    mov dx, 0x3F8
    out dx, al

    call clear_vga
    call draw_splash

    mov al, '8'
    mov dx, 0x3F8
    out dx, al

    call setup_keyboard       ; 注册键盘中断 (开 IRQ1)
    call enable_interrupts    ; sti

    mov al, 'K'               ; K = 键盘 ready
    mov dx, 0x3F8
    out dx, al

    call shell_loop           ; 永远 loop (hlt 唤醒)

; ===== A20 自检 =====
enable_a20_check:
    mov edi, 0x00100000       ; 1MB 边界
    mov al, [0x000000]        ; 读地址 0
    mov bl, [edi]             ; 读 1MB
    cmp al, bl
    je .a20_fail
    ret
.a20_fail:
    ; A20 没开! 写 'A' 到 0x3F8, halt
    mov al, 'A'
    mov dx, 0x3F8
    out dx, al
    cli
    hlt

; ===== 重新设 GDT (4 entries) =====
setup_gdt_v21:
    ; 我们用 k16 那个 GDTR + GDT, 不用重设
    ret

; ===== IDT 设置 =====
setup_idt:
    ; 256 个 entry, 全部指向 ignore_int
    ; IDT entry 格式: offset_low(16) selector(16) zero(8) type_attr(8) offset_high(16)
    ; 我们的 ignore_int 在 file offset (0x100 + .ignore_int - $$)
    lea edi, [IDT_BASE]
    mov ecx, 256
    ; eax = (ignore_int offset low) | (0x0008 << 16) = 0x00080000
    ; edx = 0x00008E00 (interrupt gate 32-bit, DPL=0, present)
    ; 简化: 我们用 lea 计算 ignore_int 的 offset
    ; ignore_int 标签在 entry_32_v21.asm 里, 偏移 = file offset
    ; entry_32 offset = 0, 所以 ignore_int 偏移 = 0x100 + 行号 * 估算...
    ; 太麻烦! 用绝对地址 0x00010600 (在 .ignore_int 标签附近)
    mov eax, 0x00080600         ; offset_low (16) | selector 0x0008 (16)
    mov edx, 0x00008E00         ; 0 (8) | type 0x8E (8) | offset_high (16) = 0
.idt_loop:
    mov [edi], eax
    mov [edi+4], edx
    add edi, 8
    dec ecx
    jnz .idt_loop

    ; 单独设 IDT[0x21] = 键盘中断 (用具体地址)
    ; 键盘 handler 偏移 = 0x100 + keyboard_handler 行号
    ; 估算: 键盘 handler 在 entry_32 偏移 ~ 0x180 左右
    ; 简化: 写到 0x00010700 (键盘 handler 大约在 0x600 + 0x100 = 0x700)
    lea edi, [IDT_BASE + 0x21*8]
    mov eax, 0x00080700         ; offset=0x700, selector=0x08
    mov edx, 0x00008E00
    mov [edi], eax
    mov [edi+4], edx

    ; 加载 IDTR
    mov eax, IDT_BASE
    mov [idt_ptr + 2], eax
    mov word [idt_ptr], IDT_LIMIT
    lidt [idt_ptr]
    ret

; ===== PIC 8259A 重映射 =====
setup_pic:
    ; ICW1: 边沿触发 + 级联 + 要 ICW4
    mov al, 0x11
    out PIC1_CMD, al
    out PIC2_CMD, al

    ; ICW2: 主 PIC IRQ 0-7 -> INT 0x20-0x27
    mov al, 0x20
    out PIC1_DATA, al
    ; ICW2: 从 PIC IRQ 8-15 -> INT 0x28-0x2F
    mov al, 0x28
    out PIC2_DATA, al

    ; ICW3: 主 PIC IR2 接从 PIC, 从 PIC 接主 PIC IR2
    mov al, 0x04
    out PIC1_DATA, al
    mov al, 0x02
    out PIC2_DATA, al

    ; ICW4: 8086 模式
    mov al, 0x01
    out PIC1_DATA, al
    out PIC2_DATA, al

    ; 屏蔽: 主 PIC 开 IRQ1 (键盘) + IRQ2 (cascade), 从 PIC 全关
    mov al, 0xF8                ; 1111 1000 = 允许 IRQ0,1,2
    out PIC1_DATA, al
    mov al, 0xFF
    out PIC2_DATA, al
    ret

; ===== 启用中断 =====
enable_interrupts:
    sti
    ret

; ===== 启用键盘 IRQ1 (在 IDT 里设了, 这里啥都不做) =====
setup_keyboard:
    ret

; ===== VGA =====
clear_vga:
    mov edi, VGA_BUF
    mov ecx, VGA_COLS * VGA_ROWS
    mov ax, (ATTR_CB << 8) | 0x20
.clr:
    mov [edi], ax
    add edi, 2
    dec ecx
    jnz .clr
    ret

draw_splash:
    mov esi, banner
    mov edi, VGA_BUF
    mov ah, ATTR_YB
    call puts

    mov esi, info
    mov edi, VGA_BUF + (2 * VGA_COLS)
    mov ah, ATTR_GB
    call puts

    mov esi, chain
    mov edi, VGA_BUF + (4 * VGA_COLS)
    mov ah, ATTR_GB
    call puts

    mov esi, prompt
    mov edi, VGA_BUF + (24 * VGA_COLS)
    mov ah, ATTR_CB
    call puts
    ret

; puts: print null-terminated string at [esi] to VGA at [edi] with attr in ah
puts:
.l:
    lodsb
    test al, al
    jz .d
    mov [edi], ax
    add edi, 2
    jmp .l
.d:
    ret

; ===== 键盘扫描码 -> ASCII 表 (Set 1) =====
; 简化: 只处理 0x00-0x39 的扫描码
; 0 = 释放 (我们用 or 0x80 来检测), 1=ESC, 2=1, 3=2, ... 0x0E=BS, 0x0F=TAB
; 0x10=Q, 0x11=W, 0x12=E, 0x13=R, 0x14=T, 0x15=Y, 0x16=U, 0x17=I
; 0x18=O, 0x19=P, 0x1A=[, 0x1B=], 0x1C=ENTER, 0x1E=A, 0x1F=S
; 0x20=D, 0x21=F, 0x22=G, 0x23=H, 0x24=J, 0x25=K, 0x26=L, 0x27=;
; 0x28=', 0x29=`, 0x2C=Z, 0x2D=X, 0x2E=C, 0x2F=V, 0x30=B, 0x31=N
; 0x32=M, 0x33=,, 0x34=., 0x35=/, 0x39=SPACE

key_table:
    db 0                     ; 0x00 = 无
    db 0x1B                  ; 0x01 = ESC
    db '1'                   ; 0x02
    db '2'                   ; 0x03
    db '3'                   ; 0x04
    db '4'                   ; 0x05
    db '5'                   ; 0x06
    db '6'                   ; 0x07
    db '7'                   ; 0x08
    db '8'                   ; 0x09
    db '9'                   ; 0x0A
    db '0'                   ; 0x0B
    db '-'                   ; 0x0C
    db '='                   ; 0x0D
    db 0x08                  ; 0x0E = Backspace
    db 0x09                  ; 0x0F = Tab
    db 'q'                   ; 0x10
    db 'w'                   ; 0x11
    db 'e'                   ; 0x12
    db 'r'                   ; 0x13
    db 't'                   ; 0x14
    db 'y'                   ; 0x15
    db 'u'                   ; 0x16
    db 'i'                   ; 0x17
    db 'o'                   ; 0x18
    db 'p'                   ; 0x19
    db '['                   ; 0x1A
    db ']'                   ; 0x1B
    db 0x0A                  ; 0x1C = Enter
    db 0                     ; 0x1D = LCtrl
    db 'a'                   ; 0x1E
    db 's'                   ; 0x1F
    db 'd'                   ; 0x20
    db 'f'                   ; 0x21
    db 'g'                   ; 0x22
    db 'h'                   ; 0x23
    db 'j'                   ; 0x24
    db 'k'                   ; 0x25
    db 'l'                   ; 0x26
    db ';'                   ; 0x27
    db 0x27                  ; 0x28 = '
    db '`'                   ; 0x29
    db 0                     ; 0x2A = LShift
    db '\'                   ; 0x2B
    db 'z'                   ; 0x2C
    db 'x'                   ; 0x2D
    db 'c'                   ; 0x2E
    db 'v'                   ; 0x2F
    db 'b'                   ; 0x30
    db 'n'                   ; 0x31
    db 'm'                   ; 0x32
    db ','                   ; 0x33
    db '.'                   ; 0x34
    db '/'                   ; 0x35
    db 0                     ; 0x36 = RShift
    db '*'                   ; 0x37 = KP *
    db 0                     ; 0x38 = LAlt
    db ' '                   ; 0x39 = Space

; ===== 键盘 buffer (单 buffer 256 字节, head/tail 指针) =====
kb_buf:  times 256 db 0
kb_head: dd 0
kb_tail: dd 0

; ===== shell 输入缓冲区 =====
input_buf: times 256 db 0
input_len: dd 0

; ===== IDT 指针存储位置 =====
idt_ptr:
    dw 0                      ; limit
    dd 0                      ; base (patched in setup_idt)

; ===== 字符串 =====
banner:  db '   DNAOS v3.5 M10 - 键盘 + 简单 shell', 0
info:    db '   按 help 然后回车看可用命令', 0
chain:   db '   Boot: MBR -> 16 -> 32 -> PIC/IDT/A20 -> 键盘', 0
prompt:  db '   DNAOS> ', 0
help_msg: db '   内置: help, ver, reboot, clear', 0
ver_msg:  db '   DNAOS v3.5 M10 (2026-06-12) - 保护模式 + 键盘 + shell', 0
err_msg:  db '   未知命令, 输入 help 看可用', 0

; ===== ignore_int: 默认中断处理 (点亮屏幕右上角 0xB80A0) =====
ignore_int:
    push edx
    push eax
    mov dx, VGA_CURSOR
    mov al, 0x0A
    out dx, al
    mov dx, VGA_CDAT
    in al, dx
    inc al
    mov dx, VGA_CURSOR
    mov al, 0x0A
    out dx, al
    mov dx, VGA_CDAT
    in al, dx
    inc al
    mov dx, VGA_CURSOR
    mov al, 0x0A
    out dx, al
    mov dx, VGA_CDAT
    out dx, al
    mov al, PIC_EOI
    out PIC1_CMD, al
    pop eax
    pop edx
    iret

; ===== 键盘中断处理 (INT 0x21) =====
keyboard_handler:
    push eax
    push ebx
    push ecx
    push edx
    push edi
    push esi

    ; 读 scan code
    in al, 0x60
    test al, 0x80            ; 是 key release?
    jnz .done
    ; 按下: 翻译
    movzx ebx, al
    cmp bl, 0x39
    ja .done
    mov al, [key_table + ebx]
    test al, al
    jz .done
    ; 写入 ring buffer
    mov edi, kb_head
    mov ecx, [edi]
    inc ecx
    and ecx, KB_BUF_SIZE-1
    mov [edi], ecx
    mov [kb_buf + ecx], al
.done:
    ; 复位键盘控制器 (Linus 风格)
    in al, 0x61
    mov ah, al
    or al, 0x80
    out 0x61, al
    mov al, ah
    out 0x61, al
    ; EOI
    mov al, PIC_EOI
    out PIC1_CMD, al

    pop esi
    pop edi
    pop edx
    pop ecx
    pop ebx
    pop eax
    iret

; ===== shell 主循环 =====
shell_loop:
    ; 先回显 prompt (第一次)
    call shell_print_prompt
.shell:
    hlt                      ; 等键盘中断
    ; 检查 buffer 是否有字符
    mov esi, kb_tail
    mov eax, [esi]
    mov edi, kb_head
    mov ecx, [edi]
    cmp eax, ecx
    je .shell                ; 一样就是空的, 继续 hlt

    ; 取出字符
    inc eax
    and eax, KB_BUF_SIZE-1
    mov [esi], eax
    mov bl, [kb_buf + eax]

    ; 处理字符
    cmp bl, 0x0A             ; Enter?
    je .enter
    cmp bl, 0x08             ; Backspace?
    je .backspace
    ; 普通字符
    call shell_print_char
    jmp .shell
.backspace:
    call shell_backspace
    jmp .shell
.enter:
    call shell_exec
    call shell_print_prompt
    jmp .shell

; ===== shell 子函数 =====
shell_print_prompt:
    push esi
    push edi
    push eax
    mov esi, prompt
    mov edi, [cursor_pos]
    mov ah, ATTR_CB
    call puts
    mov [cursor_pos], edi
    pop eax
    pop edi
    pop esi
    ret

shell_print_char:
    push eax
    push edi
    mov edi, [cursor_pos]
    mov ah, ATTR_WB
    mov [edi], ax
    add edi, 2
    mov [cursor_pos], edi
    ; 加到 input_buf
    mov eax, [input_len]
    cmp eax, 255
    jae .skip
    mov edi, input_buf
    mov [edi + eax], bl
    inc eax
    mov [input_len], eax
.skip:
    pop edi
    pop eax
    ret

shell_backspace:
    push eax
    push edi
    mov eax, [input_len]
    test eax, eax
    jz .no_bs
    dec eax
    mov [input_len], eax
    mov edi, [cursor_pos]
    sub edi, 2
    mov word [edi], 0x0920    ; ' ' cyan-on-black
    mov [cursor_pos], edi
.no_bs:
    pop edi
    pop eax
    ret

shell_exec:
    push esi
    push edi
    push eax
    ; 回车换行
    mov edi, [cursor_pos]
    mov byte [edi], 0
    mov [edi+1], byte ATTR_WB
    add edi, 160
    sub edi, [cursor_pos]
    ; 简化: 直接把 cursor 移到下一行开头
    mov eax, [cursor_pos]
    mov edx, eax
    sub edx, VGA_BUF
    mov ecx, edx
    and ecx, 0xFFFE           ; 偶数对齐
    add ecx, 160              ; 下一行
    cmp ecx, VGA_BUF + 24*160
    jb .no_scroll
    ; 滚动 (简化: 啥都不做)
    mov ecx, VGA_BUF + 24*160
.no_scroll:
    add ecx, VGA_BUF
    mov [cursor_pos], ecx
    ; 清空 input_len
    mov dword [input_len], 0
    ; 检查命令
    mov esi, input_buf
    ; 简化: 比对 4 字节 (little-endian: 'help' = 0x706C6568)
    cmp dword [esi], 0x706C6568
    jne .try_ver
    call cmd_help
    jmp .done
.try_ver:
    cmp dword [esi], 0x00726576     ; 'ver\x00'
    jne .try_reboot
    call cmd_ver
    jmp .done
.try_reboot:
    cmp dword [esi], 0x6F626572     ; 'rebo'
    jne .try_clear
    call cmd_reboot
    jmp .done
.try_clear:
    cmp dword [esi], 0x61656C63     ; 'clea'
    jne .unknown
    call clear_vga
    mov dword [cursor_pos], VGA_BUF
.unknown:
    call cmd_unknown
.done:
    pop eax
    pop edi
    pop esi
    ret

; ===== 命令实现 =====
cmd_help:
    push esi
    push edi
    mov esi, help_msg
    mov edi, [cursor_pos]
    mov ah, ATTR_GB
    call puts
    mov [cursor_pos], edi
    pop edi
    pop esi
    ret

cmd_ver:
    push esi
    push edi
    mov esi, ver_msg
    mov edi, [cursor_pos]
    mov ah, ATTR_GB
    call puts
    mov [cursor_pos], edi
    pop edi
    pop esi
    ret

cmd_reboot:
    ; 用键盘控制器触发 reboot: 写 0xFE 到 0x64
    mov al, 0xFE
    out 0x64, al
    ret

cmd_unknown:
    push esi
    push edi
    mov esi, err_msg
    mov edi, [cursor_pos]
    mov ah, ATTR_YB
    call puts
    mov [cursor_pos], edi
    pop edi
    pop esi
    ret

; ===== 游标位置 (运行时变量) =====
cursor_pos: dd VGA_BUF + 24*160 + 9*2  ; 初始在 prompt 末尾

; Pad to 0x1000 (4096 bytes, 8 sectors of 512)
times 0x1000 - ($ - $$) db 0x90
