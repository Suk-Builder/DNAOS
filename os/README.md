# DNAOS - Real Operating System (DNAsm-native)

**用DNAsm写的操作系统。BIOS直接启动，没有C，没有Linux，没有Python。**

## 语言

**DNAsm** = DNAOS的原生编程语言

| 特性 | 说明 |
|------|------|
| 寄存器 | rA(Adenine)=rax, rT(Thymine)=rcx, rC(Cytosine)=rdx, rG(Guanine)=rbx |
| 四进制指令 | qand, qor, qnot, qadd (ATCG-native) |
| 数据 | atcg "ATCGATCG" → 原始字节 |
| 编译 | .dna → dasm.py → .nasm → nasm → .o → ld → dnaos.bin |
| 自举 | 最终dasm.py用DNAsm重写自己 |

## 启动链

```
BIOS/UEFI
  └─> GRUB
       └─> boot.S (x86启动，唯一不用DNAsm的文件)
            └─> kernel.dna (DNAsm内核)
                 ├─> mm/pmm.dna       物理内存管理
                 ├─> mm/vmm.dna       虚拟内存管理
                 ├─> proc/scheduler.dna 进程调度
                 ├─> fs/vfs.dna       ATCG文件系统
                 ├─> drivers/keyboard.dna  PS/2键盘
                 ├─> drivers/mouse.dna     PS/2鼠标
                 ├─> drivers/pit.dna       定时器
                 ├─> drivers/pci.dna       PCI总线
                 ├─> drivers/e1000.dna     网卡
                 ├─> drivers/vga.dna       帧缓冲
                 ├─> drivers/ata.dna       硬盘
                 ├─> drivers/acpi.dna      电源管理
                 ├─> drivers/serial.dna    串口
                 ├─> gui/wm.dna       窗口管理器
                 ├─> sys/syscall.dna  系统调用
                 └─> shell/dnasm.dna  DNAsm Shell
```

## 为什么不用C？

| | C | DNAsm |
|---|---|---|
| 寄存器 | rax, rcx, rdx | rA, rT, rC |
| 四进制AND | 函数调用 | qand（原生指令） |
| 数据编码 | 手动位操作 | atcg "ATCG" |
| 语言归属 | 通用 | DNAOS自己的 |
| 自举 | 不可能 | 可以 |

## 快速开始

```bash
cd DNAOS/os

# 编译
make

# QEMU测试
make run

# 写U盘
make usb DEVICE=/dev/sdX
```

## 文件结构

```
os/
├── dasm/
│   ├── dasm.py           # DNAsm编译器
│   └── README.md         # 语言规范
├── kernel/
│   ├── boot.S            # x86启动代码（硬件要求）
│   ├── font.S            # 8x16位图字体
│   ├── linker.ld         # 链接脚本
│   ├── kernel.dna        # 内核主程序
│   ├── mm/
│   │   ├── pmm.dna       # 物理内存管理
│   │   └── vmm.dna       # 虚拟内存管理
│   ├── proc/
│   │   └── scheduler.dna # 进程调度器
│   ├── fs/
│   │   └── vfs.dna       # ATCG文件系统
│   ├── drivers/
│   │   ├── keyboard.dna  # PS/2键盘
│   │   ├── mouse.dna     # PS/2鼠标
│   │   ├── pit.dna       # 定时器
│   │   ├── pci.dna       # PCI总线
│   │   ├── e1000.dna     # Intel E1000网卡
│   │   ├── vga.dna       # 帧缓冲驱动
│   │   ├── ata.dna       # ATA/IDE硬盘
│   │   ├── acpi.dna      # ACPI电源管理
│   │   └── serial.dna    # 串口调试
│   ├── gui/
│   │   └── wm.dna        # 窗口管理器
│   ├── sys/
│   │   └── syscall.dna   # 系统调用
│   └── shell/
│       └── dnasm.dna     # DNAsm Shell
├── Makefile
└── README.md
```

## Shell命令

```
ATCG> H          帮助
ATCG> QAND a b   四进制AND
ATCG> QOR a b    四进制OR
ATCG> QNOT a     四进制NOT
ATCG> QADD a b   四进制ADD
ATCG> ATP        ATP预算
ATCG> LS         文件列表
ATCG> MEM        内存信息
ATCG> PROC       进程列表
ATCG> PCI        PCI设备
ATCG> NET        网络信息
ATCG> CLEAR      清屏
ATCG> BEEP       测试扬声器
ATCG> VER        版本信息
ATCG> REBOOT     重启
ATCG> SHUTDOWN   关机
ATCG> ATCG str   ATCG编码
```
