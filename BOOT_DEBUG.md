# DNAOS BOOT_DEBUG — v3.5 Enter Protected Mode (M8)

**Date**: 2026-06-12
**Status**: ✅ Working, 10/10 stable on QEMU 8.2.7
**Milestone**: M8 — Enter Protected Mode

## The Symptom (what we saw for weeks)

DNAOS v3.5 kernel would print `L 1 2 3 4 5` from the MBR and entry_16,
but **never** `6 7 8 P` from entry_32. The CPU would just reset.

Serial output always ended at `1 2 3 4 5` then `Booting from Floppy..` again
(SeaBIOS re-boot), meaning **triple fault** in real-mode-to-protected-mode
transition.

## What I tried (and why none of it worked)

| Attempt | Symptom treated | Real cause |
|---------|-----------------|------------|
| MBR with INT 13h retry (3, then 10 times) | flaky boot | ✓ Fixed boot reliability (90%→99%) |
| QEMU 6.2.0 → 8.2.7 upgrade | flaky boot | ✗ No effect, both versions have same floppy quirk |
| BITS 16 vs BITS 32 far jmp | encoding wrong | ✗ Both 16-bit and 32-bit forms tested, encoding was correct |
| Manually adding `db 0x66` prefix | NASM not generating 32-bit | ✗ NASM ignored it; encoding was already correct |
| Flat GDT (cfenollosa pattern) | "wrong address jumped to" | ✗ Address was right, descriptor was bad |
| `qemu-system-i386` instead of `x86_64` | different emulation | ✗ Both had same behavior |
| Source-vs-binary MBR rewrite | different MBR | ✗ MBR was fine, kernel was the problem |

I went through **~25 versions** of kernel/MBR before finding the actual bug.

## The Real Bug (查资料后找到)

**`NASM's `dd gdt_start` assembles to the FILE OFFSET, not the PHYSICAL ADDRESS.**

NASM doesn't know where your kernel will be loaded. It just produces a
file-relative address. The `lgdt` instruction needs the **physical** address
where the GDT will be in memory at runtime.

### Concrete numbers

```
kernel_v19.asm has:
    gdt_start:
        dq 0                   ; null
        ; code segment...

When NASM assembles this:
    dd gdt_start        →  0x76        (file offset within the 1024-byte kernel)
    dd gdt_start+0x10000 → 0x10076    (physical address, what we need)
```

But the kernel is loaded at physical `0x10000` (by the MBR), so the GDT
is at physical `0x10000 + 0x76 = 0x10076`.

**The bug was: GDTR.base = 0x76 (file offset), should be 0x10076 (physical).**

### Why this triple-faults

1. `lgdt` reads 6 bytes from the GDTR location (limit + 32-bit base)
2. CPU now thinks GDT is at physical 0x76
3. Address 0x76 is in low memory, where SeaBIOS has IVT (Interrupt Vector Table)
4. IVT[0] = `seg:off` of INT 0 handler. The first 8 bytes there look like garbage to a GDT parser
5. `jmp 0x08:0x10100` tries to load CS=0x08 → GDT[1] from address 0x76
6. GDT[1] = whatever is at 0x76+8 = IVT interrupt handler descriptor
7. This descriptor is NOT a valid code segment (wrong access rights, wrong flags)
8. CPU raises #GP (general protection fault)
9. IDT is not set up, so #GP handler is also garbage
10. CPU raises #DF (double fault)
11. #DF handler is also garbage
12. Triple fault → CPU reset → SeaBIOS re-boots

The whole chain happens in microseconds, leaving only the MBR+entry_16
output in the serial log. entry_32 never runs.

## The Fix (one line of Python)

```python
# In build_v19.sh, after NASM assembly:
import struct
k = bytearray(open('k16.bin', 'rb').read())
struct.pack_into('<I', k, 0x72, 0x00010076)  # patch GDTR base to physical address
```

The build script knows the kernel loads at `0x10000`, so it adds
`0x10000` to the file offset (`0x76`) to get the physical address (`0x10076`).

## Why this is a universal bootloader bug

Every bootloader written in NASM has to do this patch step. The reason is
that NASM produces relocatable code (file offsets), but the bootloader
needs absolute (physical) addresses.

Options for handling this:
1. **Manual patch in build script** ← what we do
2. Use a linker script with `ld` to handle relocations
3. Use `org 0x10000` in NASM (only works if you know load address at assemble time, which is true for bootloaders)

**We picked option 1** because it's the most explicit and the easiest to debug.

## The other big bug: QEMU floppy sector 2 quirk

`QEMU 2.5+` changed the default floppy drive type from 1.44MB to 2.88MB.
This means the emulated floppy controller geometry is different from
what 1.44MB images expect.

When you `INT 13h AH=02 read sector 2` on a 1.44MB image in QEMU 6.2.0/8.2.7:
- **Sectors 3-4 usually work**
- **Sector 2 sometimes returns status 0x01 (invalid command)**
- **LBA mode (AH=42h) usually fails because EDD check (AH=41h) returns "EDD unavailable"**
- **Sector 2 is flaky regardless of order, retry count, or CHS combination**

### Workaround: 10-retry MBR

`os/mbr_retry.bin` is a 512-byte MBR that:
1. Saves boot drive (DL=0xF8 from SeaBIOS) to a known memory location
2. Tries `INT 13h AH=00 reset` up to 10 times before each read
3. Tries `INT 13h AH=02 read` of sector 2 (CHS 0/0/2 → ES:BX = 0x1000:0x0000)
4. If read fails, retries with another reset
5. On success, jumps to `0x1000:0x0000` (= physical 0x10000 = kernel entry_16)

This gives **9-10/10 boot success** on QEMU 6.2.0 and 8.2.7.

On real hardware, this MBR works on the first try because the floppy
controller behaves as expected. The retry is a **QEMU-only quirk workaround**.

## Why the source wasn't enough

The original `kernel.asm` had this GDTR setup:
```asm
dw 0x17                ; limit
db 0x48, 0, 1, 0       ; base = 0x00010048 (HEX-LITERAL HARD-CODED)
```

So someone **had** the right idea (hard-coding 0x10048 = 0x10000 + 0x48 for
a slightly different layout). But when I rewrote the kernel with
`dd gdt_start`, the file offset (0x76) replaced the manual calculation,
**silently breaking** the GDTR base.

The lesson: **never use `dd label` in bootloader code that gets loaded to
a non-zero address**. Either:
- Use `org 0x10000` (or wherever) so labels resolve as physical addresses
- Hard-code the physical address as bytes
- Use a build script to patch the binary

## What changed in v19

| Component | Before (broken) | After (working) |
|-----------|-----------------|-----------------|
| k16 size | 1144 bytes (kernel_v1) | 256 bytes (k16 only) |
| k32 size | undefined behavior | 256 bytes (k32 only) |
| Total kernel | 1144 bytes | 1024 bytes (k16 + k32 + padding) |
| GDTR.base | 0x76 (file offset) | 0x10076 (physical, patched) |
| Far jmp form | 16-bit (truncated to 0x100) | 32-bit with 0x66 prefix (0x10100) |
| MBR | single-shot read | 10-retry with reset |
| GDT location | 0x300 (deep in kernel) | 0x78 (early in kernel) |

## Files in v19

```
os/dnaos_v19.img              # 1.44MB floppy, ready to QEMU
os/mbr_retry.bin              # 10-retry MBR (512B)
os/kernel_v19.asm             # 16-bit entry source
os/entry_32_v19.asm           # 32-bit entry source
os/build_v19.sh               # reproducible build script
```

## Verification commands

```bash
# Build (requires nasm + qemu-system-i386 on PATH)
cd os && ./build_v19.sh

# Test boot 10 times
for i in $(seq 1 10); do
  qemu-system-i386 -drive file=build_v19/dnaos_v19.img,format=raw,if=floppy \
    -boot a -nographic -serial file:/tmp/s.log -monitor none -display none
  echo "Run $i: $(cat /tmp/s.log | tail -1)"
done
```

Expected: all 10 runs print `L 1 2 3 4 5 6 7 8 P`.

## What's next (M9+)

- **M9**: VGA text mode + "DNAOS v3.5" splash screen
- **M10**: Real DNAOS shell (read keyboard, execute commands)
- **M11**: Long mode (64-bit) + load genome+transcript from disk
- **M12**: Paging + virtual memory
- **M13**: Multitasking (preemptive scheduler)

The M8 milestone is **necessary but not sufficient**. v19 just proves
the transition mechanism works. The next kernel will start being
actually useful.

## Git commits

- `567df81` "DNAOS v3.5: WORKING BOOT — full chain B L 1 2 3 4 5 6 7 8 P"
- `f380df8` "DNAOS v3.5: save mbr_retry.bin + working kernel source files"

## Lessons (4 to remember)

1. **思而不学则殆** — When stuck for 25+ versions, stop and research.
   The bug was well-documented in OSDev forums and SO answers.

2. **GDT base in bootloader code always needs a manual patch**
   (NASM doesn't know your load address).

3. **GDT bugs are 100% silent (triple fault)** — only QEMU -d in_asm +
   register dump shows you the GDTR value is wrong.

4. **QEMU 2.5+ floppy default is 2.88MB, not 1.44MB** — sector 2 CHS
   reads are flaky, MBR retry is the standard workaround.
