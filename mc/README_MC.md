# DNAOS v3.3 - Machine Code DNA Encoder

## 概述

这是一个**纯机器码**实现的DNA编码器——不用任何高级语言编译器，不依赖GNU assembler，直接用x86-64十六进制字节构建完整的ELF64可执行文件。

**递砖机认知操作系统 · 纯机器码实现**

## 功能

1. 打印提示 `"Input text: "` 到stdout
2. 从stdin读取一行ASCII文本（最多256字节）
3. 将每个字符转换为8位二进制
4. 每2位映射为DNA碱基: `00->A, 01->T, 10->C, 11->G`
5. 输出完整的ATCG碱基序列
6. 打印换行
7. 退出

## 输出文件

| 文件 | 说明 |
|------|------|
| `dna_encoder.bin` | ELF64可执行文件（可直接运行）|
| `dna_encoder.asm` | NASM源文件（带完整十六进制注释）|
| `dna_encoder.hex` | 纯十六进制文本dump |

## 机器码统计

- **总机器码**: 1540 字节
- **代码段**: 243 字节 (15.8%)
- **数据段**: 1297 字节 (84.2%)
- **包含2个函数**: `_start` (主程序), `write_base` (查表写入)
- **使用12种不同的x86-64指令编码**

## 程序结构

```
0x400078  _start          程序入口
0x4000AF  main_loop       主处理循环
0x4000EE  next_char       跳到下一个字符
0x4000F4  write_base      查表写入碱基 (函数)
0x40105   done            输出结果并退出

0x4014A   prompt          "Input text: " (12字节)
0x40156   buf             输入缓冲区 (256字节)
0x40256   outbuf          输出缓冲区 (1024字节)
0x40656   table           "ATCG" 映射表 (4字节)
0x4065A   newline         "\n" (1字节)
```

## 指令编码表

| 地址 | 机器码 | 指令 | 说明 |
|------|--------|------|------|
| 0x400078 | 48 C7 C0 01 00 00 00 | mov rax, 1 | sys_write |
| 0x40007F | 48 C7 C7 01 00 00 00 | mov rdi, 1 | stdout |
| 0x400086 | 48 8D 35 DE 00 00 00 | lea rsi, [rip+0xDE] | prompt地址(RIP-relative) |
| 0x400094 | 0F 05 | syscall | Linux系统调用 |
| 0x400096 | 31 C0 | xor eax, eax | 清零rax (sys_read=0) |
| 0x4000BE | 0F 83 59 00 00 00 | jae 0x11D | 条件跳转rel32 |
| 0x4000D9 | E8 2B 00 00 00 | call 0x109 | 调用write_base |
| 0x40104 | E9 B2 FF FF FF | jmp 0xBB | 跳转main_loop |
| 0x4011C | C3 | ret | 函数返回 |

## 验证机器码

### 方法1: 用objdump反汇编

```bash
# 跳过ELF头(120字节)，直接反汇编代码
objdump -D -b binary -m i386:x86-64 -M intel dna_encoder.bin -e 120
```

**验证要点**:
- 每条指令的反汇编结果应与 `dna_encoder.asm` 中的注释一致
- RIP-relative偏移应指向正确的数据地址
- 调用/跳转目标地址应对应正确的标签

### 方法2: 用xxd查看十六进制

```bash
xxd -g 1 dna_encoder.bin | head -20
```

### 方法3: 用file命令验证ELF格式

```bash
file dna_encoder.bin
# 应输出: ELF 64-bit LSB executable, x86-64, statically linked
```

## DNA编码示例

| 输入字符 | ASCII(十六进制) | 二进制 | DNA输出 |
|----------|----------------|--------|---------|
| 'A' | 0x41 | 0100 0001 | TAAT |
| 'T' | 0x54 | 0101 0100 | TTTA |
| 'C' | 0x43 | 0100 0011 | TAAG |
| 'G' | 0x47 | 0100 0111 | TATG |

例如输入 `"AT"` 输出 `TAATTTTA` (8个碱基)。

## 技术细节

### RIP-Relative寻址

所有数据访问使用RIP-relative寻址（`[rip+offset]`），这是x86-64 PIC（位置无关代码）的标准方式：

```
lea rsi, [rip+0xDE]    ; RSI = 下条指令地址 + 0xDE
```

指令编码: `REX.W + 8D /r` 其中ModRM的rm=101表示RIP-relative。

### 系统调用约定

遵循Linux x86-64 syscall ABI:
- RAX = 系统调用号 (1=write, 0=read, 60=exit)
- RDI = 第1参数 (fd)
- RSI = 第2参数 (buffer)
- RDX = 第3参数 (count)
- 执行 `syscall` 指令触发

### 32位优化

多处使用32位指令代替64位（如 `xor eax,eax` 代替 `xor rax,rax`），因为:
- 32位操作码更短（节省2字节REX前缀）
- x86-64自动将32位结果零扩展到64位

## 纯机器码的意义

这个项目展示了:
1. **x86-64指令编码**: 理解REX前缀、ModRM、SIB字节
2. **ELF文件格式**: 手工构建可执行文件
3. **Linux系统调用**: 直接与内核交互
4. **RIP-relative寻址**: 位置无关的数据访问

## 引用

- Intel 64 and IA-32 Architectures Software Developer's Manual
- System V AMD64 ABI
- ELF-64 Object File Format
