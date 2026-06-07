# ============================================================================
# DNAOS Kernel - Complete Build System
# ============================================================================

CC      = gcc
LD      = ld
NASM    = nasm

CFLAGS  = -ffreestanding -mno-red-zone -mno-mmx -mno-sse -mno-sse2 \
          -nostdlib -nodefaultlibs -fno-stack-protector -fno-pic \
          -fno-pie -Wall -Wextra -O2 -mcmodel=kernel \
          -Ikernel/

LDFLAGS = -nostdlib -T kernel/linker.ld -z max-page-size=0x1000

# Source files
C_SRCS  = kernel/kernel.c
ASM_SRCS = kernel/boot.S kernel/font.S

C_OBJS  = $(C_SRCS:.c=.o)
ASM_OBJS = $(ASM_SRCS:.S=.o)

OBJ     = $(ASM_OBJS) $(C_OBJS)

.PHONY: all clean iso run run-uefi usb

all: dnaos.bin

# ============================================================================
# Compile rules
# ============================================================================

kernel/%.o: kernel/%.S
	$(NASM) -f elf64 -o $@ $<

kernel/%.o: kernel/%.c
	$(CC) $(CFLAGS) -c -o $@ $<

dnaos.bin: $(OBJ)
	$(LD) $(LDFLAGS) -o $@ $(OBJ)

# ============================================================================
# ISO creation (GRUB bootable)
# ============================================================================

iso: dnaos.iso

dnaos.iso: dnaos.bin
	mkdir -p iso/boot/grub
	cp dnaos.bin iso/boot/dnaos.bin
	
	echo 'set timeout=3' > iso/boot/grub/grub.cfg
	echo 'set default=0' >> iso/boot/grub/grub.cfg
	echo '' >> iso/boot/grub/grub.cfg
	echo 'menuentry "DNAOS - Quaternary OS (1280x720)" {' >> iso/boot/grub/grub.cfg
	echo '    multiboot2 /boot/dnaos.bin' >> iso/boot/grub/grub.cfg
	echo '    boot' >> iso/boot/grub/grub.cfg
	echo '}' >> iso/boot/grub/grub.cfg
	echo '' >> iso/boot/grub/grub.cfg
	echo 'menuentry "DNAOS - Safe Mode (640x480)" {' >> iso/boot/grub/grub.cfg
	echo '    multiboot2 /boot/dnaos.bin' >> iso/boot/grub/grub.cfg
	echo '    boot' >> iso/boot/grub/grub.cfg
	echo '}' >> iso/boot/grub/grub.cfg
	
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

run-debug: dnaos.iso
	qemu-system-x86_64 -cdrom dnaos.iso -m 512M -smp 1 \
		-vga std -serial stdio -s -S
	# In another terminal: gdb -ex "target remote :1234"

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
	rm -f kernel/*.o *.bin *.iso
	rm -rf iso/
