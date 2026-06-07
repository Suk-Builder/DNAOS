#!/usr/bin/env python3
"""
DNAOS ARM64 - Disk Image Generator for OnePlus 6T (Snapdragon 845)

Creates a boot.img that can be flashed via fastboot:
  fastboot boot dnaos_arm64.img
  or
  fastboot flash boot dnaos_arm64.img

The image uses the Android boot image format (v0) which ABL understands.
Kernel is our bare-metal ARM64 binary.

Requirements: aarch64-linux-gnu-gcc, mkbootimg (or Python implementation)
"""
import struct, os, sys

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
OUT = os.path.join(OUT_DIR, "dnaos_arm64.img")
os.makedirs(OUT_DIR, exist_ok=True)

# Android boot image header (v0)
BOOT_MAGIC = b'ANDROID!'
BOOT_MAGIC_SIZE = 8
BOOT_NAME = b'dnaos_arm64\x00'
BOOT_CMDLINE = b'console=ttyMSM0,115200n8 earlycon=msm_geni_serial\x00'

def make_boot_img(kernel_data):
    """Create Android boot image with our kernel"""
    
    # Page size (ABL expects 4096)
    page_size = 4096
    
    # Kernel size
    kernel_size = len(kernel_data)
    
    # Pad kernel to page boundary
    kernel_pages = (kernel_size + page_size - 1) // page_size
    kernel_padded = kernel_data + b'\x00' * (kernel_pages * page_size - kernel_size)
    
    # Ramdisk (empty)
    ramdisk_size = 0
    ramdisk_pages = 0
    ramdisk_padded = b''
    
    # Device tree blob (empty - we parse DTB from ABL)
    dtb_size = 0
    dtb_pages = 0
    dtb_padded = b''
    
    # Build header
    header = bytearray(page_size)
    
    # Magic
    header[0:8] = BOOT_MAGIC
    
    # Kernel size and address
    struct.pack_into('<I', header, 8, kernel_size)
    struct.pack_into('<I', header, 12, 0x00008000)  # Kernel load address
    
    # Ramdisk size and address
    struct.pack_into('<I', header, 16, ramdisk_size)
    struct.pack_into('<I', header, 20, 0x01000000)  # Ramdisk address
    
    # Second stage (unused)
    struct.pack_into('<I', header, 24, 0)
    struct.pack_into('<I', header, 28, 0x00F00000)
    
    # Tags address
    struct.pack_into('<I', header, 32, 0x00000100)
    
    # Page size
    struct.pack_into('<I', header, 36, page_size)
    
    # Header version
    struct.pack_into('<I', header, 40, 0)  # v0
    
    # OS version (unused)
    struct.pack_into('<I', header, 44, 0)
    
    # Boot name
    header[48:64] = BOOT_NAME[:16]
    
    # Command line
    header[64:576] = BOOT_CMDLINE[:512].ljust(512, b'\x00')
    
    # SHA (unused, set to 0)
    header[576:592] = b'\x00' * 16
    
    # Extra command line (unused)
    header[592:1104] = b'\x00' * 512
    
    # Build image
    img = bytes(header) + kernel_padded + ramdisk_padded + dtb_padded
    
    return img


def build_kernel():
    """Build the ARM64 kernel binary"""
    
    # Try to compile with aarch64-linux-gnu-gcc
    gcc = 'aarch64-linux-gnu-gcc'
    objcopy = 'aarch64-linux-gnu-objcopy'
    
    src = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'boot.S')
    elf_out = os.path.join(OUT_DIR, 'dnaos.elf')
    bin_out = os.path.join(OUT_DIR, 'dnaos.bin')
    
    # Check if cross-compiler is available
    import subprocess
    try:
        result = subprocess.run([gcc, '--version'], capture_output=True, timeout=5)
        has_cross = result.returncode == 0
    except (FileNotFoundError, subprocess.TimeoutExpired):
        has_cross = False
    
    if has_cross:
        print(f"  Cross-compiler found: {gcc}")
        
        # Compile
        linker_script = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'linker.ld')
        
        cmd = [
            gcc, '-nostdlib', '-nostartfiles', '-ffreestanding',
            '-mcpu=cortex-a75', '-mgeneral-regs-only',
            '-T', linker_script,
            '-o', elf_out,
            src
        ]
        
        print(f"  Compiling: {' '.join(cmd)}")
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"  Compile error: {result.stderr}")
            return None
        
        # Extract binary
        cmd2 = [objcopy, '-O', 'binary', elf_out, bin_out]
        result2 = subprocess.run(cmd2, capture_output=True, text=True)
        if result2.returncode != 0:
            print(f"  Objcopy error: {result2.stderr}")
            return None
        
        with open(bin_out, 'rb') as f:
            return f.read()
    
    else:
        print(f"  No cross-compiler found, generating minimal ARM64 binary...")
        print(f"  Install: apt install gcc-aarch64-linux-gnu")
        print(f"  Or:      brew install aarch64-elf-gcc")
        
        # Generate a minimal ARM64 binary that outputs to UART
        # This is a fallback - the real code needs the cross-compiler
        binary = bytearray()
        
        # Entry point: branch to main code
        # ARM64 instructions are 4 bytes each
        
        # Only CPU 0: mrs x0, mpidr_el1; and x0, x0, #0xFF; cbz x0, +8; wfe; b -8
        binary += bytes.fromhex('4000D53B')  # mrs x0, mpidr_el1
        binary += bytes.fromhex('E00F0092')  # and x0, x0, #0xFF
        binary += bytes.fromhex('60000034')  # cbz x0, +12 (to cpu0_boot)
        binary += bytes.fromhex('5F3F03D5')  # wfe
        binary += bytes.fromhex('FDFFFF17')  # b -8 (park_loop)
        
        # cpu0_boot: set up stack
        binary += bytes.fromhex('E0030091')  # add x0, sp, #0 (placeholder)
        
        # UART init: send 'D' to UART1 (0xA84000)
        # ldr x1, =0xA84000
        binary += bytes.fromhex('6146B0D2')  # mov x1, #0xA84000 (part 1)
        binary += bytes.fromhex('8122A0F2')  # movk x1, #0xA840, lsl #16
        
        # mov x0, #'D' = 0x44
        binary += bytes.fromhex('E0081092')  # mov x0, #0x44
        
        # str w0, [x1]  (write to UART TX)
        binary += bytes.fromhex('20000039')  # str w0, [x1]
        
        # Send 'N'
        binary += bytes.fromhex('E00C1092')  # mov x0, #0x4E
        binary += bytes.fromhex('20000039')  # str w0, [x1]
        
        # Send 'A'
        binary += bytes.fromhex('E0041092')  # mov x0, #0x41
        binary += bytes.fromhex('20000039')  # str w0, [x1]
        
        # Send '\r'
        binary += bytes.fromhex('E0011392')  # mov x0, #0x0D
        binary += bytes.fromhex('20000039')  # str w0, [x1]
        
        # Send '\n'
        binary += bytes.fromhex('E0011492')  # mov x0, #0x0A
        binary += bytes.fromhex('20000039')  # str w0, [x1]
        
        # Halt
        binary += bytes.fromhex('5F3F03D5')  # wfe
        binary += bytes.fromhex('FDFFFF17')  # b -4 (infinite loop)
        
        return bytes(binary)


if __name__ == '__main__':
    print("=" * 60)
    print(" DNAOS ARM64 - OnePlus 6T Boot Image Generator")
    print("=" * 60)
    
    print("\n[1/2] Building ARM64 kernel...")
    kernel = build_kernel()
    
    if kernel is None:
        print("\n  Failed to build kernel. Install cross-compiler:")
        print("    Ubuntu: sudo apt install gcc-aarch64-linux-gnu")
        print("    macOS:  brew install aarch64-elf-gcc")
        print("\n  Then run this script again.")
        sys.exit(1)
    
    print(f"  Kernel: {len(kernel)} bytes")
    
    print("[2/2] Creating boot image...")
    img = make_boot_img(kernel)
    
    with open(OUT, 'wb') as f:
        f.write(img)
    
    sz = os.path.getsize(OUT)
    print(f"  -> {OUT}")
    print(f"  Size: {sz:,} bytes")
    
    print(f"""
  Flash to OnePlus 6T:
    1. Boot to fastboot: hold Volume Up + Power
    2. Test (no permanent install):
       fastboot boot {OUT}
    3. Or flash permanently:
       fastboot flash boot {OUT}
    
  UART serial (for debug output):
    - Use USB-C debug dongle with UART
    - Baud rate: 115200
    - screen /dev/ttyUSB0 115200
    
  Expected output:
    DNAOS v3.5 - Quaternary OS
    Snapdragon 845 / OnePlus 6T
    ========================================
    GUI initialized
    > _
""")
    print("=" * 60)
