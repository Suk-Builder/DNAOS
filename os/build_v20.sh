#!/bin/bash
# DNAOS v20 build script (M9: VGA splash)
# Uses pre-existing k16 from v19 (verified working) + new entry_32_v20 with VGA
#
# This is the v20 strategy: don't touch the working k16, only swap in new k32.

set -e

WORKDIR=/tmp/dnaos_v20
cd $WORKDIR

# Verify we have a k16 from v19 (or get it)
if [ ! -f k16.bin ]; then
    echo "Extracting k16 from working kernel_v19.bin..."
    python3 -c "
k = open('/tmp/kernel_v19.bin', 'rb').read()
assert len(k) == 1024, f'kernel_v19.bin must be 1024 bytes, got {len(k)}'
open('k16.bin', 'wb').write(k[:256])
"
fi

# Use the new v20 entry_32 (with VGA splash)
cp entry_32_v20.asm k32.asm

# Assemble k32
nasm -f bin k32.asm -o k32.bin
echo "k32 size: $(stat -c%s k32.bin)"

# Combine: k16 (256B) + k32 (256B) = 512B, pad to 1024B
cat k16.bin > kernel.bin
cat k32.bin >> kernel.bin
truncate -s 1024 kernel.bin
echo "kernel size: $(stat -c%s kernel.bin)"

# Verify
python3 -c "
k = open('kernel.bin', 'rb').read()
gdtr = k[0x70:0x76]
print('GDTR:', ' '.join(f'{b:02x}' for b in gdtr))
gdt = k[0x78:0x90]
print('GDT:', ' '.join(f'{b:02x}' for b in gdt))
print('Far jmp at 0x3A:', ' '.join(f'{b:02x}' for b in k[0x3A:0x42]))
print('k32 first 16B:', ' '.join(f'{b:02x}' for b in k[0x100:0x110]))
print('k32 size effective:', sum(1 for b in k[0x100:0x200] if b != 0x90), 'non-NOP bytes')
"

# Build floppy
MBR_BIN=/tmp/mbr_retry.bin
[ -f $MBR_BIN ] || MBR_BIN=/workspace/dnaos_review/os/mbr_retry.bin

dd if=/dev/zero of=image.img bs=512 count=2880 2>/dev/null
dd if=$MBR_BIN of=image.img conv=notrunc 2>/dev/null
dd if=kernel.bin of=image.img conv=notrunc seek=1 bs=512 2>/dev/null

cp image.img /tmp/dnaos_v20.img
cp kernel.bin /tmp/kernel_v20.bin
echo "Image: /tmp/dnaos_v20.img (MD5: $(md5sum image.img | cut -d' ' -f1))"
ls -la /tmp/dnaos_v20.img /tmp/kernel_v20.bin
