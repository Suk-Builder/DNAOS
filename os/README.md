# DNAOS - Real Operating System

**和Windows同级的操作系统。BIOS直接启动，没有Linux，没有Python。**

## 启动链

```
BIOS/UEFI
  └─> GRUB (引导加载器)
       └─> boot.S (32位保护模式 → 64位长模式)
            ├─> 页表 (4GB identity map, 2MB pages)
            ├─> GDT (5个描述符: null, kernel code/data, user code/data)
            ├─> IDT (256项: CPU异常 + IRQ + syscall)
            └─> kernel_main() (C)
                 ├─> PIC 重映射 (IRQ 32-47)
                 ├─> PIT 定时器 (100Hz, 10ms tick)
                 ├─> PS/2 键盘驱动 (IRQ1, scancode set 1)
                 ├─> PS/2 鼠标驱动 (IRQ12, 3-byte packet)
                 ├─> PCI 总线扫描 (找E1000网卡等)
                 ├─> E1000 网络驱动 (MMIO, RX/TX ring)
                 ├─> PMM 物理内存管理 (bitmap allocator)
                 ├─> VMM 虚拟内存管理 (4级页表)
                 ├─> VFS ATCG原生文件系统 (ramfs)
                 │    ├─ /genome/   系统配置
                 │    ├─ /ribosome/ 可执行程序
                 │    ├─ /membrane/ I/O设备
                 │    ├─ /nucleus/  内核数据
                 │    ├─ /atp/      能量记账
                 │    └─ /codon/    用户文件
                 ├─> 进程管理器 (64进程, 轮转调度)
                 ├─> 系统调用接口 (SYSCALL/SYSRET)
                 ├─> 窗口管理器 (软件渲染, 拖拽, Z序)
                 ├─> ATP代谢引擎 (每次操作消耗ATP)
                 └─> DNAsm Shell (四进制交互)
```

## 完整子系统

| 子系统 | 文件 | 功能 |
|--------|------|------|
| 启动 | `kernel/boot.S` | Multiboot2, 32→64位, GDT, IDT stubs, context switch, syscall entry |
| 内核 | `kernel/kernel.c` | 主程序, 帧缓冲, 键盘, PIT, DNAsm, GUI |
| 字体 | `kernel/font.S` | 8x16位图字体 (ASCII 32-127) |
| 链接 | `kernel/linker.ld` | 内存布局 (1MB加载) |
| 内存 | `kernel/mm/pmm.h` | 物理内存管理 (bitmap, 4KB页) |
| 内存 | `kernel/mm/vmm.h` | 虚拟内存管理 (4级页表, map/unmap) |
| 进程 | `kernel/proc/proc.h` | 进程管理 (64进程, 轮转调度, ATP per-process) |
| 文件 | `kernel/fs/vfs.h` | ATCG原生VFS (ramfs, open/close/read/write/mkdir/ls) |
| 系统调用 | `kernel/sys/syscall.h` | 22个syscall (read/write/open/close/exec/fork/atp/quat/fb) |
| 定时器 | `kernel/drivers/pit.h` | PIT 8254 (100Hz, sleep, beep) |
| 鼠标 | `kernel/drivers/mouse.h` | PS/2鼠标 (IRQ12, 3-byte packet) |
| PCI | `kernel/drivers/pci.h` | PCI总线扫描 (找E1000等设备) |
| 网络 | `kernel/drivers/e1000.h` | Intel E1000 (MMIO, RX/TX ring, MAC) |
| 窗口 | `kernel/gui/wm.h` | 窗口管理器 (拖拽, Z序, 任务栏, 开始菜单) |

## 快速开始

```bash
# 安装依赖
sudo apt install nasm gcc grub-pc-bin xorriso qemu-system-x86

# 构建
cd os
make iso

# QEMU测试
make run

# 真机 (写入U盘)
make usb DEVICE=/dev/sdX
```

## DNAsm命令

| 键 | 功能 |
|----|------|
| H | 帮助 |
| P | 打印寄存器 (ATCG格式) |
| C | AND (四进制min) |
| G | OR (四进制max) |
| N | NOT (互补) |
| + | ADD (带进位) |
| R | 重置寄存器 |
| S | 系统信息 |
| F | 文件系统 |
| M | 内存信息 |
| W | 窗口管理器桌面 |
| Q | 关机 |

## 系统调用

| 号 | 名称 | 功能 |
|----|------|------|
| 0x00 | read | 读文件 |
| 0x01 | write | 写文件 |
| 0x02 | open | 打开文件 |
| 0x03 | close | 关闭文件 |
| 0x07 | exec | 执行程序 |
| 0x08 | fork | 创建进程 |
| 0x09 | exit | 退出进程 |
| 0x0B | atp_query | 查询ATP |
| 0x0C | atp_consume | 消耗ATP |
| 0x0D | quat_and | 四进制AND |
| 0x0E | quat_or | 四进制OR |
| 0x0F | quat_not | 四进制NOT |
| 0x10 | quat_add | 四进制ADD |
| 0x11 | encode_atcg | 编码为ATCG |
| 0x12 | decode_atcg | 从ATCG解码 |
| 0x13 | fb_draw | 画像素 |
| 0x14 | fb_print | 打印文字 |
| 0x15 | wm_create | 创建窗口 |
| 0x16 | wm_destroy | 销毁窗口 |
| 0x17 | net_send | 发送网络包 |
| 0x18 | net_recv | 接收网络包 |

## 文件系统

```
/                    根目录
├── genome/          系统配置 (ATCG编码)
│   ├── boot.cfg     启动配置
│   └── display.cfg  显示配置
├── ribosome/        可执行程序
│   └── dnasm        DNAsm解释器
├── membrane/        I/O设备
│   ├── keyboard     键盘
│   ├── mouse        鼠标
│   ├── display      显示器
│   └── network      网卡
├── nucleus/         内核数据
│   ├── charter      宪章
│   └── sysinfo      系统信息
├── atp/             能量记账
│   └── budget       ATP预算
└── codon/           用户文件
    └── readme       说明
```
