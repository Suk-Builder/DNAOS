# DNAOS v3.5 M11 v11 — 撕! (撞 3 次退)

**日期**: 2026-06-13 20:25 UTC
**状态**: ⏳ 撞 3 次退, 跑通 8 marker `H K A G D P X 3 !`, VGA 写 #PF 不明

## 🎯 跑通部分 (v11 跑 8 marker)

```
H K A G D P X 3 !
```

| marker | 意义 | 状态 |
|--------|------|------|
| H | mbr 装 head 1 OK | ✓ |
| K | kernel 启动 | ✓ |
| A | A20 gate 开 | ✓ |
| G | PGD 装好 (PGD[0]=PGT#0) | ✓ |
| D | GDT desc + lgdt + IDT desc + lidt | ✓ |
| P | CR0.PE=1 | ✓ |
| X | 32-bit 段 + 栈 | ✓ |
| 3 | CR3 = 0x11000 | ✓ |
| ! | PG=1, 分页开 | ✓ |
| V | VGA 写 0xB8000 | ⏳ #PF |

## 🛑 撞 3 次 (撕)

### 撞 1: 16-bit 段 `mov bx, 0x180` 后, 装 GDT 段 `mov dword [bx+8]` 用 ds=0 (默认段)
- **真根因**: k11 entry 后 `xor ax, ax; mov ds, ax` (ds=0), 装 GDT 段寻址 [ds:bx+8] = mem 0x0+0x188 = 0x188 (IVT 区, 错)
- **修法**: 装 GDT 段前 `mov ax, 0x1020; mov ds, ax` (v9 已知撞过, ds=0x1020 段 base 0x10200)

### 撞 2: 0xB8000 PTE 索引算错 (从 0xB80 改成 0x380)
- **真根因**: 0xB8000 PTE 索引 = (0xB8000 >> 12) & 0x3FF = 0xB80 & 0x3FF = 0x380 (低 10 bit), 不是 0xB80
- **之前 v9 算错**: 0x180 (以为是 PGT#2[0x180]), 实际 PTE 索引 0x380 在 PGT#0 范围
- **修法**: 装 PGT#0[0x380] = 0x000B8003 (frame 0xB8 = 0xB8000 物理)

### 撞 3: PGT#0[0x380] 装对 (mem 0x12E00 = 0x000B8003) 但 VGA 写还 #PF
- **真根因**: 不明
- **QEMU 抓 mem**:
  - PGD[0] @ 0x11000 = 0x00012023 ✓
  - PGT#0[0x10] @ 0x12040 = 0x00010023 ✓ (A=1 bit CPU 自动设)
  - PGT#0[0x380] @ 0x12E00 = 0x000B8003 ✓
- **dlog**: v=0e e=0002 (W/R=1) at IP=0x00010114, CR2=0xB8000
- **IP=0x10114** = 32-bit 段 `mov dword [0xB8000], 0x0F50` (VGA 写)
- **寻址**: PGD[0] = PGT#0, PGT#0[0x380] = 0x000B8003 → frame 0xB8 = 0xB8000 物理
- **但 #PF** — 也许 PTE A bit / D bit 装错? 也许 PTE PC 位影响?

## 📊 v11 实际跑通

- v10' 7 marker: H K A G D P X 3
- **v11 8 marker**: H K A G D P X 3 **!** (PG=1 装好, 多了 v10' 没出的 '!')
- **v11 没出 'V'** = VGA 写 #PF

## 📚 v10' + v11 撞穿教训

1. **0xB8000 PTE 索引 = 0x380 (低 10 bit, & 0x3FF)** — 不是 0xB80
2. **0xB8000 PGD 索引 = 0** (高 10 bit, 0xB8000 < 4MB) — 不是 0x2 (我之前 v9 算错)
3. **ds 段寻址必须 reset** (装 GDT 段前 `mov ax, 0x1020; mov ds, ax`)
4. **PTE A bit / D bit CPU 自动设** — 装 PTE 写后, 32-bit 段寻址后 PTE byte 0 = 0x23 (A=1, D=1) 不是 0x03

## 🎯 撕 v11, 留 v11'

- 撞 3 次 = 撕, 收手
- 明天写 v11' = **只装 PGD[0] = 0x00012003 (PGT#0 0x12000) + PGT#0[0x380] = 0x000B8003 (VGA) + 装 PGT#0[0x10] (k11 code)**
- 不分 PGT#1/PGT#2 (简单)
- v11' 极简验证 VGA 写

## 🛑 撞 3 次停手原则 (v10' 撞 3 次撕, v11 撞 3 次撕, 2 个 milestone 撕 2 个)

| 版本 | 撞 | 修 | 结果 |
|------|----|----|------|
| v10' | 1. ds=0 装 GDT 段错 → ds=0x1020 段; 2. gdt_desc 写死 0x0180 → %define 算 | 跑通 7 marker H K A G D P X 3 |
| v11 | 1. PGD 装 PGD[2] 但 PGT#2 段没装 → 改 PGD[0] 装 PGT#0[0x380]; 2. PTE 索引算错 0x180 vs 0x380; 3. PGT#0[0x380] 装对但 VGA 写 #PF | 跑通 8 marker + 1 (PG=1), VGA 写撞穿 |

## ⏸ 留给 v11'

- VGA 写 #PF 真根因 (也许 dlog 时序, 也许 PTE PC 位, 也许 QEMU 模拟 bug)
- 也许用 `mov word [0xB8000], 0x0F50` (不用 mov dword)
- 也许 PGT#0[0x380] 装用 `mov dword` (不用 2 次 mov word)

## ✅ v11 完成定义 (部分)

- [x] 32-bit 段跑通
- [x] 分页开
- [x] 跑通 8 marker
- [ ] VGA 写 0xB8000 — 撞 3 次撕, 留 v11'
