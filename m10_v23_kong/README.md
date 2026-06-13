# M10 v23 - 16-bit BIOS 重写路线 (空鱼版)

**日期**: 2026-06-13 01:55 UTC
**作者**: AI assistant (白桦的命令: 全部重写)
**服务器**: 空鱼 (43.160.235.191, ubuntu)

## 🎯 背景

v21/v22 (16→32 切 + GDT/IDT/PIC) 在 AutoDL 跟空鱼都跑不通:
- AutoDL: GDTR bug 修了 → 跑通 v19/v20
- v21/v22: k32 起点算错, mbr 字节序错, 撞了 5-6 次

**白桦命令**: "实在不行, 全部重写得了"

**重写路线 (Orange's 16-bit BIOS)**:
- 不切 32-bit (无 GDT/IDT/PIC)
- 键盘用 BIOS INT 16h
- VGA 用 BIOS INT 10h
- 16-bit 实模式全程

## 🟢 结果

**跑通!** 串口输出 (3 秒 QEMU 测试):

```
\r\nDNAOS v3.4 MBR\r\n      (MBR 跑成功)
K                           (kernel 启动)
M                           (mode set)
P                           (polling 准备)
hello                       (按 h/e/l/l/o 全部 echo 成功)
```

26 字节干净输出, 3 秒内无重启循环。

## 📁 文件

| 文件 | 作用 |
|------|------|
| `mbr_v34.asm` | v3.4 验证的 MBR, BIOS INT 13h 读 128 扇区 (64KB) 到 0x10000 |
| `kernel_v23.asm` | 16-bit BIOS kernel, INT 10h splash + INT 16h 键盘, 256B |
| `test_v23_kb.py` | QEMU monitor Python 测试脚本 |

## 🔧 v23 kernel 256B 之内实现的功能

1. **串口** — 直接 `out 0x3F8, al` (LSR poll)
2. **VGA splash** — 4 行 (banner / info / chain / prompt), BIOS INT 10h 0Ah (写字符) + 02h (设光标) + 03h (读光标)
3. **键盘 polling** — BIOS INT 16h 01h (查有无) + 00h (读 ASCII)
4. **echo** — 按键 → 串口 + VGA
5. **光标自动前进** — 读光标位置, col+1, 写回

## 📊 跟 v22 对比

| 项 | v22 (16→32 切) | v23 (16-bit BIOS) |
|----|----------------|---------------------|
| GDT | 24 字节, GDTR | 无 |
| IDT | 2048 字节, PIC init | 无 |
| k16 | 256B (切 32-bit) | 0 (无切换) |
| k32 | 256-1024B | 0 (全程 16-bit) |
| kernel 总量 | 512-1280B | **256B** |
| 键盘 | PS/2 0x64/0x60 轮询 | BIOS INT 16h |
| VGA | 直接写 0xB8000 | BIOS INT 10h |
| 跑通率 | 0/5 (撞 5-6 次) | **3/3** |

## 🟢 状态

**M10 = 16-bit BIOS 路线完成**。

下一步: 升级到 v24 (把 4 行 splash 加上输入回显 + 简单命令如 `help` / `ver` / `clear`)
