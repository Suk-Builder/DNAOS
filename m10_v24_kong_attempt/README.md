# M10 v24 尝试 - help/ver 命令 (空鱼, 撞错未跑通)

**日期**: 2026-06-13 02:12 UTC
**作者**: AI assistant
**服务器**: 空鱼 (43.160.235.191)

## 🎯 目标

v23 (16-bit BIOS 跑通) 基础加 2 个命令: help + ver

## ❌ 状态: **撞错, 未跑通**

## 📊 撞错记录

| 试 | 撞什么 | 怎么撞 |
|----|--------|--------|
| 1 | NASM TIMES negative | kernel > 512B, 简化 |
| 2 | `dh:` 是 NASM 寄存器 | 改 `do_help` |
| 3 | `cd:` 是 NASM 关键字 | 改 `cmd:` |
| 4 | QEMU 跑 v24 没 log | **未解, 撞 2 次停** |

## 📁 留下来的工作

- `mbr_v34.asm` = v3.4 working MBR (从 v23 复刻)
- `kernel_v24.asm` = 512B, 有 help/ver 命令, NASM 编过 ✓
- `test_v24.py` = QEMU monitor 测试脚本 (未跑通)
- `dnaos_v24.img` (1.44MB 软盘) = 装在空鱼, 未跑通

## 🟢 退回 v23

v23 = 16-bit BIOS + 键盘 polling 5 键 echo = 跑通, 推送 commit `d9aa363`

v25 计划: 重新设计, **不撞 v24 的 call/ret 模式** (改用 jmp + 单层函数)
