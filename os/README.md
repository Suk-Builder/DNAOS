# DNAOS - Real Operating System

**和Windows同级的操作系统。不是套壳，不是模拟器，从BIOS直接启动。**

## 架构

```
BIOS/UEFI
  └─> GRUB (引导加载器)
       └─> boot.S (32位 → 64位切换)
            ├─> 页表设置 (4GB identity map)
            ├─> GDT加载 (64位段描述符)
            ├─> 长模式跳转
            └─> kernel_main() (C)
                 ├─> IDT (中断描述符表)
                 ├─> PS/2键盘驱动
                 ├─> 帧缓冲区控制台 (1280x720)
                 ├─> ATCG四进制ALU (内核级)
                 ├─> ATP代谢引擎 (内核级)
                 └─> DNAsm Shell
```

## 和之前版本的区别

| | tkinter版本 | 这个版本 |
|---|---|---|
| 启动方式 | python3 xxx.py | BIOS → GRUB → 内核 |
| 依赖 | Python, tkinter, Linux | 无（裸机） |
| 内核 | 无（跑在Linux上） | 自己的内核 |
| 驱动 | 用Linux的 | 自己写（PS/2, FB） |
| 内存管理 | Python GC | 自己的页表 |
| 中断 | 无 | IDT + IRQ |
| 显示 | tkinter窗口 | 直接写帧缓冲区 |
| 键盘 | tkinter事件 | PS/2中断处理 |
| 级别 | 应用程序 | **操作系统** |

## 快速开始

```bash
# 一键构建运行
chmod +x build_and_run.sh
./build_and_run.sh

# 或手动
make iso          # 构建ISO
make run          # QEMU测试
make usb DEVICE=/dev/sdX  # 写入USB
```

## 在真机上运行

1. `make iso` 生成 dnaos.iso
2. 用dd写入U盘：`sudo dd if=dnaos.iso of=/dev/sdX bs=4M`
3. 插U盘，开机进BIOS，选U盘启动
4. GRUB → DNAOS → 直接进桌面

## 内核功能

- ✅ Multiboot2启动（GRUB兼容）
- ✅ 32位→64位模式切换
- ✅ 页表设置（4GB映射）
- ✅ GDT/IDT
- ✅ PS/2键盘驱动
- ✅ 帧缓冲区控制台（1280x720x32bpp）
- ✅ 8x16位图字体
- ✅ ATCG四进制ALU（内核级）
- ✅ ATP代谢引擎
- ✅ DNAsm交互Shell
- ✅ DNA主题GUI（标题栏、窗口、任务栏、ATCG色条）
- 🚧 内存管理器
- 🚧 文件系统（ATCG-native VFS）
- 🚧 系统调用接口
- 🚧 多任务/进程
- 🚧 网络驱动

## 文件结构

```
os/
├── kernel/
│   ├── boot.S      # 启动代码（multiboot2 → 长模式）
│   ├── kernel.c    # 内核主程序
│   ├── font.S      # 8x16位图字体
│   └── linker.ld   # 链接脚本
├── Makefile        # 构建系统
├── build_and_run.sh # 一键构建运行
└── README.md       # 本文件
```
