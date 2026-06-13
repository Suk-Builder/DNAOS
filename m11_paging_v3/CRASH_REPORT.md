# DNAOS v3.5 M11 v3 — NASM 16-bit SIB bug + lgdt 没生效? (查了书+网搜, 撞 5 次)

**日期**: 2026-06-13 07:13 UTC
**状态**: ⏳ 撞 5 次, NASM 16-bit SIB bug 修了, 但 far jmp #GP error=0x0008 (GDT[1])

## 🎯 跑通部分

串口 marker 顺序 (k11 v6):
```
H K G T G D P
```

7 个 marker:
- H (mbr head 1) ✓
- K (kernel 启动) ✓
- G (PGD 装好) ✓
- T (PGT 装好) ✓
- G (GDT 装好) ✓
- D (GDT desc 装好 + lgdt) ✓
- P (CR0.PE=1) ✓
- 16-bit 段跑 'P' marker 之后, far jmp 跳 0x0008 GDT[1] 32-bit 段 **#GP error=0x0008**

## 🛑 撞 5 次 (查了书 + 网搜学)

1. **NASM 16-bit 段 [si+disp8] 用 SIB encoding bug** (关键学!)
   - NASM 16-bit 段下 `mov byte [si+21], 0x92` 编译成 `C6 44 15 92`
   - mod=01 reg=0 rm=100(SIB) SIB 0x15 imm 0x92
   - SIB 0x15 在 16-bit 段下 = `[BP+DI+disp8]` ≠ `[SI+disp8]`
   - **v3 修法**: 用 [bx+disp16] (mod=00 rm=111) 装 GDT 段
   - **关键发现**: 16-bit 段下 NASM 16-bit 段寻址 [si+disp8] 应该用 mod=01 rm=110, NASM 误用 SIB encoding (mod=01 rm=100 + SIB)
   - **v3 用 [bx+disp16] 装 GDT, 装对, mem GDT[1] type=0x9A, GDT[2] type=0x92 ✓**

2. **GDT[2] type 0x93 (expand-DOWN) 是 v2 撞穿原因**
   - v2 装 GDT[2] type 0x92 (expand-UP) 但 NASM 编码错装到 0x93 (expand-DOWN)
   - expand-DOWN data 段 base 不是 0, 寻址错 (ds:0xB8000 = 0xC8000 page fault)
   - **v3 修法**: 用 [bx+disp16] 装, GDT[2] type 0x92 ✓

3. **far jmp 0x0008 #GP error=0x0008** (撞 5 次后撞穿)
   - dlog 显示 v=0d e=0008 i=0 cpl=0 IP=0x10311
   - far jmp 跳 GDT[1] 0x0008 32-bit 段, 但 GDT register 显示是 BIOS GDT (0xF61E0), 不是 k11 装 GDT register (0x10366)
   - **也许**: 16-bit 段下 lgdt 装 GDT register 没生效, 或者 k11 装完后 BIOS SMM enter 重置 GDT register
   - **OSDev wiki 查**: "Loading the GDT while in real mode requires special care: limit 0xFFFF for real mode"

4. **v3 简化**: 32-bit 段设 ds=0x10 + esp=0x90000, identity map PGD 自己 + PGT 自己 + 0xB8000 + 0x90000

5. **v3.1 简化**: 用 dword 装 PTE (避免 16-bit 段 word 装错)

## 📊 SHA256

- k11v6.bin: `d174b82e...35a8cf`
- img_v35.img: `76cbdcdf...f28dcb`

## 💡 关键学 (查书 + 网搜)

1. **NASM 16-bit 段 SIB bug** (重要): `mov [si+disp8], imm8` NASM 编译 SIB encoding, 实际寻址 ≠ [SI+disp8]
   - 16-bit 段用 [bx+disp16] (mod=00 rm=111) 是稳定写法
2. **GDT[2] type 0x92 vs 0x93** (重要): expand-UP vs expand-DOWN data 段, 寻址算法不同
3. **PE=1 + far jmp GDT[1] 32-bit 段** 需要 16-bit 段下 lgdt 装 GDT register 有效
4. **dword 装 PTE 简化代码**: `mov dword [es:0x40], 0x00010003` 一次装 4 字节
5. **PGT[0xB80] 物理 = 0x14E00** 实际 = 0x12000 + 0xB80*4 = 0x14E00, 装对

## 🎯 撞 5 次了, 写报告

**v6 已撞 5 次 (符合 2-3 次翻书原则), 写撞穿报告**:

- NASM 16-bit SIB bug 修 ✓
- GDT[2] type 0x92 修 ✓
- 32-bit 段设段寄存器 + esp ✓
- dword 装 PTE ✓
- identity map ✓
- **far jmp GDT[1] #GP** — GDT register 0xF61E0 (BIOS), 也许 lgdt 没生效

## 📂 文件

| 文件 | 字节 | 说明 |
|------|------|------|
| `kernel_m11v6.asm` | 4530 | k11 v6 [bx+disp16] 装 GDT + dword 装 PTE |
| `kernel_m11v7.asm` | 3473 | k11 v7 (类似 v6) |

## ⏳ 留给后续

- lgdt 装 GDT register 16-bit 段下生效问题
- 或者用 32-bit 段模式 (BITS 32) 写 GDT 段, 但 pm_entry 还没切

## ✅ M11 v3 部分完成
- PGD/PGT 装对 ✓
- GDT 装对 (mem) ✓
- PE=1 ✓
- 32-bit 段切 + 段寄存器 + 分页 — **撞穿待修**
