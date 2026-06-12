# DNAOS 操作系统学习计划 (2026-06-12)

按白桦指定的 4 阶段路线, 从零开始补 OS 基础。

## 📚 资源状况

| 书 | 来源 | 状态 |
|---|------|------|
| **OSTEP** (Operating Systems: Three Easy Pieces) | `/workspace/books/ostep.pdf` 5.1MB, 687 页 | ✅ 拿到 |
| **CSAPP** (Computer Systems: A Programmer's Perspective, 3rd) | `/workspace/books/csapp.pdf` 1.3MB | ✅ 拿到 |
| **Orange's 一个操作系统的实现** | PDF 下不到, 用 Linux 0.01 源码 + 博客笔记代替 | ⚠️ 替代方案 |
| **Linux 0.01 源码** | `/workspace/linux-0.01/` (kalamangga fork) | ✅ 已下 |

## 📋 4 阶段学习路线

### 阶段 1: OSTEP 关键章节 (估 1-2 周)
**目标**: 把 OS 的核心概念吃透
- 第 2 章: 进程
- 第 4 章: 调度
- 第 13-15 章: 内存虚拟化 (页表, TLB, 段)
- 第 21-23 章: 同步/互斥
- 第 37-41 章: 文件系统 + 日志

### 阶段 2: CSAPP 关键章节 (估 3-4 周)
**目标**: 把底层原理搞透
- 第 3 章: 机器级程序 (x86-64 汇编)
- 第 6 章: 存储器层次 (缓存)
- 第 9 章: 虚拟内存 ⭐
- 第 10 章: 系统级 I/O
- 第 11 章: 网络编程
- 第 12 章: 并发编程

### 阶段 3: Orange's (用源码代替, 估 1-2 周)
读 `/workspace/linux-0.01/` + whirlys/ORANGE_OS 仓库, 对照笔记:
- 第 1 章: MBR (用 mbr_retry.bin 对照)
- 第 2 章: 保护模式 (用 kernel_v19.asm 对照)
- 第 3 章: GDT/IDT/PIC (用 entry_32_v21.asm 对照)
- 第 4 章: 进程 (M13 准备)
- 第 5 章: 内存管理 (M12 准备)
- 第 6 章: 文件系统 (M14 准备)

### 阶段 4: Linux 0.01 对照 (估 1 周)
把所有 DNAOS M8-M10 代码跟 Linus 0.01 的 boot.s / head.s / keyboard.s 一一对应, 写"我们漏做的事"清单。

## 🎯 立即开始

### 第 1 周计划
- **周一**: OSTEP 第 2 章 (进程) + 写中文摘要
- **周二**: OSTEP 第 4 章 (调度) + 写中文摘要
- **周三**: OSTEP 第 13-15 章 (内存虚拟化) + 写中文摘要
- **周四**: OSTEP 第 21-23 章 (同步) + 写中文摘要
- **周五**: OSTEP 第 37-41 章 (文件系统) + 写中文摘要
- **周末**: 写 "阶段 1 总结" 笔记

### 学习方法 (跟白桦约好)
1. 每读完一节, 给 100-200 字中文摘要
2. 摘要格式: "这节讲的 3 件事 + DNAOS 哪个 milestone 相关"
3. 每章结束写一份"这章学到的 3 件事 + DNAOS 怎么用"笔记
4. 周末整理一份"阶段 X 知识地图" 写到 DNAOS 仓库

## 📝 笔记文件位置
- `/workspace/dnaos_review/STUDY_NOTES/` 下分阶段、分章节存
- 例: `STUDY_NOTES/ostep_ch2_进程.md`

## 🚫 暂停 DNAOS 编码
- M10 (键盘+shell) 暂停到阶段 1+2 完成
- 当前 /workspace/dnaos_review/os/ 保持 v20 (M9) 不动
- 不再盲撞代码问题, 全部查资料再动手

## ⏱️ 时间线
- 阶段 1 (OSTEP): 1-2 周
- 阶段 2 (CSAPP): 3-4 周
- 阶段 3 (Orange's): 1-2 周
- 阶段 4 (Linux 0.01 对照): 1 周
- **总计: 6-9 周补完基础**
- 然后 DNAOS M10+ 会顺很多
