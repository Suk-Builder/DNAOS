#!/bin/bash
# DNAOS Build Script — multi-file C kernel
set -e

WORKDIR=/tmp/dnaos_minimal_build
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== DNAOS Build (C kernel) ==="

# Step 1: Assemble boot.S as ELF64
echo "[1/5] Assembling boot.S..."
as --64 -o "$WORKDIR/boot.o" "$SCRIPT_DIR/boot.S"

# Step 2: Compile all .c files as 64-bit freestanding
echo "[2/5] Compiling C sources..."
GCCINC=$(dirname $(gcc -print-file-name=include))
CFLAGS="-m64 -ffreestanding -nostdlib -isystem $GCCINC -fno-builtin -fno-stack-protector -fno-pic -mno-red-zone -mno-sse -Wall -Wextra -c"

for src in "$SCRIPT_DIR"/*.c; do
    base=$(basename "$src" .c)
    echo "  $base.c"
    gcc $CFLAGS -o "$WORKDIR/$base.o" "$src"
done

# Step 3: Link as ELF64
echo "[3/5] Linking (ELF64)..."
OBJS=$(ls "$WORKDIR"/*.o)
ld -T "$SCRIPT_DIR/linker.ld" -o "$WORKDIR/dnaos64.elf" -nostdlib $OBJS

# Step 4: Convert ELF64 → ELF32
echo "[4/5] Converting ELF64 → ELF32..."
python3 << 'PYEOF'
import struct
with open("/tmp/dnaos_minimal_build/dnaos64.elf", "rb") as f:
    data = f.read()
e_phoff = struct.unpack_from('<Q', data, 32)[0]
e_phentsize = struct.unpack_from('<H', data, 54)[0]
e_phnum = struct.unpack_from('<H', data, 56)[0]
e_entry = struct.unpack_from('<Q', data, 24)[0]
segments = []
for i in range(e_phnum):
    off = e_phoff + i * e_phentsize
    p_type = struct.unpack_from('<I', data, off)[0]
    if p_type != 1: continue
    p_offset = struct.unpack_from('<Q', data, off + 8)[0]
    p_vaddr = struct.unpack_from('<Q', data, off + 16)[0]
    p_filesz = struct.unpack_from('<Q', data, off + 32)[0]
    p_memsz = struct.unpack_from('<Q', data, off + 40)[0]
    segments.append((p_offset, p_vaddr, p_filesz, p_memsz))
min_vaddr = min(s[1] for s in segments)
max_end = max(s[1] + s[3] for s in segments)
image = bytearray(max_end - min_vaddr)
for p_offset, p_vaddr, p_filesz, p_memsz in segments:
    image[p_vaddr - min_vaddr : p_vaddr - min_vaddr + p_filesz] = data[p_offset:p_offset+p_filesz]
page_align = 0x1000
ehdr_size = 52
phdr_size = 32
headers_size = ehdr_size + phdr_size
file_offset = (headers_size + page_align - 1) & ~(page_align - 1)
elf32 = bytearray()
elf32 += b'\x7fELF\x01\x01\x01\x00' + b'\x00' * 8
elf32 += struct.pack('<HHIIIIIHHHHHH', 2, 3, 1, e_entry, ehdr_size, 0, 0, ehdr_size, phdr_size, 1, 0, 0, 0)
elf32 += struct.pack('<IIIIIIII', 1, file_offset, min_vaddr, min_vaddr, len(image), len(image), 7, page_align)
elf32 += b'\x00' * (file_offset - len(elf32))
elf32 += bytes(image)
with open("/tmp/dnaos_minimal_build/dnaos.elf", "wb") as f:
    f.write(elf32)
print(f"ELF32: {len(elf32)} bytes, entry=0x{e_entry:x}")
PYEOF

# Step 5: Verify
echo "[5/5] Verifying..."
file "$WORKDIR/dnaos.elf"
echo "Entry: $(readelf -h "$WORKDIR/dnaos.elf" 2>/dev/null | grep 'Entry point' | awk '{print $NF}')"
echo ""
nm "$WORKDIR/dnaos64.elf" | rg 'T ' | sort

cp "$WORKDIR/dnaos.elf" "$SCRIPT_DIR/build/dnaos.elf"
echo ""
echo "=== Build Complete ==="
ls -la "$SCRIPT_DIR/build/dnaos.elf"
