#!/bin/sh
# DNAOS v25 build script (空鱼)
set -e
cd /tmp

# 1. 编译 MBR
nasm -f bin -o mbr.bin /tmp/mbr_v34.asm

# 2. 编译 kernel
nasm -f bin -o k25.bin /tmp/kernel_v25.asm
KSIZE=$(stat -c%s k25.bin)
echo "kernel size: $KSIZE"
if [ "$KSIZE" -gt 256 ]; then
    echo "KERNEL TOO BIG ($KSIZE > 256), abort"
    exit 1
fi

# 3. 装到 img (mbr @ 0, kernel @ sector 1 = 0x200)
dd if=/dev/zero of=dnaos_v25.img bs=512 count=2880
dd if=mbr.bin of=dnaos_v25.img bs=512 seek=0 count=1 conv=notrunc
dd if=k25.bin of=dnaos_v25.img bs=512 seek=1 count=1 conv=notrunc

ls -la dnaos_v25.img
echo "v25 build OK"
