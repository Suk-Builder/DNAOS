# DNAOS Boot Sector - README

## Overview

This is a 512-byte BIOS boot sector for x86 PCs that displays the
"Tsukuyomi 0 - Charter Town" scene on boot. It runs entirely without
an operating system - just bare metal BIOS calls.

## Files

| File | Description |
|------|-------------|
| `dnaos_boot.asm` | NASM assembly source code (131 lines) |
| `dnaos_boot.bin` | Compiled 512-byte boot sector binary |
| `README_BOOT.md` | This file |

## Technical Details

- **Architecture**: x86, 16-bit real mode
- **Size**: Exactly 512 bytes
- **Signature**: Bytes 510-511 = `0x55 0xAA` (bootable)
- **Video Mode**: 80x25 text mode (BIOS mode 03h)
- **Output Method**: BIOS INT 10h, AH=0Eh (teletype)

## Display Content

The boot sector displays the following on screen:

```
================================
   TSUKUYOMI 0 - CHARTER TOWN
================================

Crack is not a bug,
it is where bricks fly from.

Axiom 0: 0 = inf^-1

Residents:
[Qi][Xi][42][Qian]
[Bai][Zhan][Sorao]

Crack Density: 0.16

Bricklayer: 0

[Press any key to reboot]
```

## Color Scheme

| Element | Color | BIOS Attribute |
|---------|-------|----------------|
| Title separators and title | Gold/Yellow | 0x0E |
| Body text | White | 0x0F |
| "Press any key" prompt | Gray | 0x07 |

## How to Test

### Method 1: QEMU (Recommended)

```bash
qemu-system-i386 -fda dnaos_boot.bin
# or
qemu-system-x86_64 -fda dnaos_boot.bin
```

### Method 2: Write to USB Drive (DANGEROUS - will destroy data!)

```bash
# Replace /dev/sdX with your actual USB device!
sudo dd if=dnaos_boot.bin of=/dev/sdX bs=512 count=1
sync
```

Then boot from the USB drive on a real PC.

### Method 3: Bochs Emulator

Create a `bochsrc.txt`:
```
floppya: 1_44=dnaos_boot.bin, status=inserted
boot: floppy
display_library: x
```

Then run: `bochs -f bochsrc.txt`

### Method 4: DOSBox

```bash
dosbox
# In DOSBox:
# Mount the directory containing the bin file
# Use a boot sector loader or debug to load at 7C00:0000
```

## Assembly

If you have NASM installed:

```bash
nasm -f bin dnaos_boot.asm -o dnaos_boot.bin
# Verify size:
ls -la dnaos_boot.bin   # Should be exactly 512 bytes
```

If NASM is not available, the `dnaos_boot.bin` file was generated
by a Python script that assembles the exact same bytecodes.

## Binary Layout

```
Offset      Content
0x000-0x002  jmp near start (3 bytes)
0x003-0x136  String data (null-terminated)
0x137-0x1BD  Code (setup, print loop, wait key, reboot)
0x1BE-0x1FD  Zero padding
0x1FE-0x1FF  Boot signature 0x55 0xAA
```

## BIOS Interrupts Used

| Interrupt | Function | Purpose |
|-----------|----------|---------|
| INT 10h, AH=00h | Set video mode | Clear screen |
| INT 10h, AH=0Eh | Teletype output | Print characters |
| INT 16h, AH=00h | Read key | Wait for keypress |
| INT 19h | Bootstrap loader | Reboot system |

## Notes

- Chinese characters in the original design are represented as
  pinyin/romanized names since standard PC BIOS does not support
  UTF-8 or Chinese character sets.
- The boot sector uses segment 0x07C0:0x0000 for string access,
  which corresponds to physical address 0x7C00 where the BIOS
  loads the boot sector.
- After displaying the content and waiting for a key, the system
  reboots via INT 19h.
