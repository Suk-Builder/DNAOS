#!/bin/sh
# DNAOS M12 FAT12 build (空鱼)
# 简化: 1KB kernel (2 sectors), 16-bit BIOS, 'r' 键读 README.TXT
set -e
cd /tmp

# 1. 编译 MBR (跟 v23 一样, 装 sector 0)
nasm -f bin -o mbr.bin /tmp/mbr_v34.asm

# 2. 编译 kernel (1024B = 2 sectors)
nasm -f bin -o k12.bin /tmp/kernel_fat12.asm
SIZE=$(stat -c%s k12.bin)
echo "kernel size: $SIZE"
if [ "$SIZE" -gt 1024 ]; then
    echo "KERNEL TOO BIG ($SIZE > 1024), abort"
    exit 1
fi

# 3. 创建 README.TXT 内容
cat > /tmp/readme.txt << 'TXTEOF'
DNAOS M12 FAT12 read test line 1
DNAOS M12 FAT12 read test line 2
DNAOS M12 FAT12 read test line 3
TXTEOF

# 4. 装 img (1.44MB)
dd if=/dev/zero of=img_with_readme.img bs=512 count=2880

# 5. 装 MBR + kernel
dd if=mbr.bin of=img_with_readme.img bs=512 seek=0 count=1 conv=notrunc
dd if=k12.bin of=img_with_readme.img bs=512 seek=1 count=2 conv=notrunc

# 6. 装 FAT12 文件系统
# 简化: hardcode 软盘 layout
#   sector 0: MBR
#   sector 1-2: kernel
#   sector 3-11: FAT #1 (9 sectors)
#   sector 12-20: FAT #2 (9 sectors)
#   sector 21-34: Root Directory (14 sectors, 224 entries)
#   sector 35+: Data (cluster 2+)

# 创建 FAT 表 (FAT12, 12-bit entries)
# cluster 0 = 0xFF8 (media), cluster 1 = 0xFFF, cluster 2 = 0xFFF (end of README, 1 sector)
python3 << 'PYEOF'
import struct

# FAT12 entry
def make_fat12(entries):
    out = bytearray()
    for i in range(0, len(entries), 2):
        e1 = entries[i]
        e2 = entries[i+1] if i+1 < len(entries) else 0
        # FAT12: 2 entries in 3 bytes
        # entry[0] = low 8 bits of e1
        # entry[1] = low 4 bits of e2 | high 4 bits of e1
        # entry[2] = high 8 bits of e2
        out.append(e1 & 0xFF)
        out.append(((e2 & 0x0F) << 4) | ((e1 >> 8) & 0x0F))
        out.append((e2 >> 4) & 0xFF)
    return bytes(out)

# 2880 sectors, 1 sector/cluster, 14 root dir sectors
# max cluster = 2880 - 1 (mbr) - 18 (FAT) - 14 (root) = 2847, 实际 cluster 0-2847
# cluster 0 = media descriptor (0xFF8)
# cluster 1 = end of chain (0xFFF)
# cluster 2 = README.TXT first cluster, end at cluster 2 (1 簇 = 1 sector = 512B)

entries = [0xFF8]  # cluster 0
entries.append(0xFFF)  # cluster 1
entries.append(0xFFF)  # cluster 2 = README.TXT (end at 1 簇)
# 其余 0 (free)
while len(entries) < 2880:
    entries.append(0)

fat = make_fat12(entries)
print("FAT size:", len(fat))
# 写到 img sector 3-11
with open('/tmp/img_with_readme.img', 'r+b') as f:
    f.seek(3 * 512)
    f.write(fat)
    # 写 FAT #2 (mirror)
    f.seek(12 * 512)
    f.write(fat)
print("FAT written")

# Root Directory (sector 21-34 = 14 sectors = 224 entries)
# 1 个 entry = README.TXT
def make_dir_entry(name, ext, cluster, size):
    # 32 字节
    e = bytearray(32)
    # name: 8 bytes (空格填充)
    name_padded = (name + '        ')[:8]
    e[0:8] = name_padded.encode('ascii')
    # ext: 3 bytes
    ext_padded = (ext + '   ')[:3]
    e[8:11] = ext_padded.encode('ascii')
    # attr: 0x20 = archive
    e[11] = 0x20
    # reserved
    e[12] = 0
    # creation time 10ms
    e[13] = 0
    # creation time
    e[14:16] = struct.pack('<H', 0)
    # creation date
    e[16:18] = struct.pack('<H', 0)
    # last access date
    e[18:20] = struct.pack('<H', 0)
    # high cluster (FAT32, 0 for FAT12)
    e[20:22] = struct.pack('<H', 0)
    # write time
    e[22:24] = struct.pack('<H', 0)
    # write date
    e[24:26] = struct.pack('<H', 0)
    # low cluster
    e[26:28] = struct.pack('<H', cluster)
    # file size
    e[28:32] = struct.pack('<I', size)
    return bytes(e)

# README.TXT 128B (截断 readme.txt)
readme_data = open('/tmp/readme.txt', 'rb').read()[:512]
readme_size = len(readme_data)

root_dir = bytearray(14 * 512)
# 1 个 entry @ offset 0
root_dir[0:32] = make_dir_entry('README', 'TXT', 2, readme_size)
# entry[1+] = 0 (empty)
# 删除 marker 0xE5 (used)

with open('/tmp/img_with_readme.img', 'r+b') as f:
    f.seek(21 * 512)
    f.write(root_dir)
print("Root dir written, README cluster=2 size=" + str(readme_size))

# Data sector 35 (cluster 2)
with open('/tmp/img_with_readme.img', 'r+b') as f:
    f.seek(35 * 512)
    f.write(readme_data)
    if len(readme_data) < 512:
        # zero-pad
        f.write(b'\x00' * (512 - len(readme_data)))
print("Data written @ sector 35")
PYEOF

ls -la img_with_readme.img
echo "v12 build OK"
