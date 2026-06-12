# DNAOS 学习路线图 (阶段 1 总结)

**日期**: 2026-06-12
**已完成**: 阶段 1 第 1 轮 (OSTEP ch2/ch4/ch13-15, CSAPP ch3/ch9/ch6, Orange's ch1-3)

---

## 📚 4 阶段进度

| 阶段 | 资源 | 已读 | 待读 |
|------|------|------|------|
| 1. OSTEP | ostep.pdf 5.1MB | ch2 进程, ch4 调度, ch13-15 内存虚拟化 | ch21-23 同步, ch37-41 文件系统 |
| 2. CSAPP | csapp.pdf 1.3MB | ch3 机器级, ch9 虚拟内存, ch6 缓存 | ch10 I/O, ch11 网络, ch12 并发 |
| 3. Orange's | (无 PDF, 用 Linux 0.01 源码) | ch1 MBR, ch2 PM, ch3 GDT/IDT/PIC | ch4 进程, ch5 内存, ch6+ 文件系统 |
| 4. Linux 0.01 对照 | 已下到 /workspace/linux-0.01/ | 详见 LINUX_0.01_NOTES.md | 等 M10 写完对照 |

---

## 🎯 DNAOS M8-M16 完整路线图 (基于 3 本书)

### M8 ✅ (已完成 2026-06-12)
**目的**: 进保护模式
**来源章节**: OSTEP ch2 (进程概念), CSAPP ch3 (位宽, CR0), Orange's ch2 (PM)
**代码**: mbr_retry.bin + kernel_v19.asm + entry_32_v20.asm (256B)
**关键知识点**:
- 32-bit CR0 bit 0 = PE (Protection Enable)
- GDT 描述符 8 字节 (limit, base, access, flags)
- 32-bit far jmp (`db 0x66` + `jmp 0x08:0x10100`)

### M9 ✅ (已完成 2026-06-12)
**目的**: VGA 文字输出
**来源章节**: CSAPP ch3 (内存映射 I/O)
**代码**: entry_32_v20.asm
**关键知识点**:
- 0xB8000 是 VGA text mode 缓冲区 (80x25, 2 字节/格)
- 不用 INT 10h, 直接写内存 (保护模式里 INT 10h 会 #GP)

### M10 ⏳ (draft 在 entry_32_v21.asm, 待 M8 学习完成)
**目的**: 键盘 + 简单 shell
**来源章节**: CSAPP ch3 (port I/O), Orange's ch3 (PIC/IDT/A20)
**代码**: entry_32_v21.asm (1.4KB, 没编译)
**关键知识点**:
- 8259A PIC 重映射: ICW1-4 写到 0x20, 0xA1 端口
- IDT 256 entry × 8 字节, 0x8E = 32-bit interrupt gate
- A20 自检: 写地址 0, 读地址 1MB, 比对
- PS/2 键盘: 0x60 端口读 scan code, 0x61 端口复位
- 简化 key_table (抄 Linux 0.01 keyboard.s)

### M11 (未开始)
**目的**: 64-bit 长模式
**来源章节**: CSAPP ch3 (64-bit 寄存器), Orange's ch4 (段页扩展)
**代码**: 新 entry_32
**关键知识点**:
- CR0.PG 已经设, 现在加 CR4.PAE
- 4 级页表: PML4 → PDPT → PD → PT
- 切换到 long mode: `mov ecx, 0xC0000080; rdmsr; or eax, 1; wrmsr` (IA-32e enable)
- LMA (Long Mode Active) bit
- 64-bit GDT descriptor: L=1, D=0

### M12 (未开始)
**目的**: 内存分页 (4MB 起始, 8MB 平坦)
**来源章节**: OSTEP ch13-15, CSAPP ch9, Orange's ch5
**代码**: 抄 Linux 0.01 head.s 的 setup_paging
**关键知识点**:
- CR0.PG = 1 (开分页)
- CR3 指向页目录 (我们放 0x00000)
- 页目录 4KB, 1024 PTE
- identity mapping: 虚拟地址 = 物理地址

### M13 (未开始)
**目的**: 多任务 + 进程切换
**来源章节**: OSTEP ch2 (PCB), ch4 (RR 调度), CSAPP ch3 (寄存器保存)
**代码**: 抄 Orange's ch6 + Linux 0.01 sched.c
**关键知识点**:
- 进程 = PCB + 内存映射 + 寄存器
- 上下文切换: 保存当前进程的 ESP/EBP/通用寄存器, 加载下一个进程的
- 调度: 简单 RR, 10ms 时间片
- PIT (Programmable Interval Timer) 触发时钟中断
- task struct: Linux 0.01 kernel/sched.c 有完整代码

### M14 (未开始)
**目的**: 简单文件系统 (FAT12)
**来源章节**: OSTEP ch37-41, CSAPP ch10, Orange's ch7-8
**代码**: 抄 Orange's ch7 + Linux 0.01 fs/* (Minix FS)
**关键知识点**:
- 文件 = 字节流, 目录 = 文件的列表
- inode + 数据块 (Linux Minix FS) / FAT 表 (DOS)
- 块大小 1KB 或 4KB
- 写盘用 PIO (port I/O), 不需要中断驱动
- 写策略: 写直达 (简单) 或写回 (复杂)

### M15 (未开始)
**目的**: 网络栈基础 (RTL8139 NIC 驱动)
**来源章节**: CSAPP ch11, Linux 0.01 net/*
**代码**: 抄 Linux 0.11 net/ (0.01 没 net)
**关键知识点**:
- 网卡 = 内存映射的 DMA 缓冲区
- RTL8139 端口 0xC000 (基地址)
- 包格式: Ethernet + IP + UDP
- 简化: 只做 UDP echo server

### M16 (未开始)
**目的**: 真硬件 boot
**来源章节**: OSTEP ch37-41 (持久化), Orange's 第 1 章
**代码**: 用真 USB 软盘启动
**关键知识点**:
- BIOS 跟 QEMU 不一样
- 真硬件 INT 13h 比 QEMU 稳
- 软盘可能没插好
- 时间问题 (QEMU 跑得快, 真机器慢)

---

## 📋 关键 takeaway (这 3 阶段读完)

1. **OSTEP 给概念**: 进程 = 内存 + 寄存器 + 状态。内存 = 虚拟 + 物理 + 分页。文件 = 块 + inode + 目录。
2. **CSAPP 给底层**: 汇编位宽、CR0/CR3 寄存器、地址翻译、缓存。
3. **Orange's 给实战**: 1000 多行 NASM + C, 真实 bootable 32-bit OS, 直接抄。

**DNAOS 跟这三本完全对得上**:
- v19/v20 = Orange's 第 2 章 + CSAPP ch3
- v21 = Orange's 第 3 章
- M12 = OSTEP ch14 + Orange's 第 5 章 + CSAPP ch9
- M13 = OSTEP ch2/ch4 + Orange's 第 6 章
- M14 = OSTEP ch37-41 + Orange's 第 7-8 章

---

## 🚫 不做

- **不一口气读完全部 OSTEP/CSAPP** (白桦说"快速翻")
- **不重新写 v19/v20** (已经稳定)
- **不盲改 v21 编译** (等 M10 真的需要时再回来细看 Orange's 第 3 章)

## ✅ 做

- 阶段 1+2 笔记已经写完 (`ostep_ch2_ch4.md`, `csapp_ch3_ch9.md`, `orange_ch2_ch3.md`)
- 这份路线图 (`roadmap_summary.md`)
- **等白桦确认是否进 M10, 或先读阶段 2 (CSAPP I/O + 网络) + 阶段 3 (Orange's 4-7 章)**
