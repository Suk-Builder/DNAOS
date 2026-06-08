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
           kernel/shell/dnasm.dna \
           kernel/net/tcpip.dna \
           kernel/lib/stdlib.dna \
           kernel/boot/compiler.dna \
           kernel/gfx/math3d.dna \
           kernel/gfx/rasterizer.dna \
           kernel/gfx/texture.dna \
           kernel/gfx/scene.dna \
           kernel/gfx/mesh.dna \
           kernel/gfx/shader.dna \
           kernel/engine/physics.dna \
           kernel/engine/audio.dna \
           kernel/engine/entity.dna \
           kernel/engine/input.dna \
           kernel/engine/tsukuyomi.dna \
           kernel/engine/worldgen.dna \
           kernel/engine/animation.dna \
           kernel/engine/ui.dna \
           kernel/engine/particles.dna \
           kernel/engine/scriptvm.dna \
           kernel/gfx/sky.dna \
           kernel/gfx/shadow.dna \
           kernel/gfx/water.dna \
           kernel/gfx/post/postfx.dna \
           kernel/engine/vegetation/vegetation.dna \
           kernel/engine/arch/architecture.dna \
           kernel/engine/arch/hologram.dna \
           kernel/engine/arch/kassen.dna \
           kernel/engine/arch/live.dna \
           kernel/engine/voice.dna \
           kernel/engine/lyrics.dna \
           kernel/engine/yachiyo.dna \
           kernel/engine/consciousness.dna \
           kernel/engine/iroha.dna \
           kernel/engine/kaguya.dna \
           kernel/engine/opening.dna \
           kernel/engine/ar_live.dna

# Assembly source files (hardware-required, not DNAsm)
ASM_SRCS = kernel/boot.S \
           kernel/font.S

# Build directory
BUILDDIR = build

# Object files
DNA_NASMS = $(patsubst kernel/%.dna,$(BUILDDIR)/%.nasm,$(DNA_SRCS))
DNA_OBJS  = $(patsubst kernel/%.dna,$(BUILDDIR)/%.o,$(DNA_SRCS))
ASM_OBJS  = $(patsubst kernel/%.S,$(BUILDDIR)/%.o,$(ASM_SRCS))

OBJ = $(ASM_OBJS) $(DNA_OBJS)

.PHONY: all clean iso run run-uefi usb dasm-test compile check

all: dnaos.bin

# ============================================================================
# Build directory
# ============================================================================

$(BUILDDIR):
        mkdir -p $(BUILDDIR)
        mkdir -p $(BUILDDIR)/mm
        mkdir -p $(BUILDDIR)/proc
        mkdir -p $(BUILDDIR)/fs
        mkdir -p $(BUILDDIR)/drivers
        mkdir -p $(BUILDDIR)/gui
        mkdir -p $(BUILDDIR)/sys
        mkdir -p $(BUILDDIR)/shell
        mkdir -p $(BUILDDIR)/net
        mkdir -p $(BUILDDIR)/lib
        mkdir -p $(BUILDDIR)/boot
        mkdir -p $(BUILDDIR)/gfx
        mkdir -p $(BUILDDIR)/gfx/post
        mkdir -p $(BUILDDIR)/engine
        mkdir -p $(BUILDDIR)/engine/vegetation
        mkdir -p $(BUILDDIR)/engine/arch

# ============================================================================
# Compile DNAsm → NASM → ELF64
# ============================================================================

# Step 1: DNAsm → NASM
$(BUILDDIR)/%.nasm: kernel/%.dna | $(BUILDDIR)
        @echo "DNAsm  $< → $@"
        @$(DASM) $< -o $@ -n

# Step 2: NASM → ELF64 object
$(BUILDDIR)/%.o: $(BUILDDIR)/%.nasm
        @echo "NASM   $< → $@"
        @$(NASM) -f elf64 -o $@ $<

# Assembly files (boot.S, font.S) → ELF64 directly
$(BUILDDIR)/%.o: kernel/%.S | $(BUILDDIR)
        @echo "NASM   $< → $@"
        @$(NASM) -f elf64 -o $@ $<

# ============================================================================
# Link
# ============================================================================

dnaos.bin: $(OBJ)
        @echo "LD     $@"
        @$(LD) $(LDFLAGS) -o $@ $(OBJ)

# ============================================================================
# ISO (GRUB bootable)
# ============================================================================

iso: dnaos.iso

dnaos.iso: dnaos.bin
        mkdir -p iso/boot/grub
        cp dnaos.bin iso/boot/
        cp grub.cfg iso/boot/grub/
        grub-mkrescue -o dnaos.iso iso/ 2>/dev/null || \
                xorriso -as mkisofs -R -J -c boot/boot.cat \
                -b boot/grub/i386-pc/eltorito.img -no-emul-boot \
                -boot-load-size 4 -boot-info-table \
                --grub2-boot-info -eltorito-alt-boot \
                -e boot/grub/efi.img -no-emul-boot \
                -o dnaos.iso iso/ 2>/dev/null || \
                echo "WARNING: Could not create ISO. Install grub-mkrescue or xorriso."

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
# Compile only (no link)
# ============================================================================

compile: $(DNA_NASMS)
        @echo "All DNAsm files compiled to NASM"

# ============================================================================
# Check syntax
# ============================================================================

check: compile
        @echo "Syntax check complete"

# ============================================================================
# Clean
# ============================================================================

clean:
        rm -rf build/ *.bin *.iso iso/
