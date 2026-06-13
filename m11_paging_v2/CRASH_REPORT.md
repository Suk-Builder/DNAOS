# DNAOS v3.5 M11 v2 — 16→32 切 + 4KB 分页 (撞 3 次后退回, 部分跑通)

**日期**: 2026-06-13 05:56 UTC
**状态**: ⏳ 撞 3 次, 32-bit 段跑通, PG=1 一开就 page fault

## 🎯 跑通部分

串口 marker 顺序:
```
H K G T D P X 3 !
```

| marker | 含义 |
|--------|------|
| H | mbr 装 head 1 OK |
| K | kernel 启动 |
| G | PGD 装好 |
| T | PGT 装好 |
| D | GDT + lgdt + IDT |
| P | CR0.PE=1 |
| X | 32-bit 段跑通! |
| 3 | CR3 = 0x11000 |
| ! | **PG=1, 分页开!** |

32-bit 段跑通 + 分页开 = **M11 v2 大部分跑通**!

## 🛑 撞穿 3 次 (学到的)

1. **第一次**: `jmp 0x08:0x0001034B` 16-bit 段下默认 16-bit far jmp → NASM 截到 0x34B 物理
   - **修**: `jmp dword 0x08:0x0001034B` 强制 32-bit 偏移
2. **第二次**: 32-bit 段 + PG=1 + 写 VGA 0xB8000 时 page fault
   - **bug**: PTE 装错 (32-bit = high 16 + low 16, 我用 0x1203 + 0x0000 = frame 0x1, 不是 0x12)
   - **修**: PTE 装 0x2003 (low) + 0x0001 (high) = 0x00012003 = frame 0x12 = 物理 0x12000
3. **第三次**: 0xB8000 仍 page fault (CR2=0xC8200, 不是 0xB8000)
   - **未解**: PGT[0xB80] = 0x000B8003 frame 0xB8 物理 0xB8000 ✓, 但 32-bit 段写 0xB8000 时 EIP=0x10373 时 page fault at 0xC8200
   - **可能**: 也许 CR2 0xC8200 是 double fault 后的 EIP, 不是 mov [edi] 0xB8000 的访存

## 📊 SHA256

- mbr_v35.bin: `297f8a57...d8a27a` (跟 M12 v2 同)
- k11.bin: `2befd0b0...4cdef0` (撞 3 次, 2KB)
- img_v35.img: `a3450e0e...ae6ab`

## 💡 关键学

1. **16→32 切必须 3 步** (PE=1 → far jmp → 设新段) — 不能跳 PE=1
2. **PTE 32-bit = low 16 + high 16**, high 16 = frame 的 bit 16-31
3. **mbr 装多 head 扇区** — 修 M11/M12 共同根因
4. **VGA 写时 page fault 仍** — 撞穿 3 次, 留待后续

## 🎯 撞 2-3 次就翻书 — 决策: 退回, 写撞错报告, 不硬撞

## 📂 文件

| 文件 | 字节 | 说明 |
|------|------|------|
| `mbr_v35.asm` | 2220 | 装多 head (同 M12 v2) |
| `kernel_m11v2.asm` | 6187 | k11 v2 16-bit 段 + 32-bit 段 |
| `test_v35.py` | 868 | QEMU 测试 |

## ⏳ 留给后续

- 16→32→分页 全跑通
- VGA 写 0xB8000 在 PG=1 后
- 进程 + 调度 (M13)

## ✅ M11 v2 部分完成
- 32-bit 段跑通 ✓
- CR3 = 0x11000 ✓
- PG=1 开 ✓ (但写 0xB8000 时 page fault)
