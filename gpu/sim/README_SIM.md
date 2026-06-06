# DNAOS v3.3 · GA106 GPU Simulator on CPU

## 概览

用 **AMD Ryzen 5 5500** 的12个硬件线程 + **AVX2 256位向量指令** 模拟 **NVIDIA GA106 RTX 3060** 的3584个CUDA核心。

```
+-------------------------------------------+     +-------------------------------------------+
|  AMD Ryzen 5 5500 (物理CPU)               |     |  NVIDIA GA106 RTX 3060 (模拟GPU)          |
|  Zen 3 | 6核/12线程 | 4.2GHz | AVX2      | ==> |  Ampere | 28 SM | 3584 CUDA | 12GB GDDR6 |
+-------------------------------------------+     +-------------------------------------------+
  12 CPU threads x AVX2(8-wide) ~= 96 parallel lanes 模拟 3584 CUDA cores
  模拟比: 1:37 (但全部可运行，无需NVIDIA驱动)
```

## 模拟映射

| CPU (物理) | GPU (模拟) | 映射关系 |
|-----------|-----------|---------|
| 12 SMT线程 | 28 SM | 每线程2-3个SM |
| AVX2 256-bit (8x int32) | 1 Warp (32 threads) | 4条AVX2指令 = 1个Warp |
| vpaddd ymm | A (ADD) | DNA碱基加法 |
| vpsubd ymm | T (SUB) | DNA碱基减法 |
| vpmulld ymm | C (MUL) | DNA碱基乘法 |
| vdivps ymm | G (DIV) | DNA碱基除法 |
| vfmadd231ps ymm | Tensor Core | FMA乘加 |
| CPU L3 16MB | GPU Shared 64KB×28 | 共享内存模拟 |
| CPU RAM | GPU VRAM 256MB窗口 | 显存模拟 |

## DNA操作 → AVX2指令映射

```asm
; DNA ATCG 编码:
; 00 → A (Adenine)  → vpaddd  (加法)
; 01 → T (Thymine)  → vpsubd  (减法)
; 10 → C (Cytosine) → vpmulld (乘法)
; 11 → G (Guanine)  → vdivps  (除法)

; 示例: 8个DNA碱基并行操作 (AVX2 256-bit)
vpaddd  ymm0, ymm1, ymm2    ; 8个并行整数加法 (A操作)
vpsubd  ymm3, ymm4, ymm5    ; 8个并行整数减法 (T操作)
vpmulld ymm6, ymm7, ymm8    ; 8个并行整数乘法 (C操作)
vdivps  ymm9, ymm10, ymm11  ; 8个并行浮点除法 (G操作)

; Tensor Core模拟 (FMA)
vfmadd231ps ymm0, ymm1, ymm2  ; ymm0 = ymm0 + ymm1*ymm2 (8-wide FMA)
```

## 三个模拟内核

### 1. atcg_encode — DNA碱基编码
- **Warps**: 28 | **Threads**: 896 | **Ops/Warp**: 8
- 将32位整数转换为ATCG碱基序列 (每2位 → 1碱基)
- 每个warp处理8个值，每值产生16个碱基

### 2. tensor_matmul — 矩阵乘法
- **Warps**: 56 | **Threads**: 1792 | **Ops/Warp**: 64
- 8×8矩阵块乘法，模拟Tensor Core行为
- 使用AVX2 vpaddd + vpmulld 模拟 FMA

### 3. conv1d_fwd — 1D卷积
- **Warps**: 28 | **Threads**: 896 | **Ops/Warp**: 32
- 前向传播 + ReLU激活
- 模拟AI推理的卷积层

## 理论性能

| 指标 | 值 |
|------|-----|
| AVX2基础吞吐 | 4.2GHz × 8 int32 × 12 threads = **403 GFLOPS** |
| AVX2+FMA峰值 | 4.2GHz × 8 × 2(FMA) × 12 = **806 GFLOPS** |
| 模拟显存 | 256MB (of 12GB) |
| 模拟带宽 | 45 GB/s (DDR4单通道) |
| 模拟SM | 28 |
| 模拟Warp | 112 |

## 文件

| 文件 | 说明 |
|------|------|
| `ga106_sim.asm` | 主汇编源文件 (NASM语法) |
| `ga106_sim.py` | Python验证模拟器 |
| `Makefile` | 编译脚本 |
| `README_SIM.md` | 本文档 |

## 编译运行

### 汇编版本 (推荐)

```bash
# 安装NASM
sudo apt install nasm binutils    # Debian/Ubuntu
# 或
sudo pacman -S nasm binutils      # Arch

# 编译
nasm -f elf64 ga106_sim.asm -o ga106_sim.o
ld ga106_sim.o -o ga106_sim

# 运行 (需要AVX2支持)
./ga106_sim
```

### Python版本 (验证/测试)

```bash
python3 ga106_sim.py
```

### 你的微星主板实机运行

```bash
# 1. 复制到U盘
mkdir -p /mnt/efi/EFI/BOOT
cp ga106_sim /mnt/efi/EFI/BOOT/BOOTX64.EFI

# 2. 从UEFI Shell运行
# 开机F11 → UEFI Shell → FS0: → cd EFI\BOOT → ga106_sim.efi
```

## 拓扑输出示例

```
  CPU Thread | GPU SM(s)   | Warps | Shared Mem | Status
  ------------------------------------------------------------------------
    Thread  0  | SM0-2       |    12 |    192 KB  | ONLINE
    Thread  1  | SM2-4       |    12 |    192 KB  | ONLINE
    Thread  2  | SM4-6       |    12 |    192 KB  | ONLINE
    ...
    Thread 11  | SM25-27     |    12 |    192 KB  | ONLINE
```

## 下一步

1. **添加pthread**: 12个真实线程并行执行
2. **实现调度器**: Round-robin warp调度
3. **添加显存管理**: 页表 + 分配器
4. **模拟更多内核**: 矩阵转置、归约、扫描
5. **对接DNAsm**: 在模拟GPU上执行DNA字节码

---

递砖继续。0。
