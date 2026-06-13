# DNAOS v3.5 设计文档 (撕掉重来, 2026-06-13)

> **写于**: 2026-06-13 16:30 UTC
> **起因**: v6-v9 撞穿 9 个版本, 32-bit+分页撞 7 次, VGA 写 page fault
> **核心病**: 没设计就写代码, 撞 1 次改 1 行, 撞 2-3 次自己违犯
> **新原则**: **设计先行, 验证每步, 撞 2 次就停, 撞 3 次撕掉**
> **资源**: 自己写的 10 主题笔记 (~50KB), Linux 0.01 boot.s/head.s, hello386, OSDev wiki

---

## 🪞 病根诊断 (写代码前先看)

| 病 | 表现 | 根因 |
|----|------|------|
| 没设计 | 9 个版本, mem 布局每次都重算 | 启动序列没写纸上 |
| 撞死磕 | v6 撞 NASM SIB → 改 v7 → v8 撞 GDT base → 改 v9 → 又撞 PGT | 撞 2-3 次原则违犯 |
| 塞太多 | M11 一天想跑通 16→32+分页+VGA | 应该 M11 只做 16→32, M12 只做分页, M13 才 VGA |
| 不画图 | 4MB mem 范围 PTE 索引 0xB80 > 1023 算错 | 应该画 0-4MB 4 张 PGT 图 |
| 不验证 | 装 GDT 段不抓 mem 看 | 应该每装一段就 QEMU 抓 mem 验证 |
| 装跑通 | 跑通 10 marker = 跑通 OS | 10 marker = 0 个用户进程 = 0 OS |

---

## 🎯 v10 启动序列 (6 阶段, 每阶段一验证)

### 阶段 0: BIOS POST + 引导
- BIOS 加载 MBR (sector 0) 到 0x7C00, 跳 0x7C00
- MBR 0x7C00: 关中断, 设栈, 加载 sector 1-N 到 0x10000+
- 验证: serial 0x3F8 输出 'B' (BIOS) + 'M' (MBR)

### 阶段 1: 16-bit 实模式内核 (M10 已有)
- k11 entry 0x10000, cs=0x1000, ds=0x1000
- 关 NMI, 开 A20 (keyboard controller 0x64/0x60, command 0xD1 0xDF)
- 验证: serial 输出 'A' (A20 open)

### 阶段 2: 16-bit 段装 GDT (32-bit 段描述符)
- GDT 段装在 k11 BSS (gdt_start_offset), **计算 physical 物理地址**
- gdt_desc 装: limit=23, base=gdt_start_phys
- 验证: serial 'G', **QEMU monitor 抓 mem 验证 gdt_desc base 装对**

### 阶段 3: lgdt + IDT desc + lidt
- `lgdt [gdt_desc]`, IDT 256 entries 全 ignore_int
- 验证: serial 'D', QEMU 抓 GDTR 寄存器

### 阶段 4: 16→32 切换 (开 PE)
- `mov eax, cr0; or eax, 1; mov cr0, eax`
- 立刻 far jmp `0x08:pm_entry` (32-bit code 段)
- 验证: serial 'P', dlog 看 CS=0x0008 32-bit

### 阶段 5: 32-bit 段初始化
- `mov ax, 0x10; mov ds, ax; mov es, ax; mov fs, ax; mov gs, ax; mov ss, ax; mov esp, 0x90000`
- 验证: serial 'X', QEMU info reg ds=0x10

### 阶段 6: 分页 (M11 主菜, 不做 VGA)
- 装 PGD @ 0x11000 (1024 entries)
- 装 PGT#0 @ 0x12000 (1024 entries, 范围 0-4MB)
- 装 PGT#1 @ 0x13000 (1024 entries, 范围 4-8MB)
- 装 PGT#2 @ 0x14000 (1024 entries, 范围 8-12MB)
- PGD[0] = 0x00012023 (PGT#0, 4KB page, R/W, supervisor)
- PGD[1] = 0x00013023 (PGT#1, 4KB page, R/W, supervisor)
- PGD[2] = 0x00014023 (PGT#2, 4KB page, R/W, supervisor)
- 设 CR3 = 0x11000
- 开 CR0.PG
- 验证: serial '3' (CR3 装) + '!' (PG 开), **不写 VGA**

---

## 📊 内存地图 (v10 单一真理源)

```
物理地址        用途                        段
─────────────────────────────────────────────────────
0x00000-0x003FF 中断向量表 (BIOS 用)        -
0x00400-0x004FF BIOS 数据区                -
0x00500-0x0FFFF 自由 (MBR 留)               -
0x07C00         MBR 加载点                  -
0x10000-0x1FFFF Kernel (k11 64KB)           ds=0x1020
  0x10000-0x10165 k11 code
  0x10166-0x1019C k11 BSS (GDT 24B + desc 8B)
  0x1019D-0x10B9C k11 BSS (IDT 2048B + desc 8B)
  0x10B9D-0x1FFFF 自由 (Stage2 用)
0x11000         PGD (4KB, 1024 entries)    -
0x12000         PGT#0 (4KB, 0-4MB)         -
0x13000         PGT#1 (4KB, 4-8MB)         -
0x14000         PGT#2 (4KB, 8-12MB)        -
0x90000-0x9FFFF Kernel 栈 (PM)             -
0xB8000         VGA 文本 (M13 再用)         -
0xF0000-0xFFFFF BIOS ROM                   -
```

## 📋 段表 (v10 静态)

| 段 | 索引 | base | limit | type | flags |
|----|------|------|-------|------|-------|
| null | 0 | 0 | 0 | 0 | 0 |
| code 32-bit | 1 (0x08) | 0 | 0xFFFFF | 0x9A (code) | G=1, D=1, P=1, DPL=0 |
| data 32-bit | 2 (0x10) | 0 | 0xFFFFF | 0x92 (data, R/W) | G=1, D=1, P=1, DPL=0 |
| code 16-bit | 3 (0x18) | 0 | 0xFFFF | 0x9A (code) | D=0, P=1, DPL=0 (备用) |

## 📋 分页 (4KB 段, identity mapping 0-12MB)

| PGD entry | PGT | 范围 | 内容 |
|-----------|-----|------|------|
| 0 | PGT#0 @ 0x12000 | 0-4MB | identity map (全 supervisor R/W) |
| 1 | PGT#1 @ 0x13000 | 4-8MB | identity map (全 supervisor R/W) |
| 2 | PGT#2 @ 0x14000 | 8-12MB | identity map (全 supervisor R/W) |
| 3+ | - | 12MB+ | 0 (没映射) |

---

## 🚦 验证协议 (每阶段必做)

| 验证项 | 工具 | 期望 |
|--------|------|------|
| Serial marker | `cat /tmp/sm35.log` | 看到该阶段 marker |
| GDT 段装对 | `xp /8bx 0x103XX` | 看到 0x9A/0x92 字节 |
| GDTR 装对 | `info registers` | `GDT=...` 跟 gdt_desc base 一致 |
| CR3 装对 | `info registers` | `CR3=0x00011000` |
| CR0.PG 装对 | `info registers` | `CR0=0x80000011` |
| dlog fault | `grep "check_exception" /tmp/qm35.dlog` | 没 v=0d/0e fault |

## 🛑 撞穿 2-3 次停手原则

| 撞 | 行动 |
|----|------|
| 撞 1 次 | 查表 (10 主题笔记, Linux 0.01, OSDev wiki) |
| 撞 2 次 | 停手, 回到设计文档看哪步不对 |
| 撞 3 次 | 撕掉 v10, 重写设计 |

## ⏸ v10 不做 (推到 M12+)

- ❌ VGA 写 (VGA 在 M13)
- ❌ IDT 装 IRQ (IRQ 在 M11.5, 现在 IDT 全 ignore_int)
- ❌ 进程/调度 (M13)
- ❌ 系统调用 (M14)
- ❌ FAT12 读 (M12)
- ❌ 键盘驱动 (M15)

## 🎯 v10 完成定义 (Done)

- [ ] MBR 加载 k11 (阶段 0-1) ✓
- [ ] A20 开 (阶段 1) ✓
- [ ] GDT 装 (阶段 2) ✓
- [ ] lgdt + IDT desc (阶段 3) ✓
- [ ] 16→32 切 (阶段 4) ✓
- [ ] 32-bit 段设 (阶段 5) ✓
- [ ] 分页开 (阶段 6) ✓
- [ ] 跑通 marker: B M A G D P X 3 ! (8 个)
- [ ] 装 dlog 看到没 v=0d/0e fault
- [ ] QEMU 抓 mem GDT 段 = 0x9A/0x92
- [ ] QEMU info reg CR3 = 0x00011000, CR0 = 0x80000011
- [ ] commit + push

## ⏭ v11+ 计划

- **v11**: 加 VGA 写 (0xB8000, frame 在 PGT#2[0x180], 验证 'P' marker 出现)
- **v12**: 加 IDT IRQ0 (PIT 100Hz, 时钟中断)
- **v13**: 加 IDT IRQ1 (PS/2 键盘)
- **v14**: 加 1 个用户进程 (用 v86 模式跑 16-bit shell)
- **v15**: 推进 M13 (进程调度)

---

## 📚 写代码前必看

1. `/workspace/memory/long-topic-1-boot.md` — 启动 + 实模式
2. `/workspace/memory/long-topic-2-pm-gdt.md` — 16→32 切 + GDT
3. `/workspace/memory/long-topic-3-paging.md` — 分页 (重点: 1024 PTE/段, 4MB 范围)
4. `/workspace/linux-0.01/boot/boot.s` — Linux 0.01 16→32 切
5. `/workspace/linux-0.01/boot/head.s` — Linux 0.01 分页 + 32-bit
6. `https://wiki.osdev.org/Setting_Up_Paging` — OSDev 分页
7. `https://www.kasperiapell.com/hello386` — hello386 32-bit VGA
8. `https://github.com/lukearend/x86-bootloader` — 完整 bootloader
