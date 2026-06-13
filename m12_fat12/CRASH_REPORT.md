# DNAOS M12 FAT12 撞错报告 (撞 2 次, 翻书退回 v25)

**日期**: 2026-06-13 04:05 UTC
**状态**: ❌ 撞穿 — 退回 v25

## 撞穿的 bug (v23 老问题没解决)

1. **mbr INT 13h 装 sector 1+ head=0**: 1.44MB 软盘 head 0 跟 head 1 都有 18 sector, **mbr 装 head=0 装 sector 1-18 (跟 kernel + FAT #1 撞)**, head 1 sector 19+ (root dir) **没装到内存**
2. **sector 19+ root dir 内容在内存 0x12400 都是 0** — 跟我装 img 的内容不一致
3. **CHS 算错**: 没在 mbr 加 `inc dh` 切 head

## 真正修法 (知道怎么修, 暂不做)

- mbr 加 `mov dh, 0` 装 head 0 (sector 1-18), 装 18 扇区
- 然后 `mov dh, 1` 装 head 1 (sector 19-36), 装 18 扇区
- 总 36 扇区 = 18KB kernel + 18KB FAT/root
- mbr 装 0x10000+ 装 head 0 sector 1-18 = kernel + FAT #1
- mbr 装 0x10000+0x2400+ 装 head 1 sector 19-36 = root dir + (start of) data

## 决定

- **M12 暂时不动** (撞 2 次翻书)
- **回 v25 (M10 完成)**
- **不再扩 v26, 不修 m11 paging, 不修 m12 fat12**
- **写撞错报告, 写日报, 跟用户报告总进度**

## 撞穿学的

- **撞错 5-6 次学的**: m8/m9 笔记的 GDT/PGD 修复只解决了 32-bit 切的问题, **MBR 装多 head 扇区的问题没解决** = 16-bit BIOS 路线只能装 head 0 = 18 扇区 = 9KB
- **要装 root dir (sector 19-32) 跟 data (sector 33+) 必须改 mbr 装多 head**
- **简化 1.44MB 软盘 = 80 cylinders, 2 heads, 18 sectors, 1 sector/cluster**
- **撞 2 次就翻书** ✓

## 当前状态

- ✅ M8 (32-bit PM boot) — 跑通 (v19, f380df8)
- ✅ M9 (VGA splash 32-bit) — 跑通 (v20, fc7f9ca)
- ✅ M10 (16-bit BIOS shell + 1 命令) — 跑通 (v23, v25, v26 撞 2 次退回)
- ⏳ M11 (32-bit + 分页) — 撞 2 次退回 (CR0.PE=1 步骤 + CHS head=1)
- ⏳ M12 (FAT12 read) — 撞 2 次退回 (CHS head=1)
- 🟢 **研读 10 主题笔记完成 (70KB)**
- 🟢 **撞错 8-10 次暴露基础不扎实, 撞错原则 = 撞 2-3 次就翻书**
