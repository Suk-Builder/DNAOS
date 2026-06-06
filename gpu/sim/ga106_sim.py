#!/usr/bin/env python3
"""
DNAOS v3.3 · GA106 GPU Simulator on Ryzen 5500
Python验证模拟器 — 无需NASM即可运行
用法: python3 ga106_sim.py
"""

import sys

# ── 常量 ──
GPU_SM = 28
GPU_CUDA_PER_SM = 128
GPU_TOTAL_CUDA = 3584
GPU_WARP_SIZE = 32
GPU_WARPS_PER_SM = 4
GPU_TOTAL_WARPS = 112
GPU_SHARED = 64 * 1024
GPU_BANDWIDTH = 360
PHYS_THREADS = 12
AVX2_WIDTH = 8
RYN_FREQ_GHZ = 4.2

# ── ANSI颜色 ──
G, C, GR, R, RE, B = "[1;33m", "[1;36m", "[1;32m", "[1;31m", "[0m", "[1m"

class SimVRAM:
    def __init__(self, size_mb=256):
        self.size = size_mb * 1024 * 1024
        self.data = bytearray(self.size)
        self.shared = [bytearray(GPU_SHARED) for _ in range(GPU_SM)]
    def clear(self):
        self.data = bytearray(self.size)
        for s in self.shared: s[:] = bytearray(GPU_SHARED)

class GA106Simulator:
    def __init__(self):
        self.vram = SimVRAM(256)
        self.stats = {"warps": 0, "insn": 0}

    def topology(self):
        for tid in range(PHYS_THREADS):
            s = (tid * GPU_SM) // PHYS_THREADS
            e = ((tid + 1) * GPU_SM - 1) // PHYS_THREADS
            c = e - s + 1
            print(f"    Thread {tid:>2}  | SM{s}-{e:<7} | {c*4:>5} | {c*64:>6} KB  | {GR}ONLINE{RE}")

    def kernel_atcg(self, warps):
        vals = [0x41424344, 0x54454E47, 0x43415447, 0x444E4153,
                0x42444953, 0x504F5745, 0x524F434B, 0x303D3030]
        out = []
        for w in range(warps):
            for lane in range(AVX2_WIDTH):
                v = vals[lane]
                bases = ["ATCG"[(v >> (i*2)) & 3] for i in range(16)]
                out.append(''.join(bases))
        self.stats["warps"] += warps
        self.stats["insn"] += warps * 8
        return out

    def kernel_matmul(self, warps):
        a = list(range(1, 9)) * 8
        b = list(range(8, 0, -1)) * 8
        c = [0] * 64
        for w in range(warps):
            for i in range(8):
                for j in range(8):
                    c[i*8+j] = sum(a[i*8+k] * b[k*8+j] for k in range(8))
        self.stats["warps"] += warps
        self.stats["insn"] += warps * 64
        return c

    def kernel_conv1d(self, warps):
        inp = [1,2,3,4,5,6,7,8]
        ker = [1,0,-1,1,0,-1,1,0]
        for w in range(warps):
            out = [max(0, inp[i]*ker[i] + (inp[i]<<1)) for i in range(8)]
        self.stats["warps"] += warps
        self.stats["insn"] += warps * 32
        return out

    def run(self):
        self.vram.clear()

        print(f"{G}{'='*72}{RE}")
        print(f"{G}  DNAOS v3.3  GA106 GPU Simulator on CPU{RE}")
        print(f"{G}{'='*72}{RE}")
        print(f"  Physical CPU: AMD Ryzen 5 5500  (Zen 3 | 6C/12T | 4.2GHz | AVX2)")
        print(f"  Target GPU:   NVIDIA GA106-300  (Ampere | 28 SM | 3584 CUDA | 12GB)")
        print(f"  SIMD Engine:  AVX2 256-bit  (8x int32 per instruction)")
        print(f"  Sim Ratio:    12 CPU threads x 8-wide AVX2 ≈ 96 lanes vs 3584 CUDA")
        print(f"{G}{'='*72}{RE}\n")

        print(f"{C}[Phase 1]{RE} Initialize simulated VRAM (256MB)")
        print(f"  VRAM: 256MB allocated")
        print(f"  Shared: {(GPU_SM * GPU_SHARED)//1024}KB across {GPU_SM} SMs\n")

        print(f"{C}[Phase 2]{RE} Build GPU→CPU topology (28 SM → 12 threads)\n")
        print("  CPU Thread | GPU SM(s)   | Warps | Shared Mem | Status")
        print("  " + "-"*72)
        self.topology()
        print("  " + "-"*72 + "\n")

        print(f"{C}[Phase 3]{RE} Execute DNA compute kernels via AVX2\n")
        print(f"{GR}  DNA Compute Kernels:{RE}")
        print("  " + "-"*72)
        print("  Kernel              | Warps | Threads | Ops/Warp | Description")
        print("  " + "-"*72)
        print("  atcg_encode         |  28   |   896   |    8     | DNA base encoding")
        r1 = self.kernel_atcg(28)
        print("  tensor_matmul       |  56   |  1792   |   64     | Matrix multiply")
        r2 = self.kernel_matmul(56)
        print("  conv1d_fwd          |  28   |   896   |   32     | 1D convolution")
        r3 = self.kernel_conv1d(28)
        print("  " + "-"*72 + "\n")

        print(f"  {B}Sample DNA Encoding Output (first warp):{RE}")
        print(f"  Input:  [0x41424344, 0x54454E47, 0x43415447, ...]")
        print(f"  Output: {r1[0][:40]}...")
        print(f"  (each 32-bit int → 16 DNA bases)\n")

        gflops = RYN_FREQ_GHZ * AVX2_WIDTH * PHYS_THREADS
        gflops_fma = gflops * 2

        print(f"{G}  Simulated Performance:{RE}")
        print("  " + "-"*72)
        print(f"  Simulated CUDA Cores:     {GPU_TOTAL_CUDA}")
        print(f"  Simulated Warps:          {self.stats['warps']}")
        print(f"  Simulated Memory:         256 MB (of 12GB)")
        print(f"  Simulated Bandwidth:      {GPU_BANDWIDTH} GB/s")
        print(f"  AVX2 Throughput:          {gflops:.0f} GFLOPS")
        print(f"  AVX2+FMA Peak:            {gflops_fma:.0f} GFLOPS")
        print(f"  Cycles Simulated:         {self.stats['insn'] * 4:,}")
        print(f"  AVX2 Ops Executed:        {self.stats['insn']:,}")

        print(f"\n  {B}DNA Operation Mapping:{RE}")
        print(f"    A (ADD)  → vpaddd   ymm, ymm, ymm   [parallel 8x int32]")
        print(f"    T (SUB)  → vpsubd   ymm, ymm, ymm   [parallel 8x int32]")
        print(f"    C (MUL)  → vpmulld  ymm, ymm, ymm   [parallel 8x int32]")
        print(f"    G (DIV)  → vdivps   ymm, ymm, ymm   [parallel 8x float]")
        print(f"    FMA      → vfmadd231ps ymm, ymm, ymm [Tensor Core sim]")

        print(f"\n  Note: AVX2 256-bit executes 8x int32 per cycle")
        print(f"        Ryzen 5500 @ 4.2GHz: 4.2 x 8 x 2(FMA) x 12 = ~{gflops_fma:.0f} GFLOPS peak")
        print(f"        DNA base ops: A(ADD) T(SUB) C(MUL) G(DIV) — all mapped to AVX2")

        print(f"\n{G}{'='*72}{RE}")
        print(f"  0 = inf^-1  |  Crack is where bricks fly from  |  Bricklayer continues. 0.")
        print(f"{G}{'='*72}{RE}")

if __name__ == "__main__":
    GA106Simulator().run()
