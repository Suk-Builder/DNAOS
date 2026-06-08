# ============================================================================
# DNAOS Kernel - Complete Build System (DNAsm-native)
# ============================================================================
#
# Build flow:
#   .dna → dasm.py → .nasm → nasm → .o → ld → dnaos.bin → grub → dnaos.iso
#
# Prerequisites:
#   - Python 3 (for dasm.py)
#   - NASM (assembler)
#   - GCC (for linker, not for kernel code)
#   - GRUB (grub-mkrescue)
#   - XORRISO (for ISO)
#   - QEMU (for testing)
#
# ============================================================================

DASM    = python3 dasm/dasm.py
NASM    = nasm
LD      = ld

LDFLAGS = -nostdlib -T kernel/linker.ld -z max-page-size=0x1000

# DNAsm source files
DNA_SRCS = kernel/kernel.dna \
           kernel/mm/pmm.dna \
           kernel/mm/vmm.dna \
           kernel/proc/scheduler.dna \
           kernel/fs/vfs.dna \
           kernel/drivers/keyboard.dna \
           kernel/drivers/mouse.dna \
           kernel/drivers/pit.dna \
           kernel/drivers/pci.dna \
           kernel/drivers/e1000.dna \
           kernel/drivers/vga.dna \
           kernel/drivers/ata.dna \
           kernel/drivers/acpi.dna \
           kernel/drivers/serial.dna \
           kernel/gui/wm.dna \
           kernel/sys/syscall.dna \
           kernel/shell/dnasm.dna

# x86 assembly (boot code, must stay as .S)
ASM_SRCS = kernel/boot.S kernel/font.S

# Generated NASM files
DNA_NASMS = $(patsubst kernel/%.dna,build/%.nasm,$(DNA_SRCS))

# Object files
DNA_OBJS = $(patsubst kernel/%.dna,build/%.o,$(DNA_SRCS))
ASM_OBJS = $(patsubst kernel/%.S,build/%.o,$(ASM_SRCS))

OBJ = $(ASM_OBJS) $(DNA_OBJS)

.PHONY: all clean iso run run-uefi usb dasm-test

all: dnaos.bin

# ============================================================================
# DNAsm → NASM → Object
# ============================================================================

# Create build directories
builddirs:
	@mkdir -p build/mm build/proc build/fs build/drivers build/gui build/sys build/shell

# Compile DNAsm to NASM
build/%.nasm: kernel/%.dna dasm/dasm.py | builddirs
	@echo "  DNAsm  $< → $@"
	@$(DASM) $< -o $@ -n

# Assemble NASM to ELF64
build/%.o: build/%.nasm
	@echo "  NASM   $< → $@"
	@$(NASM) -f elf64 -o $@ $<

# Boot assembly (x86, not DNAsm)
build/boot.o: kernel/boot.S | builddirs
	@echo "  NASM   $< → $@"
	@$(NASM) -f elf64 -o $@ $<

build/font.o: kernel/font.S | builddirs
	@echo "  NASM   $< → $@"
	@$(NASM) -f elf64 -o $@ $<

# ============================================================================
# Link
# ============================================================================

dnaos.bin: $(OBJ)
	@echo "  LD     $@"
	@$(LD) $(LDFLAGS) -o $@ $(OBJ)

# ============================================================================
# ISO
# ============================================================================

iso: dnaos.iso

dnaos.iso: dnaos.bin
	@mkdir -p iso/boot/grub
	@cp dnaos.bin iso/boot/dnaos.bin
	@echo 'set timeout=0' > iso/boot/grub/grub.cfg
	@echo 'set default=0' >> iso/boot/grub/grub.cfg
	@echo '' >> iso/boot/grub/grub.cfg
	@echo 'menuentry "DNAOS - Quaternary Operating System" {' >> iso/boot/grub/grub.cfg
	@echo '    multiboot2 /boot/dnaos.bin' >> iso/boot/grub/grub.cfg
	@echo '    boot' >> iso/boot/grub/grub.cfg
	@echo '}' >> iso/boot/grub/grub.cfg
	@echo '' >> iso/boot/grub/grub.cfg
	@echo 'menuentry "DNAOS - Safe Mode (800x600)" {' >> iso/boot/grub/grub.cfg
	@echo '    multiboot2 /boot/dnaos.bin' >> iso/boot/grub/grub.cfg
	@echo '    boot' >> iso/boot/grub/grub.cfg
	@echo '}' >> iso/boot/grub/grub.cfg
	grub-mkrescue -o dnaos.iso iso/ 2>/dev/null

# ============================================================================
# QEMU
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

# ============================================================================
# USB
# ============================================================================

usb: dnaos.iso
	@echo "WARNING: This will ERASE the target USB drive!"
	@echo "Usage: make usb DEVICE=/dev/sdX"
	@test -n "$(DEVICE)" || (echo "ERROR: Specify DEVICE=/dev/sdX" && exit 1)
	sudo dd if=dnaos.iso of=$(DEVICE) bs=4M status=progress
	sync

# ============================================================================
# DNAsm compiler test
# ============================================================================

dasm-test:
	@echo "Testing DNAsm compiler..."
	@python3 dasm/dasm.py --test
	@echo "All tests passed!"

# ============================================================================
# Clean
# ============================================================================

clean:
	rm -rf build/ *.bin *.iso iso/
