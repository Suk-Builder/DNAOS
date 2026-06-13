# DNAOS v3.5 M11 v3 (v6/v8) — 查了书+网搜, 撞 6 次

**日期**: 2026-06-13 16:00 UTC
**状态**: ⏳ 撞 6 次, 找到 2 真根因, PM 段还撞

## 🎯 跑通部分

v8 跑通 7 marker: `H K G T G D P` (跟 v6 一样)

| marker | 意义 | 状态 |
|--------|------|------|
| H | mbr head 1 OK | ✓ |
| K | kernel 启动 | ✓ |
| G | PGD 装好 | ✓ |
| T | PGT 装好 | ✓ |
| G | GDT 装好 | ✓ |
| D | GDT desc + lgdt + IDT desc + lidt 装好 | ✓ |
| P | CR0.PE=1 | ✓ |
| X | 32-bit 段跑通 | ⏳ (没跑) |

## 🛑 撞 6 次 (查了书+网搜学)

### 撞 1: NASM 16-bit 段 SIB bug
- NASM 16-bit 段 `mov byte [si+disp8], imm8` 编译 = SIB encoding (mod=01 rm=100)
- SIB 在 16-bit 段下 = [BP+DI+disp8] ≠ [SI+disp8]
- **修法**: 用 [bx+disp16] (mod=00 rm=111) 装 GDT 段

### 撞 2: GDT[2] type 0x92 vs 0x93
- expand-UP vs expand-DOWN data 段, 寻址算法不同
- v2 装 0x92 实际装 0x93 (SIB bug 副作用)
- **修法**: v6 用 [bx+disp16] 装, GDT[2] type 0x92 ✓

### 撞 3: mbr 跳错位置
- mbr 跳 0x1020:0x0000 (mem 0x10200) 但 k11 在 mem 0x10000 (差 0x200)
- **修法**: mbr 跳 0x1000:0x0000 (mem 0x10000) = k11 entry

### 撞 4: `mov ax, gdt_start_phys` 丢高 16-bit 🎯 真根因
- k11 v6 `mov ax, gdt_start_phys` 装 16-bit 0x0366, eax 高 16 = 0
- shr eax, 16 = 0, gdt_desc base = 0x00000366 (不是 0x00010366)
- lgdt 装 GDT register base = 0x00000366
- far jmp 跳 GDT[1] @ 0x0000036E (BIOS 区) = #GP error=0x0008
- **修法 (v8)**: 用 `mov eax, gdt_start_phys` 装 32-bit 0x00010366

### 撞 5: PM 段跑第一条指令死
- v8 跑 dlog 显示 CS=0x0008 32-bit 段, EIP=0x10373 (IDT BSS 段)
- 没 'X' 之后 marker (32-bit 段 + 分页 + VGA)
- **修法**: 排查 PM 段 mov ax, 0x10 / mov ds, ax / mov esp, 0x90000

### 撞 6: GDT 描述符 (BSS 段 0) 死循环
- IP=0x10373 = k11 IDT BSS 段 (全 0) = 跑 `add [bx+si], al` 死循环 = #GP
- 跟 v8 跑 hlt 之后行为一致 (也许 PM 段跑过 hlt 死 IP=0x10165, 但 dlog 抓的是 IDT BSS)

## 📊 v8 跑通部分

v8 跑 7 marker `H K G T G D P` (跟 v6 一样, 跟之前 v2/v3/v4/v5 一样)
v8 dlog 显示 GDT register 0x00010366 (修了 mov ax)
v8 dlog 显示 CS=0x0008 32-bit 段 (PE=1 + far jmp 跳 GDT[1] 成功)
但 PM 段没跑通 (没 'X' marker)

## 📊 SHA256

- k11v6.bin: `d174b82e...35a8cf` (旧)
- k11v8.bin: 待 commit
- img_v35.img: `76cbdcdf...f28dcb` (旧)

## 💡 真正查书+网搜学到 (重要!)

1. **NASM 16-bit 段 SIB encoding bug** (网搜 OSDev + MercuryOS):
   - `mov [si+disp8]` 编译 = SIB encoding, 16-bit 段下 ≠ [SI+disp8]
2. **GDT[2] type 0x92 expand-UP vs 0x93 expand-DOWN** (MercuryOS):
   - 寻址算法不同
3. **`mov ax, imm32` 丢高 16-bit** (QEMU dlog + GDB 调试):
   - 16-bit 段下 mov ax 装 16-bit, eax 高 16 不变
   - 装 gdt_desc base 必须用 `mov eax, imm32` 装 32-bit
4. **mbr 跳 k11 entry 必须用 mem 物理地址** (QEMU 调试):
   - mbr 跳 0x1000:0x0000 = mem 0x10000
5. **PM 段跑第一条指令要设 ds=0x10 + esp=0x90000** (MercuryOS):
   - 32-bit 段下 ds 必须设 GDT[2] (0x10)
   - 32-bit 段下 esp 必须设 (0x90000, 不用 BIOS 段 0x7C00)

## 🎯 撞 6 次, 写报告

**v8 已撞 6 次 (超 2-3 次原则), 写撞穿报告**:

- NASM 16-bit SIB bug 修 ✓
- GDT[2] type 0x92 修 ✓
- mbr 跳错位置修 ✓
- mov ax 丢高 16 修 ✓
- **PM 段跑第一条指令死** — 撞 6 次后写报告

## 📂 文件

| 文件 | 字节 | 说明 |
|------|------|------|
| `kernel_m11v6.asm` | 4530 | k11 v6 (mov ax 丢高 16, 修 SIB bug) |
| `kernel_m11v7.asm` | 3473 | k11 v7 (用 retf 跳 32-bit) |
| `kernel_m11v8.asm` | 3615 | k11 v8 (用 mov eax 装 32-bit base) |
| `kernel_m11v81.asm` | 3365 | k11 v8.1 (备援) |

## ⏳ 留给后续

- v8 PM 段跑第一条指令死 (mov ax, 0x10? mov ds, ax? mov esp, 0x90000?)
- dlog EIP=0x10373 (IDT BSS 段) 也许不是 PM 段跑, 是 BIOS 重启 cycle 抓的
- 用 GDB 远程调试 (-s 端口) 看到底 PM 段跑没跑

## ✅ 真正修了的部分

- M11 v3 部分跑通 (16-bit 段 PE=1 + 32-bit 段 + GDT/IDT 装对 + lgdt/lidt 装对)
- 之前 v2 撞穿 GDT[2] type 0x93 (expand-DOWN) 寻址错
- 之前 v2 撞穿 gdt_desc base 0x00000366 (丢高 16)
- 之前 mbr 跳错位置 0x1020 修 0x1000
- 32-bit 段切了 (CS=0x0008 dlog) 但 PM 段没跑通

## 📝 决策

- 撞穿 6 次, 写报告
- 留待后续: GDB 远程调试 + 单步 PM 段看第一条指令死的位置
- 之前撞穿: 报告写到 `dnaos_review/m11_paging_v3/CRASH_REPORT.md`
