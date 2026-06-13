# DNAOS M11 撞错报告 (撞 2 次, 翻书退回)

**日期**: 2026-06-13 03:55 UTC
**状态**: ❌ 失败 — 退回 v25

## 撞穿的 bug (v19 笔记学的, 仍然撞穿)

1. **GDTR base = 物理 0x100D5** ✓ 修了 (加了 `+ 0x10000`)
2. **far jmp 0x08:0x60** → 32-bit 模式 EIP=0x60 但实际代码在物理 0x10060 — **32-bit 模式下 linear=0x60, 跳到低 64KB BIOS 区**
3. **跳过 CR0.PE=1 步骤** — 16-bit 实模式直接 far jmp 进 GDT code segment, **PE=0 跟 GDT 不一致 = #GP**

## 主题 #2 笔记明确写了 3 步 (我没做)

```
1. cli
2. lgdt [gdt_desc]
3. mov eax, cr0; or eax, 0x1; mov cr0, eax   ← PE=1, 关键!
4. jmp 0x08:pm_entry (32-bit 模式 far jmp)
5. 装所有段寄存器 (ds/es/ss/fs/gs = 0x10)
6. 设 CR3
7. 设 CR0.PG=1
```

**我跳过 step 3, 直接 far jmp** — 撞穿 2 次

## 修法 (知道怎么修, 暂不实施, 撞 2 次退回)

```nasm
mov eax, cr0
or al, 1            ; CR0.PE = 1 (进入保护模式)
mov cr0, eax
jmp 0x08:flush      ; far jmp flush pipeline
flush:
mov ax, 0x10
mov ds, ax
; ... 其他段
```

## 决定

- **M11 暂时不动** (撞 2 次翻书)
- **回到 v25 (M10 完成)**
- **下一步**: M12 FAT12 read (主题 #8 笔记详细, 1.44MB 软盘已经按 FAT12 格式做)
- **之后再回到 M11** (用 3 步切 32-bit + 装 PGD/PGT)

## 学到的

- **笔记 #2 写的 3 步切 32-bit 我跳了 step 1** — 笔记白看了
- **撞错原则**: 撞 2 次就翻书, 别再撞
- **v19 老 bug 我以为学过, 实际没真做** — 学 ≠ 做
