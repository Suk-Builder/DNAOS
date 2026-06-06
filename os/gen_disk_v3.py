#!/usr/bin/env python3
"""
DNAOS v3.4 — 修复所有操作码前缀问题
直接写原始字节，不用元组抽象
QEMU: qemu-system-x86_64 -drive format=raw,file=dnaos.img -m 512 -display none -serial stdio
"""
import struct, os

OUT = "/mnt/agents/output/dnaos2/os/out/dnaos.img"
os.makedirs(os.path.dirname(OUT), exist_ok=True)

# ─────────────────────────────────────────────────────────────────────
# HELPERS — 直接写原始字节，最小抽象
# ─────────────────────────────────────────────────────────────────────

def w8(buf, p, v):
    buf[p] = v & 0xFF; return p + 1

def w16(buf, p, v):
    buf[p] = v & 0xFF; buf[p+1] = (v>>8) & 0xFF; return p + 2

def w32(buf, p, v):
    for i in range(4): buf[p+i] = (v>>(i*8)) & 0xFF
    return p + 4

def w64(buf, p, v):
    for i in range(8): buf[p+i] = (v>>(i*8)) & 0xFF
    return p + 8

def wb(buf, p, *vals):
    for v in vals:
        if isinstance(v, int): buf[p] = v & 0xFF; p += 1
        elif isinstance(v, bytes):
            for c in v: buf[p] = c; p += 1
    return p

# ─────────────────────────────────────────────────────────────────────
# MBR — 512字节
# ─────────────────────────────────────────────────────────────────────

def build_mbr():
    m = bytearray(512)
    p = 0

    # jmp 0x40 (short)
    p = wb(m, p, 0xEB, 0x3E, 0x90)

    # BPB @ 0x03
    BPB = (b"DNAOS   " + struct.pack('<H',512) + b'\x01' + struct.pack('<H',1) +
           b'\x02' + struct.pack('<H',224) + struct.pack('<H',128) + b'\xF8' +
           struct.pack('<H',1) + struct.pack('<H',32) + struct.pack('<H',64) +
           struct.pack('<I',0) + struct.pack('<I',0) + b'\x80\x00\x29' +
           b"DNAOS v3.4 " + b"FAT12   ")
    for i,c in enumerate(BPB): m[0x03+i] = c

    # ── Code @ 0x40 ──
    p = 0x40

    # xor ax,ax; mov ds,ax; mov es,ax; mov ss,ax; mov sp,0x7C00
    p = wb(m, p, 0x31,0xC0, 0x8E,0xD8, 0x8E,0xC0, 0x8E,0xD0)
    p = wb(m, p, 0xBC); p = w16(m, p, 0x7C00)   # mov sp, 0x7C00

    # mov [0x7DF8], dl
    p = wb(m, p, 0x88,0x16); p = w16(m, p, 0x7DF8)

    # Print string via COM1 (S1 after all code, avoid overlap)
    S1 = 0xC0
    p = wb(m, p, 0xBE); p = w16(m, p, 0x7C00 + S1)  # mov si, str
    p = wb(m, p, 0xE8); c1 = p; p = w16(m, p, 0)     # call print (patch)

    # INT13h: read 128 sectors to ES:BX = 0x1000:0x0000
    p = wb(m, p, 0xB4,0x02, 0xB0,0x80, 0xB5,0x00, 0xB1,0x02, 0xB6,0x00)
    p = wb(m, p, 0x8A,0x16); p = w16(m, p, 0x7DF8)   # mov dl, [bootdrv]
    p = wb(m, p, 0xBB); p = w16(m, p, 0x1000)         # mov bx, 0x1000
    p = wb(m, p, 0x8E,0xC3)                           # mov es, bx
    p = wb(m, p, 0x31,0xDB)                           # xor bx, bx
    p = wb(m, p, 0xCD,0x13)                           # int 0x13
    p = wb(m, p, 0x72, 0x06)                          # jc err
    # far jmp 0x1000:0x0000
    p = wb(m, p, 0xEA, 0x00,0x00, 0x00,0x10)

    # disk_err
    S2 = 0xE0
    p = wb(m, p, 0xBE); p = w16(m, p, 0x7C00 + S2)
    p = wb(m, p, 0xE8); c2 = p; p = w16(m, p, 0)
    p = wb(m, p, 0xEB, 0xFE)                          # jmp $

    # print_serial — DS:SI -> COM1, 0-terminated
    PS = p
    p = wb(m, p, 0x50, 0x53)        # push ax, bx
    LP = p
    p = wb(m, p, 0xAC)              # lodsb
    p = wb(m, p, 0x84, 0xC0)        # test al, al
    JZ1 = p; p = wb(m, p, 0x74, 0)  # jz DONE (patch)
    # wait THR empty
    p = wb(m, p, 0xBA); p = w16(m, p, 0x3FD)   # mov dx, LSR
    W1 = p
    p = wb(m, p, 0xEC)              # in al, dx
    p = wb(m, p, 0xA8, 0x20)        # test al, 0x20
    p = wb(m, p, 0x74, (W1-(p+1))&0xFF)  # jz W1
    # send char
    p = wb(m, p, 0xBA); p = w16(m, p, 0x3F8)   # mov dx, TX
    p = wb(m, p, 0xEE)              # out dx, al
    p = wb(m, p, 0xEB, (LP-(p+1))&0xFF)        # jmp LP
    # DONE:
    m[JZ1+1] = (p - (JZ1+2)) & 0xFF
    p = wb(m, p, 0x5B, 0x58, 0xC3)  # pop bx, ax; ret

    # Patch calls
    w16(m, c1, (PS - (c1+2)) & 0xFFFF)
    w16(m, c2, (PS - (c2+2)) & 0xFFFF)

    m[0x1F8] = 0x80
    for i in range(p, 0xC0): m[i] = 0   # clear only up to S1, NOT strings
    m[510] = 0x55; m[511] = 0xAA

    # Strings (AFTER clearing, so they don't get zeroed)
    for i,c in enumerate(b"\r\nDNAOS v3.4 MBR\r\n\x00"): m[S1+i] = c
    for i,c in enumerate(b"Disk error!\r\n\x00"): m[S2+i] = c
    assert len(m) == 512
    return bytes(m)

# ─────────────────────────────────────────────────────────────────────
# KERNEL — 64KB
# ─────────────────────────────────────────────────────────────────────

def build_kernel():
    k = bytearray(64 * 1024)

    def pq(addr, val):
        for i in range(8): k[addr+i] = (val>>(i*8)) & 0xFF

    # ═════ 16-bit @ 0x0000 ═════
    p = 0

    # COM1输出 '1\r\n'
    p = wb(k, p, 0xB0, 0x31)          # mov al, '1'
    p = wb(k, p, 0xBA); p = w16(k, p, 0x3F8)  # mov dx, 0x3F8
    p = wb(k, p, 0xEE)                # out dx, al
    p = wb(k, p, 0xB0, 0x0D, 0xEE, 0xB0, 0x0A, 0xEE)

    # Enable A20
    p = wb(k, p, 0xE4,0x92, 0x0C,0x02, 0xE6,0x92)
    # CLI
    p = wb(k, p, 0xFA)

    # GDT @ 0x80
    GDT = 0x80
    p = wb(k, p, 0x0F,0x01,0x16); p = w16(k, p, GDT)  # lgdt [GDT]
    # GDTR
    k[GDT] = 23; k[GDT+1] = 0
    k[GDT+2] = (GDT+6)&0xFF; k[GDT+3] = (GDT+6)>>8; k[GDT+4] = 0; k[GDT+5] = 0
    # Null
    for i in range(8): k[GDT+6+i] = 0
    # Code 0x08
    C = GDT+14
    k[C:C+8] = bytes([0xFF,0xFF,0x00,0x00,0x00,0x9A,0xCF,0x00])
    # Data 0x10
    D = GDT+22
    k[D:D+8] = bytes([0xFF,0xFF,0x00,0x00,0x00,0x92,0xCF,0x00])

    # Protected mode
    p = wb(k, p, 0x0F,0x20,0xC0, 0x0C,0x01, 0x0F,0x22,0xC0)
    # FAR JMP 0x08:0x00000200 (16-bit encoding of 32-bit far jmp)
    P32 = 0x200
    p = wb(k, p, 0x66,0xEA); p = w32(k, p, P32); p = w16(k, p, 0x08)

    # ═════ 32-bit @ P32 ═════
    p = P32

    # mov ax, 0x10; mov ds,ax; mov es,ax; mov ss,ax
    p = wb(k, p, 0x66,0xB8); p = w16(k, p, 0x10)   # mov ax, 0x10
    p = wb(k, p, 0x8E,0xD8, 0x8E,0xC0, 0x8E,0xD0)
    # mov esp, 0x90000
    p = wb(k, p, 0xBC); p = w32(k, p, 0x00090000)   # mov esp, imm32

    # COM1输出 '2\r\n'
    p = wb(k, p, 0xB0, 0x32)
    p = wb(k, p, 0xBA); p = w16(k, p, 0x3F8)
    p = wb(k, p, 0xEE)
    p = wb(k, p, 0xB0, 0x0D, 0xEE, 0xB0, 0x0A, 0xEE)

    # Page tables @ 0x4000 (identity map 0-4MB, 2MB pages)
    PTB = 0x4000
    for i in range(0x3000): k[PTB+i] = 0
    pq(PTB,        (PTB+0x1000) | 0x03)
    pq(PTB+0x1000, (PTB+0x2000) | 0x03)
    pq(PTB+0x2000, 0x00000000 | 0x83)  # 0-2MB
    pq(PTB+0x2008, 0x00200000 | 0x83)  # 2-4MB

    # CR3 = PTB
    p = wb(k, p, 0xB8); p = w32(k, p, PTB)          # mov eax, PTB
    p = wb(k, p, 0x0F,0x22,0xD8)                    # mov cr3, eax
    # CR4.PAE=1
    p = wb(k, p, 0x0F,0x20,0xE0, 0x83,0xC8,0x20, 0x0F,0x22,0xE0)
    # EFER.LME=1 (MSR 0xC0000080 bit 8)
    p = wb(k, p, 0xB9); p = w32(k, p, 0xC0000080)   # mov ecx, 0xC0000080
    p = wb(k, p, 0x0F,0x32)                         # rdmsr
    p = wb(k, p, 0x0D); p = w32(k, p, 0x100)        # or eax, 0x100
    p = wb(k, p, 0x0F,0x30)                         # wrmsr
    # CR0.PG=1 (PE=1 already -> long mode)
    p = wb(k, p, 0x0F,0x20,0xC0)
    p = wb(k, p, 0x81,0xC8); p = w32(k, p, 0x80000000)  # or eax, 0x80000000
    p = wb(k, p, 0x0F,0x22,0xC0)

    # FAR JMP to 64-bit via retf
    P64 = 0x1000
    p = wb(k, p, 0x68); p = w32(k, p, P64)          # push offset
    p = wb(k, p, 0x66,0x68); p = w16(k, p, 0x08)    # push 0x0008 (cs)
    p = wb(k, p, 0xCB)                              # retf

    # ═════ 64-bit @ P64 ═════
    p = P64

    # mov ax, 0x10; mov ds,ax; mov es,ax; mov ss,ax
    p = wb(k, p, 0x66,0xB8); p = w16(k, p, 0x10)
    p = wb(k, p, 0x8E,0xD8, 0x8E,0xC0, 0x8E,0xD0)
    # mov rsp, 0x1F000
    p = wb(k, p, 0x48,0xBC); p = w64(k, p, 0x1F000)

    # COM1输出 '3\r\n'
    p = wb(k, p, 0xB0, 0x33)
    p = wb(k, p, 0xBA); p = w16(k, p, 0x3F8)
    p = wb(k, p, 0xEE)
    p = wb(k, p, 0xB0, 0x0D, 0xEE, 0xB0, 0x0A, 0xEE)

    # 清屏 (VGA 0xB8000)
    p = wb(k, p, 0x48,0xBF); p = w64(k, p, 0xB8000)
    p = wb(k, p, 0x48,0xC7,0xC1); p = w64(k, p, 2000)
    p = wb(k, p, 0x66,0xB8); p = w16(k, p, 0x0720)  # mov ax, 0x0720
    p = wb(k, p, 0x66,0xF3,0xAB)                    # rep stosw

    # 初始化光标: mov word [0xB8002], 0
    p = wb(k, p, 0x66,0xC7,0x04,0x25); p = w32(k, p, 0xB8002); p = w16(k, p, 0)

    # 欢迎信息 @ 0x5000
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

    # call print_vga64(rsi=msg)
    p = wb(k, p, 0x48,0xBE); p = w64(k, p, 0x10000+WEL)
    p = wb(k, p, 0xE8); pv = p; p = w32(k, p, 0)

    # ═════ 键盘主循环 ═════
    ML = p
    p = wb(k, p, 0xE4,0x64, 0xA8,0x01, 0x74,0xF9)  # wait key
    p = wb(k, p, 0xE4,0x60)                          # read scan
    p = wb(k, p, 0x3C,0x80, 0x73,0xF2, 0x3C,0xE0, 0x74,0xEE)  # filter
    # lookup scan->ascii
    p = wb(k, p, 0x48,0x0F,0xB6,0xC0)               # movzx rax,al
    p = wb(k, p, 0x48,0x8D,0x15); tbl_r = p; p = w32(k, p, 0)
    p = wb(k, p, 0x8A,0x04,0x02, 0x84,0xC0, 0x74,0xDC)  # mov al,[rdx+rax]
    # VGA显示
    p = wb(k, p, 0x66,0x8B,0x3C,0x25); p = w32(k, p, 0xB8002)  # mov di,[cursor]
    p = wb(k, p, 0x66,0xFF,0x04,0x25); p = w32(k, p, 0xB8002)  # inc [cursor]
    p = wb(k, p, 0x48,0x0F,0xB7,0xFF)               # movzx rdi,di
    p = wb(k, p, 0x48,0xC1,0xE7,0x01)               # shl rdi,1
    p = wb(k, p, 0x48,0x81,0xC7); p = w32(k, p, 0xB8000)  # add rdi,0xB8000
    p = wb(k, p, 0x88,0x07)                         # mov [rdi],al
    p = wb(k, p, 0xB0,0x07, 0x88,0x47,0x01)         # mov [rdi+1],0x07
    p = wb(k, p, 0xEB, (ML-(p+2))&0xFF)             # jmp ML

    # ═════ print_vga64 子程序 ═════
    PV = p
    p = wb(k, p, 0x50,0x57)                          # push rax, rdi
    p = wb(k, p, 0x48,0xBF); p = w64(k, p, 0xB8000+320)  # rdi=row2
    L = p
    p = wb(k, p, 0xAC)                               # lodsb
    p = wb(k, p, 0x84,0xC0)                          # test al,al
    JZ2 = p; p = wb(k, p, 0x74, 0)                   # jz DONE (patch)
    p = wb(k, p, 0x3C,0x0A)                          # cmp al,0x0A
    JNE = p; p = wb(k, p, 0x75, 0)                   # jne NOT_NL (patch)
    # newline: add rdi, 160 (advance to next row)
    p = wb(k, p, 0x48,0x81,0xC7); p = w32(k, p, 160)
    p = wb(k, p, 0xEB); nl_jmp = p; p = wb(k, p, 0)  # jmp L (patch)
    # NOT_NL:
    k[JNE+1] = (p - (JNE+2)) & 0xFF
    p = wb(k, p, 0xAA)                               # stosb (char)
    p = wb(k, p, 0xB0,0x07, 0xAA)                    # stosb (attr)
    k[nl_jmp] = (L - (nl_jmp+1)) & 0xFF
    # DONE:
    k[JZ2+1] = (p - (JZ2+2)) & 0xFF
    p = wb(k, p, 0x5F,0x58,0xC3)                     # pop rdi, rax; ret

    # Patch call
    w32(k, pv, (PV - (pv+4)) & 0xFFFFFFFF)

    # 扫描码表
    TBL = 0x6000
    assert TBL >= WEL + len(msg)
    sc_tbl = bytes([0,0, 0x31,0x32,0x33,0x34,0x35,0x36,0x37,0x38,0x39,0x30,
        0x2D,0x3D,0,0, 0x71,0x77,0x65,0x72,0x74,0x79,0x75,0x69,0x6F,0x70,
        0x5B,0x5D,0,0, 0x61,0x73,0x64,0x66,0x67,0x68,0x6A,0x6B,0x6C,
        0x3B,0x27,0x60,0, 0x5C,0x7A,0x78,0x63,0x76,0x62,0x6E,0x6D,
        0x2C,0x2E,0x2F,0,0,0,0x20])
    k[TBL:TBL+len(sc_tbl)] = sc_tbl

    # Patch table rel32
    w32(k, tbl_r, ((0x10000+TBL) - (0x10000+tbl_r+4)) & 0xFFFFFFFF)

    return bytes(k)


# ═══════════════════════════════════════════════════════════════════════
# BUILD
# ═══════════════════════════════════════════════════════════════════════
print("=" * 72)
print(" DNAOS v3.4 Disk Image Generator (v3)")
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
print(f"  -> {OUT}")
print(f"  Size: {sz:,}B = {sz//1024//1024}MB")
print(f"\n  QEMU: qemu-system-x86_64 -drive format=raw,file={OUT} -m 512 -display none -serial stdio")
print("=" * 72)
