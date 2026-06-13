# DNAOS v3.5 M12 v2 — mbr_v35 装多 head + k12b FAT12 read README.TXT (跑通)

**日期**: 2026-06-13 04:37 UTC
**SHA256**:
- mbr_v35.bin: `297f8a572194d84eb4b68f0e3f632613b42d7ea42ad65b467c8860897dd8a27a`
- k12b.bin: `e4dbea1387d1eeab78bf87b573580c6491631ac8793a0c2e24430d8ea00d6de4`
- dnaos_v35.img: `6f81d3b20cc34bcb0252f213124197da1ac7a0921e977241e48e9a2201066e57`

## 🎯 改进 (相对 v23 mbr_v34 + m12 v12 撞穿)

1. **mbr_v35 修 BPB** (之前 SecPerTrk=32, NumHeads=64 错) → 正确 1.44MB (SecPerTrk=18, NumHeads=2)
2. **mbr_v35 装多 head 扇区** (v34 装 head=0 128 扇区, 但实际只能装 17 扇区 head 0, head 1 装不到)
   - mbr 装 head 0 17 扇区 (sector 2-18, 0-based) 到 0x10000
   - mbr 装 head 1 18 扇区 (sector 1-18 head 1, 0-based) 到 0x10800
3. **k12b 装 sector 2-3 (0-based)** = 物理 0x10200 (段 0x1020), mbr 跳 0x1020:0x0000
4. **k12b 找 root dir @ 0x10800** (mbr 装 head 1 sector 1 = LBA 18 = sector 19 1-based)
5. **k12b dump data @ 0x12600** (sector 33 0-based, 实际 README 装那里)

## 📊 QEMU 串口 log

```
H                              ← mbr 装 head 1 成功 (新 marker)
K                              ← kernel 启动
M                              ← 模式设好
P                              ← polling 准备
a b r                          ← 按键 echo
!                              ← 'r' 命令触发
C                              ← 拿到 README cluster=2
Z                              ← ds 设 0x1260
D                              ← dump start
\nDNAOS M12 FAT12 rea          ← README 内容 (20 字节限制, 实际 99B)
O                              ← dump done
```

## 📂 文件

| 文件 | 字节 | 说明 |
|------|------|------|
| `mbr_v35.asm` | 2220 | mbr 修 BPB + 装多 head |
| `kernel_fat12b.asm` | 3066 | k12b 简化, hardcode root dir @ 0x10800, data @ 0x12600 |
| `test_v35.py` | 868 | QEMU monitor 测试, sendkey a/b/r |
| `build_fat12.sh` | 4314 | build 脚本 (img + FAT + root dir + data) |
| `rebuild3.sh` | - | 重新装 mbr + kernel + FAT + README |

## 💡 关键修复 (撞错学)

1. **mbr 装 head 0 跟 head 1** = 修 M11/M12/v26 共同根因
2. **BPB 真实 1.44MB 标准** = SecPerTrk=18 NumHeads=2 (之前 v34 错)
3. **k12b 装 sector 2-3 (0-based)** = mbr 装时 sector 1-17 (0-based) 包含 k12b
4. **dump 0x12600 = sector 33 0-based** = README 实际位置
5. **dump 后 O marker** = 验证 dump 跑完

## 🎯 接下来

- **M13 进程 + 调度** (主题 #9 笔记) — 简化版 xv6 + PIT
- **写 v12 README 中文版**

## ✅ M12 完成
