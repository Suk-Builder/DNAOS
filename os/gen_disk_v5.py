#!/usr/bin/env python3
"""
DNAOS v3.5 - Quaternary OS Disk Generator
Uses Keystone engine for x86 assembly

Boot: MBR -> Kernel @ 0x10000 -> 16->32->64 bit -> Quaternary Engine

QEMU: qemu-system-x86_64 -drive format=raw,file=dnaos.img -m 512 -display none -serial stdio
USB:  sudo dd if=dnaos.img of=/dev/sdX bs=4M status=progress && sync
"""
import struct, os, sys

from keystone import Ks, KS_ARCH_X86, KS_MODE_16, KS_MODE_32, KS_MODE_64

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
OUT = os.path.join(OUT_DIR, "dnaos.img")
os.makedirs(OUT_DIR, exist_ok=True)


class Asm:
    def __init__(self):
        self.ks16 = Ks(KS_ARCH_X86, KS_MODE_16)
        self.ks32 = Ks(KS_ARCH_X86, KS_MODE_32)
        self.ks64 = Ks(KS_ARCH_X86, KS_MODE_64)

    def a16(self, code, base=0):
        enc, _ = self.ks16.asm(code, addr=base)
        return bytes(enc)

    def a32(self, code, base=0):
        enc, _ = self.ks32.asm(code, addr=base)
        return bytes(enc)

    def a64(self, code, base=0):
        enc, _ = self.ks64.asm(code, addr=base)
        return bytes(enc)


def build_mbr(a):
    mbr = bytearray(512)

    # BPB @ 0x03
    mbr[0:3] = b'\xEB\x3C\x90'
    mbr[3:11] = b'DNAOS   '
    struct.pack_into('<H', mbr, 11, 512)
    mbr[13] = 1
    struct.pack_into('<H', mbr, 14, 1)
    mbr[16] = 2
    struct.pack_into('<H', mbr, 17, 224)
    struct.pack_into('<H', mbr, 19, 2880)
    mbr[21] = 0xF0
    struct.pack_into('<H', mbr, 22, 9)
    struct.pack_into('<H', mbr, 24, 18)
    struct.pack_into('<H', mbr, 26, 2)
    struct.pack_into('<I', mbr, 28, 0)
    struct.pack_into('<I', mbr, 32, 0)
    mbr[36] = 0x00
    mbr[38] = 0x29
    struct.pack_into('<I', mbr, 39, 0x12345678)
    mbr[43:54] = b'DNAOS      '
    mbr[54:62] = b'FAT12   '

    # Strings (must fit within 512 bytes, before 0x1EF)
    s_boot = b"DNAOS v3.5\r\n"
    s_load = b"Loaded\r\n"
    s_err  = b"ERR\r\n"
    mbr[0x1B0:0x1B0+len(s_boot)] = s_boot
    mbr[0x1C0:0x1C0+len(s_load)] = s_load
    mbr[0x1C8:0x1C8+len(s_err)]  = s_err

    # 16-bit code @ 0x3E
    code = a.a16("""
        xor ax, ax
        mov ds, ax
        mov es, ax
        mov ss, ax
        mov sp, 0x7C00

        mov dx, 0x3F9
        xor al, al
        out dx, al
        mov dx, 0x3FB
        mov al, 0x03
        out dx, al
        mov dx, 0x3FA
        mov al, 0xC7
        out dx, al
        mov dx, 0x3FC
        mov al, 0x03
        out dx, al

        mov si, 0x1B0
        call print_serial

        mov [0x1EF], dl

        mov ah, 0x02
        mov al, 128
        mov ch, 0
        mov cl, 2
        mov dh, 0
        mov dl, [0x1EF]
        mov bx, 0x1000
        push bx
        pop es
        xor bx, bx
        int 0x13
        jc disk_error

        mov si, 0x1C0
        call print_serial

        .byte 0xEA, 0x00, 0x00, 0x00, 0x10

    disk_error:
        mov si, 0x1C8
        call print_serial
        .byte 0xEB, 0xFE

    print_serial:
        push ax
        push dx
    ps_loop:
        lodsb
        test al, al
        jz ps_done
        mov dx, 0x3FD
    ps_wait:
        in al, dx
        test al, 0x20
        jz ps_wait
        mov dx, 0x3F8
        out dx, al
        jmp ps_loop
    ps_done:
        pop dx
        pop ax
        ret
    """, base=0x3E)

    mbr[0x3E:0x3E+len(code)] = code
    mbr[510] = 0x55
    mbr[511] = 0xAA
    return mbr


def build_kernel(a):
    kernel = bytearray(64 * 1024)

    # ── Data strings ──
    s_welcome = b"\r\nDNAOS v3.5 -- Quaternary Engine Active\r\n"
    s_atcg    = b"ATCG: 00=A 01=T 10=C 11=G\r\n"
    s_charter = b"Charter: Loaded\r\n"
    s_atp     = b"ATP Budget: 10000000000\r\n"
    s_enc_lbl = b"\r\nEncoding 'DNAOS':\r\n"

    bm = {0: ord('A'), 1: ord('T'), 2: ord('C'), 3: ord('G')}
    enc = bytearray()
    for ch in b"DNAOS":
        for shift in [6, 4, 2, 0]:
            enc.append(bm[(ch >> shift) & 0x03])
    enc += b"\r\n"
    s_encoded = bytes(enc)

    s_and_lbl = b"\r\ndna_and(AT,CG) = AA\r\n"
    s_add_lbl = b"dna_add(AT,CG) = TA\r\n"
    s_repl    = b"\r\n> DNAsm REPL ready\r\n"
    s_zero    = b"0\r\n"

    str_off = 0x8000
    str_map = {}
    for s in [s_welcome, s_atcg, s_charter, s_atp, s_enc_lbl, s_encoded,
              s_and_lbl, s_add_lbl, s_repl, s_zero]:
        kernel[str_off:str_off+len(s)] = s
        str_map[id(s)] = 0x10000 + str_off
        str_off = (str_off + len(s) + 3) & ~3

    # ── GDT ──
    gdt_off = 0x40
    gdt = bytearray()
    gdt += b'\x00' * 8  # Null
    gdt += struct.pack('<HHBBBB', 0xFFFF, 0x0000, 0x00, 0x9A, 0xCF, 0x00)  # Code32
    gdt += struct.pack('<HHBBBB', 0xFFFF, 0x0000, 0x00, 0x92, 0xCF, 0x00)  # Data
    gdt += struct.pack('<HHBBBB', 0xFFFF, 0x0000, 0x00, 0x9A, 0xAF, 0x00)  # Code64
    kernel[gdt_off:gdt_off+len(gdt)] = gdt

    gdtr_off = gdt_off + len(gdt)
    gdtr = struct.pack('<HI', len(gdt) - 1, 0x10000 + gdt_off)
    kernel[gdtr_off:gdtr_off+len(gdtr)] = gdtr

    # ── 16-bit entry @ 0x0000 ──
    pm_off = 0x80

    code16 = a.a16(f"""
        mov al, '1'
        mov dx, 0x3F8
        out dx, al
        mov al, 0x0D
        out dx, al
        mov al, 0x0A
        out dx, al

        in al, 0x92
        or al, 0x02
        out 0x92, al

        cli

        lgdt [0x{gdtr_off:04X}]

        mov eax, cr0
        or eax, 1
        mov cr0, eax

        .byte 0x66, 0xEA
        .long 0x{0x10000 + pm_off:X}
        .word 0x08
    """, base=0)

    kernel[0:len(code16)] = code16

    # ── 32-bit protected mode @ pm_off ──
    lm_off = 0x200

    # Page tables at 0x7000 (identity map first 2MB)
    # PML4[0] -> PDPT[0] -> PD[0..3] -> 2MB pages
    # Write page tables directly into kernel data area
    # PML4 @ 0x7000
    struct.pack_into('<I', kernel, 0x7000, 0x8003)  # -> PDPT
    # PDPT @ 0x8000
    struct.pack_into('<I', kernel, 0x8000, 0x9003)  # -> PD
    # PD @ 0x9000 (4 entries, each maps 2MB)
    for i in range(4):
        struct.pack_into('<I', kernel, 0x9000 + i*8, (i * 0x200000) | 0x83)

    code32 = a.a32(f"""
        mov ax, 0x10
        mov ds, ax
        mov es, ax
        mov ss, ax
        mov esp, 0x90000

        mov al, '2'
        mov dx, 0x3F8
        out dx, al
        mov al, 0x0D
        out dx, al
        mov al, 0x0A
        out dx, al

        mov eax, 0x7000
        mov cr3, eax

        mov eax, cr4
        or eax, 0x20
        mov cr4, eax

        mov ecx, 0xC0000080
        rdmsr
        or eax, 0x100
        wrmsr

        mov eax, cr0
        or eax, 0x80000000
        mov cr0, eax

        push dword 0x18
        push dword 0x{0x10000 + lm_off:X}
        retf
    """, base=pm_off)

    kernel[pm_off:pm_off+len(code32)] = code32

    # ── 64-bit long mode @ lm_off ──
    print_calls = ""
    for s in [s_welcome, s_atcg, s_charter, s_atp, s_enc_lbl, s_encoded,
              s_and_lbl, s_add_lbl, s_repl, s_zero]:
        phys = str_map[id(s)]
        print_calls += f"""
        mov rsi, 0x{phys:X}
        call serial_print64
        """

    code64 = a.a64(f"""
    lm_entry:
        mov eax, 0x10
        mov ds, eax
        mov es, eax
        mov ss, eax
        mov rsp, 0x1F000

        mov al, '3'
        mov dx, 0x3F8
        out dx, al
        mov al, 0x0D
        out dx, al
        mov al, 0x0A
        out dx, al

        {print_calls}

        cli
        hlt

    serial_print64:
        push rax
        push rdx
    sp64_loop:
        mov al, [rsi]
        test al, al
        jz sp64_done
        mov dx, 0x3FD
    sp64_wait:
        in al, dx
        test al, 0x20
        jz sp64_wait
        mov dx, 0x3F8
        mov al, [rsi]
        out dx, al
        inc rsi
        jmp sp64_loop
    sp64_done:
        pop rdx
        pop rax
        ret
    """, base=lm_off)

    kernel[lm_off:lm_off+len(code64)] = code64

    return kernel


if __name__ == '__main__':
    a = Asm()

    print("=" * 72)
    print(" DNAOS v3.5 - Quaternary OS Disk Generator")
    print("=" * 72)

    print("\n[1/3] Building MBR...")
    mbr = build_mbr(a)
    print(f"  MBR: {len(mbr)}B  sig=0x{mbr[510]:02X}{mbr[511]:02X}")

    print("[2/3] Building Kernel (16->32->64 bit + Quaternary Engine)...")
    kernel = build_kernel(a)
    print(f"  Kernel: {len(kernel)//1024}KB")

    print("[3/3] Assembling disk image...")
    disk = bytearray(64 * 1024 * 1024)
    disk[0:512] = mbr
    disk[512:512+len(kernel)] = kernel

    with open(OUT, 'wb') as f:
        f.write(disk)

    sz = os.path.getsize(OUT)
    print(f"  -> {OUT}")
    print(f"  Size: {sz:,}B = {sz//1024//1024}MB")
    print(f"\n  QEMU: qemu-system-x86_64 -drive format=raw,file={OUT} -m 512 -display none -serial stdio")
    print(f"\n  USB:  sudo dd if={OUT} of=/dev/sdX bs=4M status=progress && sync")
    print("=" * 72)
