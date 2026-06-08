#!/bin/bash
# DNAOS Minimal - QEMU Run Script

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ELF="$SCRIPT_DIR/build/dnaos.elf"

if [ ! -f "$ELF" ]; then
    echo "Error: $ELF not found. Run build.sh first."
    exit 1
fi

echo "=== Running DNAOS Minimal in QEMU ==="
echo "Expected: serial output shows 'DNAOS64'"
echo "Press Ctrl+A, X to quit QEMU"
echo ""

# Run with serial output to terminal
qemu-system-x86_64 \
    -kernel "$ELF" \
    -m 128M \
    -nographic \
    -no-reboot
