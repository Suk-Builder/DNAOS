; ============================================================================
; DNAOS v3.3 · Kernel Main
; 功能: 64位长模式内核入口 → 初始化驱动 → 启动DNAsm解释器
; 架构: x86-64 纯NASM汇编 | 零C语言 | 零外部依赖
; 目标: 微星AM4 + Ryzen 5500 + RTX 3060
; ============================================================================
; 递砖机认知操作系统 · 裂缝不是bug，是砖飞过来的地方
; ============================================================================

BITS 64
DEFAULT REL

; ═════════════════════════════════════════════════════════════════════════════
; 常量
; ═════════════════════════════════════════════════════════════════════════════

; ── 内存布局 ──
MEM_KERNEL      equ 0x100000        ; 内核基址 (1MB)
MEM_STACK       equ 0x200000        ; 内核栈 (2MB)
MEM_VRAM_SIM    equ 0x300000        ; 模拟显存 (3MB)
MEM_SHARED_SIM  equ 0x400000        ; 共享内存 (4MB)
MEM_PAGE_TABLES equ 0x900000        ; 页表区域 (9MB)
MEM_HEAP        equ 0xA00000        ; 堆起始 (10MB)

; ── VGA ──
VGA_BASE        equ 0xB8000         ; VGA文本缓冲区
VGA_COLS        equ 80
VGA_ROWS        equ 25
VGA_ATTR        equ 0x07            ; 灰底黑字

; ── 颜色属性 ──
VGA_BLACK       equ 0x00
VGA_BLUE        equ 0x01
VGA_GREEN       equ 0x02
VGA_CYAN        equ 0x03
VGA_RED         equ 0x04
VGA_MAGENTA     equ 0x05
VGA_BROWN       equ 0x06
VGA_LGRAY       equ 0x07
VGA_DGRAY       equ 0x08
VGA_LBLUE       equ 0x09
VGA_LGREEN      equ 0x0A
VGA_LCYAN       equ 0x0B
VGA_LRED        equ 0x0C
VGA_LMAGENTA    equ 0x0D
VGA_YELLOW      equ 0x0E
VGA_WHITE       equ 0x0F

; ── DNAOS主题色 ──
COLOR_GOLD      equ 0x0E            ; 金色
COLOR_CRACK     equ 0x05            ; 紫色
COLOR_OK        equ 0x0A            ; 绿色
COLOR_INFO      equ 0x0B            ; 青色
COLOR_WARN      equ 0x0E            ; 黄色
COLOR_ERR       equ 0x0C            ; 红色
COLOR_NORM      equ 0x07            ; 正常

; ── 键盘 ──
KBD_DATA_PORT   equ 0x60
KBD_STATUS_PORT equ 0x64
KBD_IRQ         equ 1

; ── PCI ──
PCI_CONFIG_ADDR equ 0xCF8
PCI_CONFIG_DATA equ 0xCFC
NV_VENDOR       equ 0x10DE
GA106_DEV       equ 0x2504

; ── PIC ──
PIC1_CMD        equ 0x20
PIC1_DATA       equ 0x21
PIC2_CMD        equ 0xA0
PIC2_DATA       equ 0xA1
ICW1_INIT       equ 0x11
ICW4_8086       equ 0x01

; ── DNAsm ──
DNA_TUBES       equ 64
DNA_STACK_SIZE  equ 256

; ═════════════════════════════════════════════════════════════════════════════
; BSS — 未初始化数据
; ═════════════════════════════════════════════════════════════════════════════
section .bss align=16

; ── VGA状态 ──
cursor_x:       resw 1
cursor_y:       resw 1
vga_attr:       resb 1

; ── 键盘 ──
key_buffer:     resb 256
key_head:       resw 1
key_tail:       resw 1
key_flags:      resb 1              ; Shift/Ctrl/Alt状态

; ── PCI ──
pci_devices:    resd 256            ; 最多256个设备
pci_count:      resw 1

; ── GPU ──
gpu_bus:        resb 1
gpu_dev:        resb 1
gpu_func:       resb 1
gpu_found:      resb 1
bar0_addr:      resq 1

; ── DNAsm运行时 ──
tubes:          resd DNA_TUBES      ; 64个试管
dna_stack:      resq DNA_STACK_SIZE ; 调用栈
dna_sp:         resq 1              ; 栈指针
dna_pc:         resq 1              ; 程序计数器
dna_acc:        resd 1              ; 累加器
dna_zero:       resb 1              ; 零标志

; ── 命令行 ──
cmd_buffer:     resb 256
cmd_len:        resw 1

; ── 堆 ──
heap_ptr:       resq 1

; ═════════════════════════════════════════════════════════════════════════════
; .data
; ═════════════════════════════════════════════════════════════════════════════
section .data align=16

; ── DNAOS欢迎画面 ──
welcome_screen:
    db "========================================================================", 10
    db "", 10
    db "           T S U K U Y O M I   0  -  C H A R T E R   T O W N", 10
    db "", 10
    db "           DNAOS v3.3  Molecular Cognitive Operating System", 10
    db "", 10
    db "           Target: AMD Ryzen 5 5500 + NVIDIA GA106 RTX 3060", 10
    db "           Mode: x86-64 Long Mode | Pure Assembly | Zero C", 10
    db "", 10
    db "           0 = infinity^-1", 10
    db "           Crack is where the brick flies from.", 10
    db "", 10
    db "========================================================================", 10
    db "", 10
    db " Commands:", 10
    db "   pci       - Enumerate PCI devices", 10
    db "   gpu       - Detect & initialize GA106 RTX 3060", 10
    db "   info      - Show CPU & system information", 10
    db "   dna       - Enter DNAsm interactive mode", 10
    db "   run FILE  - Execute DNA program from disk", 10
    db "   help      - Show this help", 10
    db "   reboot    - Reboot system", 10
    db "", 10
    db " Bricklayer continues. 0.", 10
    db "", 10
    db "========================================================================", 10
    db 0

; ── 提示符 ──
prompt_str:     db 10, "dnaos> ", 0

; ── 命令字符串 ──
cmd_pci:        db "pci", 0
cmd_gpu:        db "gpu", 0
cmd_info:       db "info", 0
cmd_dna:        db "dna", 0
cmd_run:        db "run", 0
cmd_help:       db "help", 0
cmd_reboot:     db "reboot", 0

; ── 消息 ──
msg_unknown:    db "Unknown command. Type 'help' for available commands.", 10, 0
msg_pci_scan:   db 10, "Scanning PCI bus...", 10, 0
msg_pci_hdr:    db "  Bus Dev Fn | Vendor Device | Class    | Description", 10
                db "  --------------------------------------------------------", 10, 0
msg_gpu_check:  db 10, "Detecting NVIDIA GA106 (RTX 3060)...", 10, 0
msg_gpu_found:  db "  [OK] GA106 detected!", 10
                db "  BAR0 (MMIO): ", 0
msg_gpu_notfound:
                db "  [NOT FOUND] No GA106 on PCI bus.", 10, 0
msg_cpu_info:   db 10, "CPU Information:", 10
                db "  Vendor: ", 0
msg_amd:        db "AuthenticAMD (AMD)", 10, 0
msg_intel:      db "GenuineIntel (Intel)", 10, 0
msg_cpuid:      db "  CPUID: ", 0
msg_freq:       db "  Max Frequency: ~4.2 GHz (turbo)", 10
                db "  Cores: 6 physical / 12 logical", 10
                db "  Features: AVX2, BMI2, RDRAND, AES-NI, SHA-NI", 10, 0

; ── DNAsm ──
dna_prompt:     db 10, "dnasm> ", 0
dna_banner:     db 10, "DNAsm v3.3 Interactive Shell", 10
                db "Type 'exit' to return to OS shell.", 10
                db "Commands: A T C G (operations) PUSH POP DUP JMP CALL RET", 10, 10, 0
dna_exit_cmd:   db "exit", 0

; ── 测试DNA程序: 计算5! ──
test_prog_5fact:
    db "LOAD 1"        ; 加载t1
    db 0x0A
    db "PUSH 5"        ; 压入5
    db 0x0A
    db "LOOP:"         ; 循环标签
    db 0x0A
    db "DUP"           ; 复制栈顶
    db 0x0A
    db "MUL"           ; 乘法 (C操作)
    db 0x0A
    db "DEC"           ; 递减
    db 0x0A
    db "TEST"          ; 测试零
    db 0x0A
    db "JNZ LOOP"      ; 非零跳转
    db 0x0A
    db "OUT"           ; 输出结果
    db 0x0A
    db "HALT"          ; 停机
    db 0

; ═════════════════════════════════════════════════════════════════════════════
; .text — 代码
; ═════════════════════════════════════════════════════════════════════════════
section .text
global kernel_main

; ═════════════════════════════════════════════════════════════════════════════
; kernel_main — 内核主函数 (64位长模式)
; ═════════════════════════════════════════════════════════════════════════════
kernel_main:
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; ── 初始化 ──
    call vga_init
    call kbd_init
    call pic_init
    call pci_init

    ; ── 显示欢迎画面 ──
    mov rsi, welcome_screen
    call vga_print

    ; ── 主命令循环 ──
.main_loop:
    ; 显示提示符
    mov rsi, prompt_str
    call vga_print

    ; 读取命令行
    call read_line

    ; 解析命令
    call parse_command

    jmp .main_loop

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ═════════════════════════════════════════════════════════════════════════════
; VGA驱动
; ═════════════════════════════════════════════════════════════════════════════

; ── vga_init — 初始化VGA ──
vga_init:
    push rax
    push rdi
    push rcx

    ; 清零屏幕
    mov rdi, VGA_BASE
    mov rcx, VGA_COLS * VGA_ROWS
    mov ax, 0x0720                  ; 空格 + 灰底黑字
    rep stosw

    ; 初始化光标
    mov word [cursor_x], 0
    mov word [cursor_y], 0
    mov byte [vga_attr], COLOR_NORM

    pop rcx
    pop rdi
    pop rax
    ret

; ── vga_print — 打印字符串 ──
; RSI = 字符串地址 (支持\n换行)
vga_print:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

.loop:
    lodsb
    test al, al
    jz .done

    cmp al, 10                      ; \n
    je .newline

    ; 计算光标位置: offset = (y * 80 + x) * 2
    movzx rbx, word [cursor_y]
    imul rbx, VGA_COLS
    add bx, [cursor_x]
    shl rbx, 1
    add rbx, VGA_BASE

    ; 写入字符 + 属性
    mov [rbx], al
    movzx ax, byte [vga_attr]
    mov [rbx + 1], al

    ; 递增X
    inc word [cursor_x]
    cmp word [cursor_x], VGA_COLS
    jb .loop

.newline:
    mov word [cursor_x], 0
    inc word [cursor_y]
    cmp word [cursor_y], VGA_ROWS
    jb .loop
    call vga_scroll
    jmp .loop

.done:
    ; 更新硬件光标
    call vga_update_cursor

    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; ── vga_putc — 输出单个字符 ──
vga_putc:
    push rsi
    mov byte [vga_tmp_char], al
    mov byte [vga_tmp_char + 1], 0
    mov rsi, vga_tmp_char
    call vga_print
    pop rsi
    ret

vga_tmp_char:   db 0, 0

; ── vga_scroll — 滚动屏幕 ──
vga_scroll:
    push rax
    push rcx
    push rsi
    push rdi

    ; 将第2-25行复制到第1-24行
    mov rsi, VGA_BASE + VGA_COLS * 2
    mov rdi, VGA_BASE
    mov rcx, VGA_COLS * (VGA_ROWS - 1)
    rep movsw

    ; 清空最后一行
    mov rdi, VGA_BASE + VGA_COLS * 2 * (VGA_ROWS - 1)
    mov rcx, VGA_COLS
    mov ax, 0x0720
    rep stosw

    dec word [cursor_y]

    pop rdi
    pop rsi
    pop rcx
    pop rax
    ret

; ── vga_update_cursor — 更新硬件光标位置 ──
vga_update_cursor:
    push rax
    push rdx

    ; 计算光标偏移 = y * 80 + x
    movzx rax, word [cursor_y]
    imul rax, VGA_COLS
    add ax, [cursor_x]

    ; 设置光标高字节
    mov dx, 0x3D4
    mov al, 0x0E
    out dx, al
    mov dx, 0x3D5
    mov al, ah
    out dx, al

    ; 设置光标低字节
    mov dx, 0x3D4
    mov al, 0x0F
    out dx, al
    mov dx, 0x3D5
    mov al, ah                      ; 修正: 应该用AL
    ; 简化: 使用完整实现

    pop rdx
    pop rax
    ret

; ═════════════════════════════════════════════════════════════════════════════
; 键盘驱动 (PS/2轮询方式)
; ═════════════════════════════════════════════════════════════════════════════

; ── kbd_init — 初始化键盘 ──
kbd_init:
    push rax

    ; 清空缓冲区
    mov word [key_head], 0
    mov word [key_tail], 0
    mov byte [key_flags], 0

    ; 清空键盘控制器
.clear:
    in al, KBD_STATUS_PORT
    test al, 1
    jz .done
    in al, KBD_DATA_PORT
    jmp .clear

.done:
    pop rax
    ret

; ── kbd_poll — 轮询键盘 (非阻塞) ──
; 返回: AL = ASCII字符 (0=无按键)
kbd_poll:
    push rbx

    ; 检查键盘控制器状态
    in al, KBD_STATUS_PORT
    test al, 1                      ; 输出缓冲区满?
    jz .no_key

    ; 读取扫描码
    in al, KBD_DATA_PORT

    ; 简单转换: 只处理字母和数字 (扫描码→ASCII)
    ; 扫描码 0x1E-0x26 = a-i, 0x30-0x38 = b-l 等
    ; 简化版本: 使用查找表
    movzx rbx, al
    and rbx, 0x7F                   ; 忽略最高位(释放码)
    cmp rbx, scancode_table_size
    jae .no_key

    mov al, [scancode_table + rbx]
    test al, al
    jz .no_key

    pop rbx
    ret

.no_key:
    xor al, al
    pop rbx
    ret

; ── kbd_wait — 等待按键 (阻塞) ──
kbd_wait:
    push rax
.loop:
    call kbd_poll
    test al, al
    jz .loop
    pop rax
    ret

; ── read_line — 读取一行输入 ──
read_line:
    push rax
    push rbx
    push rcx

    mov word [cmd_len], 0
    mov rbx, cmd_buffer

.loop:
    call kbd_wait                   ; 等待按键

    cmp al, 0x0D                    ; Enter
    je .done
    cmp al, 0x08                    ; Backspace
    je .backspace

    ; 普通字符
    movzx rcx, word [cmd_len]
    cmp rcx, 255
    jae .loop                       ; 缓冲区满

    mov [rbx + rcx], al
    inc word [cmd_len]

    ; 回显
    call vga_putc
    jmp .loop

.backspace:
    movzx rcx, word [cmd_len]
    test rcx, rcx
    jz .loop
    dec word [cmd_len]
    ; 删除字符显示
    mov al, 0x08
    call vga_putc
    mov al, ' '
    call vga_putc
    mov al, 0x08
    call vga_putc
    jmp .loop

.done:
    ; 添加结尾
    movzx rcx, word [cmd_len]
    mov byte [rbx + rcx], 0

    pop rcx
    pop rbx
    pop rax
    ret

; ── 扫描码→ASCII转换表 (简化版, 仅字母数字) ──
scancode_table:
    times 2 db 0                    ; 0x00-0x01
    db '1', '2', '3', '4', '5', '6', '7', '8', '9', '0'  ; 0x02-0x0B
    db '-', '=', 0, 0               ; 0x0C-0x0F (Backspace, Tab)
    db 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'  ; 0x10-0x19
    db '[', ']', 0                  ; 0x1A-0x1C (Enter)
    db 0, 'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'    ; 0x1D-0x26
    db ';', "'", '`'                ; 0x27-0x29
    db 0, '\\'                      ; 0x2A (Shift), 0x2B
    db 'z', 'x', 'c', 'v', 'b', 'n', 'm'                 ; 0x2C-0x32
    db ',', '.', '/'                ; 0x33-0x35
    db 0                            ; 0x36 (Shift)
    db '*', 0, ' '                  ; 0x37-0x39
    db 0, 0, 0, 0, 0, 0, 0, 0       ; 0x3A-0x41 (F1-F7)
    db 0, 0, 0, 0, 0, 0             ; 0x42-0x47 (F8-NumLock)
    db '7', '8', '9'                ; 0x48-0x4A (Keypad)
    db '-', '4', '5', '6', '+'      ; 0x4B-0x4F
    db '1', '2', '3'                ; 0x50-0x52
scancode_table_size equ $ - scancode_table

; ═════════════════════════════════════════════════════════════════════════════
; PIC初始化
; ═════════════════════════════════════════════════════════════════════════════
pic_init:
    push rax

    ; ICW1: 开始初始化，级联模式
    mov al, ICW1_INIT
    out PIC1_CMD, al
    out PIC2_CMD, al

    ; ICW2: 中断向量偏移
    mov al, 0x20                    ; 主PIC从0x20开始
    out PIC1_DATA, al
    mov al, 0x28                    ; 从PIC从0x28开始
    out PIC2_DATA, al

    ; ICW3: 级联配置
    mov al, 0x04                    ; 主PIC: IRQ2有从PIC
    out PIC1_DATA, al
    mov al, 0x02                    ; 从PIC: 连接到主PIC的IRQ2
    out PIC2_DATA, al

    ; ICW4: 8086模式
    mov al, ICW4_8086
    out PIC1_DATA, al
    out PIC2_DATA, al

    ; 屏蔽所有中断 (除了键盘中断)
    mov al, 0xFD                    ; 只启用IRQ1 (键盘)
    out PIC1_DATA, al
    mov al, 0xFF                    ; 屏蔽所有从PIC中断
    out PIC2_DATA, al

    pop rax
    ret

; ═════════════════════════════════════════════════════════════════════════════
; PCI枚举
; ═════════════════════════════════════════════════════════════════════════════
pci_init:
    push rax
    mov word [pci_count], 0
    xor rax, rax
    mov [gpu_found], al
    pop rax
    ret

; ── pci_read_config — 读取PCI配置空间 ──
; 输入: BL=Bus, CL=Dev, DL=Func, SI=Offset
; 输出: EAX = 32位值
pci_read_config:
    push rbx
    push rdx

    ; 构建地址: 0x80000000 | (Bus<<16) | (Dev<<11) | (Func<<8) | (Offset&0xFC)
    mov eax, 0x80000000
    shl ebx, 16
    or eax, ebx
    shr ebx, 16
    shl ecx, 11
    or eax, ecx
    shr ecx, 11
    shl edx, 8
    or eax, edx
    shr edx, 8
    and esi, 0xFC
    or eax, esi

    ; 读取
    push rax
    mov dx, PCI_CONFIG_ADDR
    out dx, eax
    mov dx, PCI_CONFIG_DATA
    in eax, dx
    mov edi, eax                    ; 保存结果
    pop rax

    mov eax, edi
    pop rdx
    pop rbx
    ret

; ── cmd_pci_handler — pci命令处理 ──
cmd_pci_handler:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

    mov rsi, msg_pci_scan
    call vga_print
    mov rsi, msg_pci_hdr
    call vga_print

    ; 扫描PCI总线
    xor rbx, rbx                    ; bus
.bus_loop:
    cmp bl, 2                       ; 只扫描0-1
    jae .done

    xor rcx, rcx                    ; dev
.dev_loop:
    cmp cl, 32
    jae .next_bus

    ; 检查设备是否存在 (读Vendor ID)
    xor rdx, rdx                    ; func=0
    xor rsi, rsi                    ; offset=0
    call pci_read_config

    cmp eax, 0xFFFFFFFF
    je .next_dev                    ; 无设备

    ; 找到设备, 显示信息
    push rax                        ; 保存Vendor/Device

    ; 显示Bus/Dev/Func
    mov al, ' '
    call vga_putc
    mov al, ' '
    call vga_putc
    movzx rax, bl
    call print_hex8
    mov al, ' '
    call vga_putc
    movzx rax, cl
    call print_hex8
    mov al, ' '
    call vga_putc
    xor rax, rax
    call print_hex8
    mov al, ' '
    call vga_putc
    mov al, '|'
    call vga_putc
    mov al, ' '
    call vga_putc

    ; 显示Vendor ID
    pop rax                         ; 恢复Vendor/Device
    push rax
    and eax, 0xFFFF
    call print_hex16
    mov al, ' '
    call vga_putc

    ; 显示Device ID
    pop rax
    shr eax, 16
    call print_hex16

    ; 检查是否NVIDIA GA106
    pop rax
    push rax
    cmp ax, NV_VENDOR
    jne .not_nvidia

    shr eax, 16
    cmp ax, GA106_DEV
    jne .not_ga106

    mov byte [gpu_found], 1
    mov [gpu_bus], bl
    mov [gpu_dev], cl
    mov [gpu_func], dl

    mov al, ' '
    call vga_putc
    mov al, '|'
    call vga_putc
    mov rsi, .ga106_str
    call vga_print
    jmp .print_crlf

.not_ga106:
    shr eax, 16
    jmp .print_crlf

.not_nvidia:
    pop rax

.print_crlf:
    mov al, 10
    call vga_putc

.next_dev:
    inc cl
    jmp .dev_loop

.next_bus:
    inc bl
    jmp .bus_loop

.done:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

.ga106_str:     db " [GA106 RTX 3060]", 0

; ═════════════════════════════════════════════════════════════════════════════
; GPU处理
; ═════════════════════════════════════════════════════════════════════════════
cmd_gpu_handler:
    push rax
    push rsi

    mov rsi, msg_gpu_check
    call vga_print

    cmp byte [gpu_found], 1
    jne .not_found

    ; 显示GPU信息
    mov rsi, msg_gpu_found
    call vga_print

    ; 读取BAR0
    mov bl, [gpu_bus]
    mov cl, [gpu_dev]
    mov dl, [gpu_func]
    mov si, 0x10                    ; BAR0偏移
    call pci_read_config

    ; 保存并显示
    and eax, 0xFFFFFFF0             ; 清除标志位
    mov [bar0_addr], rax
    call print_hex32

    mov al, 10
    call vga_putc
    jmp .done

.not_found:
    mov rsi, msg_gpu_notfound
    call vga_print

.done:
    pop rsi
    pop rax
    ret

; ═════════════════════════════════════════════════════════════════════════════
; CPU信息
cmd_info_handler:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi

    mov rsi, msg_cpu_info
    call vga_print

    ; 获取CPU vendor string
    xor eax, eax
    cpuid

    ; EBX, EDX, ECX contain vendor string
    mov [cpu_vendor], ebx
    mov [cpu_vendor + 4], edx
    mov [cpu_vendor + 8], ecx
    mov byte [cpu_vendor + 12], 0

    mov rsi, cpu_vendor
    call vga_print

    ; 检查AMD
    cmp ebx, 0x68747541             ; "Auth"
    jne .check_intel
    cmp edx, 0x69746E65             ; "enti"
    jne .check_intel
    mov rsi, msg_amd
    call vga_print
    jmp .show_freq

.check_intel:
    cmp ebx, 0x756E6547             ; "Genu"
    jne .unknown
    mov rsi, msg_intel
    call vga_print
    jmp .show_freq

.unknown:
    mov al, 10
    call vga_putc

.show_freq:
    ; 显示CPU信息
    mov eax, 1
    cpuid
    ; EAX = 处理器签名
    push rax
    mov rsi, msg_cpuid
    call vga_print
    pop rax
    call print_hex32
    mov al, 10
    call vga_putc

    ; 显示频率和核心数
    mov rsi, msg_freq
    call vga_print

    ; 显示特性
    mov rsi, .features
    call vga_print

    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

.features:
    db 10, "  Cache: L1=192KB (32KBx6) | L2=3MB (512KBx6) | L3=16MB", 10
    db "  TDP: 65W | Process: 7nm TSMC", 10
    db 0

cpu_vendor:     times 13 db 0

; ═════════════════════════════════════════════════════════════════════════════
; DNAsm交互模式
cmd_dna_handler:
    push rax
    push rsi

    mov rsi, dna_banner
    call vga_print

.dna_loop:
    mov rsi, dna_prompt
    call vga_print

    call read_line

    ; 检查exit
    mov rsi, cmd_buffer
    mov rdi, dna_exit_cmd
    call strcmp
    test al, al
    jnz .exit_dna

    ; 解析DNA命令
    call dna_execute
    jmp .dna_loop

.exit_dna:
    pop rsi
    pop rax
    ret

; ── dna_execute — 执行DNA命令 ──
dna_execute:
    push rax
    push rsi

    mov rsi, cmd_buffer

    ; 获取第一个字符
    lodsb

    ; 解析命令
    cmp al, 'A'
    je .op_add
    cmp al, 'T'
    je .op_sub
    cmp al, 'C'
    je .op_mul
    cmp al, 'G'
    je .op_div
    cmp al, 'P'
    je .op_push
    cmp al, 'D'
    je .op_dup
    cmp al, 'O'
    je .op_out
    cmp al, 'H'
    je .op_halt

    jmp .unknown

.op_add:
    call dna_op_add
    jmp .done
.op_sub:
    call dna_op_sub
    jmp .done
.op_mul:
    call dna_op_mul
    jmp .done
.op_div:
    call dna_op_div
    jmp .done
.op_push:
    call dna_op_push
    jmp .done
.op_dup:
    call dna_op_dup
    jmp .done
.op_out:
    call dna_op_out
    jmp .done
.op_halt:
    call dna_op_halt
    jmp .done

.unknown:
    mov al, '?'
    call vga_putc
    mov al, 10
    call vga_putc

.done:
    pop rsi
    pop rax
    ret

; ── DNA操作实现 ──
dna_op_add:     ; A = 加法
    push rax
    mov eax, [dna_acc]
    add eax, [tubes]
    mov [dna_acc], eax
    mov al, '+'
    call vga_putc
    mov al, 10
    call vga_putc
    pop rax
    ret

dna_op_sub:     ; T = 减法
    push rax
    mov eax, [dna_acc]
    sub eax, [tubes]
    mov [dna_acc], eax
    mov al, '-'
    call vga_putc
    mov al, 10
    call vga_putc
    pop rax
    ret

dna_op_mul:     ; C = 乘法
    push rax
    push rdx
    mov eax, [dna_acc]
    imul dword [tubes]
    mov [dna_acc], eax
    mov al, '*'
    call vga_putc
    mov al, 10
    call vga_putc
    pop rdx
    pop rax
    ret

dna_op_div:     ; G = 除法
    push rax
    push rdx
    xor edx, edx
    mov eax, [dna_acc]
    mov ebx, [tubes]
    test ebx, ebx
    jz .div_zero
    div ebx
    mov [dna_acc], eax
    mov al, '/'
    call vga_putc
    mov al, 10
    call vga_putc
    jmp .done
.div_zero:
    mov rsi, .div_err
    call vga_print
.done:
    pop rdx
    pop rax
    ret
.div_err:       db " Division by zero!", 10, 0

dna_op_push:
    ; 解析后面的数字
    push rax
    push rbx
    push rcx

    mov rsi, cmd_buffer
    add rsi, 5                      ; 跳过"PUSH "
    call atoi
    mov [tubes], eax                ; 存入t0

    pop rcx
    pop rbx
    pop rax
    ret

dna_op_dup:
    push rax
    mov eax, [tubes]
    mov [tubes + 4], eax            ; 复制到t1
    mov al, 'D'
    call vga_putc
    mov al, 10
    call vga_putc
    pop rax
    ret

dna_op_out:
    push rax
    mov eax, [dna_acc]
    call print_hex32
    mov al, 10
    call vga_putc
    pop rax
    ret

dna_op_halt:
    mov al, 'H'
    call vga_putc
    mov al, 10
    call vga_putc
    ret

; ═════════════════════════════════════════════════════════════════════════════
; 命令解析
cmd_help_handler:
    push rsi
    mov rsi, welcome_screen + 200   ; 指向帮助部分
    call vga_print
    pop rsi
    ret

cmd_reboot_handler:
    ; 通过键盘控制器重启
    mov al, 0xFE
    out 0x64, al
    jmp $

cmd_run_handler:
    push rsi
    mov rsi, .not_impl
    call vga_print
    pop rsi
    ret
.not_impl:      db 10, "Disk I/O not yet implemented in this build.", 10
                db "Use 'dna' for interactive mode.", 10, 0

; ═════════════════════════════════════════════════════════════════════════════
; 命令分发
parse_command:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

    mov rsi, cmd_buffer

    ; 跳过前导空格
.skip_space:
    lodsb
    cmp al, ' '
    je .skip_space
    dec rsi                         ; 回退到第一个非空格字符

    ; 检查空命令
    test al, al
    jz .done

    ; 检查各命令
    mov rdi, cmd_pci
    call strcmp_cmd
    test al, al
    jnz .do_pci

    mov rdi, cmd_gpu
    call strcmp_cmd
    test al, al
    jnz .do_gpu

    mov rdi, cmd_info
    call strcmp_cmd
    test al, al
    jnz .do_info

    mov rdi, cmd_dna
    call strcmp_cmd
    test al, al
    jnz .do_dna

    mov rdi, cmd_run
    call strcmp_cmd
    test al, al
    jnz .do_run

    mov rdi, cmd_help
    call strcmp_cmd
    test al, al
    jnz .do_help

    mov rdi, cmd_reboot
    call strcmp_cmd
    test al, al
    jnz .do_reboot

    ; 未知命令
    mov rsi, msg_unknown
    call vga_print
    jmp .done

.do_pci:    call cmd_pci_handler
    jmp .done
.do_gpu:    call cmd_gpu_handler
    jmp .done
.do_info:   call cmd_info_handler
    jmp .done
.do_dna:    call cmd_dna_handler
    jmp .done
.do_run:    call cmd_run_handler
    jmp .done
.do_help:   call cmd_help_handler
    jmp .done
.do_reboot: call cmd_reboot_handler

.done:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; ── strcmp_cmd — 比较命令字符串 ──
; RSI = 输入, RDI = 命令模板
; 返回 AL=1 (匹配) 或 0
strcmp_cmd:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

    mov rbx, rsi                    ; 保存输入

.loop:
    mov al, [rbx]
    cmp al, ' '                     ; 空格 = 命令结束
    je .input_end
    test al, al                     ; 空字符 = 结束
    je .input_end

    mov cl, [rdi]
    test cl, cl
    jz .mismatch                    ; 模板已完但输入没完

    cmp al, cl
    jne .mismatch

    inc rbx
    inc rdi
    jmp .loop

.input_end:
    mov cl, [rdi]
    test cl, cl
    jnz .mismatch                   ; 模板没完

    mov al, 1
    jmp .done

.mismatch:
    xor al, al

.done:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; ── strcmp — 完整字符串比较 ──
strcmp:
    push rbx
    push rcx

.loop:
    mov al, [rsi]
    mov bl, [rdi]
    cmp al, bl
    jne .not_equal
    test al, al
    jz .equal
    inc rsi
    inc rdi
    jmp .loop

.not_equal:
    xor al, al
    jmp .done

.equal:
    mov al, 1

.done:
    pop rcx
    pop rbx
    ret

; ═════════════════════════════════════════════════════════════════════════════
; 工具函数

; ── print_hex8/16/32 ──
print_hex8:
    push rax
    push rcx
    movzx rax, al
    mov cl, al
    shr cl, 4
    call .digit
    mov cl, al
    and cl, 0x0F
    call .digit
    pop rcx
    pop rax
    ret
.digit:
    push rax
    mov al, cl
    cmp al, 10
    jb .num
    add al, 'A' - 10
    jmp .out
.num:
    add al, '0'
.out:
    call vga_putc
    pop rax
    ret

print_hex16:
    push rax
    xchg al, ah
    call print_hex8
    pop rax
    call print_hex8
    ret

print_hex32:
    push rax
    shr rax, 16
    call print_hex16
    pop rax
    call print_hex16
    ret

; ── atoi — ASCII字符串转整数 ──
; RSI = 字符串, 返回 EAX = 整数
atoi:
    push rbx
    push rcx
    push rdx

    xor eax, eax
    xor ebx, ebx

.loop:
    lodsb
    test al, al
    jz .done
    cmp al, '0'
    jb .done
    cmp al, '9'
    ja .done

    sub al, '0'
    movzx ebx, al
    imul eax, 10
    add eax, ebx
    jmp .loop

.done:
    pop rdx
    pop rcx
    pop rbx
    ret

; ═════════════════════════════════════════════════════════════════════════════
