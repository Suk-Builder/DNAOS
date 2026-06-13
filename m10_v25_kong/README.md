# DNAOS v3.5 M10 v25 — 16-bit BIOS + jmp 分派 (重写 v24 撞穿)

**日期**: 2026-06-13 03:42 UTC
**v23 → v24 撞错 (commit 7318a59) → v25 跑通 (本次)**
**路线**: 16-bit BIOS 重写, 不调 sub-routine 分派命令, 避 v24 撞穿的 call/ret 栈深度

## 🎯 改动 (相对 v23)

| 项 | v23 | v25 |
|----|-----|-----|
| 命令 | 0 (只 echo) | 1 (`h` = help) |
| 命令分派 | 无 | **jmp-only inline** (主循环内 `cmp/jne`, 不调 sub) |
| Enter 响应 | 无 | `#` (CR) |
| Kernel 大小 | 256B | 256B (跟 v23 一样!) |

## 🟢 关键策略 (从 v24 撞错学)

- **v24 撞穿**: sub-routine `call pc` (print char) 之后, 栈不平衡, QEMU 跑不出 log
- **v25 修法**: **不在命令分派里 call sub-routine**, 把所有 "h" 命令响应 inline 写在主循环
  - `cmp al, 'h' / jne .no_help / 串口输出 'h=' / call puts_bios / jmp .poll`
  - `puts_bios` 只在 h 响应里调一次, 简单
  - **避免 call/ret 深度 = 不会栈不平衡**

## 📊 QEMU 串口 log (`sv25.log` 448 字节)

```
K              ← kernel 启动
M              ← 模式设好 (AX=0x0003 80x25)
P              ← polling 准备
h=             ← 按 'h' = help 命令响应
[04;03Ha       ← 按 'a' = 普通字符 echo
[04;04Hb       ← 按 'b' = 普通字符 echo
[04;05Hx       ← 按 'x' = 普通字符 echo
[04;06H
#              ← 按 Enter (CR) 响应
```

(中间 `[04;0xH` 是 ANSI 序列, SeaBIOS/VGA 正常输出, 不用管)

## 📂 文件

| 文件 | 字节 | 用途 |
|------|------|------|
| `mbr_v34.asm` | 1330 | MBR, BIOS INT 13h 读 128 扇区到 0x1000:0x0000 |
| `kernel_v25.asm` | 2595 | 16-bit BIOS kernel, 256B 编译后 |
| `test_v25.py` | 1585 | QEMU monitor `sendkey` 测试 |
| `build_v25_kong.sh` | 604 | 空鱼 build 脚本 |
| `sv25.log` | 448 | QEMU 串口 log (raw) |

## 🔗 SHA256

- v25 image `dnaos_v25.img`: `c31957348ff214612a86a12b6bf0af834f75a8b2db0b91c6f91b2640d280cca4`
- v25 kernel `k25.bin`: `45a672c5d3355151ca6ad9cdccbc000f78a7e97e52d7202059d8db562050bbed`

## 🚀 跑通的事

- ✅ MBR 装 sector 0 (512B, 含 BPB)
- ✅ Kernel 装 sector 1 (256B, 16-bit BIOS)
- ✅ 16-bit BIOS 切视频模式 (AX=0x0003)
- ✅ 4 行 splash (banner / info / chain / prompt)
- ✅ 串口 echo (每个按键 → 0x3F8 输出)
- ✅ `h` 命令响应 (help 字符串)
- ✅ Enter 响应 (`#` 字符)
- ✅ 普通字符 (a/b/x) VGA 显示 + 串口 echo

## 🎯 接下来 (M10 v26 可选)

- v26 = 加 2 个命令 (`v` = ver, `c` = clear)
- 加 1 个 command buffer (8 字符)
- 加 1 个 strcmp (避免字符串命令分派靠 `cmp al, 'h'` 单字符)

## 💡 研读笔记关联

- 主题 #2 (GDT/IDT): v25 不切 32-bit, 不用 GDT, 跟 v23 一样 16-bit 全程
- 主题 #4 (PIC): v25 不用 PIC, 走 BIOS INT 16h 轮询
- 主题 #5 (PS/2 键盘): v25 = BIOS INT 16h 读键, BIOS 已处理 PS/2
- 主题 #6 (VGA): v25 = BIOS INT 10h 0Ah 写字符 + 02h 设光标
- 主题 #7 (Shell): v25 简化版, jmp-only dispatch, 1 命令

## 🟢 v25 = M10 完成 (16-bit BIOS 路线, 1 个命令)

**撞错 5-6 次学的**: call/ret 栈 = 复杂, 越简单越稳, 256B 能做啥就做啥
