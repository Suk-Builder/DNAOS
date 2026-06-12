#!/bin/bash
# DNAOS v21 build script (M10: 键盘 + shell, draft)
# - k16 = 256B (v20 working k16)
# - k32 = 4096B (entry_32_v21.asm, padded to 0x1000)
# - kernel.bin = k16 + k32 = 4352B (9 sectors)
# - mbr: /tmp/mbr_v21.bin (patched mbr_retry.bin to read 9 sectors)
# - dnaos_v21.img = mbr (sector 0) + 1 unused sector + 9 sectors kernel (sector 1-9)

set -e
cd /tmp/dnaos_v21

echo "[1/5] 提取 k16 (v20 working)"
cp /tmp/dnaos_v20/k16.bin k16.bin
ls -la k16.bin
echo

echo "[2/5] 编译 k32 (entry_32_v21.asm)"
nasm -f bin entry_32_v21.asm -o k32.bin
ls -la k32.bin
echo

echo "[3/5] 拼成 kernel.bin (k16 + k32 = 4352B = 9 sectors)"
cat k16.bin k32.bin > kernel.bin
ls -la kernel.bin
echo

echo "[4/5] 拼成 dnaos_v21.img (1.44MB floppy)"
# sector 0: patched mbr (9 sectors)
# sector 1-9: kernel.bin (4352B)
dd if=/dev/zero of=dnaos_v21.img bs=512 count=2880 2>/dev/null
dd if=/tmp/mbr_v21.bin of=dnaos_v21.img bs=512 count=1 conv=notrunc 2>&1 | tail -1
dd if=kernel.bin of=dnaos_v21.img bs=512 count=9 seek=1 conv=notrunc 2>&1 | tail -1
ls -la dnaos_v21.img
echo

echo "[5/5] QEMU 测试 (5秒)"
rm -f /tmp/sv21.log
timeout 5 /usr/bin/qemu-system-i386 \
    -fda dnaos_v21.img \
    -serial file:/tmp/sv21.log \
    -display none \
    -no-reboot \
    -m 8M \
    2>&1 | head -3 || true
echo
echo "--- /tmp/sv21.log ---"
cat /tmp/sv21.log
echo "--- end log ---"

cp dnaos_v21.img /tmp/dnaos_v21.img
cp kernel.bin /tmp/kernel_v21.bin
echo "Build complete."
