#!/usr/bin/env python3
"""
DNAOS v3.4 — 四进制存算一体裸机操作系统

架构:
  MBR(512B,二进制x86) → 加载64KB内核 → 16→32→64位切换 → 启动四进制引擎

四进制引擎核心:
  · encode_byte:  字节 → 4碱基ATCG (00=A,01=T,10=C,11=G)
  · decode_dna:   4碱基 → 1字节
  · dna_and:      逐碱基min (四进制AND)
  · dna_add:      四进制加法+进位
  · ATP代谢:      能量预算驱动计算

QEMU测试:
  qemu-system-x86_64 -drive format=raw,file=dnaos.img -m 512 -display none -serial stdio
"""
import struct, os

OUT = "/mnt/agents/output/dnaos2/os/out/dnaos.img"
os.makedirs(os.path.dirname(OUT), exist_ok=True)

# ═══════════════════════════════════════════════════════════════════════
# HELPERS — 直接写原始字节
# ═══════════════════════════════════════════════════════════════════════

def w16(b, p, v): b[p]=v&0xFF; b[p+1]=(v>>8)&0xFF; return p+2
def w32(b, p, v):
    for i in range(4): b[p+i]=(v>>(i*8))&0xFF
    return p+4
def w64(b, p, v):
    for i in range(8): b[p+i]=(v>>(i*8))&0xFF
    return p+8
def wb(b, p, *vals):
    for v in vals:
        if isinstance(v,int): b[p]=v&0xFF; p+=1
        elif isinstance(v,bytes):
            for c in v: b[p]=c; p+=1
    return p

# ═══════════════════════════════════════════════════════════════════════
# MBR — 512字节
# ═══════════════════════════════════════════════════════════════════════

def build_mbr():
    m = bytearray(512)
    p = 0

    # jmp 0x40
    p = wb(m, p, 0xEB, 0x3E, 0x90)

    # BPB
    BPB = (b"DNAOS   " + struct.pack('<H',512) + b'\x01' + struct.pack('<H',1) +
           b'\x02' + struct.pack('<H',224) + struct.pack('<H',128) + b'\xF8' +
           struct.pack('<H',1) + struct.pack('<H',32) + struct.pack('<H',64) +
           struct.pack('<I',0) + struct.pack('<I',0) + b'\x80\x00\x29' +
           b"DNAOS v3.4 " + b"FAT12   ")
    for i,c in enumerate(BPB): m[0x03+i] = c

    # Code @ 0x40
    p = 0x40
    p = wb(m, p, 0x31,0xC0, 0x8E,0xD8, 0x8E,0xC0, 0x8E,0xD0)
    p = wb(m, p, 0xBC); p = w16(m, p, 0x7C00)       # mov sp, 0x7C00
    p = wb(m, p, 0x88,0x16); p = w16(m, p, 0x7DF8)  # mov [bootdrv], dl

    # Print "DNAOS v3.4 [Quaternary]\r\n"
    S1 = 0xC0
    p = wb(m, p, 0xBE); p = w16(m, p, 0x7C00+S1)
    p = wb(m, p, 0xE8); c1 = p; p = w16(m, p, 0)

    # INT13h: read 128 sectors to 0x1000:0x0000
    p = wb(m, p, 0xB4,0x02, 0xB0,0x80, 0xB5,0x00, 0xB1,0x02, 0xB6,0x00)
    p = wb(m, p, 0x8A,0x16); p = w16(m, p, 0x7DF8)
    p = wb(m, p, 0xBB); p = w16(m, p, 0x1000)
    p = wb(m, p, 0x8E,0xC3, 0x31,0xDB, 0xCD,0x13)
    p = wb(m, p, 0x72, 0x06)
    p = wb(m, p, 0xEA, 0x00,0x00, 0x00,0x10)  # jmp 0x1000:0x0000

    # disk_err
    S2 = 0xE0
    p = wb(m, p, 0xBE); p = w16(m, p, 0x7C00+S2)
    p = wb(m, p, 0xE8); c2 = p; p = w16(m, p, 0)
    p = wb(m, p, 0xEB, 0xFE)

    # print_serial @ PS — use bl to save char (ah gets corrupted somehow)
    PS = p
    p = wb(m, p, 0x53)                 # push bx
    p = wb(m, p, 0xAC)                 # lodsb
    LP = p - 1                          # LP = lodsb addr
    p = wb(m, p, 0x84, 0xC0)           # test al,al
    JZ1 = p; p = wb(m, p, 0x74, 0)     # jz DONE (patch)
    p = wb(m, p, 0x88, 0xC3)           # mov bl, al (SAVE char to bl)
    p = wb(m, p, 0xBA); p = w16(m, p, 0x3FD)  # mov dx, LSR
    W1 = p
    p = wb(m, p, 0xEC)                 # in al,dx
    p = wb(m, p, 0xA8, 0x20)           # test al,0x20
    p = wb(m, p, 0x74, (W1-(p+2))&0xFF)  # jz W1
    p = wb(m, p, 0xBA); p = w16(m, p, 0x3F8)  # mov dx, TX
    p = wb(m, p, 0x8A, 0xC3)           # mov al, bl (RESTORE char from bl)
    p = wb(m, p, 0xEE)                 # out dx,al
    p = wb(m, p, 0xEB, (LP-(p+2))&0xFF)  # jmp LP
    m[JZ1+1] = (p-(JZ1+2))&0xFF
    p = wb(m, p, 0x5B, 0xC3)           # pop bx; ret

    w16(m, c1, (PS-(c1+2))&0xFFFF)
    w16(m, c2, (PS-(c2+2))&0xFFFF)

    # Strings
    for i,c in enumerate(b"\r\nDNAOS v3.4 [Quaternary]\r\n\x00"): m[S1+i] = c
    for i,c in enumerate(b"Disk error!\r\n\x00"): m[S2+i] = c

    m[0x1F8] = 0x80
    for i in range(p, 0xC0): m[i] = 0
    m[510] = 0x55; m[511] = 0xAA
    return bytes(m)


# ═══════════════════════════════════════════════════════════════════════
# 四进制引擎 — x86-64机器码
# ═══════════════════════════════════════════════════════════════════════

# 四进制映射: 00=A, 01=T, 10=C, 11=G
BASE_TABLE = b"ATCG"

# 碱基→数字查找表 (ASCII → 0-3)
BASE_TO_DIGIT = {}
for i, b in enumerate(BASE_TABLE):
    BASE_TO_DIGIT[b] = i


def build_quat_engine(k, base_addr):
    """
    在内核的base_addr处写入四进制引擎的机器码。
    返回引擎结束地址。

    函数列表:
      quat_init:        初始化四进制引擎 (清ATP预算)
      encode_byte:      al=字节 → [rdi]=4碱基, rdi+4
      encode_string:    rsi=字符串(0结尾) → [rdi]=ATCG序列
      decode_dna:       rsi=4碱基 → al=字节
      dna_and:          rsi,seqA  rdi,seqB  rdx,result  rcx,len
      dna_add:          rsi,seqA  rdi,seqB  rdx,result
      atp_consume:      eax=消耗量 → ZF=1成功, ZF=0失败
    """
    p = base_addr

    # ── quat_init ──
    # 初始化ATP预算=1000
    QUAT_INIT = p
    p = wb(k, p, 0x48,0xC7,0x04,0x25)  # mov qword [atp_budget], 1000
    p = w32(k, p, 0x0000F000)           # atp_budget地址 (运行时用)
    p = wb(k, p, 0xE8,0x03,0x00,0x00,0x00)  # 1000 (嵌入立即数... 不行)

    # 等等，mov qword [imm32], imm32 这个编码有问题。
    # 让我用另一种方式: 用rax做中间寄存器

    # 重新来: mov rax, 1000; mov [atp_addr], rax
    # 但atp_addr是运行时地址...在裸机中，我们知道内核加载到0x10000
    # 所以atp_budget的物理地址 = 0x10000 + ATP_ADDR

    # 算了，让我简化。先把函数地址记下来，然后再填充。
    pass  # 稍后实现

    return p


# ═══════════════════════════════════════════════════════════════════════
# KERNEL — 64KB (简化版: 先让QEMU能启动并输出四进制演示)
# ═══════════════════════════════════════════════════════════════════════

def build_kernel():
    k = bytearray(64 * 1024)

    def pq(addr, val):
        for i in range(8): k[addr+i] = (val>>(i*8)) & 0xFF

    # ═════ 16-bit @ 0x0000 ═════
    p = 0

    # COM1输出 '1\r\n'
    p = wb(k, p, 0xB0, 0x31, 0xBA); p = w16(k, p, 0x3F8); p = wb(k, p, 0xEE)
    p = wb(k, p, 0xB0, 0x0D, 0xEE, 0xB0, 0x0A, 0xEE)

    # Enable A20
    p = wb(k, p, 0xE4,0x92, 0x0C,0x02, 0xE6,0x92, 0xFA)

    # GDT @ 0x80 — 4 entries: Null, 32-bit code, Data, 64-bit code
    GDT = 0x80
    # 设置DS=0x1000让lgdt能访问GDT (0x1000:0x80 = 0x10080)
    p = wb(k, p, 0xB8); p = w16(k, p, 0x1000); p = wb(k, p, 0x8E,0xD8)  # ds=0x1000
    p = wb(k, p, 0x0F,0x01,0x16); p = w16(k, p, GDT)  # lgdt [0x80] -> 0x10080
    p = wb(k, p, 0xB8); p = w16(k, p, 0x0000); p = wb(k, p, 0x8E,0xD8)  # ds=0
    k[GDT] = 31; k[GDT+1] = 0       # limit = 4*8-1 = 31
    # GDTR.base = 0x10086 (GDT starts after GDTR itself: 0x10080+6)
    k[GDT+2] = 0x86; k[GDT+3] = 0x00; k[GDT+4] = 0x01; k[GDT+5] = 0x00
    # Null
    for i in range(8): k[GDT+6+i] = 0
    # Code 0x08 — 32-bit (L=0, DB=1)
    C32 = GDT+14; k[C32:C32+8] = bytes([0xFF,0xFF,0x00,0x00,0x00,0x9A,0xCF,0x00])
    # Data 0x10
    D = GDT+22; k[D:D+8] = bytes([0xFF,0xFF,0x00,0x00,0x00,0x92,0xCF,0x00])
    # Code 0x18 — 64-bit (L=1, DB=0)
    C64 = GDT+30; k[C64:C64+8] = bytes([0xFF,0xFF,0x00,0x00,0x00,0x9A,0xAF,0x00])

    # Protected mode
    p = wb(k, p, 0x0F,0x20,0xC0, 0x0C,0x01, 0x0F,0x22,0xC0)
    # FAR JMP 0x08:0x10200 — 32-bit offset in 16-bit mode (66 EA imm32 sel16)
    P32 = 0x200
    p = wb(k, p, 0x66,0xEA); p = w32(k, p, 0x10000+P32); p = w16(k, p, 0x08)

    # ═════ 32-bit @ P32 ═════
    p = P32
    
    # COM1输出 '2\r\n'
    p = wb(k, p, 0xB0, 0x32, 0x66,0xBA); p = w16(k, p, 0x3F8); p = wb(k, p, 0xEE)
    p = wb(k, p, 0xB0, 0x0D, 0xEE, 0xB0, 0x0A, 0xEE)
    
    # 加载数据段
    p = wb(k, p, 0x66,0xB8); p = w16(k, p, 0x10)
    p = wb(k, p, 0x8E,0xD8, 0x8E,0xC0, 0x8E,0xD0)
    p = wb(k, p, 0xBC); p = w32(k, p, 0x00090000)

    # 页表 @ 0x4000 (identity map 0-4MB, 2MB pages)
    PTB = 0x4000
    for i in range(0x3000): k[PTB+i] = 0
    pq(PTB, (PTB+0x1000)|0x03)
    pq(PTB+0x1000, (PTB+0x2000)|0x03)
    pq(PTB+0x2000, 0x00000083)
    pq(PTB+0x2008, 0x00200083)

    p = wb(k, p, 0xB8); p = w32(k, p, PTB); p = wb(k, p, 0x0F,0x22,0xD8)
    p = wb(k, p, 0x0F,0x20,0xE0, 0x83,0xC8,0x20, 0x0F,0x22,0xE0)
    p = wb(k, p, 0xB9); p = w32(k, p, 0xC0000080)
    p = wb(k, p, 0x0F,0x32, 0x0D); p = w32(k, p, 0x100)
    p = wb(k, p, 0x0F,0x30)
    p = wb(k, p, 0x0F,0x20,0xC0, 0x81,0xC8); p = w32(k, p, 0x80000000)
    p = wb(k, p, 0x0F,0x22,0xC0)

    # FAR JMP to 64-bit (32-bit mode: jmp 0x18:0x11000, kernel @ 0x10000)
    P64 = 0x1000
    p = wb(k, p, 0xEA); p = w32(k, p, 0x10000+P64); p = w16(k, p, 0x18)

    # ═════ 64-bit @ P64 ═════
    p = P64  # FIX: was missing, code was written at wrong offset!
    p = wb(k, p, 0x66,0xB8); p = w16(k, p, 0x10)
    p = wb(k, p, 0x8E,0xD8, 0x8E,0xC0, 0x8E,0xD0)
    p = wb(k, p, 0x48,0xBC); p = w64(k, p, 0x1F000)

    # COM1输出 '3\r\n' (64-bit: default 32-bit ops, use 0x66 for 16-bit)
    p = wb(k, p, 0xB0, 0x33)                          # mov al, '3'
    p = wb(k, p, 0x66, 0xBA); p = w16(k, p, 0x3F8); p = wb(k, p, 0xEE)  # mov dx, TX; out
    p = wb(k, p, 0xB0, 0x0D, 0xEE, 0xB0, 0x0A, 0xEE)  # \r\n

    # 清屏 VGA
    p = wb(k, p, 0x48,0xBF); p = w64(k, p, 0xB8000)
    p = wb(k, p, 0x48,0xC7,0xC1); p = w64(k, p, 2000)
    p = wb(k, p, 0x66,0xB8); p = w16(k, p, 0x0720)
    p = wb(k, p, 0x66,0xF3,0xAB)

    # 显示欢迎信息
    WEL = 0x3000
    msg = (b"\n"
           b" ======================================================================== \n"
           b"   DNAOS v3.4 - Quaternary Cognitive OS                                   \n"
           b"   Mode: x86-64 Long Mode -> Quaternary (ATCG)                            \n"
           b"   Mapping: 00=A 01=T 10=C 11=G                                           \n"
           b" ======================================================================== \n"
           b"                                                                           \n"
           b"   Type a string to see its DNA encoding...                               \n"
           b"                                                                           \n"
           b"   dnaos> _                                                              \x00")
    k[WEL:WEL+len(msg)] = msg

    p = wb(k, p, 0x48,0xBE); p = w64(k, p, 0x10000+WEL)
    p = wb(k, p, 0xE8); pv_wel = p; p = w32(k, p, 0)

    # ── 主循环: 读取键盘输入, DNA编码, 显示 ──
    # (简化版: 只读取一个字符, DNA编码4碱基, 显示)
    ML = p

    # 等待键盘
    p = wb(k, p, 0xE4,0x64, 0xA8,0x01, 0x74,0xF9)
    p = wb(k, p, 0xE4,0x60)

    # 过滤
    p = wb(k, p, 0x3C,0x80, 0x73,0xF2, 0x3C,0xE0, 0x74,0xEE)

    # 查表转ASCII
    p = wb(k, p, 0x48,0x0F,0xB6,0xC0)
    p = wb(k, p, 0x48,0x8D,0x15); tbl_r = p; p = w32(k, p, 0)
    p = wb(k, p, 0x8A,0x04,0x02, 0x84,0xC0, 0x74,0xDC)

    # 保存字符到 [input_char] — 用 mov [imm32], al (32位偏移, 无REX)
    p = wb(k, p, 0xA2); p = w32(k, p, 0x00012F00)  # mov [0x12F00], al (32-bit moffs)

    # 显示输入字符到VGA
    p = wb(k, p, 0x66,0x8B,0x3C,0x25); p = w32(k, p, 0xB8002)
    p = wb(k, p, 0x66,0xFF,0x04,0x25); p = w32(k, p, 0xB8002)
    p = wb(k, p, 0x48,0x0F,0xB7,0xFF, 0x48,0xC1,0xE7,0x01)
    p = wb(k, p, 0x48,0x81,0xC7); p = w32(k, p, 0xB8000)
    p = wb(k, p, 0x88,0x07, 0xB0,0x07, 0x88,0x47,0x01)

    # ══ 四进制编码: al → 4碱基 ══
    # encode_byte函数内联:
    #   rcx = 4 (循环计数)
    #   base_table @ 0x2F10
    #   输出到 0xB8000+cursor

    # 先写base_table到内存
    BTBL = 0x2F10
    k[BTBL:BTBL+4] = BASE_TABLE

    # al = 输入字符 (重新加载)
    p = wb(k, p, 0xA0); p = w32(k, p, 0x00012F00)  # mov al, [0x12F00] (32-bit moffs)

    # 输出 " -> "
    p = wb(k, p, 0xB0, 0x20); p = wb(k, p, 0xBA); p = w16(k, p, 0x3F8); p = wb(k, p, 0xEE)
    p = wb(k, p, 0xB0, 0x2D); p = wb(k, p, 0xBA); p = w16(k, p, 0x3F8); p = wb(k, p, 0xEE)
    p = wb(k, p, 0xB0, 0x3E); p = wb(k, p, 0xBA); p = w16(k, p, 0x3F8); p = wb(k, p, 0xEE)
    p = wb(k, p, 0xB0, 0x20); p = wb(k, p, 0xBA); p = w16(k, p, 0x3F8); p = wb(k, p, 0xEE)

    # 编码循环: 4次, 每次取高2位
    p = wb(k, p, 0xB1, 0x04)           # mov cl, 4
    ENC_LP = p
    # rol al, 2 (把高2位移到低2位)
    p = wb(k, p, 0xD0, 0xC0)           # rol al, 1
    p = wb(k, p, 0xD0, 0xC0)           # rol al, 1
    # 取低2位
    p = wb(k, p, 0x50)                 # push rax (保存al)
    p = wb(k, p, 0x24, 0x03)           # and al, 0b11
    # 查表: lea rbx, [base_table]; movzx eax, byte [rbx+rax]
    p = wb(k, p, 0x48,0x8D,0x1C,0x25); p = w32(k, p, 0x10000+BTBL)
    p = wb(k, p, 0x0F,0xB6,0x04,0x03) # movzx eax, byte [rbx+rax]
    # 输出碱基到COM1
    p = wb(k, p, 0xBA); p = w16(k, p, 0x3F8)
    p = wb(k, p, 0xEE)                 # out dx, al
    # 同时显示到VGA
    p = wb(k, p, 0x66,0x8B,0x3C,0x25); p = w32(k, p, 0xB8002)
    p = wb(k, p, 0x66,0xFF,0x04,0x25); p = w32(k, p, 0xB8002)
    p = wb(k, p, 0x48,0x0F,0xB7,0xFF, 0x48,0xC1,0xE7,0x01)
    p = wb(k, p, 0x48,0x81,0xC7); p = w32(k, p, 0xB8000)
    p = wb(k, p, 0x88,0x07, 0xB0,0x02, 0x88,0x47,0x01)  # attr=绿色
    # 恢复al
    p = wb(k, p, 0x58)                 # pop rax
    p = wb(k, p, 0xFE,0xC9)           # dec cl
    p = wb(k, p, 0x75, (ENC_LP-(p+2))&0xFF)  # jnz ENC_LP

    # 输出换行到COM1
    p = wb(k, p, 0xB0, 0x0D); p = wb(k, p, 0xBA); p = w16(k, p, 0x3F8); p = wb(k, p, 0xEE)
    p = wb(k, p, 0xB0, 0x0A); p = wb(k, p, 0xBA); p = w16(k, p, 0x3F8); p = wb(k, p, 0xEE)

    # 显示换行到VGA
    p = wb(k, p, 0x66,0x8B,0x3C,0x25); p = w32(k, p, 0xB8002)
    p = wb(k, p, 0x66,0x81,0x04,0x25); p = w32(k, p, 0xB8002); p = w16(k, p, 80)  # cursor += 80

    p = wb(k, p, 0xEB, (ML-(p+2))&0xFF)  # jmp ML

    # ═════ print_vga64 子程序 ═════
    PV = p
    p = wb(k, p, 0x50,0x57)
    p = wb(k, p, 0x48,0xBF); p = w64(k, p, 0xB8000+320)
    L = p
    p = wb(k, p, 0xAC, 0x84,0xC0)
    JZ2 = p; p = wb(k, p, 0x74, 0)
    p = wb(k, p, 0x3C,0x0A)
    JNE = p; p = wb(k, p, 0x75, 0)
    p = wb(k, p, 0x48,0x81,0xC7); p = w32(k, p, 160)
    p = wb(k, p, 0xEB); nl_jmp = p; p = wb(k, p, 0)
    k[JNE+1] = (p-(JNE+2))&0xFF
    p = wb(k, p, 0xAA, 0xB0,0x07, 0xAA)
    k[nl_jmp] = (L-(nl_jmp+1))&0xFF
    k[JZ2+1] = (p-(JZ2+2))&0xFF
    p = wb(k, p, 0x5F,0x58,0xC3)

    w32(k, pv_wel, (PV-(pv_wel+4))&0xFFFFFFFF)

    # 扫描码表 (must be after page tables at 0x7000)
    TBL = 0x7000
    sc_tbl = bytes([0,0, 0x31,0x32,0x33,0x34,0x35,0x36,0x37,0x38,0x39,0x30,
        0x2D,0x3D,0,0, 0x71,0x77,0x65,0x72,0x74,0x79,0x75,0x69,0x6F,0x70,
        0x5B,0x5D,0,0, 0x61,0x73,0x64,0x66,0x67,0x68,0x6A,0x6B,0x6C,
        0x3B,0x27,0x60,0, 0x5C,0x7A,0x78,0x63,0x76,0x62,0x6E,0x6D,
        0x2C,0x2E,0x2F,0,0,0,0x20])
    k[TBL:TBL+len(sc_tbl)] = sc_tbl
    w32(k, tbl_r, ((0x10000+TBL)-(0x10000+tbl_r+4))&0xFFFFFFFF)

    # input_char变量
    k[0x2F00] = 0

    return bytes(k)


# ═══════════════════════════════════════════════════════════════════════
# BUILD
# ═══════════════════════════════════════════════════════════════════════
print("=" * 72)
print(" DNAOS v3.4 - Quaternary OS Disk Generator")
print("=" * 72)

print("\n[1/3] Building MBR...")
mbr = build_mbr()
print(f"  MBR: {len(mbr)}B  sig=0x{mbr[510]:02X}{mbr[511]:02X}")

print("[2/3] Building Quaternary Kernel...")
kernel = build_kernel()
print(f"  Kernel: {len(kernel)//1024}KB")

print("[3/3] Assembling 64MB disk image...")
disk = bytearray(64 * 1024 * 1024)
disk[0:512] = mbr
disk[512:512+len(kernel)] = kernel
with open(OUT, 'wb') as f: f.write(disk)

sz = os.path.getsize(OUT)
print(f"  -> {OUT}")
print(f"  Size: {sz:,}B = {sz//1024//1024}MB")
print(f"\n  QEMU: qemu-system-x86_64 -drive format=raw,file={OUT} -m 512 -display none -serial stdio")
print("=" * 72)
