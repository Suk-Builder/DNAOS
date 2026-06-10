# DNAOS v3.5 — 四进制存算一体操作系统

> **开发状态**：内核12个子系统代码完成，GRUB Multiboot2引导已通。用户态模拟器完整可用，裸机QEMU测试中。

---

## 项目概述

DNAOS 是一个以 **四进制（ATCG 碱基编码）** 为核心的存算一体操作系统，和Windows同级——不是套壳Linux，是从boot.S开始自己写的裸机OS。

- **四进制编码**：`00=A, 01=T, 10=C, 11=G`，每字节存储 4 个碱基
- **四进制逻辑门**：AND=min, OR=max, NOT=3-x, ADD=逐碱基进位加法
- **DNAsm 指令集**：自定义四进制汇编语言，56条操作码，10大类（DAT/IMM/REG/STR/MEM/JMP/MTH/SYS/LOG/VEC/CRK）
- **NSM数学后端**：忆阻器交叉阵列模拟，Null-Soft-Math
- **CPU模拟GPU**：Ryzen 5500 AVX2 模拟 GA106 RTX 3060 的 3584 CUDA 核心
- **裸机引导**：BIOS → GRUB Multiboot2 → boot.S(32→64) → kernel_main()
- **Tiny Tapeout芯片**：SkyWater 130nm四进制ALU Verilog，Python验证通过

---

## 目录结构

```
DNAOS/
├── os/                        # 裸机 OS（核心）
│   ├── kernel/                    # 内核源码
│   │   ├── kernel.c               # 主内核（12个子系统集成，单文件编译）
│   │   ├── boot.S                 # GRUB Multiboot2 入口 + ISR stubs
│   │   ├── font.S                 # 8x16 位图字体
│   │   ├── linker.ld              # 链接脚本
│   │   ├── minimal/               # 最小化内核（调试用）
│   │   ├── drivers/               # 驱动头文件（e1000/pci/pit/mouse）
│   │   ├── mm/                    # 内存管理（pmm.h/vmm.h）
│   │   ├── fs/                    # 文件系统（vfs.h）
│   │   ├── gui/                   # 窗口管理（wm.h）
│   │   ├── proc/                  # 进程管理（proc.h）
│   │   └── sys/                   # 系统调用（syscall.h）
│   ├── gen_disk_v4.py             # 主磁盘镜像生成器
│   ├── DESIGN_v34_quaternary.md   # v3.4 架构设计文档
│   └── build.sh                   # 构建脚本
│
├── simulator/                 # 用户态模拟器（Linux上运行）
│   ├── boot.c                  # 模拟器主入口（Genome→Transcript→Protein循环）
│   ├── dnasm_v33.c             # DNAsm v33 编译器（56条操作码）
│   ├── dnasm_v32.c             # DNAsm v32 编译器
│   ├── dnasm_nsm.c             # DNAsm NSM 后端
│   ├── gpu_emulator.c          # CPU模拟GPU并行（pthread+AVX2）
│   ├── dna_hal.c/h             # DNA硬件抽象层（试管模拟）
│   ├── nsm_backend.c/h         # NSM数学后端（忆阻器交叉阵列）
│   ├── genome/                  # AI基因组系统（charter/d1d4/capabilities）
│   ├── transcript/              # 转录层（ATP能量/ESV状态向量）
│   ├── protein/                 # 蛋白质计算层（素数筛/LL测试）
│   └── kernel_legacy/           # 旧版内核（归档）
│
├── programs/                  # DNAsm 程序（.dna 格式）
│   ├── kernel.dna               # 内核DNAsm程序
│   ├── stdlib.dna               # 标准库
│   ├── engine/                  # 引擎（物理/粒子/动画/意识/月读）
│   ├── drivers/                 # 驱动程序
│   ├── gfx/                     # 图形渲染
│   ├── gui/                     # 界面
│   ├── mm/                      # 内存管理
│   ├── net/                     # 网络
│   ├── fs/                      # 文件系统
│   ├── proc/                    # 进程
│   ├── sys/                     # 系统调用
│   ├── shell/                   # DNAsm Shell
│   └── boot/                    # 引导程序
│
├── boot/                      # MBR引导扇区
│   ├── dnaos_boot.asm
│   ├── dnaos_boot.bin
│   └── README_BOOT.md
│
├── chip/                      # Tiny Tapeout芯片设计
│   ├── dnaos_quat.v            # 四进制ALU Verilog
│   ├── dnaos_quat_tb.v         # 测试台
│   └── Makefile
│
├── gpu/                       # GPU直接访问与模拟
│   ├── dnaos_gpu_direct.asm    # BIOS模式GPU访问
│   ├── dnaos_gpu_uefi.asm      # UEFI模式GPU访问
│   ├── gpu_scanner.asm         # PCIe扫描器
│   └── sim/                    # GA106模拟器
│
├── asm/                       # DNAsm核心汇编器（NASM）
├── bench/                     # 基准测试
├── include/                   # 头文件（dnaos.h）
├── mc/                        # 机器码生成器
├── docs/                      # 设计文档
├── tests/                     # 测试套件
├── game/                      # TubeBattle游戏
├── desktop/                   # 桌面环境
├── arm64/                     # ARM64移植
├── website/                   # 项目网站
└── gw_skymap_fetch/           # 引力波天空图
```

---

## 内核子系统

| # | 子系统 | 状态 | 说明 |
|---|--------|------|------|
| 1 | PMM | ✅ | 物理内存管理器 |
| 2 | VMM | ✅ | 虚拟内存管理器（4级页表，2MB大页） |
| 3 | PIT | ✅ | 可编程间隔定时器（100Hz） |
| 4 | IDT | ✅ | 中断描述符表（CPU异常+硬件IRQ+syscall） |
| 5 | PS/2 Keyboard | ✅ | 键盘驱动（扫描码→ASCII） |
| 6 | PS/2 Mouse | ✅ | 鼠标驱动 |
| 7 | PCI Bus Scanner | ✅ | PCI设备枚举 |
| 8 | E1000 Network | ✅ | Intel E1000网卡驱动 |
| 9 | VFS | ✅ | ATCG原生虚拟文件系统（/genome/ /ribosome/ /membrane/ /nucleus/ /atp/ /codon/） |
| 10 | Process Scheduler | ✅ | 进程管理与调度 |
| 11 | Window Manager | ✅ | 窗口管理器（DNA双螺旋桌面+ATP能量条+任务栏） |
| 12 | DNAsm Shell | ✅ | 四进制交互Shell（AND/OR/NOT/ADD/寄存器/文件系统/内存信息） |

---

## 引导流程

```
BIOS POST
  → GRUB (Multiboot2)
    → boot.S (32位→64位切换)
      → kernel_main()
        → PIC重映射
        → IDT初始化
        → PIT初始化(100Hz)
        → STI开中断
        → 绘制桌面（DNA双螺旋+ATCG色带+任务栏）
        → DNAsm Shell
```

---

## 四进制运算

```
编码：00=A  01=T  10=C  11=G  （每字节4个碱基）

AND = min(x, y)    逐碱基取最小
OR  = max(x, y)    逐碱基取最大
NOT = 3 - x        逐碱基取补
ADD = 逐碱基加法 + 进位传播

示例：
  ATCG AND GCTA = ACTA
  ATCG OR  GCTA = GCTG
  NOT ATCG       = TAGC
  ATCG ADD GCTA  = CAAA (carry=1)
```

---

## 如何运行

### 用户态模拟器

```bash
cd simulator/
gcc -o dnaos boot.c dnasm_v33.c dna_hal.c nsm_backend.c -lm -lpthread
./dnaos
```

### 裸机磁盘镜像

```bash
cd os/
python3 gen_disk_v4.py
```

### QEMU 测试

```bash
qemu-system-x86_64 -drive file=out/dnaos.img,format=raw \
  -serial stdio -display none -cpu qemu64
```

### 调试（带异常跟踪）

```bash
qemu-system-x86_64 -drive file=out/dnaos.img,format=raw \
  -serial stdio -display none -cpu qemu64 \
  -no-reboot -d int
```

---

## 相关文档

- [架构设计](os/DESIGN_v34_quaternary.md) — v3.4 四进制存算一体架构
- [DNAsm 规范](docs/SPEC.md) — 指令集完整规范
- [指令集参考](docs/ISA_REFERENCE.md) — 所有指令速查
- [使用教程](docs/TUTORIAL.md) — 从入门到进阶
- [GPU 直接访问](gpu/README_GPU.md) — PCIe 与 MMIO 编程
- [GPU 模拟](gpu/sim/README_SIM.md) — GA106 架构模拟
- [芯片设计](chip/) — Tiny Tapeout SkyWater 130nm 四进制ALU

---

## 许可证

MIT License

---

> *DNAOS — 以生命的编码方式，重新设计计算。*
