#!/bin/bash
# Build DNAOS v19 working kernel image
# Requires: nasm, qemu-system-i386 (or x86_64)
# Run on a Linux host with access to these tools.

set -e

OS_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${OS_DIR}/build_v19"
mkdir -p "$BUILD_DIR"

echo "=== Building DNAOS v19 ==="

# Assemble k16 (16-bit real-mode setup)
nasm -f bin -o "$BUILD_DIR/k16.bin" "$OS_DIR/kernel_v19.asm"

# Assemble k32 (32-bit protected-mode entry)
nasm -f bin -o "$BUILD_DIR/k32.bin" "$OS_DIR/entry_32_v19.asm"

# Patch GDTR base (fix NASM file-offset vs physical-address issue)
# The GDTR is at k16 offset 0x70-0x77. NASM sets the base to the file offset (0x76),
# but we need the PHYSICAL address (0x10000 + 0x76 = 0x10076).
python3 -c "
import struct
k = bytearray(open('$BUILD_DIR/k16.bin', 'rb').read())
struct.pack_into('<I', k, 0x72, 0x00010076)  # GDT base = physical 0x10076
open('$BUILD_DIR/k16_patched.bin', 'wb').write(bytes(k))
print('GDTR base patched to 0x00010076')
"

# Build the kernel: k16 (256B) + k32 (256B) = 512B, padded to 1024B
python3 -c "
k16 = open('$BUILD_DIR/k16_patched.bin', 'rb').read()
k32 = open('$BUILD_DIR/k32.bin', 'rb').read()
assert len(k16) == 256
assert len(k32) == 256
kernel = k16 + k32 + b'\\x00' * 512  # pad to 1024
open('$BUILD_DIR/kernel.bin', 'wb').write(kernel)
print(f'kernel.bin: {len(kernel)} bytes')
"

# Build the floppy image: MBR (512B) + kernel (1024B) + padding
python3 -c "
img = bytearray(1440 * 1024)  # 1.44MB
mbr = open('$OS_DIR/mbr_retry.bin', 'rb').read()
assert len(mbr) == 512
kernel = open('$BUILD_DIR/kernel.bin', 'rb').read()
img[:512] = mbr
img[512:512 + len(kernel)] = kernel
open('$BUILD_DIR/dnaos_v19.img', 'wb').write(bytes(img))
print(f'dnaos_v19.img: {len(img)} bytes')
"

# Verify
python3 -c "
img = open('$BUILD_DIR/dnaos_v19.img', 'rb').read()
mbr = img[0:512]
kernel = img[512:512+1024]
print(f'MBR == mbr_retry.bin: {mbr == open(\"$OS_DIR/mbr_retry.bin\", \"rb\").read()}')
# Verify far jmp
for i in range(0, 0x80):
    if kernel[i] == 0x66 and kernel[i+1] == 0xEA:
        off = int.from_bytes(kernel[i+2:i+6], 'little')
        seg = int.from_bytes(kernel[i+6:i+8], 'little')
        print(f'Far jmp at k16+0x{i:04x}: offset=0x{off:08x} seg=0x{seg:04x}')
# Verify GDTR
print(f'GDTR (kernel[0x70]): {kernel[0x70:0x78].hex()}')
# Verify entry_32 first byte
print(f'entry_32 first byte: 0x{kernel[0x100]:02x} (expect 0x66)')
"

echo ""
echo "=== Test boot in QEMU ==="
QEMU="${QEMU:-qemu-system-i386}"
"$QEMU" -drive "file=$BUILD_DIR/dnaos_v19.img,format=raw,if=floppy" -boot a -nographic \
        -serial "file:$BUILD_DIR/serial.log" -monitor none -display none || true
echo "=== Serial output ==="
cat "$BUILD_DIR/serial.log" 2>/dev/null || echo "(no serial output)"
echo ""
echo "=== Expected: 'L12345678P' (full boot chain) ==="
