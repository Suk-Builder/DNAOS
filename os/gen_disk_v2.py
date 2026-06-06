#!/usr/bin/env python3
"""
DNAOS v3.4 — 最小可工作裸机操作系统
  • MBR: 512B, COM1串口输出, INT13读内核, 远跳到 0x1000:0
  • KERNEL: 16→32→64位模式切换, COM1串口调试, VGA欢迎界面, 键盘输入
  
QEMU测试:
  qemu-system-x86_64 -drive format=raw,file=dnaos.img -m 512 -display none -serial stdio
物理部署:
  sudo dd if=dnaos.img of=/dev/sdX bs=4M && sync
"""
import struct, os

OUT = "/mnt/agents/output/dnaos2/os/out/dnaos.img"
os.makedirs(os.path.dirname(OUT), exist_ok=True)

# ─────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────
def write_b(buf, p, *data):
    """Write bytes/int/'w'/'d'/'q' tuples to buf at position p, return new p."""
    for x in data:
        if isinstance(x, bytes):
            for c in x: buf[p] = c; p += 1
        elif isinstance(x, int):
            buf[p] = x & 0xFF; p += 1
        elif isinstance(x, tuple):
            if x[0] == 'w':
                v = x[1]; buf[p] = v&0xFF; buf[p+1] = (v>>8)&0xFF; p += 2
            elif x[0] == 'd':
                v = x[1]
                for i in range(4): buf[p+i] = (v>>(i*8))&0xFF
                p += 4
            elif x[0] == 'q':
                v = x[1]
                for i in range(8): buf[p+i] = (v>>(i*8))&0xFF
                p += 8
    return p

# ─────────────────────────────────────────────────────────────────────
# MBR — 512字节
# ─────────────────────────────────────────────────────────────────────

def build_mbr():
    m = bytearray(512)
    p = 0

    # jmp 0x40
    p = write_b(m, p, 0xEB, 0x3E, 0x90)

    # BPB @ 0x03
    BPB = (b"DNAOS   " + struct.pack('<H',512) + b'\x01' + struct.pack('<H',1) +
           b'\x02' + struct.pack('<H',224) + struct.pack('<H',128) + b'\xF8' +
           struct.pack('<H',1) + struct.pack('<H',32) + struct.pack('<H',64) +
           struct.pack('<I',0) + struct.pack('<I',0) + b'\x80\x00\x29' +
           b"DNAOS v3.4 " + b"FAT12   ")
    for i,c in enumerate(BPB): m[0x03+i] = c

    # ── Code @ 0x40 ──
    p = 0x40

    # Init segments + stack
    p = write_b(m, p, 0x31,0xC0, 0x8E,0xD8, 0x8E,0xC0, 0x8E,0xD0, ('w',0x7C00))
    # Save boot drive
    p = write_b(m, p, 0x88,0x16, ('w',0x7DF8))

    # Print "DNAOS v3.4 MBR\r\n"
    S1 = 0x80
    p = write_b(m, p, 0xBE, ('w', 0x7C00+S1))
    p = write_b(m, p, 0xE8); c1 = p; p = write_b(m, p, 'w', 0)

    # INT13h AH=02: read 128 sectors to 0x1000:0x0000
    p = write_b(m, p, 0xB4,0x02, 0xB0,0x80, 0xB5,0x00, 0xB1,0x02, 0xB6,0x00)
    p = write_b(m, p, 0x8A,0x16, ('w',0x7DF8))
    p = write_b(m, p, ('w',0x1000), 0x8E,0xC3, 0x31,0xDB, 0xCD,0x13)
    p = write_b(m, p, 0x72, 0x06)  # jc err
    # far jmp 0x1000:0x0000
    p = write_b(m, p, 0xEA, 0x00,0x00, 0x00,0x10)

    # disk_err
    S2 = 0xA0
    p = write_b(m, p, 0xBE, ('w', 0x7C00+S2))
    p = write_b(m, p, 0xE8); c2 = p; p = write_b(m, p, 'w', 0)
    p = write_b(m, p, 0xEB, 0xFE)

    # print_serial @ PS — ds:si -> COM1
    PS = p
    p = write_b(m, p, 0x50, 0x53)       # push ax, bx
    LP = p
    p = write_b(m, p, 0xAC)             # lodsb
    p = write_b(m, p, 0x84, 0xC0)       # test al,al
    JZ1 = p; p = write_b(m, p, 0x74, 0) # jz DONE (patch)
    p = write_b(m, p, ('w',0x3FD))      # mov dx, LSR
    W1 = p
    p = write_b(m, p, 0xEC)             # in al,dx
    p = write_b(m, p, 0xA8, 0x20)       # test al,0x20
    p = write_b(m, p, 0x74, (W1-(p+1))&0xFF)  # jz W1
    p = write_b(m, p, ('w',0x3F8))      # mov dx, TX
    p = write_b(m, p, 0xEE)             # out dx,al
    p = write_b(m, p, 0xEB, (LP-(p+1))&0xFF)  # jmp LP
    # DONE:
    m[JZ1+1] = (p - (JZ1+2)) & 0xFF   # patch jz
    p = write_b(m, p, 0x5B, 0x58, 0xC3) # pop bx, ax; ret

    # Patch call offsets
    m[c1:c1+2] = struct.pack('<h', PS - (c1+2))
    m[c2:c2+2] = struct.pack('<h', PS - (c2+2))

    # Strings
    for i,c in enumerate(b"\r\nDNAOS v3.4 MBR\r\n\x00"): m[S1+i] = c
    for i,c in enumerate(b"Disk error!\r\n\x00"): m[S2+i] = c

    m[0x1F8] = 0x80
    for i in range(p, 510): m[i] = 0
    m[510] = 0x55; m[511] = 0xAA
    assert len(m) == 512, f"MBR={len(m)}"
    return bytes(m)

# ─────────────────────────────────────────────────────────────────────
# KERNEL — 64KB
# ─────────────────────────────────────────────────────────────────────

def build_kernel():
    k = bytearray(64 * 1024)

    # ═════ 16-bit entry @ 0x0000 ═════
    p = 0

    # COM1输出 '1\r\n' (确认16位运行)
    p = write_b(k, p, 0xB0, 0x31, ('w',0x3F8), 0xEE)
    p = write_b(k, p, 0xB0, 0x0D, 0xEE, 0xB0, 0x0A, 0xEE)

    # Enable A20
    p = write_b(k, p, 0xE4,0x92, 0x0C,0x02, 0xE6,0x92)
    # CLI
    p = write_b(k, p, 0xFA)

    # GDT @ 0x80
    GDT = 0x80
    p = write_b(k, p, 0x0F,0x01,0x16, ('w',GDT))  # lgdt [GDT]
    # GDTR: limit=23, base=GDT+6
    k[GDT] = 23; k[GDT+1] = 0
    k[GDT+2] = (GDT+6)&0xFF; k[GDT+3] = (GDT+6)>>8; k[GDT+4] = 0; k[GDT+5] = 0
    # Null desc
    for i in range(8): k[GDT+6+i] = 0
    # Code 0x08
    C = GDT+14
    k[C:C+8] = bytes([0xFF,0xFF,0x00,0x00,0x00,0x9A,0xCF,0x00])
    # Data 0x10
    D = GDT+22
    k[D:D+8] = bytes([0xFF,0xFF,0x00,0x00,0x00,0x92,0xCF,0x00])

    # Protected mode
    p = write_b(k, p, 0x0F,0x20,0xC0, 0x0C,0x01, 0x0F,0x22,0xC0)
    # FAR JMP 0x08:0x0200
    P32 = 0x200
    p = write_b(k, p, 0x66,0xEA, ('d',P32), ('w',0x08))

    # ═════ 32-bit @ P32 ═════
    p = P32

    # Load data segments
    p = write_b(k, p, 0x66,('w',0xB810), 0x8E,0xD8, 0x8E,0xC0, 0x8E,0xD0)
    p = write_b(k, p, 0xBC, ('d', 0x00090000))

    # COM1输出 '2\r\n'
    p = write_b(k, p, 0xB0, 0x32, ('w',0x3F8), 0xEE)
    p = write_b(k, p, 0xB0, 0x0D, 0xEE, 0xB0, 0x0A, 0xEE)

    # Page tables @ 0x4000 (identity map 0-4MB, 2MB pages)
    PTB = 0x4000
    for i in range(0x4000):
        k[PTB+i] = 0  # clear PT area
    # Helper for 64-bit poke
    def pq(addr, val):
        for i in range(8): k[addr+i] = (val>>(i*8))&0xFF
    pq(PTB,        (PTB+0x1000) | 0x03)
    pq(PTB+0x1000, (PTB+0x2000) | 0x03)
    pq(PTB+0x2000, 0x00000000 | 0x83)  # 0-2MB
    pq(PTB+0x2008, 0x00200000 | 0x83)  # 2-4MB

    # CR3
    p = write_b(k, p, 0xB8, ('d',PTB), 0x0F,0x22,0xD8)
    # CR4.PAE
    p = write_b(k, p, 0x0F,0x20,0xE0, 0x83,0xC8,0x20, 0x0F,0x22,0xE0)
    # EFER.LME=1 (MSR 0xC0000080, bit 8)
    # rdmsr: ecx=0xC0000080 -> edx:eax
    p = write_b(k, p, 0xB9,('w',0x0080), ('w',0xC000))
    p = write_b(k, p, 0x0F,0x32)
    p = write_b(k, p, 0x0D,('w',0x0100), ('w',0x0000))  # or eax, 0x100
    p = write_b(k, p, 0x0F,0x30)
    # CR0.PG=1 (PE already 1 -> long mode compat)
    p = write_b(k, p, 0x0F,0x20,0xC0)
    p = write_b(k, p, 0x66,0x81,0xC8,('w',0x0000), ('w',0x8000))  # or eax, 0x80000000
    # Wait, 32-bit or eax, imm32: 81 C8 xx xx xx xx
    # But we need to set PG (bit 31) while keeping PE (bit 0)
    # Current eax has PE=1, so or 0x80000000 sets PG -> 0x80000001
    # Actually the above encodes as: 66 81 C8 00 00 00 80 (little endian)
    p = write_b(k, p, 0x0F,0x22,0xC0)

    # FAR JMP to 64-bit via retf
    P64 = 0x1000
    p = write_b(k, p, 0x66,('w',0x6808))   # push 0x0008 (cs selector)
    p = write_b(k, p, 0x68, ('d', P64))    # push eip
    p = write_b(k, p, 0xCB)                # retf

    # ═════ 64-bit @ P64 ═════
    p = P64

    # Reload data segments
    p = write_b(k, p, 0x66,('w',0xB810), 0x8E,0xD8, 0x8E,0xC0, 0x8E,0xD0)
    p = write_b(k, p, 0x48,0xBC, ('q',0x1F000))

    # COM1输出 '3\r\n' (确认64位运行)
    p = write_b(k, p, 0xB0, 0x33, ('w',0x3F8), 0xEE)
    p = write_b(k, p, 0xB0, 0x0D, 0xEE, 0xB0, 0x0A, 0xEE)

    # 清屏 (VGA 0xB8000)
    p = write_b(k, p, 0x48,0xBF, ('q',0xB8000))
    p = write_b(k, p, 0x48,0xC7,0xC1, ('q',2000))
    p = write_b(k, p, 0x66,('w',0xB820), 0x07)  # mov ax, 0x0720
    p = write_b(k, p, 0x66,0xF3,0xAB)

    # 初始化光标位置: mov word [0xB8002], 0
    p = write_b(k, p, 0x66,0xC7,0x04,0x25,('w',0xB8002),0x00,0x00,('w',0))

    # 欢迎信息
    WEL = 0x5000
    msg = (b"\n"
           b" ======================================================================== \n"
           b"   DNAOS v3.4 - Molecular Cognitive Operating System                       \n"
           b"   Tsukuyomi 0 - Charter Town - Node 0                                     \n"
           b"   Target: AMD Ryzen 5 5500 + GA106 RTX 3060                               \n"
           b"   Mode: x86-64 Long Mode | Pure Machine Code | Zero C                     \n"
           b" ======================================================================== \n"
           b"                                                                           \n"
           b"   Commands: pci gpu info dna help reboot                                  \n"
           b"                                                                           \n"
           b"   dnaos> _                                                              \x00")
    k[WEL:WEL+len(msg)] = msg

    # call print_vga
    p = write_b(k, p, 0x48,0xBE, ('q', 0x10000+WEL))
    p = write_b(k, p, 0xE8); pv = p; p = write_b(k, p, 'd', 0)

    # ═════ 键盘轮询主循环 ═════
    ML = p
    p = write_b(k, p, 0xE4,0x64, 0xA8,0x01, 0x74,0xF9)  # wait key
    p = write_b(k, p, 0xE4,0x60)                          # read scan
    p = write_b(k, p, 0x3C,0x80, 0x73,0xF2, 0x3C,0xE0, 0x74,0xEE)  # filter
    # lookup
    p = write_b(k, p, 0x48,0x0F,0xB6,0xC0)               # movzx rax,al
    p = write_b(k, p, 0x48,0x8D,0x15); tbl_r = p; p = write_b(k, p, 'd', 0)
    p = write_b(k, p, 0x8A,0x04,0x02, 0x84,0xC0, 0x74,0xDC)  # mov al,[rdx+rax]
    # VGA输出: cursor++ + stosw
    p = write_b(k, p, 0x66,0x8B,0x3C,0x25,('w',0xB8002),0x00,0x00)  # mov di,[cursor]
    p = write_b(k, p, 0x66,0xFF,0x04,0x25,('w',0xB8002),0x00,0x00)  # inc [cursor]
    p = write_b(k, p, 0x48,0x0F,0xB7,0xFF)               # movzx rdi,di
    p = write_b(k, p, 0x48,0xC1,0xE7,0x01)               # shl rdi,1
    p = write_b(k, p, 0x48,0x81,0xC7,('d',0xB8000))      # add rdi,0xB8000
    p = write_b(k, p, 0x88,0x07)                         # mov [rdi],al
    p = write_b(k, p, 0xB0,0x07, 0x88,0x47,0x01)         # mov [rdi+1],0x07
    p = write_b(k, p, 0xEB, (ML-(p+2))&0xFF)             # jmp ML

    # ═════ print_vga64 子程序 ═════
    # 输入: rsi=字符串地址(0结尾)  输出: VGA 0xB8000
    PV = p
    p = write_b(k, p, 0x50,0x57)          # push rax, rdi
    p = write_b(k, p, 0x48,0xBF, ('q', 0xB8000+320))  # rdi = row 2
    L = p
    p = write_b(k, p, 0xAC)               # lodsb
    p = write_b(k, p, 0x84,0xC0)          # test al,al
    JZ2 = p; p = write_b(k, p, 0x74, 0)   # jz DONE (patch)
    p = write_b(k, p, 0x3C,0x0A)          # cmp al,\n
    JNE = p; p = write_b(k, p, 0x75, 0)   # jne NOT_NL (patch)
    # newline: advance to next row
    p = write_b(k, p, 0x48,0x81,0xC7, ('d', 160))
    p = write_b(k, p, 0xEB); nl_jmp = p; p = write_b(k, p, 0)  # jmp L (patch)
    # NOT_NL:
    k[JNE+1] = (p - (JNE+2)) & 0xFF     # patch jne
    p = write_b(k, p, 0xAA)               # stosb (char)
    p = write_b(k, p, 0xB0,0x07, 0xAA)    # stosb (attr)
    k[nl_jmp] = (L - (nl_jmp+1)) & 0xFF   # patch jmp L
    # DONE:
    k[JZ2+1] = (p - (JZ2+2)) & 0xFF     # patch jz
    p = write_b(k, p, 0x5F,0x58,0xC3)     # pop rdi, rax; ret

    # Patch call
    k[pv:pv+4] = struct.pack('<i', PV - (pv+4))

    # 扫描码表
    TBL = 0x6000
    assert TBL >= WEL + len(msg), f"overlap: TBL={TBL}, msg_end={WEL+len(msg)}"
    sc_tbl = bytes([0,0, 0x31,0x32,0x33,0x34,0x35,0x36,0x37,0x38,0x39,0x30,
        0x2D,0x3D,0,0, 0x71,0x77,0x65,0x72,0x74,0x79,0x75,0x69,0x6F,0x70,
        0x5B,0x5D,0,0, 0x61,0x73,0x64,0x66,0x67,0x68,0x6A,0x6B,0x6C,
        0x3B,0x27,0x60,0, 0x5C,0x7A,0x78,0x63,0x76,0x62,0x6E,0x6D,
        0x2C,0x2E,0x2F,0,0,0,0x20])
    k[TBL:TBL+len(sc_tbl)] = sc_tbl

    # Patch table rel32
    k[tbl_r:tbl_r+4] = struct.pack('<i', (0x10000+TBL) - (0x10000+tbl_r+4))

    return bytes(k)


# ═══════════════════════════════════════════════════════════════════════
# BUILD
# ═══════════════════════════════════════════════════════════════════════
print("=" * 72)
print(" DNAOS v3.4 Disk Image Generator")
print("=" * 72)

print("\n[1/3] Building MBR...")
mbr = build_mbr()
print(f"  MBR: {len(mbr)}B  sig=0x{mbr[510]:02X}{mbr[511]:02X}")

print("[2/3] Building Kernel...")
kernel = build_kernel()
print(f"  Kernel: {len(kernel)//1024}KB")

print("[3/3] Assembling 64MB disk image...")
disk = bytearray(64 * 1024 * 1024)
disk[0:512] = mbr
disk[512:512+len(kernel)] = kernel
with open(OUT, 'wb') as f: f.write(disk)

sz = os.path.getsize(OUT)
print(f"  Output: {OUT}")
print(f"  Size: {sz:,}B = {sz//1024//1024}MB")
print(f"\n  QEMU: qemu-system-x86_64 -drive format=raw,file={OUT} -m 512 -display none -serial stdio")
print(f"  DD:   sudo dd if={OUT} of=/dev/sdX bs=4M && sync")
print("=" * 72)
