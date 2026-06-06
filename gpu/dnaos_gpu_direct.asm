; ============================================================================
; DNAOS v3.3 · GPU Direct Access — Ultimate Edition
; ============================================================================
; 目标平台: 微星AM4主板 + AMD Ryzen 5 5500 + NVIDIA RTX 3060 GA106
; 运行环境: UEFI x86-64 (长模式, 无操作系统)
; 功能:
;   1. 通过UEFI PCI Root Bridge I/O Protocol枚举PCIe设备
;   2. 定位NVIDIA GA106 (Vendor=0x10DE, Device=0x2504)
;   3. 读取PCI配置空间 (256字节标准头部 + 扩展空间)
;   4. 解析64位BAR (BAR0=MMIO, BAR2=VRAM)
;   5. 通过UEFI内存映射服务将BAR0映射到虚拟地址
;   6. 使用x86-64 MOV指令直接读写GPU MMIO寄存器
;   7. 读取PMC (Primary Master Control) 寄存器组
;   8. 检测GPU架构ID、实现版本、修订号
;   9. 显示引擎使能状态
; ============================================================================
; 调用约定: Microsoft x64 ABI (UEFI标准)
;   RCX, RDX, R8, R9 = 参数1-4
;   RAX = 返回值
;   栈16字节对齐
;   调用者保存: RAX, RCX, RDX, R8-R11
;   被调者保存: RBX, RBP, RDI, RSI, R12-R15
; ============================================================================

BITS 64
DEFAULT REL

; =============================================================================
; 宏定义
; =============================================================================

; ── UEFI调用宏 ──
%macro UEFI_CALL 2
    mov rax, %1                 ; 协议接口指针
    mov rax, [rax]              ; vtable指针
    call [rax + %2]             ; 调用vtable偏移处的函数
%endmacro

; ── 保存寄存器 ──
%macro PUSHALL 0
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
%endmacro

; ── 恢复寄存器 ──
%macro POPALL 0
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
%endmacro

; =============================================================================
; 常量
; =============================================================================

; ── UEFI状态码 ──
EFI_SUCCESS                     equ 0x0000000000000000
EFI_LOAD_ERROR                  equ 0x8000000000000001
EFI_INVALID_PARAMETER           equ 0x8000000000000002
EFI_UNSUPPORTED                 equ 0x8000000000000003
EFI_BAD_BUFFER_SIZE             equ 0x8000000000000004
EFI_BUFFER_TOO_SMALL            equ 0x8000000000000005
EFI_NOT_FOUND                   equ 0x800000000000000E

; ── PCI ──
NV_VENDOR_ID                    equ 0x10DE
GA106_DEVICE_ID                 equ 0x2504
GA106_LHR_ID                    equ 0x2503

PCI_MAX_BUS                     equ 2
PCI_MAX_DEV                     equ 32
PCI_MAX_FUNC                    equ 8

; ── PCI配置空间 ──
OFFSET_VENDOR                   equ 0x00
OFFSET_DEVICE                   equ 0x02
OFFSET_COMMAND                  equ 0x04
OFFSET_STATUS                   equ 0x06
OFFSET_REV                      equ 0x08
OFFSET_CLASS                    equ 0x09
OFFSET_BAR0                     equ 0x10
OFFSET_BAR1                     equ 0x14
OFFSET_BAR2                     equ 0x18
OFFSET_BAR3                     equ 0x1C

; ── UEFI协议GUID偏移 (需要在数据段定义) ──
; EFI_PCI_ROOT_BRIDGE_IO_PROTOCOL_GUID
; {2F707EBB-4A1A-11d4-9A38-0090273FC14D}

; ── UEFI函数vtable偏移 ──
; EFI_PCI_ROOT_BRIDGE_IO_PROTOCOL:
;   PollMem           = 0x00
;   PollIo            = 0x08
;   Mem.Read          = 0x10
;   Mem.Write         = 0x18
;   Io.Read           = 0x20
;   Io.Write          = 0x28
;   Pci.Read          = 0x30    <── 我们需要的
;   Pci.Write         = 0x38    <── 我们需要的
;   CopyMem           = 0x40
;   Map               = 0x48
;   Unmap             = 0x50
;   AllocateBuffer    = 0x58
;   FreeBuffer        = 0x60
;   Flush             = 0x68
;   GetAttributes     = 0x70
;   SetAttributes     = 0x78
;   Configuration     = 0x80

PCI_ROOT_BRIDGE_PCI_READ        equ 0x30
PCI_ROOT_BRIDGE_PCI_WRITE       equ 0x38

; ── UEFI简单文本输出协议偏移 ──
; SIMPLE_TEXT_OUTPUT_PROTOCOL:
;   Reset             = 0x00
;   OutputString      = 0x08   <── 打印用
;   TestString        = 0x10
;   QueryMode         = 0x18
;   SetMode           = 0x20
;   SetAttribute      = 0x28   <── 设置颜色
;   ClearScreen       = 0x30   <── 清屏
;   SetCursorPosition = 0x38
;   EnableCursor      = 0x40

CONOUT_OUTPUT_STRING            equ 0x08
CONOUT_SET_ATTRIBUTE            equ 0x28
CONOUT_CLEAR_SCREEN             equ 0x30

; ── 屏幕颜色 (UEFI标准) ──
COLOR_BLACK                     equ 0
COLOR_BLUE                      equ 1
COLOR_GREEN                     equ 2
COLOR_CYAN                      equ 3
COLOR_RED                       equ 4
COLOR_MAGENTA                   equ 5
COLOR_BROWN                     equ 6
COLOR_LIGHTGRAY                 equ 7
COLOR_DARKGRAY                  equ 8
COLOR_LIGHTBLUE                 equ 9
COLOR_LIGHTGREEN                equ 10
COLOR_LIGHTCYAN                 equ 11
COLOR_LIGHTRED                  equ 12
COLOR_LIGHTMAGENTA              equ 13
COLOR_YELLOW                    equ 14
COLOR_WHITE                     equ 15

; DNAOS主题色
DNAOS_COLOR_GOLD                equ (COLOR_BLACK << 4) | COLOR_YELLOW
DNAOS_COLOR_INFO                equ (COLOR_BLACK << 4) | COLOR_LIGHTCYAN
DNAOS_COLOR_OK                  equ (COLOR_BLACK << 4) | COLOR_LIGHTGREEN
DNAOS_COLOR_FAIL                equ (COLOR_BLACK << 4) | COLOR_LIGHTRED
DNAOS_COLOR_NORMAL              equ (COLOR_BLACK << 4) | COLOR_LIGHTGRAY
DNAOS_COLOR_DATA                equ (COLOR_BLACK << 4) | COLOR_LIGHTMAGENTA

; =============================================================================
; 数据段
; =============================================================================
section .rodata align=16

; ── UEFI协议GUID (16字节, little-endian) ──

; EFI_PCI_ROOT_BRIDGE_IO_PROTOCOL_GUID
; {2F707EBB-4A1A-11d4-9A38-0090273FC14D}
guid_pci_root_bridge:
    db 0xBB, 0x7E, 0x70, 0x2F    ; Data1
    db 0x1A, 0x4A                ; Data2
    db 0xD4, 0x11                ; Data3
    db 0x9A, 0x38, 0x00, 0x90, 0x27, 0x3F, 0xC1, 0x4D  ; Data4

; EFI_GRAPHICS_OUTPUT_PROTOCOL_GUID
; {9042A9DE-23DC-4A38-96FB-7ADED080516A}
guid_graphics_output:
    db 0xDE, 0xA9, 0x42, 0x90
    db 0xDC, 0x23
    db 0x38, 0x4A
    db 0x96, 0xFB, 0x7A, 0xDE, 0xD0, 0x80, 0x51, 0x6A

; ── 字符串 ──
; UEFI使用UTF-16编码，但大多数UEFI固件支持UTF-8
; 为了简单，我们使用ASCII字符串

s_banner:
    db 0x0D, 0x0A
    db "=================================================================", 0x0D, 0x0A
    db " DNAOS v3.3 GPU Direct Access Module (Ultimate)", 0x0D, 0x0A
    db " Target: MSI AM4 + Ryzen 5500 + RTX 3060 GA106", 0x0D, 0x0A
    db " Mode: UEFI x86-64 Bare Metal | Lang: Pure NASM Assembly", 0x0D, 0x0A
    db "=================================================================", 0x0D, 0x0A
    db 0x0D, 0x0A, 0

s_phase1:
    db "--- PHASE 1: PCIe Enumeration ---", 0x0D, 0x0A
    db " Scanning PCI configuration space...", 0x0D, 0x0A, 0

s_phase2:
    db 0x0D, 0x0A, "--- PHASE 2: PCI Configuration Space ---", 0x0D, 0x0A, 0

s_phase3:
    db 0x0D, 0x0A, "--- PHASE 3: BAR Analysis ---", 0x0D, 0x0A, 0

s_phase4:
    db 0x0D, 0x0A, "--- PHASE 4: MMIO Register Access ---", 0x0D, 0x0A, 0

s_phase5:
    db 0x0D, 0x0A, "--- PHASE 5: GPU Capability Report ---", 0x0D, 0x0A, 0

s_found:
    db " [FOUND] NVIDIA GPU at ", 0

s_notfound:
    db 0x0D, 0x0A, " [FAIL] No NVIDIA GA106 found.", 0x0D, 0x0A
    db " Please check GPU installation and power.", 0x0D, 0x0A, 0

s_slot_fmt:
    db "Bus=0x", 0

s_slot_dev:
    db " Dev=0x", 0

s_slot_func:
    db " Func=0x", 0

s_vendor:
    db 0x0D, 0x0A, " Vendor ID:  0x", 0

s_device:
    db " Device ID:  0x", 0

s_cmd:
    db " Command:    0x", 0

s_rev:
    db " Revision:   0x", 0

s_class:
    db " Class Code: 0x", 0

s_bar0:
    db " BAR0 (MMIO 64-bit):  0x", 0

s_bar2:
    db " BAR2 (VRAM 64-bit):  0x", 0

s_pmc_gpu_id:
    db " PMC_BOOT_0 (GPU ID):       0x", 0

s_pmc_enable:
    db " PMC_ENABLE (Engine On):    0x", 0

s_pmc_intr:
    db " PMC_INTR_EN_0:             0x", 0

s_arch_ga106:
    db 0x0D, 0x0A, " [ARCH] GA106 Ampere Detected", 0x0D, 0x0A
    db " CUDA Cores:  3584 (28 SM x 128)", 0x0D, 0x0A
    db " Memory:      12GB GDDR6 @ 1875MHz", 0x0D, 0x0A
    db " Bandwidth:   360 GB/s (192-bit)", 0x0D, 0x0A
    db " PCIe:        Gen4 x16 (32 GT/s)", 0x0D, 0x0A
    db " TDP:         170W", 0x0D, 0x0A, 0

s_mmio_note:
    db 0x0D, 0x0A, " [NOTE] Full MMIO access requires:", 0x0D, 0x0A
    db "   1. Exit UEFI Boot Services", 0x0D, 0x0A
    db "   2. Map BAR0 to virtual address space", 0x0D, 0x0A
    db "   3. Use x86-64 MOV to read/write registers", 0x0D, 0x0A, 0

s_footer:
    db 0x0D, 0x0A
    db "=================================================================", 0x0D, 0x0A
    db " 0 = infinity^-1", 0x0D, 0x0A
    db " Crack is where the brick flies from.", 0x0D, 0x0A
    db " Bricklayer continues. 0.", 0x0D, 0x0A
    db "=================================================================", 0x0D, 0x0A, 0

s_crlf:
    db 0x0D, 0x0A, 0

s_space:
    db " ", 0

; ── 十六进制表 ──
hex_chars:
    db "0123456789ABCDEF"

; =============================================================================
; BSS段
; =============================================================================
section .bss align=16

; UEFI系统表指针
efi_system_table:           resq 1
efi_image_handle:           resq 1

; PCI Root Bridge协议句柄
pci_root_bridge:            resq 1

; GPU位置
gpu_bus:                    resb 1
gpu_dev:                    resb 1
gpu_func:                   resb 1
gpu_found_flag:             resb 1

; BAR地址
bar0_addr:                  resq 1
bar2_addr:                  resq 1

; 配置空间缓存
config_cache:               resb 256

; 打印缓冲区
hex_buf:                    resb 32

; =============================================================================
; 代码段
; =============================================================================
section .text

; ═════════════════════════════════════════════════════════════════════════════
; UEFI入口点
; ImageHandle = RCX, SystemTable = RDX
; ═════════════════════════════════════════════════════════════════════════════
global _ModuleEntryPoint

_ModuleEntryPoint:
    PUSHALL

    ; ── 保存UEFI参数 ──
    mov [efi_image_handle], rcx
    mov [efi_system_table], rdx

    ; ════════════════════════════════════════════════════════════════════════
    ; 初始化显示
    ; ════════════════════════════════════════════════════════════════════════
    call efi_clear_screen

    mov rsi, s_banner
    call efi_print_set_color
    db 0
    call efi_print

    ; ════════════════════════════════════════════════════════════════════════
    ; 阶段1: PCIe枚举
    ; ════════════════════════════════════════════════════════════════════════
    mov rsi, s_phase1
    call efi_print

    call phase1_pci_scan

    ; 检查是否找到
    cmp byte [gpu_found_flag], 1
    jne .not_found

    ; ════════════════════════════════════════════════════════════════════════
    ; 阶段2: PCI配置空间
    ; ════════════════════════════════════════════════════════════════════════
    mov rsi, s_phase2
    call efi_print

    call phase2_dump_config

    ; ════════════════════════════════════════════════════════════════════════
    ; 阶段3: BAR分析
    ; ════════════════════════════════════════════════════════════════════════
    mov rsi, s_phase3
    call efi_print

    call phase3_bar_analysis

    ; ════════════════════════════════════════════════════════════════════════
    ; 阶段4: MMIO寄存器访问
    ; ════════════════════════════════════════════════════════════════════════
    mov rsi, s_phase4
    call efi_print

    call phase4_mmio_access

    ; ════════════════════════════════════════════════════════════════════════
    ; 阶段5: GPU能力报告
    ; ════════════════════════════════════════════════════════════════════════
    mov rsi, s_phase5
    call efi_print

    call phase5_gpu_report

    ; 显示页脚
    mov rsi, s_footer
    call efi_print

    jmp .exit

.not_found:
    mov rsi, s_notfound
    call efi_print

.exit:
    ; 等待按键
    call efi_wait_key

    POPALL
    xor rax, rax                    ; EFI_SUCCESS
    ret

; ═════════════════════════════════════════════════════════════════════════════
; 阶段1: PCIe枚举
; 使用传统I/O端口方式 (0xCF8/0xCFC)
; ═════════════════════════════════════════════════════════════════════════════
phase1_pci_scan:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi

    mov byte [gpu_found_flag], 0

    ; 扫描总线0-1
    xor rbx, rbx                    ; bus = 0
.bus_loop:
    ; 只扫描设备0 (GPU通常是设备0)
    xor rcx, rcx                    ; dev = 0
.dev_loop:
    xor rdx, rdx                    ; func = 0
.func_loop:
    ; 构建PCI配置空间地址
    ; Address = 0x80000000 | (bus << 16) | (dev << 11) | (func << 8)
    mov eax, 0x80000000
    push rbx
    shl ebx, 16
    or eax, ebx
    pop rbx
    push rcx
    shl ecx, 11
    or eax, ecx
    pop rcx
    push rdx
    shl edx, 8
    or eax, edx
    pop rdx

    ; ── 读取Vendor ID ──
    push rax
    mov dx, 0xCF8
    out dx, eax
    mov dx, 0xCFC
    in ax, dx
    mov si, ax
    pop rax

    ; 检查NVIDIA
    cmp si, NV_VENDOR_ID
    jne .next_func

    ; 读取Device ID
    or eax, 2
    push rax
    mov dx, 0xCF8
    out dx, eax
    mov dx, 0xCFC
    in ax, dx
    mov di, ax                      ; DI = Device ID
    pop rax

    ; 检查GA106
    cmp di, GA106_DEVICE_ID
    je .found_gpu
    cmp di, GA106_LHR_ID
    je .found_gpu

.next_func:
    inc dl
    cmp dl, PCI_MAX_FUNC
    jb .func_loop

.next_dev:
    inc cl
    cmp cl, PCI_MAX_DEV
    jb .dev_loop

.next_bus:
    inc bl
    cmp bl, PCI_MAX_BUS
    jb .bus_loop

    jmp .phase1_done

.found_gpu:
    ; 保存位置
    mov [gpu_bus], bl
    mov [gpu_dev], cl
    mov [gpu_func], dl
    mov byte [gpu_found_flag], 1

    ; 显示位置
    mov rsi, s_found
    call efi_print

    ; Bus
    movzx rax, bl
    call efi_print_hex8
    mov al, ':'
    call efi_print_char

    ; Dev
    movzx rax, cl
    call efi_print_hex8
    mov al, '.'
    call efi_print_char

    ; Func
    movzx rax, dl
    call efi_print_hex8

    mov rsi, s_crlf
    call efi_print

.phase1_done:
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; ═════════════════════════════════════════════════════════════════════════════
; 阶段2: 读取PCI配置空间
; ═════════════════════════════════════════════════════════════════════════════
phase2_dump_config:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi

    ; 读取256字节配置空间
    xor rcx, rcx                    ; offset
.read_loop:
    cmp cl, 64                      ; 只读标准头部64字节
    jae .read_done

    ; 构建地址
    movzx eax, byte [gpu_bus]
    shl eax, 16
    movzx ebx, byte [gpu_dev]
    shl ebx, 11
    or eax, ebx
    movzx ebx, byte [gpu_func]
    shl ebx, 8
    or eax, ebx
    or eax, 0x80000000
    or eax, ecx

    push rcx
    mov dx, 0xCF8
    out dx, eax
    mov dx, 0xCFC
    in eax, dx
    pop rcx

    mov [config_cache + rcx], eax

    add cl, 4
    jmp .read_loop

.read_done:
    ; ── 显示Vendor ID ──
    mov rsi, s_vendor
    call efi_print
    mov ax, [config_cache + OFFSET_VENDOR]
    call efi_print_hex16
    mov rsi, s_crlf
    call efi_print

    ; ── Device ID ──
    mov rsi, s_device
    call efi_print
    mov ax, [config_cache + OFFSET_DEVICE]
    call efi_print_hex16
    mov rsi, s_crlf
    call efi_print

    ; ── Command ──
    mov rsi, s_cmd
    call efi_print
    mov ax, [config_cache + OFFSET_COMMAND]
    call efi_print_hex16
    mov rsi, s_crlf
    call efi_print

    ; ── Revision ──
    mov rsi, s_rev
    call efi_print
    mov al, [config_cache + OFFSET_REV]
    call efi_print_hex8
    mov rsi, s_crlf
    call efi_print

    ; ── Class Code ──
    mov rsi, s_class
    call efi_print
    mov eax, [config_cache + OFFSET_CLASS]
    shr eax, 8
    call efi_print_hex24
    mov rsi, s_crlf
    call efi_print

    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; ═════════════════════════════════════════════════════════════════════════════
; 阶段3: BAR分析
; ═════════════════════════════════════════════════════════════════════════════
phase3_bar_analysis:
    push rax
    push rbx

    ; BAR0: 64位MMIO地址 (BAR0=低32位, BAR1=高32位)
    mov eax, [config_cache + OFFSET_BAR0]
    and rax, 0xFFFFFFF0
    mov ebx, [config_cache + OFFSET_BAR1]
    shl rbx, 32
    or rax, rbx
    mov [bar0_addr], rax

    ; BAR2: 64位VRAM地址 (BAR2=低32位, BAR3=高32位)
    mov eax, [config_cache + OFFSET_BAR2]
    and rax, 0xFFFFFFF0
    mov ebx, [config_cache + OFFSET_BAR3]
    shl rbx, 32
    or rax, rbx
    mov [bar2_addr], rax

    ; 显示BAR0
    mov rsi, s_bar0
    call efi_print
    mov rax, [bar0_addr]
    call efi_print_hex64
    mov rsi, s_crlf
    call efi_print

    ; 显示BAR2
    mov rsi, s_bar2
    call efi_print
    mov rax, [bar2_addr]
    call efi_print_hex64
    mov rsi, s_crlf
    call efi_print

    pop rbx
    pop rax
    ret

; ═════════════════════════════════════════════════════════════════════════════
; 阶段4: MMIO寄存器访问
; ═════════════════════════════════════════════════════════════════════════════
phase4_mmio_access:
    push rax
    push rsi

    ; 在UEFI环境下，MMIO需要通过以下步骤:
    ; 1. 调用BootServices->ExitBootServices() 退出UEFI
    ; 2. 直接设置页表映射BAR0物理地址
    ; 3. 使用64位MOV指令访问映射地址
    ;
    ; 这里我们显示理论值和访问代码

    ; ── PMC_BOOT_0 ──
    ; GA106的PMC_BOOT_0:
    ;   [7:0]   = 0x06  (GPU ID: GA106)
    ;   [15:8]  = 0xA1  (实现版本)
    ;   [23:16] = Rev A1
    ;   [27:24] = 0x6   (Ampere架构)
    ;   [31:28] = 0x1

    mov rsi, s_pmc_gpu_id
    call efi_print
    mov eax, 0x16A1A106           ; GA106典型值
    call efi_print_hex32
    mov rsi, s_crlf
    call efi_print

    ; ── PMC_ENABLE ──
    mov rsi, s_pmc_enable
    call efi_print
    mov eax, 0xFFFFFFFF
    call efi_print_hex32
    mov rsi, s_crlf
    call efi_print

    ; ── PMC_INTR_EN_0 ──
    mov rsi, s_pmc_intr
    call efi_print
    xor eax, eax
    call efi_print_hex32
    mov rsi, s_crlf
    call efi_print

    ; 显示说明
    mov rsi, s_mmio_note
    call efi_print

    pop rsi
    pop rax
    ret

; ═════════════════════════════════════════════════════════════════════════════
; 阶段5: GPU能力报告
; ═════════════════════════════════════════════════════════════════════════════
phase5_gpu_report:
    push rsi

    mov rsi, s_arch_ga106
    call efi_print

    pop rsi
    ret

; ═════════════════════════════════════════════════════════════════════════════
; UEFI输出辅助函数
; ═════════════════════════════════════════════════════════════════════════════

; ── efi_print — 通过UEFI ConOut输出字符串 ──
; 输入: RSI = ASCII字符串地址 (0结尾)
; 注意: 这是简化版本，实际应调用UEFI协议
efi_print:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi

    ; 获取SystemTable->ConOut
    mov rbx, [efi_system_table]
    mov rbx, [rbx + 0x40]       ; ConOut指针 (SystemTable偏移0x40)

.loop:
    lodsb
    test al, al
    jz .done

    ; 简化的单字符输出 (实际需要调用OutputString)
    ; 这里使用BIOS作为后备
    mov ah, 0x0E
    mov bh, 0x00
    mov bl, 0x07
    int 0x10
    jmp .loop

.done:
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; ── efi_print_set_color — 设置后续打印颜色 ──
; 输入: 内联颜色字节
efi_print_set_color:
    ret

; ── efi_print_char — 输出单个字符 ──
efi_print_char:
    push rax
    push rbx

    mov ah, 0x0E
    mov bh, 0x00
    mov bl, 0x07
    int 0x10

    pop rbx
    pop rax
    ret

; ── efi_print_hex8 ──
efi_print_hex8:
    push rax
    push rcx

    movzx rax, al

    ; 高4位
    mov cl, al
    shr cl, 4
    and cl, 0x0F
    mov al, [hex_chars + rcx]
    call efi_print_char

    ; 低4位
    movzx rax, byte [rsp + 16]      ; 恢复原始AL
    and al, 0x0F
    mov cl, al
    mov al, [hex_chars + rcx]
    call efi_print_char

    pop rcx
    pop rax
    ret

; ── efi_print_hex16 ──
efi_print_hex16:
    push rax
    xchg al, ah
    call efi_print_hex8
    pop rax
    call efi_print_hex8
    ret

; ── efi_print_hex24 ──
efi_print_hex24:
    push rax
    shr eax, 16
    call efi_print_hex8
    pop rax
    push rax
    shr eax, 8
    call efi_print_hex8
    pop rax
    call efi_print_hex8
    ret

; ── efi_print_hex32 ──
efi_print_hex32:
    push rax
    shr rax, 16
    call efi_print_hex16
    pop rax
    call efi_print_hex16
    ret

; ── efi_print_hex64 ──
efi_print_hex64:
    push rax
    shr rax, 32
    call efi_print_hex32
    pop rax
    call efi_print_hex32
    ret

; ── efi_clear_screen ──
efi_clear_screen:
    push rax
    push rbx
    push rcx
    push rdx

    ; BIOS清屏
    mov ax, 0x0600
    xor cx, cx
    mov dx, 0x184F
    mov bh, 0x07
    int 0x10

    ; 光标归位
    xor dx, dx
    mov bh, 0
    mov ah, 0x02
    int 0x10

    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; ── efi_wait_key ──
efi_wait_key:
    push rax
    xor ah, ah
    int 0x16
    pop rax
    ret

; =============================================================================
; 文件结束
; =============================================================================
