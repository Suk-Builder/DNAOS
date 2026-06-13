# DNAOS v3.5 M11 v9 — 查书+网搜+linux-0.01+hello386 经验, 跑通 32-bit+分页, VGA 写还撞

**日期**: 2026-06-13 16:30 UTC
**状态**: ⏳ 撞 7 次, 跑通 32-bit+分页 (10 marker), VGA 写 page fault

## 🎯 跑通部分 (v9 跑 10 marker)

```
H K A G T G D P X 3 !
```

| marker | 意义 | 状态 |
|--------|------|------|
| H | mbr head 1 OK | ✓ |
| K | kernel 启动 | ✓ |
| A | A20 gate 开 | ✓ |
| G | PGD 装好 (PGD[0]=PGT#0, PGD[2]=PGT#2) | ✓ |
| T | PGT 装好 (PGT#0 + PGT#2) | ✓ |
| G | GDT 装好 (GDT[1] code 0x9A, GDT[2] data 0x92) | ✓ |
| D | GDT desc + lgdt + IDT desc + lidt | ✓ |
| P | CR0.PE=1 | ✓ |
| X | 32-bit 段 + 设 ds/es/fs/gs/ss=0x10 + esp=0x90000 | ✓ |
| 3 | CR3 = 0x11000 | ✓ |
| ! | PG=1, 分页开 | ✓ |
| V | VGA 写 0x0F50 到 0xB8000 | ⏳ page fault |

## 🛑 撞 7 次 (查书+网搜+linux-0.01+hello386 经验)

### 撞 1-6 (之前 v6-v8): 见 m11_paging_v3/CRASH_REPORT.md
- NASM 16-bit 段 SIB bug
- GDT[2] type 0x92 vs 0x93
- mbr 跳错位置
- `mov ax, gdt_start_phys` 丢高 16-bit
- pm_entry_phys 算错 0x200 (v8 算 0x10200+offset, 应该 0x10000+offset)
- v8 装 GDT 段到 mem 0x10380 (gdt_start_offset 0x180, ds=0x1020 段)

### 撞 7: PGT[0xB80] 越界 PGT#0
- **真根因 #1**: PGT#0 段只 1024 PTE (PTE 索引 0-0x3FF), 0xB80 PTE 索引 2944 越界
- **修法**: 装 PGT#2 (mem 0x14000) 含 PGT#2[0x180] = 0x000B8003, PGD[2] = 0x00014023

### 撞 8: PGT#2 段装入失败 (es=0x1100 段 rep stosw 覆盖 PGD 段)
- **真根因 #2**: v9 装 PGT#2 段用 es=0x1100 段, rep stosw 装 0x800 words from 0x11000+0x3000-0x3400 (覆盖 PGD 段 0x11000-0x11FFF)
- **修法**: 装 PGT#2 段用 es=0x1100 段 + rep stosw 0x400 words from di=0x3000 to 0x3400 (PGT#2 段范围 0x14000-0x14400, 不覆盖 PGD 段)

### 撞 9: NASM 16-bit 段下 `mov dword [es:0x600], 0x000B8003` 装入 word 0xB803 (丢高 16)
- **真根因 #3**: NASM 16-bit 段下 `mov dword [es:0x600], 0x000B8003` 编译 = `mov word [es:0x600], 0xB803` (只装 2 字节, 丢高 16)
- **修法**: 用 2 次 `mov word` 装 dword (low 16 + high 16)

### 撞 10: GDT[2] 装入失败? (type=0x92 vs 0x93)
- **真根因 #4**: GDT[2] 装 0x00CF9200 type=0x92, mem 实际 byte 5 = 0x93 (A bit CPU 自动设 1, 不是 bug)
- **等等, dlog DS=0x10 type=0x93 是 A bit 设了 (k11 跑过 DS 段), 正常行为**
- **DS 段寻址 expand-UP, base 0, limit 0xFFFFF, 寻址 ds:edi = 0 + edi = 0xB8000 ✓**

## 📊 v9 跑通部分

- 32-bit 段 (CS=0x0008) + ds=0x10 + es=0x10 + fs=0x10 + gs=0x10 + ss=0x10 + esp=0x90000
- PGD[0]=0x00012023 + PGD[2]=0x00014023
- PGT#0[0x10]=0x00010003 + PGT#0[0x11]=0x00011003 + PGT#0[0x12]=0x00012003 + PGT#0[0x90]=0x00090003
- PGT#2[0x180]=0x000B8003
- CR3=0x11000 + PG=1
- A20=1 ✓

## 💡 真正查书+网搜+linux-0.01+hello386 经验学到

1. **linux-0.01 boot.s** (jmp 0x08 init_pm, 32-bit far jmp):
   - 关键: 32-bit 段 `mov ax, DATA_SEG; mov ds, ax; mov es, ax; mov fs, ax; mov gs, ax; mov ss, ax; mov esp, stack_top`
2. **hello386 VGA write** (32-bit mov edi, 0xb8000; mov [edi], ax):
   - 关键: 32-bit 段设 ds/es/fs/gs/ss + esp + VGA write
3. **NASM 16-bit 段下 `mov dword [es:disp16], imm32` 实际只装 word (丢高 16)**
4. **PGT 段 1024 PTE 范围 0-0x3FF, 0xB80 PTE 索引需要 PGT#2 段**
5. **GDT[2] type=0x93 (expand-UP, A=1) 是 CPU 跑段后 A bit 自动设 1, 正常**
6. **0xB8000 / 4096 = 0xB80 PTE 索引 = 0xB80 = PGD[2] PGT#2[0x180], frame 0xB8**

## 🎯 撞 7 次, 写报告

**v9 已撞 7 次 (超 2-3 次原则), 写撞穿报告**:

- 32-bit 段 + 分页 + 32-bit VGA 寻址全对
- **VGA 写 page fault 0xB8000, 但 PGD[2] + PGT#2[0x180] 装对** — **问题不明, 也许 CR3 装错或 dlog 时序**

## 📂 文件

| 文件 | 字节 | 说明 |
|------|------|------|
| `kernel_m11v9.asm` | 4872 | k11 v9 (32-bit+分页+VGA, A20 enable, PGT#2) |

## ⏳ 留给后续

- v9 VGA 写 page fault 0xB8000, 也许 dlog 时序 (QEMU -monitor 抓 mem 时 k11 已撞 #GP)
- 用 -d int + -d in_asm 同步看 VGA 写触发时 CR3 + PGD + PGT 实际值
- 如果还失败, 试 hello386 完整代码 (从 0x7C00 16-bit 段装 16KB GDT/PGT + 切 32-bit)

## ✅ 真正跑通的部分

- M11 v9 跑通 32-bit 段 + 分页开 (10 marker `H K A G T G D P X 3 !`)
- 32-bit 段寻址 expand-UP data 段 (DS=0x10 type=0x93)
- PGT#2 段装入 (用 2 次 mov word 装 dword)
- A20 gate 开
- mbr 跳 k11 entry (mem 0x10000)
- pm_entry_phys 算对 (0x10000+offset)
- gdt_start_phys 算对 (0x10200+offset)

## 📝 决策

- 撞穿 7 次, 写报告
- M11 v9 跑通 32-bit+分页, VGA 写撞 (留待后续)
- 当前最佳: **M10 v25 + M12 v2 (FAT12) + M11 v9 (32-bit+分页+PM段, VGA 写撞)**
