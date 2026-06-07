#!/bin/bash
# ============================================================================
# DNAOS - Quick Build & Run Script
# ============================================================================
# 
# This script builds the DNAOS kernel and runs it in QEMU.
# No installation needed - just run this script.
#
# Prerequisites (auto-installed on Ubuntu/Debian):
#   - nasm, gcc, ld, grub-mkrescue, xorriso, qemu-system-x86
#
# Usage:
#   chmod +x build_and_run.sh
#   ./build_and_run.sh
#
# ============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  DNAOS Build System                  ║${NC}"
echo -e "${GREEN}║  Quaternary Operating System         ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
echo ""

# Check prerequisites
echo -e "${BLUE}[1/5]${NC} Checking prerequisites..."

MISSING=()

command -v nasm >/dev/null 2>&1 || MISSING+=("nasm")
command -v gcc >/dev/null 2>&1 || MISSING+=("gcc")
command -v ld >/dev/null 2>&1 || MISSING+=("ld")
command -v grub-mkrescue >/dev/null 2>&1 || MISSING+=("grub-pc-bin")
command -v xorriso >/dev/null 2>&1 || MISSING+=("xorriso")
command -v qemu-system-x86_64 >/dev/null 2>&1 || MISSING+=("qemu-system-x86")

if [ ${#MISSING[@]} -ne 0 ]; then
    echo -e "${YELLOW}Missing: ${MISSING[*]}${NC}"
    echo -e "Installing..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq nasm gcc grub-pc-bin xorriso qemu-system-x86 2>/dev/null
    echo -e "${GREEN}Installed!${NC}"
else
    echo -e "${GREEN}All prerequisites met.${NC}"
fi

# Build
echo -e "${BLUE}[2/5]${NC} Assembling boot.S..."
nasm -f elf64 kernel/boot.S -o boot.o

echo -e "${BLUE}[3/5]${NC} Compiling kernel..."
gcc -ffreestanding -mno-red-zone -mno-mmx -mno-sse -mno-sse2 \
    -nostdlib -nodefaultlibs -fno-stack-protector -fno-pic \
    -fno-pie -Wall -Wextra -O2 -mcmodel=kernel \
    -c kernel/kernel.c -o kernel.o

nasm -f elf64 kernel/font.S -o font.o

echo -e "${BLUE}[4/5]${NC} Linking..."
ld -nostdlib -T kernel/linker.ld -o dnaos.bin boot.o kernel.o font.o

echo -e "${BLUE}[5/5]${NC} Creating bootable ISO..."
mkdir -p iso/boot/grub
cp dnaos.bin iso/boot/dnaos.bin

cat > iso/boot/grub/grub.cfg << 'EOF'
set timeout=3
set default=0
set color_normal=light-green/black
set color_highlight=green/black

menuentry "DNAOS - Quaternary Operating System" {
    multiboot2 /boot/dnaos.bin
    boot
}

menuentry "DNAOS - Safe Mode (800x600)" {
    multiboot2 /boot/dnaos.bin
    boot
}
EOF

grub-mkrescue -o dnaos.iso iso/ 2>/dev/null

echo ""
echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Build successful!                   ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
echo ""
echo -e "ISO: ${YELLOW}dnaos.iso${NC} ($(du -h dnaos.iso | cut -f1))"
echo ""
echo -e "Run in QEMU:"
echo -e "  ${BLUE}qemu-system-x86_64 -cdrom dnaos.iso -m 512M${NC}"
echo ""
echo -e "Flash to USB (ERASES drive!):"
echo -e "  ${RED}sudo dd if=dnaos.iso of=/dev/sdX bs=4M${NC}"
echo ""
echo -e "Boot on real PC:"
echo -e "  1. Write ISO to USB drive"
echo -e "  2. Boot from USB in BIOS/UEFI"
echo -e "  3. DNAOS loads directly - no Linux, no Python"
echo ""

# Ask to run
read -p "Run in QEMU now? [Y/n] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    qemu-system-x86_64 -cdrom dnaos.iso -m 512M -smp 1 -vga std
fi
