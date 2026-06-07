# ============================================================================
# DNAOS Kernel - Build System
# ============================================================================
# 
# Prerequisites:
#   - NASM (assembler)
#   - GCC x86_64 cross-compiler (or system gcc with -ffreestanding)
#   - GRUB (grub-mkrescue)
#   - XORRISO (for ISO creation)
#   - QEMU (for testing)
#
# Build:
#   make              # Build kernel
#   make iso          # Create bootable ISO
#   make run          # Test in QEMU
#   make usb          # Flash to USB drive
#
# ============================================================================

CC      = gcc
LD      = ld
NASM    = nasm
CFLAGS  = -ffreestanding -mno-red-zone -mno-mmx -mno-sse -mno-sse2 \
          -nostdlib -nodefaultlibs -fno-stack-protector -fno-pic \
          -fno-pie -Wall -Wextra -O2 -mcmodel=kernel
LDFLAGS = -nostdlib -T kernel/linker.ld

OBJ = boot.o kernel.o font.o

.PHONY: all clean iso run usb

all: dnaos.bin

boot.o: kernel/boot.S
	$(NASM) -f elf64 $< -o $@

kernel.o: kernel/kernel.c
	$(CC) $(CFLAGS) -c $< -o $@

font.o: kernel/font.S
	$(NASM) -f elf64 $< -o $@

dnaos.bin: $(OBJ)
	$(LD) $(LDFLAGS) -o $@ $(OBJ)

# ============================================================================
# ISO creation (bootable USB/CD)
# ============================================================================
iso: dnaos.iso

dnaos.iso: dnaos.bin
	mkdir -p iso/boot/grub
	cp dnaos.bin iso/boot/dnaos.bin
	
	# GRUB config
	echo 'set timeout=0' > iso/boot/grub/grub.cfg
	echo 'set default=0' >> iso/boot/grub/grub.cfg
	echo '' >> iso/boot/grub/grub.cfg
	echo 'menuentry "DNAOS - Quaternary Operating System" {' >> iso/boot/grub/grub.cfg
	echo '    multiboot2 /boot/dnaos.bin' >> iso/boot/grub/grub.cfg
	echo '    boot' >> iso/boot/grub/grub.cfg
	echo '}' >> iso/boot/grub/grub.cfg
	
	# GRUB theme
	echo 'menu_color_normal=light-green/black' >> iso/boot/grub/grub.cfg
	echo 'menu_color_highlight=green/black' >> iso/boot/grub/grub.cfg
	
	grub-mkrescue -o dnaos.iso iso/ 2>/dev/null || \
		echo "ERROR: grub-mkrescue failed. Install: sudo apt install grub-pc-bin xorriso"

# ============================================================================
# QEMU testing
# ============================================================================
run: dnaos.iso
	qemu-system-x86_64 -cdrom dnaos.iso -m 512M -smp 1 \
		-vga std -serial stdio

run-uefi: dnaos.iso
	qemu-system-x86_64 -cdrom dnaos.iso -m 512M -smp 1 \
		-bios /usr/share/OVMF/OVMF_CODE.fd \
		-vga std -serial stdio

# ============================================================================
# USB flash
# ============================================================================
usb: dnaos.iso
	@echo "WARNING: This will ERASE the target USB drive!"
	@echo "Usage: make usb DEVICE=/dev/sdX"
	@test -n "$(DEVICE)" || (echo "ERROR: Specify DEVICE=/dev/sdX" && exit 1)
	sudo dd if=dnaos.iso of=$(DEVICE) bs=4M status=progress
	sync

# ============================================================================
# Clean
# ============================================================================
clean:
	rm -f *.o *.bin *.iso
	rm -rf iso/
