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
| 自举 | compiler.dna 用DNAsm写的编译器，能编译自己 |

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
                 ├─> drivers/serial.dna    串口调试
                 ├─> net/tcpip.dna   TCP/IP协议栈
                 ├─> gui/wm.dna       窗口管理器
                 ├─> sys/syscall.dna  系统调用
                 ├─> shell/dnasm.dna  DNAsm Shell
                 ├─> lib/stdlib.dna   标准库
                 └─> boot/compiler.dna 自举编译器
```

## 完整文件列表

```
os/
├── dasm/
│   ├── dasm.py           # DNAsm编译器 (Python引导)
│   └── README.md         # DNAsm语言规范
├── kernel/
│   ├── kernel.dna        # 内核主程序
│   ├── boot.S            # 启动汇编 (硬件要求)
│   ├── font.S            # 8x16位图字体
│   ├── linker.ld         # 链接脚本
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
│   ├── net/
│   │   └── tcpip.dna     # TCP/IP协议栈
│   ├── gui/
│   │   └── wm.dna        # 窗口管理器
│   ├── sys/
│   │   └── syscall.dna   # 系统调用
│   ├── shell/
│   │   └── dnasm.dna     # DNAsm Shell
│   ├── lib/
│   │   └── stdlib.dna    # 标准库
│   └── boot/
│       └── compiler.dna  # 自举编译器
├── usr/
│   └── programs.dna      # 用户程序
├── iso/
│   └── boot/grub/
│       └── grub.cfg      # GRUB配置
├── Makefile
└── README.md
```

## 网络协议栈

```
应用层    Shell命令 (ping, dns, dhcp)
传输层    TCP (三次握手, 四次挥手, 重传) / UDP
网络层    IP (分片重组, TTL) / ICMP (ping) / ARP
链路层    Ethernet (E1000驱动)
物理层    网卡硬件
```

## 自举编译器

```
Phase 1: Tokenizer   (.dna源码 → Token流)
Phase 2: Parser      (Token流 → AST)
Phase 3: Code Gen    (AST → x86_64机器码)
Phase 4: ELF Writer  (机器码 → ELF64可执行文件)

当compiler.dna能编译自己 → DNAOS自举完成
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
ATCG> CAT path   查看文件
ATCG> MEM        内存信息
ATCG> PROC       进程列表
ATCG> PCI        PCI设备
ATCG> NET        网络信息
ATCG> PING host  Ping
ATCG> DNS name   DNS查询
ATCG> DHCP       获取IP
ATCG> CLEAR      清屏
ATCG> BEEP       测试扬声器
ATCG> VER        版本信息
ATCG> REBOOT     重启
ATCG> SHUTDOWN   关机
ATCG> ATCG str   ATCG编码
ATCG> COMPILE file  编译DNAsm文件
```

## 构建

```bash
# 编译DNAsm到NASM
make compile

# 构建内核
make

# 制作ISO
make iso

# QEMU运行
make run

# 写U盘
make usb DEVICE=/dev/sdX
```

## 编译流程

```
.dna源码 → dasm.py → .nasm中间代码 → nasm → .o目标文件 → ld → dnaos.bin → grub → dnaos.iso
```
