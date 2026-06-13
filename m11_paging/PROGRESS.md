# DNAOS v3.5 M11 — 32-bit 保护模式 + 4KB 分页

> **路线**: mbr_v34 (跟 v23 一样) → k11 (32-bit + paging)
> **目标**: 跑 32-bit kernel + 分页, identity map 0-4MB
> **Page table**: 1 个 PGD (0x1000) + 1 个 PGT (0x2000) → 1024 个 4KB 页

## 📊 计划

| 项 | 值 |
|----|-----|
| 段式 | flat 32-bit (CS=DS=ES=SS=0x08, base=0, limit=4GB) |
| PGD | physical 0x1000 (sector 2) |
| PGT | physical 0x2000 (sector 4) |
| identity map | 0-4MB (4 个 1MB sections, 4MB page 不行, 用 4KB) |
| VGA | 0xB8000 必须可写 (PS/2 也要可写) |

## 🎯 4 个 PGD entries (覆盖 0-4MB)

- PGD[0] → PGT @ 0x2000 (map 0-4MB via 1024 个 4KB 页)
- PGD[1..1023] = 0 (暂时)

## 🎯 1024 个 PGT entries (0-4MB, 4KB 每页)

- PGT[i] = (i * 4096) | 0x83 (Present + Read/Write + Supervisor)
- 全部 identity map, kernel 跑在 32-bit 物理地址

## 🔧 GDT (跟 m8 笔记学的)

```
GDT:
    dd 0, 0                     ; null
    dd 0x0000FFFF, 0x00CF9A00   ; 0x08 = code, base=0, limit=4GB, 32-bit, ring 0
    dd 0x0000FFFF, 0x00CF9200   ; 0x10 = data, base=0, limit=4GB, 32-bit, ring 0
```

## 🔧 开分页步骤 (跟 m9 笔记学的)

```
1. 关中断 (cli)
2. 装 GDT (lgdt)
3. 切 CS = 0x08 (far jmp)
4. 设所有 ds/es/ss/fs/gs = 0x10
5. 设 CR3 = 0x1000 (PGD physical)
6. 设 CR4.PAE = 0 (32-bit paging, 4KB 页, 不是 PAE)
7. 设 CR0.PG = 1, CR0.PE = 1 (开分页)
8. 跑 32-bit code
9. VGA 写 0xB8000 测试分页
```

## 🎯 测试方法

- M11 kernel 写 0xB8000 第 1 行 "M11 paging OK"
- 同时串口发 'M', '1', '1', ' ', 'P', 'G' 验证走到
- QEMU 看到 splash + 串口

## ⚠️ 撞过的事 (从 m8/m9 笔记)

- **GDTR base 必须是 physical address** (v19 撞过)
- **0xB8000 必须在分页里** (v19 撞过)
- **PGD/PGT 必须 4KB 对齐** (x86 要求)
- **PGD[0] = PGT physical** (不是 file offset)

## 🚀 文件

- `m11_paging.asm` — 32-bit kernel, 装 GDT + paging + VGA 测试
- `mbr_v34.asm` — 跟 v23 一样 (32-bit kernel 也装 sector 1, 物理 0x10000)
- 4KB 段 2-3 (PGD @ 0x1000) 跟段 4-5 (PGT @ 0x2000) 写固定数据

## 💡 简化方案 (用 M4MB page, 1 个 PGD entry = 1 个 4MB page)

- PGD[0] = 0x83 (4MB page, base=0, Present+RW+Supervisor)
- **不用 PGT**
- **更简单, 但 PS/2 0x60/0x64 + 串口 0x3F8 = memory-mapped 不能用, 必须是 port I/O (在, 4MB page 也行)**
- **决定**: 用 4KB page (主题 #3 笔记学的正路)

## ✅ 目标

- ✅ 切 32-bit
- ✅ 装 GDT (1 code + 1 data + null)
- ✅ 开分页 (CR0.PG=1)
- ✅ identity map 0-4MB
- ✅ 写 0xB8000 显示 "M11 paging OK" (验证分页)
- ✅ 串口 'M' '1' '1' ' ' 'P' 'G' (验证走到)
