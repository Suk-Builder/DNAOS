# DNAOS v3.3 · GPU Direct Access Module

## 目标平台

| 组件 | 型号 | 规格 |
|------|------|------|
| **主板** | 微星 MSI AM4 | B450/B550 芯片组 |
| **CPU** | AMD Ryzen 5 5500 | Zen 3, 6核12线程, 3.6-4.2GHz |
| **GPU** | NVIDIA RTX 3060 | GA106-300, 3584 CUDA核心, 12GB GDDR6 |

## 技术路线

```
UEFI Firmware (微星AMI BIOS)
    ↓
DNAOS.efi (本程序) — 纯x86-64汇编，零C语言
    ↓
PCIe枚举 → 定位GA106 → 读取配置空间 → 映射BAR0 → MMIO读写
    ↓
GPU寄存器直接访问 (PMC/PGRAPH/PCOPY等引擎)
```

## 五个阶段

### PHASE 1: PCIe总线枚举
- 使用x86 I/O端口 `0xCF8/0xCFC` 访问PCI配置空间
- 扫描总线0-1，设备0-31，功能0-7
- 匹配 Vendor ID = `0x10DE` (NVIDIA)
- 匹配 Device ID = `0x2504` (GA106 RTX 3060)

### PHASE 2: PCI配置空间转储
读取并显示标准PCI头部 (64字节):
- Vendor ID / Device ID
- Command / Status
- Revision ID
- Class Code (0x030000 = VGA控制器)
- BAR0-BAR5

### PHASE 3: BAR分析与映射
解析64位Base Address Register:

| BAR | 类型 | 用途 | 大小 |
|-----|------|------|------|
| BAR0+BAR1 | 64位MMIO | GPU寄存器空间 | 16MB |
| BAR2+BAR3 | 64位MMIO | VRAM窗口 | 256MB-8GB |
| BAR4 | 32位MMIO | 扩展功能 | - |
| BAR5 | - | 保留 | - |

GA106 MMIO布局 (16MB BAR0空间):
```
0x000000-0x000FFF  PMC      主控制器 (GPU ID、引擎开关)
0x001000-0x00FFFF  PBUS     总线控制
0x010000-0x01FFFF  PFIFO    GPU调度器
0x020000-0x03FFFF  PGRAPH   3D/计算引擎
0x040000-0x05FFFF  PCOPY    复制引擎
0x060000-0x07FFFF  PPCI     PCIe接口
0x080000-0x09FFFF  PVIC     视频编解码
0x0A0000-0x0BFFFF  PTHERM   温度/功耗
0x100000-0x1FFFFF  PDISPLAY 显示输出
0x200000-0xFFFFFF  其他引擎
```

### PHASE 4: MMIO寄存器直接访问
**PMC (Primary Master Control)** 关键寄存器:

| 偏移 | 名称 | 功能 |
|------|------|------|
| `0x000000` | PMC_BOOT_0 | GPU ID [7:0], 实现版本 [15:8], 修订 [23:16], 架构 [31:24] |
| `0x000200` | PMC_ENABLE | 引擎使能开关 (每一位对应一个引擎) |
| `0x000400` | PMC_INTR_0 | 中断状态 |
| `0x000404` | PMC_INTR_EN_0 | 中断使能 |

GA106预期PMC_BOOT_0值: `0x16A1A106`
- `0x06` = GPU ID: GA106
- `0xA1` = 实现版本 A1
- `0xA1` = 修订 A1
- `0x06` = Ampere架构

### PHASE 5: GPU能力报告
基于Device ID和PCI类代码推断:
- 架构: NVIDIA Ampere (GA106)
- CUDA核心: 3584 (28个SM × 128核心)
- Tensor Core: 112 (第三代)
- RT Core: 28 (第二代)
- 显存: 12GB GDDR6 @ 1875MHz
- 带宽: 360 GB/s (192-bit)
- PCIe: Gen4 x16

## 关键技术: 裸机PCIe访问

### 1. I/O端口方式 (本程序使用)

```nasm
; 构建配置地址
mov eax, 0x80000000         ; 使能位31
or  eax, (bus   << 16)      ; 总线号 [23:16]
or  eax, (dev   << 11)      ; 设备号 [15:11]
or  eax, (func  <<  8)      ; 功能号 [10:8]
or  eax, offset             ; 寄存器偏移 [7:2]

; 写入地址端口
mov dx, 0xCF8
out dx, eax

; 从数据端口读取
mov dx, 0xCFC
in  eax, dx                 ; EAX = 32位寄存器值
```

### 2. MMIO方式 (需要内存映射)

```nasm
; 前提: BAR0已映射到虚拟地址 [mmio_base]

; 读取GPU ID
mov rax, [mmio_base]        ; 读取PMC_BOOT_0

; 读取引擎使能状态
mov rax, [mmio_base + 0x200] ; 读取PMC_ENABLE

; 写入引擎控制
mov dword [mmio_base + 0x200], 0xFFFFFFFF ; 使能所有引擎
```

### 3. UEFI PCI Root Bridge I/O Protocol (推荐方式)

```nasm
; 获取协议
; LocateProtocol(&gEfiPciRootBridgeIoProtocolGuid, NULL, &PciRbIo)

; 使用Pci.Read函数
; PciRbIo->Pci.Read(PciRbIo, EfiPciWidthUint32, Address, Count, Buffer)
```

## 编译

### 方法1: 使用GNU-EFI

```bash
# 安装依赖
sudo apt install nasm gcc make gnu-efi

# 编译
nasm -f elf64 dnaos_gpu_direct.asm -o dnaos_gpu.o

gcc -nostdlib -znocombreloc -T /usr/lib/elf_x86_64_efi.lds \
    /usr/lib/crt0-efi-x86_64.o dnaos_gpu.o \
    -o dnaos_gpu.so -lefi -lgnuefi

objcopy -j .text -j .sdata -j .data -j .dynamic -j .dynsym \
    -j .rel -j .rela -j .reloc \
    --target efi-app-x86_64 --subsystem=10 \
    dnaos_gpu.so dnaos_gpu.efi
```

### 方法2: 使用EDK2

```bash
# 设置EDK2环境
source edksetup.sh

# 放置在正确的目录结构
# MyPkg/Application/DnaosGpu/DnaosGpu.inf
# MyPkg/Application/DnaosGpu/dnaos_gpu_direct.asm

# 编译
build -a X64 -t GCC5 -p MyPkg/MyPkg.dsc \
    -m MyPkg/Application/DnaosGpu/DnaosGpu.inf
```

## 实机测试

### 1. 准备U盘
```bash
# 格式化为FAT32
sudo mkfs.fat -F32 /dev/sdX1

# 创建目录结构
mkdir -p /mnt/efi/EFI/BOOT

# 复制EFI文件
cp dnaos_gpu.efi /mnt/efi/EFI/BOOT/BOOTX64.EFI
```

### 2. 微星主板启动
1. 插入U盘
2. 开机按 `DEL` 进入BIOS
3. 设置: Settings → Advanced → Windows OS Configuration → **Disable CSM**
4. 保存退出
5. 开机按 `F11` (Boot Menu)
6. 选择 `UEFI: USB Drive`

### 3. QEMU测试 (无GPU)
```bash
# 安装OVMF (UEFI固件)
sudo apt install ovmf

# 创建磁盘镜像
dd if=/dev/zero of=gpu_test.img bs=1M count=64
mkfs.fat gpu_test.img

# 挂载并复制
mkdir -p /mnt/efi
mount gpu_test.img /mnt/efi
mkdir -p /mnt/efi/EFI/BOOT
cp dnaos_gpu.efi /mnt/efi/EFI/BOOT/BOOTX64.EFI
umount /mnt/efi

# 运行 (注意: QEMU没有真实GPU，枚举会失败但程序不会崩溃)
qemu-system-x86_64 \
    -bios /usr/share/OVMF/OVMF_CODE.fd \
    -hda gpu_test.img \
    -m 4096 \
    -cpu host \
    -vga none \
    -nographic
```

## 已知限制

1. **GSP固件**: Turing/Ampere GPU需要NVIDIA签名的GSP固件才能完整初始化。没有固件无法运行计算任务。
2. **显示输出**: 需要初始化显示引擎和显存，这通常由UEFI GOP或VBIOS处理。
3. **UEFI环境**: 当前版本在UEFI Boot Services下运行，无法直接映射64位物理地址到虚拟地址。

## 进阶: 完整GPU控制

要获得完整的GPU控制权，需要:

1. **加载GSP固件**: 从NVIDIA驱动包中提取 `gsp_ga10x.bin`
2. **初始化内存控制器**: 配置GDDR6时序和电压
3. **启动GSP**: 通过PMC寄存器释放GSP复位
4. **建立命令队列**: 与GSP通信发送任务

这是Nouveau开源驱动正在逆向的工程。截至2025年:
- Nouveau支持GA106的基本显示 (GSP模式)
- 计算支持仍在开发中
- NVIDIA于2022年发布了开源内核模块 (GPL/MIT)

## 参考资源

| 项目 | 链接 | 说明 |
|------|------|------|
| envytools | https://github.com/envytools/envytools | NVIDIA GPU逆向工具 |
| Nouveau | https://nouveau.freedesktop.org | 开源NVIDIA驱动 |
| NVIDIA Open GPU | https://github.com/NVIDIA/open-gpu-kernel-modules | 官方开源内核模块 |
| EDK2 | https://github.com/tianocore/edk2 | UEFI开发环境 |
| GNU-EFI | https://sourceforge.net/projects/gnu-efi | UEFI库 |

## 递砖机术语

| 术语 | 含义 |
|------|------|
| 0 = ∞⁻¹ | 零公理: 零是无限的倒数 |
| 裂缝 | GPU架构中的边界/接口，不是bug |
| 递砖 | 将计算任务从CPU传递给GPU |
| 宪章小镇 | DNAOS的虚拟城市隐喻 |

---

**递砖继续。0。**
