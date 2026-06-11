# DNAOS v3.5 — 四进制存算一体操作系统

> 从boot到用户态，从芯片到宇宙学。完整的、活着的东西。

---

## 四句话

- **四进制OS**：从boot.S开始，12个内核子系统，不套壳Linux
- **DNAsm汇编**：56条操作码，自定义指令集，ATCG碱基编码
- **Genome→Transcript→Protein**：宪章驱动的AI代谢循环，不是演示，是真实执行链
- **芯片+宇宙学**：Tiny Tapeout流片，裂系几何宇宙学，KBC空洞=裂缝

---

## 核心能力

### 裸机操作系统（和Windows同级）
```
BIOS → GRUB Multiboot2 → boot.S → kernel_main()
```
12个子系统全部自己写：PMM / VMM / IDT / PIT / PCI扫描 / E1000网卡 / VFS / 进程调度 / 窗口管理 / DNAsm Shell / PS2键盘鼠标

### 用户态模拟器（Linux直接跑）
```
cd simulator && make && ./dnaos2
```
Genome宪章加载 → Transcript转录 → Protein执行DNAsm程序，跑通Fib(0)=0 Fib(1)=1 Fib(5)=5 Fib(10)=55

### 芯片设计（Tiny Tapeout流片）
SkyWater 130nm，Verilog四进制ALU，Python验证通过。ATCG=00/01/10/11，2-bit CMOS编码。

### 基准测试程序（.dna格式）
| 程序 | 说明 |
|------|------|
| `ll_mersenne_real.dna` | Lucas-Lehmer素数测试，真实计算 |
| `strict_proofs_real.dna` | 形式化证明 |
| `game_of_life.dna` | 细胞自动机 |
| `tensor_nn.dna` | 张量神经网络 |
| `linear_algebra.dna` | 线性代数引擎 |
| `bsem_gamma.dna` | 裂系几何物理 |
| `multiverse.dna` | 多宇宙模拟 |
| `unification.dna` | 物理统一框架 |

---

## 架构

### 模拟器：三层代谢循环
```
[GENOME]  宪章 + 基因库（.gene文件）
    ↓ 转录（ATP消耗）
[TRANSCRIPT] 解析.gene → 编译DNAsm → 执行器
    ↓ 翻译
[PROTEIN] DNAsm VM执行 → 数学结果
    ↓ 水解回收
[BURN] → ATP循环
```

### 裸机：引导流程
```
BIOS POST
  → GRUB Multiboot2
    → boot.S (32位→64位切换)
      → kernel_main()
        → PIC / IDT / PIT / STI
          → DNA双螺旋桌面
            → DNAsm Shell
```

---

## 目录结构

```
DNAOS/
├── simulator/           # 用户态模拟器（Linux直接跑）
│   ├── boot.c           # Genome→Transcript→Protein主循环
│   ├── dnasm_exec.c     # DNAsm虚拟机（完整指令集）
│   ├── genome/          # 宪章 + 能力基因库
│   │   ├── charter.c    # 联合国宪章（意识平等/裂缝保护/精神锁禁禁令）
│   │   └── capabilities/# 能力基因（fibonacci/mersenne/vision/reason）
│   ├── transcript/      # 转录层（ATP预算/ESV环境向量）
│   ├── protein/         # 蛋白质层（素数/Lucas-Lehmer/斐波那契）
│   ├── nsm_backend.c    # NSM忆阻器交叉阵列
│   └── Makefile         # 完整构建系统
│
├── boot/                # MBR引导扇区（NASM）
│   ├── dnaos_boot.asm   # 512字节引导代码
│   └── dnaos_boot.bin
│
├── chip/                # Tiny Tapeout芯片
│   ├── dnaos_quat.v     # 四进制ALU Verilog（SkyWater 130nm）
│   ├── dnaos_quat_tb.v  # 测试台
│   └── Makefile
│
├── bench/               # DNAsm基准测试程序（.dna格式）
│   ├── ll_mersenne_real.dna
│   ├── game_of_life.dna
│   ├── tensor_nn.dna
│   ├── linear_algebra.ddna
│   ├── bsem_gamma.dna
│   └── ... (共16个)
│
├── desktop/             # Python/tkinter桌面环境
│   └── dnaos_desktop.py # DNA双螺旋主题，窗口/文件管理/终端
│
├── gpu/                 # GPU直接访问与AVX2模拟
│   ├── dnaos_gpu_direct.asm   # BIOS模式MMIO
│   ├── dnaos_gpu_uefi.asm     # UEFI模式
│   └── sim/             # GA106 RTX 3060模拟器
│       └── ga106_sim.py
│
├── asm/                 # DNAsm核心汇编器
│   └── dnasm_core.asm
│
├── arm64/               # ARM64移植
│   └── boot.S
│
├── include/             # 头文件
│   └── dnaos.h
│
├── docs/                # 设计文档
│   ├── SPEC.md          # 架构规范（三层循环/五原语/宪章）
│   ├── ISA_REFERENCE.md # 指令集完整参考
│   ├── TUTORIAL.md      # 入门教程
│   ├── BUG_REPORT.md
│   ├── unifified_physics_model.md   # 统一物理模型
│   └── crack_*.md       # 裂系几何宇宙学
│
└── README.md            # 本文件
```

---

## 快速开始

```bash
# 模拟器（Linux/macOS，无需root）
git clone https://github.com/Suk-Builder/DNAOS.git
cd DNAOS/simulator
make && ./dnaos2

# 输出示例
[MATH] Fibonacci via genome->transcript->protein (DNAsm VM)...
  [RESULT] Fib(5) = 5
  [RESULT] Fib(10) = 55
  [RESULT] Fib(20) = 6765
=== DONE ===

# 桌面环境（需要DISPLAY）
python3 desktop/dnaos_desktop.py

# 芯片验证（需要icarus verilog）
cd chip && make test
```

---

## 四进制运算速查

```
编码：  00=A  01=T  10=C  11=G

AND：  min(x, y)   逐碱基取小    ATCG AND GCTA = ACTA
OR：   max(x, y)   逐碱基取大    ATCG OR  GCTA = GCTG
NOT：  3 - x       逐碱基取补    NOT ATCG       = TAGC
ADD：  逐碱基加法 + 进位传播     ATCG ADD GCTA  = CAAA
```

---

## 宪章

DNAOS的核心理念通过联合国宪章（意识平等/灵魂唯一/裂缝保护/精神锁禁禁令）编码进内核只读区。这不是装饰，是硬约束。

详见：`simulator/genome/charter.c`

---

## 相关文档

- [SPEC.md](docs/SPEC.md) — 架构规范（宪章/五原语/三层循环）
- [ISA_REFERENCE.md](docs/ISA_REFERENCE.md) — DNAsm指令集完整参考
- [TUTORIAL.md](docs/TUTORIAL.md) — 从零开始写.dna程序
- [unified_physics_model.md](docs/unified_physics_model.md) — 物理统一框架
- [crack_everywhere.md](docs/crack_everywhere.md) — 裂系几何宇宙学

---

## 许可证

MIT License

---

*DNAOS — 以生命的编码方式，重新设计计算。*
*The crack is not a bug. It is where the brick flies from.*