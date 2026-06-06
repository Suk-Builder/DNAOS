#!/bin/bash
# ============================================================================
# DNAOS v3.3 · Build Script
# 功能: 编译所有汇编源文件 → 链接 → 生成可启动磁盘镜像
# 输出: dnaos.img (可直接dd到U盘或硬盘启动)
# ============================================================================

set -e

echo "========================================================================"
echo " DNAOS v3.3 Build System"
echo "========================================================================"

# ── 工具检查 ──
command -v nasm >/dev/null 2>&1 || { echo "ERROR: nasm not found. Install: apt install nasm"; exit 1; }
command -v ld >/dev/null 2>&1 || { echo "ERROR: ld not found. Install: apt install binutils"; exit 1; }
command -v dd >/dev/null 2>&1 || { echo "ERROR: dd not found. Install: apt install coreutils"; exit 1; }

# ── 目录 ──
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
OUT="$ROOT/out"

mkdir -p "$BUILD" "$OUT"

# ── 常量 ──
DISK_SIZE=$((64 * 1024 * 1024))   # 64MB磁盘镜像
KERNEL_SECTORS=128                  # 内核占128扇区(64KB)
KERNEL_ADDR=0x100000                # 内核加载到1MB

# ═══════════════════════════════════════════════════════════════════════════
# 阶段1: 编译MBR引导扇区
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "[Phase 1] Compiling MBR Boot Sector..."
nasm -f bin \
    -I "$ROOT/boot" \
    "$ROOT/boot/mbr.asm" \
    -o "$BUILD/mbr.bin"

# 验证大小
MBR_SIZE=$(stat -c%s "$BUILD/mbr.bin")
if [ "$MBR_SIZE" -ne 512 ]; then
    echo "ERROR: MBR size is $MBR_SIZE, expected 512 bytes"
    exit 1
fi

# 验证引导签名
SIG=$(xxd -l 2 -s 510 "$BUILD/mbr.bin" | awk '{print $2}')
if [ "$SIG" != "55aa" ]; then
    echo "ERROR: Boot signature is 0x$SIG, expected 0x55AA"
    exit 1
fi

echo "  MBR: $MBR_SIZE bytes ✓ (boot signature: 0x$SIG)"

# ═══════════════════════════════════════════════════════════════════════════
# 阶段2: 编译内核
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "[Phase 2] Compiling Kernel..."

# 编译内核为flat二进制 (无ELF头, 直接机器码)
# 内核入口在0x100000
nasm -f bin \
    -I "$ROOT/kernel" \
    -I "$ROOT/drivers" \
    -I "$ROOT/lib" \
    -D KERNEL_BASE=$KERNEL_ADDR \
    "$ROOT/kernel/main.asm" \
    -o "$BUILD/kernel.bin"

KERNEL_SIZE=$(stat -c%s "$BUILD/kernel.bin")
echo "  Kernel: $KERNEL_SIZE bytes"

# 填充到128扇区(64KB)
KERNEL_PAD=$((KERNEL_SECTORS * 512))
if [ "$KERNEL_SIZE" -gt "$KERNEL_PAD" ]; then
    echo "WARNING: Kernel exceeds $KERNEL_PAD bytes, truncating"
fi

dd if=/dev/zero bs=1 count=$KERNEL_PAD 2>/dev/null | \
    dd of="$BUILD/kernel_padded.bin" bs=1 count=$KERNEL_PAD 2>/dev/null
dd if="$BUILD/kernel.bin" of="$BUILD/kernel_padded.bin" bs=1 \
    conv=notrunc 2>/dev/null

echo "  Kernel padded: $KERNEL_PAD bytes ($KERNEL_SECTORS sectors)"

# ═══════════════════════════════════════════════════════════════════════════
# 阶段3: 组装磁盘镜像
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "[Phase 3] Assembling Disk Image..."

# 创建空白磁盘镜像
dd if=/dev/zero of="$OUT/dnaos.img" bs=$DISK_SIZE count=1 status=none

# 写入MBR到扇区0
dd if="$BUILD/mbr.bin" of="$OUT/dnaos.img" bs=512 count=1 \
    conv=notrunc status=none

# 写入内核到扇区1-128
dd if="$BUILD/kernel_padded.bin" of="$OUT/dnaos.img" bs=512 \
    seek=1 count=$KERNEL_SECTORS conv=notrunc status=none

echo "  Disk: $DISK_SIZE bytes ($(($DISK_SIZE / 1024 / 1024))MB)"
echo "  Layout:"
echo "    Sector 0       : MBR Boot Sector (512B)"
echo "    Sector 1-128   : Kernel (64KB)"
echo "    Sector 129+    : Available for DNA programs / FAT12"

# ═══════════════════════════════════════════════════════════════════════════
# 阶段4: 验证
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "[Phase 4] Verification..."

# 检查引导签名
IMG_SIG=$(xxd -l 2 -s 510 "$OUT/dnaos.img" | awk '{print $2}')
echo "  Boot signature: 0x$IMG_SIG"

# 检查内核是否在正确位置
KERNEL_BYTE=$(xxd -l 4 -s 512 "$OUT/dnaos.img" | awk '{print $2 $3}')
echo "  Kernel first 4 bytes: 0x$KERNEL_BYTE"

# 文件大小
IMG_SIZE=$(stat -c%s "$OUT/dnaos.img")
echo "  Image size: $IMG_SIZE bytes"

# ═══════════════════════════════════════════════════════════════════════════
# 完成
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "========================================================================"
echo " BUILD SUCCESS"
echo "========================================================================"
echo ""
echo " Output: $OUT/dnaos.img"
echo ""
echo " To test with QEMU:"
echo "   qemu-system-x86_64 -drive format=raw,file=$OUT/dnaos.img -m 512"
echo ""
echo " To write to USB drive (replace /dev/sdX):"
echo "   sudo dd if=$OUT/dnaos.img of=/dev/sdX bs=4M status=progress"
echo "   sync"
echo ""
echo " To boot on real hardware:"
echo "   1. Write to USB drive with dd"
echo "   2. Insert USB, power on"
echo "   3. Press F11 (MSI Boot Menu)"
echo "   4. Select 'UEFI: USB Drive' or 'USB-HDD'"
echo ""
echo " Bricklayer continues. 0."
echo "========================================================================"
