# DNAOS 跟 Linus 0.01 对照笔记 (2026-06-12)

读完了 Linux 0.01 的 `boot/boot.s`、`boot/head.s`、`kernel/keyboard.s`。
整理出**我们 (DNAOS) 已经做了哪些、Linus 是怎么做的、还缺哪些**。

---

## 🗺️ 文件对应表

| Linux 0.01 | DNAOS v20 (M8+M9) | DNAOS 现状 |
|------------|-------------------|----------|
| `boot/boot.s` (329行) | `os/mbr_retry.bin` + `os/kernel_v19.asm` (entry_16) | ⚠️ 缺好几个关键步骤 |
| `boot/head.s` (175行) | `os/entry_32_v20.asm` (256B) | ✅ 大致对齐, 但有遗漏 |
| `kernel/keyboard.s` (264行) | ❌ 还没有 | ⏳ M10 必读 |
| `kernel/console.c` | ❌ 还没有 | ⏳ 我们的 entry_32_v20 用 VGA 直写代替 |
| `kernel/system_call.s` | ❌ 还没有 | ⏳ M13+ |
| `kernel/sched.c` | ❌ 还没有 | ⏳ M13 |
| `mm/page.s` | ❌ 还没有 | ⏳ M12 |

---

## 🔥 Linus 0.01 boot.s 里我们 MBR/entry_16 漏做的事

按 boot.s 流程顺序, **Linus 做的事, 我们没做的** (按重要性排):

### 1️⃣ **`empty_8042` 等待键盘控制器就绪** (boot.s 117-125行)
```asm
empty_8042:
    .word 0x00eb,0x00eb      ; jmp $+2 (延迟)
    in al, #0x64              ; 读键盘状态端口
    test al, #2               ; 检查输入缓冲是否空
    jnz empty_8042            ; 不空就等
    ret
```
**我们做的**: 我直接 `out 0x92` 强开 A20, 没用 0x64 端口。
**为啥 Linus 这么做**: 0x92 端口 (fast A20) 在某些机器上不可靠, 0x64+0x60 (keyboard controller A20) 是更通用的方法。
**影响**: 真实硬件上可能 A20 开不了 → 32位地址穿越1MB边界时出错。
**要不要做**: **M10 时加**, 不然键盘驱动开了也没用。

### 2️⃣ **重新编程 8259A PIC** (boot.s 137-180行)
Linus 把 IRQ 0-15 重新映射到 INT 0x20-0x2F, 避开 Intel 保留的 0x08-0x0F。
**为啥**: BIOS 默认 IRQ 0-7 → INT 0x08-0x0F, 但 INT 0x08+ 是 Intel 保留中断号, 会冲突。
**我们做的**: 没做, 还在用 BIOS 默认映射。
**影响**: 调 INT 0x21 (IRQ1 = 键盘) 时, 默认映射是 INT 0x09, 这跟 Intel 保留的 IRQ 7 (INT 0x0F) 几乎撞上, 一调就死。
**要不要做**: **M10 必须做**, 不然键盘 IRQ 起不来。

### 3️⃣ **`lmsw ax` vs `mov cr0, eax`** (boot.s 190-192行)
Linus 用 `lmsw ax` 设 CR0.PE (只设低 16 位), 我们用 `mov cr0, eax` 设全 32 位。
**区别**: `lmsw` 不会动 CR0 的高 16 位 (PG, AM, WP 等), `mov cr0, eax` 会覆盖全部。
**为啥 Linus 用 lmsw**: 在只切保护模式 (没分页) 时, 保留高 16 位比较安全。
**我们要不要改**: **不用改**, 我们的 `or eax, 1` 不会动高 16 位, 等价于 lmsw。但写 `mov cr0, eax` 没问题, 只是要小心。

### 4️⃣ **`jmp 0, 8` 而非 `jmp 8:offset`** (boot.s 194行)
Linus 跳到 **段选择子 0x08 + 偏移 0**。
**我们跳到**: `jmp 0x08:0x00010100` (GDT base=0, 跳到 0x10100)。
**为啥 Linus 跳到 0**: 他把整个内核 (head.s) **从 0x10000 搬到了 0x00000**! 详见下面 5️⃣。
**我们没搬**, 所以跳到 0x10100。**正确**, 风格不同而已。

### 5️⃣ **把内核从 0x10000 搬到 0x00000** (boot.s 81-99行) ⭐ 关键!
Linus 用 `rep movsw` 把 0x10000-0x90000 的内核内容整个搬到 0x00000-0x80000。
**为啥**: 让 head.s 里 `jmp 0, 8` 后能直接执行, 因为 GDT[1] 的 base 是 0。
**我们没搬**: 所以我们的 far jmp 偏移 0x10100 才合法。
**缺点**: 0x00000 区域现在还有 IVT (中断向量表, 1024 字节), 我们跳过去**不能踩到 0x00000**。
**我们要不要学 Linus**: **不学**, 我们的方案同样正确。但**学他有个好处**: 0x00000 之后是空的, 未来分页表/页目录正好放那, Linus 0.01 的 head.s 就是把页目录放在 `_pg_dir` (地址 0x00000)。

### 6️⃣ **`sectors` 配置项** (boot.s 33-37行)
Linus 把它做成**编译时常量**:
```asm
| 1.44Mb disks:
sectors = 18
| 1.2Mb disks:
| sectors = 15
| 720kB disks:
| sectors = 9
```
**我们**: 写死了 18 (1.44MB) 在 MBR 里, 通过手动 `dd` 偏移读 sectors 2-3。
**区别**: Linus 用更聪明的"整轨道读" (read_track 一次读整磁道, 跨 64K 边界时分段), 我们 MBR 是 sector-by-sector。
**Linus 的好处**: **快很多**, 1.44MB 内核只要几十个 INT 13h。
**我们 MBR 慢但简单**。M10 改不改变? **可以改进**, 但非必需。

### 7️⃣ **`kill_motor`** (boot.s 295-303行)
Linus 关掉软盘马达: `mov al, 0; out 0x3F2, al`。
**为啥**: 内核接管后不需要软盘马达一直转, 节省电 + 减少噪音。
**我们没做**: 不重要, QEMU 软盘没有真马达。

---

## 🔥 Linus 0.01 head.s 里我们 entry_32 漏做的事

### 1️⃣ **A20 真的开了吗? 自检!** (head.s 22-25行) ⭐⭐
```asm
1:  incl %eax           ; eax = 1, 2, 3, ...
    movl %eax, 0x000000  ; 写地址 0
    cmpl %eax, 0x100000  ; 读地址 1MB
    je  1b               ; 如果一样, A20 没开! 死循环
```
**为啥**: 即使我们 `out 0x92` 强开 A20, 也得**验证** A20 真的开了。
如果没开, 写地址 0x000000 + 0x100000 (16-bit wrap) 等于写地址 0x000000, 看起来"成功"但其实没真写到 1MB 之上。
**我们要不要加**: **M10 加**, 1 行汇编。非常便宜, 防真实硬件 boot 失败。

### 2️⃣ **FPU 检测** (head.s 27-33行)
Linus 检查 CR0.ET (Extension Type) 位, 没设就置 emulate bit, 用软件模拟 FPU。
**我们不需要**: 我们**完全不用浮点**。

### 3️⃣ **`setup_idt` + 256 个 ignore_int 处理器** (head.s 50-77行) ⭐
Linus 上来就把 IDT (中断描述符表) 设了, 256 个 entry 都指向同一个 `ignore_int`:
```asm
ignore_int:
    incb 0xb8000+160      ; 屏幕右上角 0xB80A0 字节 +1
    movb $2, 0xb8000+161  ; 改成红字
    iret
```
**为啥**: 进保护模式**必须**有 IDT, 不然任何中断 (除零、键盘、时钟) 进来都 #GP → #DF → 三重故障 → 死。
**我们没做**: 我们的 v20 halt 后**会接键盘中断**, 但**没有 IDT**, 第一个键盘中断就 #GP → 死。
**我们要不要加**: **M10 必须加**, 跟 PIC 重映射一起。

### 4️⃣ **`setup_gdt` 重新设 GDT** (head.s 81-85行)
Linus 在 head.s 里**重新设了 GDT** (虽然描述符一样)。
**为啥**: boot.s 里设的 GDT 是临时的, head.s 重新设一个**永久**的, 在 0x00000 之后。
**我们不需要**: 我们的 GDT 已经在 kernel.bin 里设好了, 不会被覆盖。

### 5️⃣ **`after_page_tables: jmp setup_paging`** (head.s 89-101行)
Linus 在 head.s 里**直接设了分页** (8MB identity mapping)。
**我们没做**: **M12 才做**。M10/M11 不用分页。

---

## 🖮️ Linus keyboard.s 我们 M10 必须学

### 1️⃣ **IDT gate type = 0x8E00** (head.s 56行)
```asm
movw $0x8E00, %dx     ; interrupt gate, dpl=0, present
```
**含义**: `0x8E = 10001110`, P=1, DPL=0, S=0 (interrupt/trap), Type=0xE (32-bit interrupt gate)。
**我们要学**: 32-bit interrupt gate, 跟 GDT 一样是 flat model。

### 2️⃣ **PIC EOI (End Of Interrupt)** (keyboard.s 60-62行)
```asm
movb $0x20, %al
outb %al, $0x20        ; 给主 PIC 发 EOI
```
**为啥**: 处理完中断必须告诉 PIC "我处理完了", 不然 PIC 不会再触发该 IRQ。
**我们 M10 要加**。

### 3️⃣ **`out 0x61` 复位键盘控制器** (keyboard.s 48-58行)
Linus 每次读键盘扫描码后, 写 0x61 端口"翻转"bit 7, 让键盘缓冲释放。
**这是 IBM PC 键盘的硬件 quirk**, 任何键盘驱动都要做。
**我们 M10 要加**。

### 4️⃣ **Scan code set 1 (XT) vs Set 2 (AT)**
Linus 用 **Set 1** (IBM XT 兼容), 用了一个 256-entry 的表 (key_table) 翻译扫描码。
**我们 M10**: 同样用 Set 1, 抄 Linus 的 key_table 即可, **最小化实现** (只翻译字母数字 + Enter + Backspace)。

---

## 📊 DNAOS 当前 vs Linux 0.01 状态

| 组件 | Linux 0.01 (1991) | DNAOS v20 (2026-06-12) | 缺什么 |
|------|-------------------|------------------------|--------|
| MBR (512B) | boot.s, 含 `jmp 0,8` 进 PM | mbr_retry.bin, 进 PM 后 jmp 0x08:0x10100 | 不缺, 风格不同 |
| 16-bit setup | 移内核+重映射 IRQ+PIC | 设 DS+lgdt+CR0.PE | ⚠️ 缺 PIC 重映射、empty_8042 |
| 32-bit head | IDT+GDT+分页+main | halt | ⚠️ 缺 IDT、A20 自检 |
| VGA 文字 | 间接通过 console.c | 直接写 0xB8000 | ✅ 比 Linus 简单, 正常 |
| 键盘 | 264 行 keyboard.s | 没有 | ❌ M10 必加 |
| 内存分页 | 8MB identity | 没有 | ⏳ M12 |
| 多任务 | fork+sched | 没有 | ⏳ M13 |
| 系统调用 | int 0x80 | 没有 | ⏳ M14+ |

---

## 🛠️ M10 实施清单 (基于 Linux 0.01)

按这个清单做, **保证不再撞新坑**:

### 阶段 1: IDT + PIC + A20 自检 (entry_32 增强)
1. ✅ 重新映射 8259A PIC: IRQ 0-7 → INT 0x20-0x27, IRQ 8-15 → INT 0x28-0x2F
2. ✅ 建 IDT: 256 entries, 都指向 `ignore_int` (暂用 ignore_int)
3. ✅ A20 自检: 写 0x00000, 读 0x100000, 看是否一样
4. ✅ 屏蔽所有 IRQ (写到 0x21, 0xA1): `out 0xA1, 0xFF; out 0x21, 0xFB` (留 IRQ2 = cascade)

### 阶段 2: 键盘驱动
1. ✅ 设 IDT[0x21] = 键盘中断处理器 (INT 0x21 = IRQ1 = 键盘)
2. ✅ 在键盘 handler 里:
   - 读 0x60 端口得 scan code
   - 用 key_table[scan_code] 翻成 ASCII
   - 写 0x61 端口翻转 bit 7 (复位键盘)
   - 给 PIC 发 EOI (写 0x20 到 0x20)
3. ✅ sti 启用中断
4. ✅ 写一个简化的 key_table (只用 ~30 个 keycode)

### 阶段 3: 简单 shell
1. ✅ 在 entry_32 末尾 (`hlt` 之前), 启 sti, 然后轮询键盘 buffer
2. ✅ 按 'h' 'e' 'l' 'p' + Enter → 显示 "help, ver, reboot" 列表
3. ✅ 按 'v' 'e' 'r' + Enter → 显示 "DNAOS v3.5 M10"
4. ✅ 按 'r' 'e' 'b' 'o' 'o' 't' + Enter → 系统重启 (触发三键 ctrl+alt+del)

### 阶段 4: VGA 行编辑
1. ✅ Backspace: 退一格, 把光标位置写 0x20 (空格)
2. ✅ Enter: 跳到下一行
3. ✅ 光标闪烁: 用 VGA 13h 端口写, 或自己实现 (但要写 VGA 索引寄存器 0x3D4, 数据 0x3D5)

### 预估代码量
- IDT: 2KB (1 IDT entry = 8 bytes, 256 = 2048 bytes)
- GDT: 32 bytes (4 entries)
- PIC 重映射: 20 字节
- 键盘 handler: 50 字节
- key_table: 256 bytes (1 byte per scan code, 只填用到的)
- shell 主循环: 200 字节
- 文本字符串: 200 字节

**总: 约 3KB**, 比 1KB 的 v20 大很多。需要把 kernel 改成 4KB 起步。

---

## 🎯 M10 完成后的样子

打开 QEMU 启动 dnaos_v21.img:
```
[黑屏 1秒, 然后 SeaBIOS]
Booting from Floppy..
[黑屏 0.5秒, 然后 DNAOS 自己的画面]
   DNAOS v3.5 M10 - 键盘可用
   ===========================
   
   > [光标闪]                <-- 你可以输入
```

按 `help` 回车:
```
   > help
   内置命令: help, ver, reboot
```

按 `ver` 回车:
```
   > ver
   DNAOS v3.5 (M10) - 2026-06-12 - 进入保护模式 + 键盘 + 简单 shell
```

按 `reboot` 回车:
```
   > reboot
   [系统重启]
```

---

## 🗒️ 这次读书的关键 takeaway

1. **Linus 0.01 跟 DNAOS v20 在 boot 阶段是同一种东西**, 风格差而已
2. **PIC 重映射 + IDT 是 32-bit 内核的"最低配置"**, 我们 M10 必须加
3. **A20 自检只多 4 行汇编, 非常便宜, 必须加**
4. **键盘驱动照抄 Linus keyboard.s 的扫描码表就行**, 不用查别的资料
5. **entry_32 现在 256 字节, M10 之后会到 3-4KB**, 是个大跳跃, 但这就是真实内核的样子
6. **Linus 自己说**: "This version is also meant mostly for reading" - 0.01 是个**教学版本**, 我们 DNAOS v3.5 在做的跟他 0.01 是同个量级的事
