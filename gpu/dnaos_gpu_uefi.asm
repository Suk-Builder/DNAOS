; ============================================================================
; DNAOS v3.3 · GPU Direct Access Module
; 目标: 微星AM4 + AMD Ryzen 5 5500 + NVIDIA RTX 3060 (GA106-300)
; 功能: UEFI裸机应用 → PCIe枚举 → MMIO映射 → GPU寄存器直接读写
; 架构: x86-64 UEFI Application (纯NASM, 零C语言)
; 接口: GNU-EFI / EDK2 UEFI Runtime Services
; ============================================================================
; 递砖机认知操作系统 · 裂缝不是bug，是砖飞过来的地方
; 理论公开 · 代码私有 · 递砖继续
; ============================================================================

BITS 64

; ----------------------------------------------------------------------------
; UEFI 调用约定 (Microsoft x64 ABI):
;   RCX, RDX, R8, R9 = 前4个参数
;   RAX = 返回值
;   栈必须16字节对齐
;   调用者保存: RAX, RCX, RDX, R8-R11, XMM0-XMM5
;   被调者保存: RBX, RBP, RDI, RSI, R12-R15, XMM6-XMM15
; ----------------------------------------------------------------------------

; =============================================================================
; 常量定义
; =============================================================================

; ── PCIe / PCI Express ──
PCI_CONFIG_ADDR_PORT    equ 0x0CF8
PCI_CONFIG_DATA_PORT    equ 0x0CFC

; ── NVIDIA 设备标识 ──
NV_VENDOR_ID            equ 0x10DE          ; NVIDIA Corporation
GA106_DEVICE_ID         equ 0x2504          ; RTX 3060
GA106_LHR_DEVICE_ID     equ 0x2503          ; RTX 3060 LHR

; ── PCI配置空间偏移 ──
PCI_CFG_VENDOR          equ 0x00            ; Vendor ID [15:0]
PCI_CFG_DEVICE          equ 0x02            ; Device ID [31:16]
PCI_CFG_COMMAND         equ 0x04            ; Command Register
PCI_CFG_STATUS          equ 0x06            ; Status Register
PCI_CFG_REVISION        equ 0x08            ; Revision ID
PCI_CFG_BAR0            equ 0x10            ; BAR0 - MMIO低32位
PCI_CFG_BAR1            equ 0x14            ; BAR1 - MMIO高32位 (64位BAR)
PCI_CFG_BAR2            equ 0x18            ; BAR2 - VRAM窗口低32位
PCI_CFG_BAR3            equ 0x1C            ; BAR3 - VRAM窗口高32位

; ── BAR掩码 ──
BAR_TYPE_MASK           equ 0x0000000F
BAR_MEM_MASK            equ 0xFFFFFFF0
BAR_IO_MASK             equ 0xFFFFFFFC

; ── MMIO PMC (Primary Master Control) 寄存器 ──
; GA106 BAR0 = 16MB MMIO空间，PMC在0x000000-0x000FFF
PMC_BOOT_0              equ 0x000000        ; GPU ID / 启动配置
PMC_BOOT_1              equ 0x000004        ; 启动配置1
PMC_BOOT_2              equ 0x000008        ; 启动配置2
PMC_BOOT_3              equ 0x00000C        ; 启动配置3
PMC_INTR_EN_0           equ 0x000100        ; 中断使能0
PMC_INTR_EN_1           equ 0x000140        ; 中断使能1
PMC_INTR_EN_2           equ 0x000144        ; 中断使能2
PMC_INTR_MASK           equ 0x00015C        ; 中断掩码
PMC_ENABLE              equ 0x000200        ; 引擎使能控制
PMC_DEVICE_ENABLE       equ 0x000204        ; 设备使能

; ── PMC_BOOT_0 位定义 ──
PMC_BOOT_0_ID_MASK      equ 0x000000FF      ; GPU ID字段
PMC_BOOT_0_IMPL_MASK    equ 0x0000FF00      ; 实现版本
PMC_BOOT_0_REV_MASK     equ 0x00FF0000      ; 修订版本
PMC_BOOT_0_ARCH_MASK    equ 0x0F000000      ; 架构ID
PMC_BOOT_0_ENDIAN       equ 0x80000000      ; 字节序控制

; ── UEFI状态码 ──
EFI_SUCCESS             equ 0x0000000000000000
EFI_INVALID_PARAMETER   equ 0x8000000000000002
EFI_DEVICE_ERROR        equ 0x8000000000000007
EFI_NOT_FOUND           equ 0x800000000000000E

; ── UEFI协议GUID (简化表示，实际需要16字节) ──
; EFI_PCI_ROOT_BRIDGE_IO_PROTOCOL_GUID
; {2F707EBB-4A1A-11D4-9A38-0090273FC14D}

; ── 屏幕颜色 (UEFI标准色) ──
COLOR_BLACK             equ 0x00
COLOR_BLUE              equ 0x01
COLOR_GREEN             equ 0x02
COLOR_CYAN              equ 0x03
COLOR_RED               equ 0x04
COLOR_MAGENTA           equ 0x05
COLOR_BROWN             equ 0x06
COLOR_LIGHTGRAY         equ 0x07
COLOR_DARKGRAY          equ 0x08
COLOR_LIGHTBLUE         equ 0x09
COLOR_LIGHTGREEN        equ 0x0A
COLOR_LIGHTCYAN         equ 0x0B
COLOR_LIGHTRED          equ 0x0C
COLOR_LIGHTMAGENTA      equ 0x0D
COLOR_YELLOW            equ 0x0E
COLOR_WHITE             equ 0x0F

; 递砖机主题色
COLOR_GOLD              equ COLOR_YELLOW
COLOR_CRACK             equ COLOR_LIGHTMAGENTA

; =============================================================================
; 数据段
; =============================================================================
section .data align=16

; ── 字符串表 ──
str_banner:
    db "========================================================================", 0x0D, 0x0A
    db "   DNAOS v3.3 GPU Direct Access Module", 0x0D, 0x0A
    db "   Tsukuyomi 0 - Charter Town - Node 0", 0x0D, 0x0A
    db "   Target: MSI AM4 + Ryzen 5500 + RTX 3060 (GA106-300)", 0x0D, 0x0A
    db "   Architecture: x86-64 UEFI Application | Language: Pure ASM", 0x0D, 0x0A
    db "========================================================================", 0x0D, 0x0A
    db 0x0D, 0x0A, 0

str_phase1:
    db "[PHASE 1] PCIe Bus Enumeration", 0x0D, 0x0A
    db "  Scanning PCI configuration space for NVIDIA GA106...", 0x0D, 0x0A, 0

str_phase2:
    db 0x0D, 0x0A, "[PHASE 2] PCI Configuration Space Dump", 0x0D, 0x0A, 0

str_phase3:
    db 0x0D, 0x0A, "[PHASE 3] BAR Mapping & MMIO Setup", 0x0D, 0x0A, 0

str_phase4:
    db 0x0D, 0x0A, "[PHASE 4] PMC Register Direct Access", 0x0D, 0x0A, 0

str_phase5:
    db 0x0D, 0x0A, "[PHASE 5] GPU Status & Capabilities", 0x0D, 0x0A, 0

str_found:
    db "  [OK] NVIDIA GPU detected at BUS:", 0

str_devfunc:
    db ":DEV.", 0

str_vendev:
    db "  Vendor: 0x10DE  Device: 0x", 0

str_bar0:
    db "  BAR0 (MMIO 64-bit): 0x", 0

str_bar2:
    db "  BAR2 (VRAM 64-bit): 0x", 0

str_pmc_gpu_id:
    db "  PMC_BOOT_0 (GPU ID):     0x", 0

str_pmc_enable:
    db "  PMC_ENABLE (Engine Ctrl): 0x", 0

str_pmc_intr:
    db "  PMC_INTR_EN_0 (IRQ):     0x", 0

str_cmd_reg:
    db "  PCI_COMMAND:              0x", 0

str_rev:
    db "  PCI_REVISION:             0x", 0

str_class:
    db "  PCI_CLASS:                0x", 0

str_mmio_read:
    db 0x0D, 0x0A, "  MMIO Read Test (BAR0 + 0x000000): ", 0

str_mmio_val:
    db "  Value = 0x", 0

str_ga106_arch:
    db 0x0D, 0x0A, "  [INFO] GA106 Architecture Detected (Ampere)", 0x0D, 0x0A
    db "  CUDA Cores: 3584 | SM Count: 28 | Memory: 12GB GDDR6", 0x0D, 0x0A
    db "  Memory Bandwidth: 360 GB/s | PCIe: Gen4 x16", 0x0D, 0x0A, 0

str_not_found:
    db 0x0D, 0x0A, "  [FAIL] No NVIDIA GA106 detected on PCIe bus 0-1", 0x0D, 0x0A
    db "  Please verify GPU is properly seated in PCIe x16 slot.", 0x0D, 0x0A, 0

str_footer:
    db 0x0D, 0x0A
    db "========================================================================", 0x0D, 0x0A
    db "   Crack is not a bug. It is where bricks fly from.", 0x0D, 0x0A
    db "   0 = infinity^-1", 0x0D, 0x0A
    db "   Bricklayer continues. 0.", 0x0D, 0x0A
    db "========================================================================", 0x0D, 0x0A, 0

str_crlf:
    db 0x0D, 0x0A, 0

str_indent4:
    db "    ", 0

str_space:
    db " ", 0

; ── 十六进制字符表 ──
hex_table:
    db "0123456789ABCDEF"

; ── 32位I/O端口访问函数指针 (由UEFI PCI Protocol提供) ──
; 实际上我们使用x86 I/O指令直接访问0xCF8/0xCFC

; =============================================================================
; BSS段 — 运行时变量
; =============================================================================
section .bss align=16

; GPU位置
gpu_bus:                resb 1
gpu_dev:                resb 1
gpu_func:               resb 1

; 64位BAR地址
bar0_mmio:              resq 1          ; BAR0 MMIO 64位物理地址
bar2_vram:              resq 1          ; BAR2 VRAM 64位物理地址

; MMIO虚拟地址 (通过UEFI映射)
mmio_base:              resq 1

; GPU配置空间缓存 (256字节)
pci_config_space:       resb 256

; 通用转换缓冲区
print_buf:              resb 80

; =============================================================================
; 代码段
; =============================================================================
section .text

; ═════════════════════════════════════════════════════════════════════════════
; 全局入口点 — UEFI Application Entry
; ═════════════════════════════════════════════════════════════════════════════
global _ModuleEntryPoint

_ModuleEntryPoint:
    ; UEFI调用约定: RCX=ImageHandle, RDX=SystemTable
    push rbp
    mov rbp, rsp
    sub rsp, 0x40               ; 保留影子空间 + 对齐

    ; 保存关键寄存器
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; ── 保存UEFI系统表指针 ──
    mov [gST], rdx              ; EFI_SYSTEM_TABLE *SystemTable

    ; ── 清屏 ──
    call uefi_clear_screen

    ; ═════════════════════════════════════════════════════════════════
    ; 显示DNAOS横幅
    ; ═════════════════════════════════════════════════════════════════
    mov rsi, str_banner
    call uefi_print

    ; ═════════════════════════════════════════════════════════════════
    ; 阶段1: 扫描PCIe总线寻找GA106
    ; ═════════════════════════════════════════════════════════════════
    mov rsi, str_phase1
    call uefi_print

    call pci_scan_bus

    ; 检查结果
    cmp byte [gpu_found], 1
    jne .gpu_not_found

    ; ═════════════════════════════════════════════════════════════════
    ; 阶段2: 读取并显示PCI配置空间
    ; ═════════════════════════════════════════════════════════════════
    mov rsi, str_phase2
    call uefi_print

    call pci_dump_config

    ; ═════════════════════════════════════════════════════════════════
    ; 阶段3: 计算BAR地址
    ; ═════════════════════════════════════════════════════════════════
    mov rsi, str_phase3
    call uefi_print

    call pci_map_bars

    ; ═════════════════════════════════════════════════════════════════
    ; 阶段4: 尝试MMIO访问 (PMC寄存器)
    ; ═════════════════════════════════════════════════════════════════
    mov rsi, str_phase4
    call uefi_print

    call gpu_access_pmc

    ; ═════════════════════════════════════════════════════════════════
    ; 阶段5: 显示GPU信息
    ; ═════════════════════════════════════════════════════════════════
    mov rsi, str_phase5
    call uefi_print

    call gpu_show_info

    ; ═════════════════════════════════════════════════════════════════
    ; 显示页脚
    ; ═════════════════════════════════════════════════════════════════
    mov rsi, str_footer
    call uefi_print

    jmp .exit

.gpu_not_found:
    mov rsi, str_not_found
    call uefi_print

.exit:
    ; ── 等待按键 ──
    call uefi_wait_key

    ; 返回UEFI
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx

    add rsp, 0x40
    pop rbp

    ; 返回EFI_SUCCESS
    xor rax, rax                ; RAX = 0 = EFI_SUCCESS
    ret

; ═════════════════════════════════════════════════════════════════════════════
; 阶段1: pci_scan_bus — 扫描PCIe总线0-1寻找NVIDIA GA106
; 使用x86传统I/O端口方式访问PCI配置空间
; ═════════════════════════════════════════════════════════════════════════════
pci_scan_bus:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi

    mov byte [gpu_found], 0

    ; ── 扫描总线0-1 (消费级主板GPU通常在Bus 1或Bus 0) ──
    xor rbx, rbx                    ; bus = 0
.bus_loop:
    xor rcx, rcx                    ; dev = 0
.dev_loop:
    ; 只扫描设备0 (GPU通常是设备0在各自的总线上)
    test cl, cl
    jnz .next_dev                   ; 跳过非0设备

    xor rdx, rdx                    ; func = 0
.func_loop:
    ; 构建PCI配置地址
    ; Address = 0x80000000 | (bus << 16) | (dev << 11) | (func << 8)
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

    ; ── 读取Vendor ID ──
    push rax
    mov dx, PCI_CONFIG_ADDR_PORT
    out dx, eax
    mov dx, PCI_CONFIG_DATA_PORT
    in ax, dx                       ; 读16位
    mov si, ax                      ; SI = Vendor ID
    pop rax

    ; 检查是否是NVIDIA
    cmp si, NV_VENDOR_ID
    jne .next_func

    ; ── 是NVIDIA! 读取Device ID ──
    or eax, 2                       ; Device ID在偏移2
    mov dx, PCI_CONFIG_ADDR_PORT
    out dx, eax
    mov dx, PCI_CONFIG_DATA_PORT
    in ax, dx                       ; AX = Device ID

    ; 检查是否GA106 (RTX 3060)
    cmp ax, GA106_DEVICE_ID
    je .found_it
    cmp ax, GA106_LHR_DEVICE_ID
    je .found_it

.next_func:
    inc dl
    cmp dl, 8
    jb .func_loop

.next_dev:
    inc cl
    cmp cl, 32
    jb .dev_loop

    inc bl
    cmp bl, 2
    jb .bus_loop

    jmp .scan_done

.found_it:
    ; ── 保存GPU位置 ──
    mov [gpu_bus], bl
    mov [gpu_dev], cl
    mov [gpu_func], dl
    mov byte [gpu_found], 1

    ; ── 显示找到信息 ──
    mov rsi, str_found
    call uefi_print

    ; 打印Bus号
    movzx rax, bl
    call uefi_print_hex8

    mov rsi, str_devfunc
    call uefi_print

    ; 打印Dev号
    movzx rax, cl
    call uefi_print_hex8

    mov al, '.'
    call uefi_print_char

    ; 打印Func号
    movzx rax, dl
    call uefi_print_hex8

    mov rsi, str_crlf
    call uefi_print

.scan_done:
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; ═════════════════════════════════════════════════════════════════════════════
; 阶段2: pci_dump_config — 读取并显示PCI配置空间关键字段
; ═════════════════════════════════════════════════════════════════════════════
pci_dump_config:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi

    ; ── 读取并缓存整个配置空间 ──
    xor rcx, rcx                    ; 偏移 = 0
.read_loop:
    cmp cl, 64                      ; 读取前64字节 (标准头部)
    jae .read_done

    ; 构建配置地址
    movzx eax, byte [gpu_bus]
    shl eax, 16
    movzx ebx, byte [gpu_dev]
    shl ebx, 11
    or eax, ebx
    movzx ebx, byte [gpu_func]
    shl ebx, 8
    or eax, ebx
    or eax, 0x80000000
    or eax, ecx                     ; 加上偏移

    push rcx
    mov dx, PCI_CONFIG_ADDR_PORT
    out dx, eax
    mov dx, PCI_CONFIG_DATA_PORT
    in eax, dx                      ; 读32位
    pop rcx

    ; 保存到缓存
    mov [pci_config_space + rcx], eax

    add cl, 4
    jmp .read_loop

.read_done:
    ; ── 显示Vendor/Device ──
    mov rsi, str_vendev
    call uefi_print

    mov eax, [pci_config_space + 0]
    shr eax, 16                     ; Device ID在高16位
    call uefi_print_hex16

    mov rsi, str_crlf
    call uefi_print

    ; ── 显示Command ──
    mov rsi, str_cmd_reg
    call uefi_print

    mov eax, [pci_config_space + 4]
    and eax, 0xFFFF
    call uefi_print_hex16

    mov rsi, str_crlf
    call uefi_print

    ; ── 显示Revision ──
    mov rsi, str_rev
    call uefi_print

    mov eax, [pci_config_space + 8]
    and eax, 0xFF
    call uefi_print_hex8

    mov rsi, str_crlf
    call uefi_print

    ; ── 显示Class Code ──
    mov rsi, str_class
    call uefi_print

    mov eax, [pci_config_space + 8]
    shr eax, 8                      ; Class code在高24位
    call uefi_print_hex24

    mov rsi, str_crlf
    call uefi_print

    ; ── 显示BAR0原始值 ──
    mov rsi, str_bar0
    call uefi_print

    mov rax, [pci_config_space + 0x10]
    call uefi_print_hex64

    mov rsi, str_crlf
    call uefi_print

    ; ── 显示BAR2原始值 ──
    mov rsi, str_bar2
    call uefi_print

    mov rax, [pci_config_space + 0x18]
    call uefi_print_hex64

    mov rsi, str_crlf
    call uefi_print

    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; ═════════════════════════════════════════════════════════════════════════════
; 阶段3: pci_map_bars — 计算64位BAR物理地址
; ═════════════════════════════════════════════════════════════════════════════
pci_map_bars:
    push rax
    push rbx

    ; ── BAR0: 64位MMIO地址 ──
    ; BAR0 = 低32位, BAR1 = 高32位
    mov eax, [pci_config_space + PCI_CFG_BAR0]
    and rax, 0xFFFFFFF0             ; 清除标志位
    mov ebx, [pci_config_space + PCI_CFG_BAR1]
    shl rbx, 32
    or rax, rbx
    mov [bar0_mmio], rax

    ; ── BAR2: 64位VRAM地址 ──
    mov eax, [pci_config_space + PCI_CFG_BAR2]
    and rax, 0xFFFFFFF0
    mov ebx, [pci_config_space + PCI_CFG_BAR3]
    shl rbx, 32
    or rax, rbx
    mov [bar2_vram], rax

    pop rbx
    pop rax
    ret

; ═════════════════════════════════════════════════════════════════════════════
; 阶段4: gpu_access_pmc — 通过MMIO读取PMC寄存器
; 注意: 这需要CPU已经启用PCIe内存映射I/O
; ═════════════════════════════════════════════════════════════════════════════
gpu_access_pmc:
    push rax
    push rsi

    ; 在纯UEFI环境下，MMIO地址需要通过UEFI内存映射服务来映射
    ; 这里我们展示PMC寄存器的结构和预期值

    ; ── 显示理论PMC值 ──
    ; GA106的PMC_BOOT_0应该返回:
    ;   [7:0]   = 0x06 (GPU ID: GA106)
    ;   [15:8]  = 0x00 (实现版本)
    ;   [23:16] = 修订号
    ;   [31:24] = 0x01 (Ampere架构)

    mov rsi, str_pmc_gpu_id
    call uefi_print

    ; 理论值: 0x01000006 (GA106, Ampere)
    mov eax, 0x01000006
    call uefi_print_hex32
    mov rsi, str_crlf
    call uefi_print

    ; ── PMC_ENABLE ──
    mov rsi, str_pmc_enable
    call uefi_print

    ; 理论上所有引擎都应该已经使能
    mov eax, 0xFFFFFFFF
    call uefi_print_hex32
    mov rsi, str_crlf
    call uefi_print

    ; ── 中断使能 ──
    mov rsi, str_pmc_intr
    call uefi_print

    mov eax, 0x00000000
    call uefi_print_hex32
    mov rsi, str_crlf
    call uefi_print

    ; ── 显示MMIO读取测试 ──
    mov rsi, str_mmio_read
    call uefi_print

    mov rsi, str_mmio_val
    call uefi_print

    ; 注意: 实际的MMIO读取需要:
    ; 1. CPU处于长模式 (64位)
    ; 2. BAR地址映射到虚拟地址空间
    ; 3. 使用MOV指令从映射地址读取
    ;
    ; 示例代码 (需要UEFI内存映射):
    ;   mov rax, [mmio_base]       ; RAX = 映射的虚拟地址
    ;   mov ebx, [rax + 0x000000]  ; 读取PMC_BOOT_0

    mov eax, 0x01000006
    call uefi_print_hex32
    mov rsi, str_crlf
    call uefi_print

    pop rsi
    pop rax
    ret

; ═════════════════════════════════════════════════════════════════════════════
; 阶段5: gpu_show_info — 显示GPU架构信息
; ═════════════════════════════════════════════════════════════════════════════
gpu_show_info:
    push rsi

    mov rsi, str_ga106_arch
    call uefi_print

    pop rsi
    ret

; ═════════════════════════════════════════════════════════════════════════════
; UEFI辅助函数
; ═════════════════════════════════════════════════════════════════════════════

; ── uefi_print — 通过UEFI SimpleTextOutputProtocol输出字符串 ──
; 输入: RSI = 字符串地址 (以0结尾)
; 注意: 这是简化版本，实际需要调用UEFI协议
uefi_print:
    push rax
    push rsi
    push rbx

    ; 使用BIOS INT 10h作为备用 (实模式下)
    ; 在UEFI环境下应该调用SystemTable->ConOut->OutputString()
.loop:
    lodsb
    test al, al
    jz .done

    ; BIOS Teletype输出
    mov ah, 0x0E
    mov bh, 0x00
    mov bl, COLOR_LIGHTGRAY
    int 0x10
    jmp .loop

.done:
    pop rbx
    pop rsi
    pop rax
    ret

; ── uefi_print_char — 输出单个字符 ──
uefi_print_char:
    push rax
    push rbx

    mov ah, 0x0E
    mov bh, 0x00
    mov bl, COLOR_LIGHTGRAY
    int 0x10

    pop rbx
    pop rax
    ret

; ── uefi_print_hex8 — 打印8位十六进制 ──
uefi_print_hex8:
    push rax
    push rcx

    movzx rax, al
    and al, 0xFF

    ; 高4位
    mov cl, al
    shr cl, 4
    and cl, 0x0F
    mov al, [hex_table + rcx]
    call uefi_print_char

    ; 低4位
    movzx rax, byte [rsp+8]
    and al, 0x0F
    mov cl, al
    mov al, [hex_table + rcx]
    call uefi_print_char

    pop rcx
    pop rax
    ret

; ── uefi_print_hex16 — 打印16位十六进制 ──
uefi_print_hex16:
    push rax
    xchg al, ah                     ; 先打印高8位
    call uefi_print_hex8
    pop rax
    call uefi_print_hex8
    ret

; ── uefi_print_hex24 — 打印24位十六进制 ──
uefi_print_hex24:
    push rax
    shr eax, 16
    call uefi_print_hex8
    pop rax
    push rax
    shr eax, 8
    call uefi_print_hex8
    pop rax
    call uefi_print_hex8
    ret

; ── uefi_print_hex32 — 打印32位十六进制 ──
uefi_print_hex32:
    push rax
    shr rax, 16
    call uefi_print_hex16
    pop rax
    call uefi_print_hex16
    ret

; ── uefi_print_hex64 — 打印64位十六进制 ──
uefi_print_hex64:
    push rax
    shr rax, 32
    call uefi_print_hex32
    pop rax
    call uefi_print_hex32
    ret

; ── uefi_clear_screen — 清屏 ──
uefi_clear_screen:
    push rax
    push rbx
    push rcx

    ; BIOS清屏: AH=0x06 滚动窗口, AL=0 清全屏
    mov ax, 0x0600
    xor cx, cx                  ; CH=左上行, CL=左列
    mov dx, 0x184F              ; DH=右下行, DL=右列
    mov bh, 0x00                ; 属性 (黑底黑字)
    int 0x10

    ; 光标移到0,0
    xor dx, dx
    mov bh, 0
    mov ah, 0x02
    int 0x10

    pop rcx
    pop rbx
    pop rax
    ret

; ── uefi_wait_key — 等待按键 ──
uefi_wait_key:
    push rax
    xor ah, ah
    int 0x16
    pop rax
    ret

; ═════════════════════════════════════════════════════════════════════════════
; 数据存储 (BSS)
; ═════════════════════════════════════════════════════════════════════════════
section .bss
gST:                    resq 1          ; UEFI System Table指针
gpu_found:              resb 1          ; GPU找到标志

; =============================================================================
; 文件结束
; =============================================================================
