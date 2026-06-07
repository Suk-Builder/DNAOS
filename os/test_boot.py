#!/usr/bin/env python3
"""
DNAOS v3.5 - x86 Boot Emulator (Unicorn v2)
Emulates MBR boot + 16->32->64 bit mode switch
Shows serial output from COM1 (0x3F8)
"""
import struct, os
from unicorn import Uc, UC_ARCH_X86, UC_MODE_16, UC_MODE_32, UC_MODE_64
from unicorn import UC_HOOK_CODE, UC_HOOK_INSN, UC_HOOK_INTR
from unicorn.x86_const import *

DISK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "dnaos.img")

serial_buf = ""
disk_data = b""
step_count = 0
MAX_STEPS = 500000


def load_disk():
    global disk_data
    with open(DISK, "rb") as f:
        disk_data = f.read()
    print(f"Disk: {len(disk_data):,} bytes")


def hook_out(uc, port, size, value, user_data):
    global serial_buf
    if port == 0x3F8:
        ch = chr(value & 0xFF)
        serial_buf += ch
        if ch == '\n':
            print(serial_buf.rstrip('\n'))
            serial_buf = ""


def hook_in(uc, port, size, user_data):
    if port == 0x3FD:
        return 0x20  # LSR: TX empty
    return 0


def hook_intr(uc, intno, user_data):
    global disk_data
    if intno == 0x13:
        ah = uc.reg_read(UC_X86_REG_AH)
        if ah == 0x02:
            al = uc.reg_read(UC_X86_REG_AL)
            ch = uc.reg_read(UC_X86_REG_CH)
            cl = uc.reg_read(UC_X86_REG_CL)
            dh = uc.reg_read(UC_X86_REG_DH)
            dl = uc.reg_read(UC_X86_REG_DL)
            es = uc.reg_read(UC_X86_REG_ES)
            bx = uc.reg_read(UC_X86_REG_BX)

            lba = (ch << 8 | cl) & 0x3FF
            offset = lba * 512
            addr = (es << 4) + bx

            data = disk_data[offset:offset + al * 512]
            if len(data) > 0:
                uc.mem_write(addr, data)
            uc.reg_write(UC_X86_REG_AH, 0x00)
            # Clear CF in FLAGS
            flags = uc.reg_read(UC_X86_REG_FLAGS)
            uc.reg_write(UC_X86_REG_FLAGS, flags & ~0x0001)

    elif intno == 0x10:
        ax = uc.reg_read(UC_X86_REG_AX)
        ah = (ax >> 8) & 0xFF
        if ah == 0x4F:
            uc.reg_write(UC_X86_REG_AX, 0x004F)
            flags = uc.reg_read(UC_X86_REG_FLAGS)
            uc.reg_write(UC_X86_REG_FLAGS, flags & ~0x0001)


def hook_code(uc, address, size, user_data):
    global step_count
    step_count += 1
    if step_count > MAX_STEPS:
        uc.emu_stop()


def emulate():
    global serial_buf, step_count
    load_disk()

    uc = Uc(UC_ARCH_X86, UC_MODE_16)

    # Map memory (1MB low memory, covers everything we need)
    uc.mem_map(0x00000, 0x200000)

    # Load MBR at 0x7C00
    uc.mem_write(0x7C00, disk_data[0:512])

    # Load kernel at 0x10000
    uc.mem_write(0x10000, disk_data[512:512 + 64 * 1024])

    # Set registers
    uc.reg_write(UC_X86_REG_DL, 0x80)
    uc.reg_write(UC_X86_REG_SP, 0x7C00)
    uc.reg_write(UC_X86_REG_DS, 0)
    uc.reg_write(UC_X86_REG_ES, 0)
    uc.reg_write(UC_X86_REG_SS, 0)

    # Hooks
    uc.hook_add(UC_HOOK_INSN, hook_out, None, 1, 0, UC_X86_INS_OUT)
    uc.hook_add(UC_HOOK_INSN, hook_in, None, 1, 0, UC_X86_INS_IN)
    uc.hook_add(UC_HOOK_INTR, hook_intr)
    uc.hook_add(UC_HOOK_CODE, hook_code)

    print("\n" + "=" * 60)
    print(" DNAOS v3.5 - Boot Emulation (Unicorn)")
    print("=" * 60 + "\n")

    try:
        uc.emu_start(0x7C00, 0x7C00 + 512, timeout=30 * 1000000, count=MAX_STEPS)
    except Exception as e:
        print(f"\nEmulation stopped: {e}")

    if serial_buf:
        print(serial_buf.rstrip('\n'))

    print(f"\nSteps: {step_count}")
    print("=" * 60)


if __name__ == '__main__':
    emulate()
