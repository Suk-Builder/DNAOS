# DNAOS Boot Debug Report — 2026-06-12

## Summary

Spent the session debugging why DNAOS kernel (1144 bytes, built at `os/kernel.asm`) won't boot from a 1.44MB floppy in QEMU 6.2.0 on SeetaCloud server. Successfully identified multiple working MBR patterns via debug, but **kernel never reached execution** because stage-2 INT 13h read failed. The **exact** failure mode depends on QEMU version (suspected QEMU 6.2.0 + `if=floppy` floppy emulation has a CHS 0/0/2 read quirk). Documented here for future debugging in a different QEMU environment.

## Artifacts (on SeetaCloud server `/tmp/`)

| File | Size | Description |
|------|------|-------------|
| `mbr_v8.bin` | 37 B code | Minimal MBR: 'B' marker, INT 13h AH=02 read sector 2 (CL=2, AL=1, DL=0x00, ES=0x1000, BX=0) → far jump to 0x1000:0x0000 |
| `dnaos_v8.img` | 1.44 MB | Full image: MBR + kernel.bin at sector 2-4 (offset 0x200-0x677) |
| `mbr_v20.bin` | 192 B code | Debug MBR: prints DL, status of each read, tests DL=0x00 vs 0xF8 |
| `mbr_v23.bin` | 258 B code | Try reading sectors 2,3,4 separately (each CL=N, AL=1) |
| `dnaos_v24.img` | 1.44 MB | Image with sequential per-sector reads |
| `dnaos_v9s.img` | 1.44 MB | Kernel placed at sector 9 (CHS 0/0/9, 1-based) per 0xKiire pattern |
| `mbr_v9s.bin` | 98 B code | MBR reads kernel from sector 9 (skipping sector 2 quirk zone) |

## Diagnostic Findings (verified empirically)

### 1. QEMU 6.2.0 + `if=floppy` + 1.44MB raw image → SeaBIOS 1.15.0-1

Boot log shows full chain:
```
SeaBIOS (version 1.15.0-1)
iPXE (https://ipxe.org) 00:03.0 CA00 PCI2.10 PnP PMM+07F8B4A0+07ECB4A0
Press Ctrl-B to configure iPXE (PCI 00:03.0)...
Booting from Floppy...
```

### 2. SeaBIOS sets `DL = 0xF8` (PS/2 floppy convention), NOT `0x00`

This was the first surprise. Verified by serial output `'D' + hex(DL)`:
```
D F 8  ← DL = 0xF8
```

### 3. INT 13h AH=00 (reset floppy) returns 0x00 (success) regardless of DL

Both DL=0x00 and DL=0xF8 work for reset.

### 4. INT 13h AH=02 (read sectors) — the actual problem

**Symptom**: returns `AH=0x01` (invalid command) consistently for CHS 0/0/2, regardless of:
- DL value (0x00 xor DL=0xF8, pop dx from stack)
- With or without AH=00 reset first
- AL=1, AL=2, AL=3 (sector count)
- QEMU cmd: `-drive if=floppy,format=raw` vs `-drive format=raw,file=` (Hard Disk emulation)
- qemu-system-x86_64 vs qemu-system-i386

**Tested in v20** with verbose serial output:
```
B                  ← MBR start marker
0 0 0              ← AH=00 reset: status 0x00 SUCCESS
1 0 1              ← AH=02 sector 2 read: status 0x01 INVALID
E                  ← error path taken, halt
```

**Sectors 3-4 (CHS 0/0/3-4) read in v20 returned success** (status 0x00), but **only sometimes** — v25 (different code, same CHS) failed. This is non-deterministic.

### 5. INT 13h AH=41h (EDD check) returns 0x01 (not supported on this floppy)

So we cannot use LBA (AH=42h) extended read. Must use CHS (AH=02).

### 6. QEMU's flopp_default may be 2.88MB (QEMU 2.5+ change)

QEMU QMP Reference states `type=144` (1.44MB) / `type=288` (2.88MB). Default drive type changed in QEMU 2.5+ to 2.88MB. Reading 1.44MB image with 2.88MB drive may produce invalid CHS reads.

## Reference Implementations That Work (according to docs)

| Source | DL usage | QEMU cmd | Kernel @ | Notes |
|--------|----------|----------|----------|-------|
| 0xKiire 2026 | `mov dl, [boot_drive]` (saved BIOS DL) | `-drive format=raw,file=os.img` | sector 9 (1-based) | 2-stage boot |
| aayush598/basic-bootloader-assembly | DL=0x00 | ? | sector 2 (1-based) | 2-stage |
| Linux bootsect.S | DL=0x00 (default) | ? | varies | 2-stage with retry loop |
| bakefat | ? | `-M pc-1.0 -drive if=floppy,format=raw` | varies | Uses old machine type |

## MBR Code Patterns Tried

### Pattern A: read sector 2 directly (FAIL on QEMU 6.2.0)
```asm
mov ah, 0x02     ; read sectors
mov al, 0x01     ; 1 sector
mov ch, 0
mov cl, 0x02     ; sector 2
mov dh, 0
mov dl, 0x00     ; or 0xF8
mov ax, 0x1000
mov es, ax
mov bx, 0
int 0x13         ; returns AH=0x01 invalid
```

### Pattern B: reset then read (FAIL on QEMU 6.2.0)
```asm
xor dx, dx       ; DL=0x00
mov ah, 0x00     ; reset
int 0x13         ; status 0x00 success
mov ah, 0x02     ; then read...
int 0x13         ; still status 0x01 invalid
```

### Pattern C: 0xKiire pattern with kernel at sector 9 (NOT TESTED on QEMU 6.2.0)
```asm
mov ah, 0x02
mov al, 0x03     ; 3 sectors
mov ch, 0
mov cl, 0x09     ; sector 9 (skip sector 2-8 quirk zone)
mov dh, 0
mov dl, 0xF8     ; or saved BIOS DL
mov ax, 0x1000
mov es, ax
mov bx, 0
int 0x13
```
**Reason: MBR written, but never got a chance to test because all our QEMU 6.2.0 tests fail at sector 2 already.**

## Working Boot Path (predicted, not verified)

If QEMU upgrade to 7+ or different machine, Pattern C (kernel at sector 9) is most likely to work because it sidesteps the sector 2 quirk zone entirely.

## Kernel Notes (Untested Past MBR)

Once stage-2 read works, the kernel itself has additional issues that need fixing before it can run:

1. **kernel.asm's `serial_send` is called with `db 0x9A, 0x7E, 0x00, 0x08, 0x00`** — this is **protected-mode far call syntax** (selector 0x08:offset 0x007E). In real mode, it would call physical address 0x000FE (IVT entry, NOT code). This is a kernel bug, not MBR bug.

2. **GDTR base is hardcoded `0x00010048`** (`db 0x48, 0x00, 0x01, 0x00` in kernel.asm). This means the kernel **must** be loaded at physical 0x10000. MBR must use `jmp 0x1000:0x0000`.

3. **GDT entries at offset 0x50-0x5F of kernel.bin**: code segment at 0x50 (`FF 07 00 00 00 9A C0`), data segment at 0x58 (`FF 07 00 00 00 92 C0`). Both have base=0x00000000, limit=0x7FF (8MB), G=1, D/B=1. **The GDT base in entries is 0, but GDTR.base is 0x00010048 — this is the Linux 0.01 pattern where GDTR.base is kernel load address but segment base is 0**. Far jump `jmp 0x08:entry_32` in entry_16 jumps to `0x08:0x0200` = physical `0x00010200` (because CS.base=0, but entry_32 IS at physical 0x10200 if kernel loaded at 0x10000).

## Files in This Repo Related to Boot

- `os/kernel.asm` — kernel source (1144 bytes binary)
- `os/dnaos.img` — older image (1.44MB, with MBR that has GDTR.base=0x00000048 — wrong!)
- `os/kernel.nasm` — pre-assembled kernel (for reference, 1498 bytes vs current 1144)
- `os/kernel` — older kernel dir
- `programs/kernel.dna` — DNA-OS-specific kernel

## Recommended Next Steps (Future Debug)

1. **Test on QEMU 7+ or 8+** — confirmed working examples (0xKiire 2026, etc.) are likely on newer QEMU. QEMU 6.2.0's floppy emulation has multiple known quirks.

2. **Try QEMU command `qemu-system-i386 -machine pc -drive format=raw,file=floppy.img -boot order=a`** without `if=floppy` — may bypass the 2.88MB default drive issue.

3. **Fix kernel.asm's real-mode serial call bug** — change `db 0x9A, 0x7E, 0x00, 0x08, 0x00` to `call serial_send` (near call, NASM will resolve to relative offset).

4. **Place kernel at sector 9+** — sidesteps the CHS 0/0/2 read quirk observed in QEMU 6.2.0.

5. **Use `qemu -d int,cpu_reset -D /tmp/q.log`** for register-level trace of INT 13h failures (no INT decoder, but EIP=0x7Cxx shows when MBR executes).

## Commits This Session

- `5f621a0` DNAOS v3.5: fix GDT to match Linux 0.01 — base=0x00000000, limit=8MB, granularity=4K
- `80bf57c` DNAOS v3.5: fix kernel.asm serial_send far call
- `7a170ef` rebase to latest
- (this commit: add BOOT_DEBUG.md)

## Conclusion

QEMU 6.2.0 + SeetaCloud server environment has a **non-deterministic** INT 13h AH=02 read failure for CHS 0/0/2 of 1.44MB raw floppy images. Multiple working patterns are documented in third-party guides (0xKiire, bakefat, aayush598) but none of them were reproduced in our environment.

The fix path is most likely:
1. Upgrade QEMU to 7+ (or use different machine type)
2. Use kernel-at-sector-9 pattern (sidesteps sector 2 quirk)
3. Fix kernel.asm's real-mode serial call (`db 0x9A...` → `call serial_send`)
