# DNAOS v3.5 Changelog

## v3.5 — 2026-06-12

### M8: Enter Protected Mode ✅

- Kernel now successfully boots to 32-bit protected mode in QEMU 8.2.7
- 10/10 stable boot success rate on `dnaos_v19.img`
- Serial output: `L 1 2 3 4 5 6 7 8 P` (MBR + entry_16 + entry_32)

### What works

- 1.44MB floppy boot from QEMU/SeaBIOS
- MBR with 10-retry INT 13h (workaround for QEMU floppy sector 2 quirk)
- 16-bit real-mode setup (DS, A20, GDTR, CR0.PE)
- 32-bit far jump to flat 4GB GDT
- 32-bit protected mode entry (DS/ES/SS/ESP setup, serial I/O, halt)
- All in pure NASM, no C runtime

### What doesn't (yet)

- No VGA text mode (only serial output on COM1 0x3F8)
- No keyboard input
- No filesystem, no genome, no transcript
- No long mode (32-bit only)
- No IDT, no exception handlers, no paging
- GDT base still hard-coded in binary (build script patches it)

### Files

- `os/dnaos_v19.img` (1.44MB, MD5 `c2bf41fdfbb7c4cc371ee997df13eedc`)
- `os/mbr_retry.bin` (10-retry MBR, 512B)
- `os/kernel_v19.asm` (16-bit entry source)
- `os/entry_32_v19.asm` (32-bit entry source)
- `os/build_v19.sh` (reproducible build + GDTR patch)
- `BOOT_DEBUG.md` (full debugging story)

### Commits

- `567df81` "DNAOS v3.5: WORKING BOOT — full chain B L 1 2 3 4 5 6 7 8 P"
- `f380df8` "DNAOS v3.5: save mbr_retry.bin + working kernel source files"

---

## v3.5 prior (before M8) — 2026-06-11

### Simulator (user-space)

- `simulator/dnasm_exec.c` (16KB VM executor)
- `simulator/transcript/transcript.c` (`dnasm_exec_file()`)
- `simulator/boot.c` rewritten (bench mode + AVal field fix)
- `simulator/dasm.py` (Python DNAsm assembler)
- 15/15 bench programs passing including fibonacci.gene

### Misc

- `Builder-System/digital-psychopathology.md` v0.1
- 32-bit shell code added (not yet bootable)
- GDT fixes (commit 5f621a0, 544ea11, 33414d3, fa9624b)
- BOOT_DEBUG.md v1 (QEMU 6.2.0 floppy sector 2 quirk documented)

---

## Roadmap (v3.6+)

| Milestone | Description | Status |
|-----------|-------------|--------|
| M8 | Enter Protected Mode | ✅ Done (2026-06-12) |
| M9 | VGA text mode + "DNAOS v3.5" splash | ⏳ Next |
| M10 | Real DNAOS shell (keyboard + commands) | ⏳ |
| M11 | Long mode (64-bit) + load genome+transcript | ⏳ |
| M12 | Paging + virtual memory | ⏳ |
| M13 | Multitasking (preemptive scheduler) | ⏳ |
| M14 | ELF loader (load .dna binaries) | ⏳ |
| M15 | Network stack (RTL8139 driver) | ⏳ |
| M16 | Real hardware boot test | ⏳ |
