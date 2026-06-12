# CSAPP 阶段 1 笔记 (2)

**日期**: 2026-06-12
**章节**: 第 3 章 (机器级程序) + 第 9 章 (虚拟内存) + 第 6 章 (存储器层次)
**目标**: 跟 OSTEP 互补 — OSTEP 讲 OS 概念, CSAPP 讲"程序怎么在机器上跑"

---

## 第 3 章: 机器级程序 (x86-64 汇编)

### 这章讲的 3 件事

#### 1. x86-64 寄存器
- 16 个 64-bit 通用寄存器: rax, rbx, rcx, rdx, rsi, rdi, rbp, rsp, r8-r15
- 32/16/8 bit 别名: eax, ax, al 等
- **rsp** 永远指向栈顶, 不能乱用
- **rbp** 是帧指针, 用来访问函数参数和本地变量 (但 GCC -fomit-frame-pointer 会废掉它)

#### 2. 数据格式
- byte (8 bit), word (16 bit), double word (32 bit), quad word (64 bit)
- 汇编里 `mov` 操作数后缀: `movb` (byte), `movw` (word), `movl` (double), `movq` (quad)

#### 3. 指令格式
- 操作数有 3 种: 立即数 ($0x10), 寄存器 (%rax), 内存引用 (0x10(%rax))
- 例子: `movq 0x10(%rax), %rbx` = 把 [rax+0x10] 处的 8 字节移到 rbx

### DNAOS 对应 ⭐

**我们 v20 的汇编就是 x86, 但用 NASM 语法** (不是 AT&T):
- NASM: `mov ax, 0x1000` (dest 左边, 立即数没 $)
- AT&T: `mov $0x1000, %ax` (dest 右边, 立即数有 $)

**v20 里很多 16-bit/32-bit 切换**:
- `mov ax, 0x1000` 是 16-bit 写 ax
- `mov eax, cr0` 是 32-bit (CR0 总是 32-bit)
- **CSAPP 第 3.2 节**详细讲了这些位宽切换 — 我们 v20 的代码是教科书例子

**回头看 v20 kernel_v19.asm**:
- `mov al, '1'` ← movb (byte)
- `mov ax, 0x1000` ← movw (word)
- `mov dx, 0x3F8` ← movw (port I/O 必须是 16-bit)
- `mov eax, cr0` ← movl (CR0 32-bit)
- `db 0x66; db 0xEA; dd 0x10100; dw 0x0008` ← far jmp 32-bit form

---

## 第 9 章: 虚拟内存 (Virtual Memory) ⭐⭐

### 这章讲的 3 件事

#### 1. 虚拟地址 = 虚拟页号 (VPN) + 页内偏移
- 4KB 页: 12 bit 偏移, 剩下 36 (32-bit) 或 52 (64-bit) 是 VPN
- 64-bit x86-64: 48 bit 虚拟地址, 4 级页表 (PML4 → PDPT → PD → PT)

#### 2. 缺页 (Page Fault)
- 进程访问一个**没映射**的虚拟页 → 触发 page fault → OS 在磁盘找这个页 → 装入物理内存 → 改页表 → 重试指令
- **这是按需分页 (demand paging) 的基础**

#### 3. 地址翻译 (TLB)
- CPU 每次内存访问都要查页表, 太慢
- TLB 是页表的小缓存, 命中就 0 cycle
- 进程切换时, **TLB 必须 flush** (因为新进程的虚拟地址空间不一样)

### DNAOS 对应 ⭐⭐

**M12 (分页) 必备知识**。Linus head.s 的 setup_paging 就是这章的实操:

```asm
setup_paging:
    movl $1024*3, %ecx     ; 清 3 个页表 (pg_dir, pg0, pg1)
    xorl %eax, %eax
    xorl %edi, %edi          ; pg_dir 在 0x00000
    cld; rep; stosl          ; 全部清 0
    
    movl $pg0+7, _pg_dir     ; pg_dir[0] = pg0 (P=1, R/W=U)
    movl $pg1+7, _pg_dir+4   ; pg_dir[1] = pg1
    movl $pg1+4092, %edi     ; pg1 的最后一项
    movl $0x7ff007, %eax     ; 8MB - 4096 = 0x7FF000, +7 = P|U|R/W
    ; 反向填充 1024 个 PTE, 每个映射 4KB
    std
1:  stosl
    subl $0x1000, %eax
    jge 1b
    
    xorl %eax, %eax
    movl %eax, %cr3          ; CR3 = 0x00000 (pg_dir 在那)
    movl %cr0, %eax
    orl $0x80000000, %eax    ; CR0 bit 31 = PG
    movl %eax, %cr0
    ret
```

**写 M12 时直接抄这段**, 改 8MB → 我们想要的 (32MB? 64MB?)

---

## 第 6 章: 存储器层次 (Memory Hierarchy)

### 这章讲的 3 件事

#### 1. 局部性原理 (Principle of Locality)
- **时间局部性**: 一个内存位置被访问, 近期很可能再被访问
- **空间局部性**: 附近的地址也可能被访问 (数组遍历)

#### 2. 缓存 (Cache)
- L1 (CPU 内部, 4 cycle, 32KB)
- L2 (CPU 内部, 10 cycle, 256KB)
- L3 (CPU 内部, 40 cycle, 8MB)
- 主存 (200 cycle)
- 磁盘 (10M cycle)

#### 3. 写策略
- 写直达 (write-through): 改了缓存就立刻写回主存
- 写回 (write-back): 标记"脏", 淘汰时才写

### DNAOS 对应

**M12 之后**才需要考虑缓存。Linus 0.01 没设缓存, 我们的 v20 也没设。

但**M14+ 文件系统**会用到: 写盘是慢操作, 必须**批量写 + 缓存**。

---

## 这阶段学到的, DNAOS 接下来要用的

| DNAOS Milestone | 需要的概念 | CSAPP 章节 |
|----------------|-----------|-----------|
| M10 (键盘) | x86 汇编位宽, port I/O | 第 3 章 ✓ |
| M11 (64-bit 长模式) | 新的寄存器, 系统调用约定 | 第 3 章 + 9 章 |
| M12 (分页) | 虚拟地址翻译, CR3, 多级页表 | 第 9 章 ⭐ |
| M13 (多任务) | 上下文切换, 寄存器保存 | 第 3 章 |
| M14+ (文件系统) | 写策略, 缓存, 局部性 | 第 6 章 ⭐ |

---

## 关键 takeaway (CSAPP 给 DNAOS 最大的帮助)

1. **位宽要清楚**: `mov al` 是 byte, `mov ax` 是 word, `mov eax` 是 dword
2. **CR0/CR3 永远是 32-bit**: 用 `mov eax, cr0` 不能用 `mov ax, cr0`
3. **TLB 在进程切换时 flush**: `mov cr3, cr3` 一行就能 flush TLB
4. **page fault 是好事**: 缺页异常就是"按需调页"的机制, 不必一开始就全部装入
