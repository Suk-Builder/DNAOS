; ============================================================================
; DNAOS v3.3 · Master Boot Record (MBR)
; 功能: BIOS引导 → 加载内核到0x100000 → 跳转执行
; 大小: 恰好512字节 (第510-511字节 = 0x55 0xAA)
; 目标: x86-64 PC (BIOS模式)
; ============================================================================
; 递砖机认知操作系统 · 裂缝不是bug，是砖飞过来的地方
; ============================================================================

BITS 16
ORG 0x7C00

; ── 常量 ──
KERNEL_SEG      equ 0x1000        ; 内核加载段 (物理地址 = 0x10000)
KERNEL_OFF      equ 0x0000        ; 内核加载偏移
KERNEL_LBA      equ 1             ; 内核从LBA扇区1开始
KERNEL_SECTORS  equ 128           ; 内核大小 = 128扇区 = 64KB
STACK_TOP       equ 0x7C00        ; 栈顶 (引导扇区下方)

; ── BPB (BIOS Parameter Block) 用于兼容某些BIOS ──
jmp short start
nop
bpb_oem:        db "DNAOS   "     ; OEM标识
bpb_bytes:      dw 512            ; 每扇区字节数
bpb_clust:      db 1              ; 每簇扇区数
bpb_rsvd:       dw 1              ; 保留扇区数 (MBR)
bpb_fats:       db 2              ; FAT表数
bpb_roots:      dw 224            ; 根目录项数
bpb_total:      dw 2880           ; 总扇区数 (1.44MB软盘)
bpb_media:      db 0xF0           ; 媒体描述符
bpb_fat_sz:     dw 9              ; 每FAT扇区数
bpb_track:      dw 18             ; 每磁道扇区数
bpb_heads:      dw 2              ; 磁头数
bpb_hidden:     dd 0              ; 隐藏扇区
bpb_total32:    dd 0              ; 大总扇区数
bpb_drv_num:    db 0x80           ; 驱动器号 (硬盘)
bpb_resv1:      db 0
bpb_sig:        db 0x29           ; 扩展BPB签名
bpb_vol_id:     dd 0xTSUKUYO      ; 卷序列号
bpb_vol_lab:    db "DNAOS v3.3 "  ; 卷标
bpb_sys_id:     db "FAT12   "     ; 文件系统类型

; ═════════════════════════════════════════════════════════════════════════════
; MBR入口
; ═════════════════════════════════════════════════════════════════════════════
start:
    ; ── 初始化段寄存器 ──
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, STACK_TOP

    ; ── 保存引导驱动器号 ──
    mov [boot_drive], dl

    ; ── 显示DNAOS引导消息 ──
    mov si, msg_boot
    call print16

    ; ── 启用A20地址线 ──
    call enable_a20

    ; ── 重置磁盘 ──
    call disk_reset

    ; ── 从磁盘加载内核 ──
    ; 使用INT 13h AH=42h (扩展读) 或 AH=02h (CHS读)
    mov si, msg_load
    call print16

    ; 尝试使用LBA扩展读 (INT 13h AH=42h)
    mov ah, 0x41
    mov bx, 0x55AA
    int 0x13
    jc .use_chs                     ; 不支持LBA扩展，用CHS
    cmp bx, 0xAA55
    jne .use_chs

    ; 使用LBA扩展读
    call load_kernel_lba
    jmp .kernel_loaded

.use_chs:
    ; 使用传统CHS读
    call load_kernel_chs

.kernel_loaded:
    mov si, msg_done
    call print16

    ; ── 获取内存映射 (E820) ──
    call get_memory_map

    ; ── 跳转到内核 ──
    ; 内核被加载到 0x1000:0x0000 = 物理地址 0x10000
    ; 但我们在编译时把内核链接到 0x100000 (1MB)
    ; 所以需要把数据从0x10000复制到0x100000

    ; 复制内核到1MB以上 (使用实模式大地址访问技巧)
    mov si, msg_copy
    call print16
    call copy_high

    ; ── 显示进入消息 ──
    mov si, msg_enter
    call print16

    ; ── 远跳转到内核 ──
    ; 内核在0x100000, 但我们先进入保护模式
    jmp 0x0000:kernel_stage2

; ═════════════════════════════════════════════════════════════════════════════
; kernel_stage2 — 在0x100000处运行 (物理内存1MB处)
; 这里直接嵌入在MBR后面的代码 (通过build.sh拼接)
; ═════════════════════════════════════════════════════════════════════════════
kernel_stage2:
    ; 这段代码会在0x100000处运行
    ; 先切换到保护模式，然后长模式

    BITS 16
    ; ── 加载GDT ──
    cli
    lgdt [gdt_descriptor]

    ; ── 启用保护模式 (CR0.PE = 1) ──
    mov eax, cr0
    or al, 1
    mov cr0, eax

    ; ── 远跳转到32位代码 ──
    jmp 0x08:protected_mode_32

; ═════════════════════════════════════════════════════════════════════════════
; 32位保护模式
; ═════════════════════════════════════════════════════════════════════════════
BITS 32
protected_mode_32:
    ; ── 设置32位段寄存器 ──
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x90000            ; 32位栈

    ; ── 显示'P'表示进入保护模式 ──
    mov byte [0xB8000], 'P'
    mov byte [0xB8001], 0x0A    ; 绿色

    ; ── 检测是否支持长模式 ──
    mov eax, 0x80000001
    cpuid
    test edx, (1 << 29)         ; LM位 (长模式支持)
    jz no_long_mode

    ; ── 设置页表 ──
    ; 页表放在0x8000-0xBFFF (16KB)
    call setup_page_tables

    ; ── 启用PAE (CR4.PAE = 1) ──
    mov eax, cr4
    or eax, (1 << 5)
    mov cr4, eax

    ; ── 设置CR3指向PML4 ──
    mov eax, 0x9000             ; PML4在0x9000
    mov cr3, eax

    ; ── 启用长模式 (EFER.LME = 1) ──
    mov ecx, 0xC0000080         ; EFER MSR
    rdmsr
    or eax, (1 << 8)            ; LME位
    wrmsr

    ; ── 启用分页 (CR0.PG = 1) ──
    mov eax, cr0
    or eax, (1 << 31)
    mov cr0, eax

    ; ── 远跳转到64位代码 ──
    jmp 0x08:long_mode_64

; ═════════════════════════════════════════════════════════════════════════════
; 64位长模式
; ═════════════════════════════════════════════════════════════════════════════
BITS 64
long_mode_64:
    ; ── 设置64位段寄存器 ──
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov rsp, 0x200000           ; 64位栈在2MB

    ; ── 显示'L'表示进入长模式 ──
    mov rax, 0x0A4C             ; 'L' 绿色
    mov [0xB8000], ax

    ; ── 调用内核主函数 ──
    ; 内核主函数在链接时确定地址
    extern kernel_main
    call kernel_main

    ; ── 停机 ──
    cli
.halt:
    hlt
    jmp .halt

; ═════════════════════════════════════════════════════════════════════════════
; 子程序 (16位)
; ═════════════════════════════════════════════════════════════════════════════
BITS 16

; ── print16 — 16位实模式打印字符串 ──
; SI = 字符串地址 (以0结尾)
print16:
    push ax
    push si
.loop:
    lodsb
    test al, al
    jz .done
    mov ah, 0x0E
    mov bh, 0x00
    mov bl, 0x07
    int 0x10
    jmp .loop
.done:
    pop si
    pop ax
    ret

; ── enable_a20 — 启用A20地址线 ──
enable_a20:
    push ax
    ; 方法: 尝试BIOS INT 15h AH=2401
    mov ax, 0x2401
    int 0x15
    jc .fallback
    test ah, ah
    jnz .fallback
    pop ax
    ret
.fallback:
    ; 备选: 键盘控制器方法
    in al, 0x92
    or al, 2
    out 0x92, al
    pop ax
    ret

; ── disk_reset — 重置磁盘 ──
disk_reset:
    push ax
    push dx
    xor ax, ax
    mov dl, [boot_drive]
    int 0x13
    pop dx
    pop ax
    ret

; ── load_kernel_lba — 使用LBA扩展读加载内核 ──
load_kernel_lba:
    push si
    push dx

    ; 设置DAP (Disk Address Packet)
    mov si, dap
    mov word [si], 0x0010         ; 大小 = 16字节
    mov word [si + 2], KERNEL_SECTORS  ; 要读的扇区数
    mov word [si + 4], 0x0000     ; 偏移
    mov word [si + 6], KERNEL_SEG ; 段
    mov dword [si + 8], KERNEL_LBA  ; 起始LBA (低32位)
    mov dword [si + 12], 0        ; 起始LBA (高32位)

    mov ah, 0x42
    mov dl, [boot_drive]
    int 0x13
    jc disk_error

    pop dx
    pop si
    ret

; ── load_kernel_chs — 使用CHS读加载内核 ──
load_kernel_chs:
    push ax
    push bx
    push cx
    push dx

    mov ax, KERNEL_SEG
    mov es, ax
    xor bx, bx                    ; ES:BX = 0x1000:0x0000

    mov ah, 0x02                  ; 读扇区
    mov al, KERNEL_SECTORS        ; 扇区数
    mov ch, 0                     ; 柱面0
    mov cl, 2                     ; 扇区2开始 (MBR是扇区1)
    mov dh, 0                     ; 磁头0
    mov dl, [boot_drive]
    int 0x13
    jc disk_error

    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ── disk_error — 磁盘错误处理 ──
disk_error:
    mov si, msg_disk_err
    call print16
    jmp $

; ── get_memory_map — 使用INT 15h E820获取内存映射 ──
get_memory_map:
    push ax
    push bx
    push cx
    push dx
    push di
    push es

    mov ax, 0x0000
    mov es, ax
    mov di, memory_map            ; 缓冲区在0x8000
    xor ebx, ebx                  ; 第一次调用EBX=0
    xor bp, bp                    ; 条目计数

.loop:
    mov eax, 0x0000E820
    mov ecx, 24                   ; 每个条目24字节
    mov edx, 0x534D4150           ; 'SMAP'
    int 0x15
    jc .done                      ; 错误 = 完成
    cmp eax, 0x534D4150
    jne .done                     ; 签名不匹配

    add di, 24
    inc bp
    test ebx, ebx
    jz .done                      ; EBX=0 = 完成
    cmp bp, 32
    jb .loop

.done:
    mov [memory_entries], bp

    pop es
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ── copy_high — 将内核从0x10000复制到0x100000 ──
copy_high:
    push ax
    push cx
    push si
    push di
    push es
    push ds

    ; 源 = 0x1000:0x0000 = 0x10000
    mov ax, 0x1000
    mov ds, ax
    xor si, si

    ; 目标 = 0xFFFF:0x0010 = 0x100000 (使用段绕回)
    ; 或者使用rep movsd with 32-bit addressing in unreal mode
    ; 简化: 使用INT 15h AH=87h (扩展内存拷贝)

    ; 使用BIOS扩展内存拷贝
    mov ah, 0x87
    mov cx, KERNEL_SECTORS * 512 / 2  ; 字数
    mov si, gdt_87h
    int 0x15

    pop ds
    pop es
    pop di
    pop si
    pop cx
    pop ax
    ret

; ── setup_page_tables — 设置64位页表 ──
; 页表放在0x9000-0xCFFF
; PML4@0x9000, PDP@0xA000, PD@0xB000, PT@0xC000
setup_page_tables:
    push eax
    push edi
    push ecx

    ; 清零页表区域
    mov edi, 0x9000
    mov ecx, 4096                 ; 16KB / 4 = 4096 dwords
    xor eax, eax
    rep stosd

    ; PML4[0] → PDP (0xA000)
    mov dword [0x9000], 0xA003    ; 存在 + 可写

    ; PDP[0] → PD (0xB000)
    mov dword [0xA000], 0xB003

    ; PD[0] → PT (0xC000)
    mov dword [0xB000], 0xC003

    ; PT[0-511] → 物理页 0x0000-0x1FF000 (2MB映射)
    mov edi, 0xC000
    mov eax, 0x00000003           ; 存在 + 可写
    mov ecx, 512
.pt_loop:
    mov [edi], eax
    add edi, 8                    ; 每个PTE 8字节
    add eax, 0x1000               ; 下一页
    dec ecx
    jnz .pt_loop

    ; 也映射 0x100000 (1MB) 以上的内存
    ; PD[1] → 另一个PT映射高内存
    mov dword [0xB008], 0xD003    ; PT@0xD000

    ; 映射0x100000-0x1FFFFF (内核区域)
    mov edi, 0xD000
    mov eax, 0x00100003           ; 从1MB开始
    mov ecx, 256
.pt_loop2:
    mov [edi], eax
    add edi, 8
    add eax, 0x1000
    dec ecx
    jnz .pt_loop2

    pop ecx
    pop edi
    pop eax
    ret

; ═════════════════════════════════════════════════════════════════════════════
; 数据区
; ═════════════════════════════════════════════════════════════════════════════

; ── GDT (Global Descriptor Table) ──
gdt_start:
    ; 空描述符
    dq 0x0000000000000000

    ; 代码段描述符 (32位)
    dw 0xFFFF                     ; 限长低16位
    dw 0x0000                     ; 基址低16位
    db 0x00                       ; 基址中8位
    db 10011010b                  ; 属性: 代码段, 存在, 可执行, 可读
    db 11001111b                  ; 属性: 32位, 限长高4位
    db 0x00                       ; 基址高8位

    ; 数据段描述符 (32位)
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 10010010b                  ; 数据段, 存在, 可写
    db 11001111b
    db 0x00

gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1    ; GDT限长
    dd gdt_start                  ; GDT基址

; ── GDT for INT 15h AH=87h ──
gdt_87h:
    dq 0x0000000000000000         ; 空
    dq 0x0000000000000000         ; GDT (由BIOS填充)
    ; 源段描述符 (0x10000, 64KB)
    dw 0xFFFF                     ; 限长
    dw 0x0000                     ; 基址低16
    db 0x01                       ; 基址中8
    db 10010010b                  ; 数据段
    db 00000000b
    db 0x00
    ; 目标段描述符 (0x100000, 64KB)
    dw 0xFFFF
    dw 0x0000
    db 0x10
    db 10010010b
    db 00000000b
    db 0x00
    dq 0x0000000000000000         ; 空
    dq 0x0000000000000000         ; 空

; ── DAP (Disk Address Packet) ──
dap:
    db 0x10, 0x00                 ; 大小
    db 0x00, 0x00                 ; 扇区数 (运行时填充)
    db 0x00, 0x00                 ; 偏移 (运行时填充)
    db 0x00, 0x00                 ; 段 (运行时填充)
    db 0x00, 0x00, 0x00, 0x00     ; LBA低32位
    db 0x00, 0x00, 0x00, 0x00     ; LBA高32位

; ── 字符串 ──
msg_boot:       db 0x0D, 0x0A, "DNAOS v3.3 Bootloader", 0x0D, 0x0A, 0
msg_load:       db "Loading kernel... ", 0
msg_done:       db "OK", 0x0D, 0x0A, 0
msg_copy:       db "Copying kernel to high memory... ", 0
msg_enter:      db "Entering kernel...", 0x0D, 0x0A, 0
msg_disk_err:   db "Disk error!", 0x0D, 0x0A, 0

; ── 变量 ──
boot_drive:     db 0
memory_entries: dw 0
memory_map:     times 768 db 0    ; 32条目 × 24字节

; ── 长模式不支持时的错误 ──
no_long_mode:
    mov si, msg_no_lm
    call print16
    jmp $
msg_no_lm:      db "Error: CPU does not support x86-64 long mode!", 0x0D, 0x0A, 0

; ═════════════════════════════════════════════════════════════════════════════
; 填充到510字节 + 引导签名
; ═════════════════════════════════════════════════════════════════════════════
times 510-($-$$) db 0
dw 0xAA55
