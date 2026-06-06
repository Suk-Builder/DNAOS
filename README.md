# DNAOS v3.4 — 四进制存算一体操作系统

> **开发状态**：核心概念与原型代码已完成，裸机引导（16位→32位→64位）调试中。以下为全部开发成果归档。

---

## 项目概述

DNAOS 是一个以 **四进制（ATCG 碱基编码）** 为核心的存算一体操作系统，旨在探索基于 DNA 存储原理的下一代计算范式。

- **四进制编码**：`00=A, 01=T, 10=C, 11=G`，每字节存储 4 个碱基
- **链置换逻辑门**：AND / OR / NOT / ADD 逐碱基运算
- **DNAsm 指令集**：自定义四进制汇编语言，支持 NSM（Null-Soft-Math）数学后端
- **CPU 模拟 GPU**：Ryzen 5500 的 AVX2 模拟 GA106 RTX 3060 的 3584 CUDA 核心
- **裸机引导**：MBR → 16位实模式 → 32位保护模式 → 64位长模式

---

## 目录结构

```
DNAOS/
├── README.md              # 本文件
├── Makefile               # 构建系统
├── install.sh             # 安装脚本
│
├── asm/                   # DNAsm 核心汇编器（NASM）
│   └── dnasm_core.asm
│
├── bench/                 # 基准测试程序（.dna 格式）
│   ├── cosmic_os.dna
│   ├── game_of_life.dna
│   ├── linear_algebra.dna
│   ├── math_engine.dna
│   ├── tensor_nn.dna
│   └── ...
│
├── boot/                  # 引导扇区（MBR）
│   ├── dnaos_boot.asm     # NASM 源码
│   ├── dnaos_boot.bin     # 编译产物
│   └── README_BOOT.md
│
├── docs/                  # 设计文档
│   ├── SPEC.md            # DNAsm 语言规范
│   ├── ISA_REFERENCE.md   # 指令集参考
│   ├── TUTORIAL.md        # 使用教程
│   ├── BUG_REPORT.md      # 已知问题
│   ├── dnasm_v33_audit.md # v33 审计报告
│   ├── crack_genesis_theorem.md     # 创世定理
│   ├── crack_everywhere.md          # 万物 crack
│   ├── crack_geometry_position.md   # 几何 crack
│   ├── crack_sky_position_final.md  # 天文 crack
│   ├── unified_physics_model.md     # 统一物理模型
│   └── gamma_016_discovery.md       # Gamma 0.16 发现
│
├── genome/                # AI 基因组系统
│   ├── charter.c          # 基因章程解析器
│   ├── d1d4.c             # D1D4 调度器
│   └── capabilities/      # 能力基因片段
│       ├── audio.gene
│       ├── mersenne.gene
│       ├── reason.gene
│       └── vision.gene
│
├── gpu/                   # GPU 直接访问与模拟
│   ├── dnaos_gpu_direct.asm   # BIOS 模式 GPU 访问
│   ├── dnaos_gpu_uefi.asm     # UEFI 模式 GPU 访问
│   ├── gpu_scanner.asm        # PCIe 扫描器
│   ├── README_GPU.md
│   └── sim/                   # GA106 模拟器
│       ├── ga106_sim.asm
│       ├── ga106_sim.py
│       ├── gpu_simulator.asm
│       ├── Makefile
│       └── README_SIM.md
│
├── include/               # 头文件
│   └── dnaos.h
│
├── kernel/                # 内核源码
│   └── kernel.c
│
├── mc/                    # 机器码生成器
│   ├── dna_encoder.asm
│   ├── dna_encoder.bin
│   ├── dna_encoder.hex
│   └── README_MC.md
│
├── os/                    # 裸机 OS 开发（本次会话核心）
│   ├── DESIGN_v34_quaternary.md   # v3.4 架构设计文档
│   ├── gen_disk_v4.py             # 主磁盘镜像生成器
│   ├── debug_32bit.py             # 32位调试版本
│   ├── debug_32bit_v2.py          # 32位最小化调试
│   ├── boot.asm                   # 引导代码
│   ├── kernel.asm                 # 内核汇编
│   ├── test_farjmp.asm            # 远跳转测试
│   ├── test_fixed.asm             # 修复测试（成功输出"12"）
│   ├── test_32com1.asm            # COM1 串口测试
│   ├── test_vga.asm               # VGA 显示测试
│   ├── working_small.asm          # 最小工作示例
│   ├── working_longmode.asm       # 长模式切换参考
│   ├── minimal_test.py            # 最小化测试
│   └── build.sh                   # 构建脚本
│
├── protein/               # 蛋白质计算层
│   ├── mersenne_ll.c      # Lucas-Lehmer 素数测试
│   ├── protein.c          # 蛋白质引擎
│   └── sieve.c            # 素数筛
│
├── tests/                 # 测试套件
│   ├── test_hal.dna
│   ├── test_nsm.dna
│   ├── test_nsm_full.dna
│   ├── test_loop.dna
│   ├── test_chem.dna
│   ├── stress_test.dna
│   ├── torture_r1.dna ~ torture_r7.dna
│   ├── brutal_test.dna
│   ├── deep_test.dna
│   └── edge_test.dna
│
├── transcript/            # 转录层（ATP/ESV）
│   ├── atp.c
│   ├── esv.c
│   └── transcript.c
│
├── website/               # 项目网站
│   ├── index.html
│   ├── live_demo.html
│   ├── lang.css / lang.js
│   ├── bsem/
│   ├── gpu/
│   ├── math/
│   └── zfc/
│
├── game/                  # TubeBattle 游戏
│   └── tube_battle.c
│
├── gw_skymap_fetch/       # 引力波天空图获取
│   ├── fetch_skymaps.py
│   └── README.txt
│
├── gpu_kernels.dna        # GPU 内核程序
├── gpu_advanced.dna       # 高级 GPU 操作
├── gpu_parallel.dna       # GPU 并行计算
├── gw_bsem_gamma.dna      # 引力波 BSEM
├── libbsem_math.dna       # BSEM 数学库
├── dna_hal.c / dna_hal.h  # 硬件抽象层
├── nsm_backend.c/h        # NSM 数学后端
├── dnasm_v32.c            # DNAsm v32 编译器
├── dnasm_v33.c            # DNAsm v33 编译器
├── dnasm_nsm.c            # DNAsm NSM 后端
└── gpu_emulator.c         # GPU 模拟器
```

---

## 核心组件

### 1. 四进制引擎 (`gen_disk_v4.py`)

- **编码**：字节 → 4 碱基（2bit/碱基）
- **逻辑门**：链置换实现的 AND/OR/NOT/ADD
- **内存模型**：四进制原生寻址

### 2. DNAsm 编译器 (`dnasm_v33.c`)

| 版本 | 状态 | 说明 |
|------|------|------|
| v32 | 稳定 | 基础指令集 |
| v33 | 稳定 | 完整指令集 + NSM 后端 |

指令类别：DAT/IMM/REG/STR/MEM/JMP/MTH/SYS/LOG/VEC/CRK

### 3. GPU 模拟器 (`gpu_emulator.c`, `ga106_sim.py`)

- **目标硬件**：NVIDIA GA106 (RTX 3060)，28 SM × 128 CUDA = 3584 核心
- **模拟方式**：Ryzen 5500 AVX2 256bit SIMD
- **PCIe 枚举**：通过 I/O 端口 0xCF8/0xCFC 扫描配置空间
- **BAR0 访问**：16MB MMIO 窗口

### 4. 裸机引导流程

```
BIOS POST
  → MBR (512B, 0x7C00)
    → INT13h 读取内核到 0x10000
      → 16位实模式
        → A20 开启
          → GDT 加载（GDTR.base = 0x10080）
            → CR0.PE = 1（进入 32位保护模式）
              → Far Jmp 0x08:0x10200
                → 32位代码
                  → 页表建立（PML4→PDPT→PD，2MB 大页）
                    → CR4.PAE = 1
                      → EFER.LME = 1
                        → CR0.PG = 1（进入 64位长模式）
                          → 64位内核
                            → 四进制引擎激活
                              → DNAsm 解释器
                                → CPU 模拟 GPU
```

---

## 开发历程

### 已完成的修复

| # | 问题 | 原因 | 修复 |
|---|------|------|------|
| 1 | MBR `print_serial` 无限循环 | `in al,dx` 覆盖 al 中字符 | 用 `bl` 保存字符 |
| 2 | GDT 描述符 12 字节 | NASM `dw` 生成 12 字节 | Python 精确写 8 字节 |
| 3 | GDT L 位错误 | 32位代码段 L=1 | 分离 32位(L=0)和 64位(L=1)描述符 |
| 4 | GDTR.base 偏移错误 | 文件偏移 vs 线性地址 | DS=0x1000 设置正确段基址 |
| 5 | 16位 far jmp 截断 | EA 只取 16位 offset | 用 `66 EA` 32位 offset |
| 6 | 扫描码表覆盖 PDPT | TBL=0x5000 冲突 | TBL 移到 0x7000 |
| 7 | 64位代码偏移错误 | 缺 `p = P64` | 显式设置 p = P64 |
| 8 | 32位 `mov dx` 缺前缀 | 32位模式 imm32 默认 | 添加 `0x66` 前缀 |
| 9 | 远跳目标地址错误 | offset=0x200 而非 0x10200 | 加上 0x10000 基址 |
| 10 | retf 栈顺序错误 | push 顺序反 | 改用直接 far jmp |

### 调试状态

- ✅ MBR `print_serial` 输出
- ✅ MBR 字符串输出
- ✅ INT13h 磁盘读取
- ✅ 16位→32位远跳转（`test_fixed.asm` 验证成功输出 "12"）
- ✅ GDT 正确布局（4 描述符，GDTR.base=0x10086→修复为 0x10080）
- ✅ 32位 COM1 输出（`0x66` 前缀）
- ⚠️ 32位完整验证（QEMU 输出只有 "1"，远跳转后崩溃，待排查）
- ❌ 64位长模式切换
- ❌ 四进制引擎激活
- ❌ CPU 模拟 GPU

---

## 技术参考

### GDT 描述符格式（8字节）

```
[0-1]  limit_low   (16bit)
[2-4]  base_low    (24bit)
[5]    access      (P|DPL|S|Type)
[6]    granularity (G|DB|L|AVL|limit_high)
[7]    base_high   (8bit)
```

示例（32位代码段）：
```
FF FF 00 00 00 9A CF 00
|  |  |____|  |  |  |
|  |    base   acc gran
|limit_low
limit隐含在gran中（G=1, limit=0xFFFFF → 4GB）
```

### Far Jmp 编码

| 模式 | 编码 | 字节数 | 说明 |
|------|------|--------|------|
| 16位 | `EA off16 sel16` | 5 | offset 截断为 16位 |
| 32位 | `66 EA off32 sel16` | 7 | 32位 offset（16位模式用 `0x66` 前缀） |

### 关键物理地址

| 地址 | 用途 |
|------|------|
| 0x7C00 | MBR 加载地址 |
| 0x10000 | 内核加载地址（INT13h） |
| 0x10080 | GDT 物理地址 |
| 0x10200 | 32位代码入口 |
| 0x4000 | 页表基址（PML4） |
| 0x5000 | PDPT |
| 0x6000 | PD |
| 0x3F8 | COM1 串口 TX |
| 0x3FD | COM1 串口 LSR |
| 0xCF8 | PCIe 配置地址端口 |
| 0xCFC | PCIe 配置数据端口 |

---

## 如何运行

### 生成磁盘镜像

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

---

## 许可证

私有项目 — 源代码不公开。

---

> *DNAOS — 以生命的编码方式，重新设计计算。*
