# Orange's 一个操作系统的实现 阶段 1 笔记 (3)

**日期**: 2026-06-12
**章节**: 第 1 章 (MBR) + 第 2 章 (保护模式) + 第 3 章 (GDT/IDT/PIC)
**资源**: 由于 PDF 下不到, 用以下资源:
- Linux 0.01 完整源码 (`/workspace/linux-0.01/`) 代替 Orange's 完整例子
- whirlys/ORANGE_OS 仓库的代码
- CSDN/blog 上的 Orange's 章节笔记

**目标**: 把 Orange's 当作"实战", 把 DNAOS 跟它**一一对应**

---

## 第 1 章: MBR (跟我们的 v20 对照)

### Orange's 做的
1. 写一个 `mbr.s`, 512 字节
2. `mov ax, 0x7C0; mov ds, ax` (DS 指向 MBR 自己)
3. 打印 "Hello, OS world!" 通过 INT 10h (BIOS)
4. 死循环

### DNAOS 做的 (mbr_retry.bin)
1. 一样的 DS 初始化
2. **没打印, 直接读 sector 2** (kernel) 到 0x10000
3. **10 次重试** (QEMU floppy quirk workaround)
4. 跳到 0x10000 (entry_16)

### DNAOS 比 Orange's 多的
- 10-retry MBR (Linus 0.01 没做, 因为他的 MBR 是 1.2MB/720KB/1.44MB 都支持, 我们的写死 1.44MB)
- 不打印 hello, 安静地 boot (更适合 headless / serial 输出)

### DNAOS 比 Orange's 少的
- Orange's 第 1 章**没进保护模式**, 就是 16-bit 实模式
- 我们 v19 之后就进保护模式了 (M8 已完成)

---

## 第 2 章: 保护模式 (Protect Mode)

### Orange's 讲的事
1. **为什么需要保护模式**: 实模式 1MB 限制, 16-bit 段, 没分页
2. **GDT (Global Descriptor Table)**: 数组, 每个 entry 8 字节, 描述一个内存段
3. **段描述符格式**: 64-bit, 含 base (32-bit), limit (20-bit), access (8-bit), flags (4-bit)
4. **进入保护模式**: 关中断 → lgdt → 设 CR0.PE → far jump
5. **保护模式特性**: 4GB flat model, 分页可加, 特权级 (ring 0-3)

### DNAOS 跟它的对比

| 项 | Orange's 第 2 章 | DNAOS v19/v20 |
|---|------------------|----------------|
| 段描述符格式 | `dw, dw, db, db, db, db, dw` (6 个字段) | `dw, dw, db, db, db, db` (5 个字段, NASM) |
| GDT 位置 | 在 MBR 里 (`mbr.s` + `protect.c`) | 在 kernel 里 (offset 0x78) |
| 进入保护模式 | `mov cr0, 0x11` (PE + ET) | `mov cr0, eax` (OR 1) |
| Far jump | `jmp dword SelectorCode:0` | `db 0x66; jmp 0x08:0x00010100` |
| GDTR base | 用 `dd gdt_start` (Orange's 用 GAS, 知道 org 0x7C00) | 用 `struct.pack_into('<I', k, 0x72, 0x00010076)` (NASM 不知道 load addr) |

### 关键 learning
**GDT 描述符的 flags 字节**:
- `11001111` = G=1, D=1, L=0, AVL=0
- G=1: 4KB 粒度 (limit 20 bit × 4KB = 4GB)
- D=1: 32-bit 默认操作数
- L=0: 不是 64-bit (我们 M11 才用 L=1)

**v20 用的就是 0xCF** ✓

---

## 第 3 章: GDT/IDT/PIC (跟我们的 v21 draft 对照)

### Orange's 讲的事
1. **完善 GDT**: 4 个 entry (null + 代码 + 数据 + TSS 模板)
2. **IDT (Interrupt Descriptor Table)**: 类似 GDT, 256 个 entry, 每个 8 字节
3. **IDT 描述符格式**: offset_low (16) | selector (16) | zero (8) | type (8) | offset_high (16) = 64 bit
4. **PIC 8259A 重映射**: IRQ 0-7 → INT 0x20-0x27, IRQ 8-15 → INT 0x28-0x2F
5. **8259A ICW1-4**: 初始化序列, 4 个 control word

### DNAOS 跟它的对比

| 项 | Orange's 第 3 章 | DNAOS v21 draft (未编译) |
|---|------------------|--------------------------|
| GDT 位置 | 仍在 loader (0x90000) | 在 kernel 0x10078 |
| GDT 重新设 | 是 (因为搬到 0x00000) | 不需要 (我们不搬内核) |
| IDT 位置 | 0x00000 (跟页目录共享) | 0x10500 (独立) |
| IDT[0x21] (键盘) | 单独设 | 单独设 (0x100 + offset 0x600 ≈ 0x700) |
| PIC 重映射 | 完整 8259A ICW1-4 | 完整 8259A ICW1-4 |
| A20 | fast A20 (端口 0x92) | fast A20 + 自检 |

### 关键 learning
**IDT 描述符 type 字节**:
- `0x8E` = 10001110 = P=1, DPL=0, S=0, Type=0xE
- **0xE = 32-bit interrupt gate**
- 我们 v21 用 `0x8E00` ✓

**为什么 IDT 必须设**:
- 进保护模式后, **中断向量表 (IVT) 失效**
- 任何中断进来 (键盘, 时钟, 异常) 都会 #GP
- IDT 是 32-bit 保护模式的"中断路由表"
- 我们 v20 暂时不需要, 因为 halt 后**不会有中断**
- **v21 必须设, 因为键盘 IRQ 进来要路由**

---

## 阶段 1 总结: DNAOS v8-v21 跟 Orange's / Linux 0.01 对应

| DNAOS | Orange's 第几章 | Linux 0.01 文件 | 状态 |
|-------|----------------|----------------|------|
| v8 (GDT 错) | 第 2 章 | boot.s (gdt: 段) | ✅ M8 修好 |
| v19 (M8 完工) | 第 2 章 | boot.s + head.s (startup_32) | ✅ |
| v20 (M9 VGA) | 第 2 章 | kernel/console.c (早期) | ✅ |
| v21 (M10 键盘) | 第 3 章 | kernel/keyboard.s | ⏳ draft |
| v22 (M11 64-bit) | 第 4 章 (部分) | 不在 0.01 范围 | ⏳ |
| v23 (M12 分页) | 第 5 章 | mm/page.s | ⏳ |
| v24 (M13 多任务) | 第 6 章 | kernel/sched.c + fork.c | ⏳ |
| v25+ (文件系统) | 第 7+ 章 | fs/* | ⏳ |

---

## 关键 takeaway (Orange's 给 DNAOS 最大的帮助)

1. **Orange's 跟我们的 M8 是一回事** (GDT + 保护模式), 我们 v19 跟它同等
2. **第 3 章 (IDT + PIC) 是 M10 必读**, 我们 v21 draft 已经按 Orange's 风格写
3. **Orange's 第 5-7 章 (内存管理 / 进程 / 文件系统) 是 M12-M14 的圣经**
4. **Orange's 跟 Linux 0.01 是同一种东西**: Orange's 是中国版, Linux 0.01 是 Linus 原版, 思路几乎一样

---

## 接下来 (回到 A 模式: 快速翻)

读完这三本, 写一份 "DNAOS M10-M16 完整路线图", 引用具体章节。
然后**等白桦说开始 M10 再开始动手**。
