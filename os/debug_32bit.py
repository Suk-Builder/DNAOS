#!/usr/bin/env python3
"""
DNAOS v3.4 — 32位调试版本
输出: 1(MBR) -> 2(32位入口) -> a(CR3) -> b(PAE) -> c(LME) -> d(PG) -> halt
不跳64位，先确认32位每一步正确。
"""
import struct, os

OUT = "/mnt/agents/output/dnaos2/os/out/debug_32bit.img"
os.makedirs(os.path.dirname(OUT), exist_ok=True)

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

def build_mbr():
    m = bytearray(512)
    p = 0
    p = wb(m, p, 0xEB, 0x3E, 0x90)
    BPB = (b"DNAOS   " + struct.pack('<H',512) + b'\x01' + struct.pack('<H',1) +
           b'\x02' + struct.pack('<H',224) + struct.pack('<H',128) + b'\xF8' +
           struct.pack('<H',1) + struct.pack('<H',32) + struct.pack('<H',64) +
           struct.pack('<I',0) + struct.pack('<I',0) + b'\x80\x00\x29' +
           b"DNAOS v3.4 " + b"FAT12   ")
    for i,c in enumerate(BPB): m[0x03+i] = c
    
    p = 0x40
    p = wb(m, p, 0x31,0xC0, 0x8E,0xD8, 0x8E,0xD0, 0xBC); p = w16(m, p, 0x7C00)
    p = wb(m, p, 0x88,0x16); p = w16(m, p, 0x7DF8)
    
    S1 = 0xC0
    p = wb(m, p, 0xBE); p = w16(m, p, 0x7C00+S1)
    p = wb(m, p, 0xE8); c1 = p; p = w16(m, p, 0)
    
    p = wb(m, p, 0xB4,0x02, 0xB0,0x80, 0xB5,0x00, 0xB1,0x02, 0xB6,0x00)
    p = wb(m, p, 0x8A,0x16); p = w16(m, p, 0x7DF8)
    p = wb(m, p, 0xBB); p = w16(m, p, 0x1000)
    p = wb(m, p, 0x8E,0xC3, 0x31,0xDB, 0xCD,0x13)
    p = wb(m, p, 0x72, 0x06)
    p = wb(m, p, 0xEA, 0x00,0x00, 0x00,0x10)
    
    p = wb(m, p, 0xB0,0x45, 0xBA,0xF8,0x03, 0xEE, 0xEB,0xFE)
    
    PS = p
    p = wb(m, p, 0x53)
    p = wb(m, p, 0xAC)
    LP = p - 1
    p = wb(m, p, 0x84, 0xC0)
    JZ = p; p = wb(m, p, 0x74, 0)
    p = wb(m, p, 0x88, 0xC3)
    p = wb(m, p, 0xBA); p = w16(m, p, 0x3FD)
    W1 = p
    p = wb(m, p, 0xEC, 0xA8, 0x20, 0x74, (W1-(p+2))&0xFF)
    p = wb(m, p, 0xBA); p = w16(m, p, 0x3F8)
    p = wb(m, p, 0x8A, 0xC3, 0xEE)
    p = wb(m, p, 0xEB, (LP-(p+2))&0xFF)
    m[JZ+1] = (p-(JZ+2))&0xFF
    p = wb(m, p, 0x5B, 0xC3)
    
    m[c1:c1+2] = struct.pack('<h', (PS-(c1+2))&0xFFFF)
    
    for i,c in enumerate(b"\r\nDNAOS v3.4 [32bit-debug]\r\n\x00"): m[S1+i] = c
    m[510] = 0x55; m[511] = 0xAA
    return bytes(m)

def build_kernel():
    k = bytearray(64 * 1024)
    
    def pq(addr, val):
        for i in range(8): k[addr+i] = (val>>(i*8)) & 0xFF
    
    # 16-bit @ 0x0000
    p = 0
    k[p:p+12] = bytes([0xB0,0x31, 0xBA,0xF8,0x03, 0xEE, 0xB0,0x0D,0xEE, 0xB0,0x0A,0xEE]); p += 12
    k[p:p+7] = bytes([0xE4,0x92, 0x0C,0x02, 0xE6,0x92, 0xFA]); p += 7
    
    # GDT @ 0x80
    GDT = 0x80
    # DS=0x1000 for lgdt
    k[p:p+5] = bytes([0xB8, 0x00, 0x10, 0x8E, 0xD8]); p += 5
    k[p:p+5] = bytes([0x0F, 0x01, 0x16, GDT&0xFF, (GDT>>8)&0xFF]); p += 5
    k[p:p+5] = bytes([0xB8, 0x00, 0x00, 0x8E, 0xD8]); p += 5
    
    # GDTR: limit=31, base=0x10080 (GDT physical address = 0x10000 + 0x80)
    k[GDT] = 31; k[GDT+1] = 0
    k[GDT+2] = 0x80; k[GDT+3] = 0x00; k[GDT+4] = 0x01; k[GDT+5] = 0x00
    for i in range(8): k[GDT+6+i] = 0
    C32 = GDT+14; k[C32:C32+8] = bytes([0xFF,0xFF,0x00,0x00,0x00,0x9A,0xCF,0x00])
    D = GDT+22; k[D:D+8] = bytes([0xFF,0xFF,0x00,0x00,0x00,0x92,0xCF,0x00])
    C64 = GDT+30; k[C64:C64+8] = bytes([0xFF,0xFF,0x00,0x00,0x00,0x9A,0xAF,0x00])
    
    k[p:p+8] = bytes([0x0F,0x20,0xC0, 0x0C,0x01, 0x0F,0x22,0xC0]); p += 8
    P32 = 0x200
    k[p:p+7] = bytes([0x66,0xEA]); p += 2
    p = w32(k, p, 0x10000+P32); p = w16(k, p, 0x08)
    
    # 32-bit @ 0x200
    p = P32
    
    # '2'
    k[p:p+7] = bytes([0xB0, 0x32, 0x66, 0xBA]); p += 4
    p = w16(k, p, 0x3F8); k[p] = 0xEE; p += 1
    k[p:p+6] = bytes([0xB0, 0x0D, 0xEE, 0xB0, 0x0A, 0xEE]); p += 6
    
    # load data segments
    k[p:p+10] = bytes([0x66, 0xB8, 0x10, 0x00, 0x8E, 0xD8, 0x8E, 0xC0, 0x8E, 0xD0]); p += 10
    p = wb(k, p, 0xBC); p = w32(k, p, 0x00090000)
    
    # page tables @ 0x4000
    PTB = 0x4000
    for i in range(0x3000): k[PTB+i] = 0
    pq(PTB, (PTB+0x1000) | 0x03)
    pq(PTB+0x1000, (PTB+0x2000) | 0x03)
    pq(PTB+0x2000, 0x00000083)
    pq(PTB+0x2008, 0x00200083)
    
    # 'a' = CR3 set
    p = wb(k, p, 0xB8); p = w32(k, p, PTB)
    k[p:p+3] = bytes([0x0F, 0x22, 0xD8]); p += 3
    k[p:p+6] = bytes([0xB0, 0x61, 0x66, 0xBA]); p += 4
    p = w16(k, p, 0x3F8); k[p] = 0xEE; p += 1
    
    # 'b' = PAE on
    k[p:p+9] = bytes([0x0F, 0x20, 0xE0, 0x83, 0xC8, 0x20, 0x0F, 0x22, 0xE0]); p += 9
    k[p:p+6] = bytes([0xB0, 0x62, 0x66, 0xBA]); p += 4
    p = w16(k, p, 0x3F8); k[p] = 0xEE; p += 1
    
    # 'c' = LME on
    k[p:p+12] = bytes([0xB9, 0x80, 0x00, 0x00, 0xC0, 0x0F, 0x32, 0x0D, 0x00, 0x01, 0x00, 0x00]); p += 12
    k[p:p+3] = bytes([0x0F, 0x30]); p += 3
    k[p:p+6] = bytes([0xB0, 0x63, 0x66, 0xBA]); p += 4
    p = w16(k, p, 0x3F8); k[p] = 0xEE; p += 1
    
    # 'd' = PG on
    k[p:p+10] = bytes([0x0F, 0x20, 0xC0, 0x81, 0xC8]); p += 5
    p = w32(k, p, 0x80000000)
    k[p:p+3] = bytes([0x0F, 0x22, 0xC0]); p += 3
    k[p:p+6] = bytes([0xB0, 0x64, 0x66, 0xBA]); p += 4
    p = w16(k, p, 0x3F8); k[p] = 0xEE; p += 1
    
    # halt
    k[p:p+2] = bytes([0xEB, 0xFE])
    
    return bytes(k)

# Build
mbr = build_mbr()
kernel = build_kernel()
disk = bytearray(64 * 1024 * 1024)
disk[0:512] = mbr
disk[512:512+len(kernel)] = kernel
with open(OUT, 'wb') as f: f.write(disk)

print(f"Debug 32-bit: {OUT}")
print("Expected: MBR msg -> 1 -> 2 -> a -> b -> c -> d")
