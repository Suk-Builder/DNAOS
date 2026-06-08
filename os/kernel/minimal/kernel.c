/* ============================================================================
 * DNAOS Kernel v0.4 — C
 * ============================================================================
 * Boot: boot.S (32→64) → kernel_main (C)
 * Features: Serial, VGA, GDT/TSS/IDT, PIC, PIT, Keyboard, PMM, VMM, kmalloc
 * ============================================================================ */

#include <stdint.h>
#include "serial.h"
#include "vga.h"
#include "idt.h"
#include "pmm.h"
#include "vmm.h"

void kernel_main(uint32_t mb1_magic, uint32_t mb1_info) {
    /* Serial first — so we can debug everything */
    serial_init();

    serial_print("\n========================================\n");
    serial_print("  DNAOS64 v0.4 — Quaternary OS\n");
    serial_print("  Boot: Multiboot → 32-bit → Long Mode\n");
    serial_print("  Kernel: C (freestanding, no stdlib)\n");
    serial_print("========================================\n\n");

    /* Initialize interrupt subsystems */
    serial_print("[init] GDT/TSS/IDT/PIC/PIT/Keyboard... ");
    idt_setup_all();
    serial_print("OK\n");

    /* Initialize physical memory manager */
    serial_print("[init] PMM... ");
    pmm_init(mb1_magic, mb1_info);
    serial_print("OK\n");

    /* Initialize virtual memory manager */
    serial_print("[init] VMM... ");
    vmm_init();
    serial_print("OK\n");

    /* Initialize kernel heap */
    serial_print("[init] kmalloc... ");
    kmalloc_init();
    serial_print("OK\n");

    /* ---- Test VMM ---- */
    serial_print("\n[test] VMM:\n");

    /* Map a page at 0xD0000000 */
    serial_print("  map 0xD0000000 → new page... ");
    uint64_t test_virt = 0xD0000000ULL;
    vmm_alloc_and_map(test_virt, VMM_PRESENT | VMM_WRITABLE);
    uint64_t phys = vmm_get_physical(test_virt);
    serial_print("phys=");
    serial_print_hex(phys);
    serial_print("\n");

    /* Write to it */
    volatile uint64_t *test_ptr = (volatile uint64_t *)test_virt;
    *test_ptr = 0xDEADBEEF12345678ULL;
    serial_print("  wrote 0xDEADBEEF12345678, read back: ");
    serial_print_hex(*test_ptr);
    serial_print(*test_ptr == 0xDEADBEEF12345678ULL ? " OK\n" : " MISMATCH!\n");

    /* Unmap and verify */
    vmm_unmap_page(test_virt);
    serial_print("  unmapped, phys=");
    serial_print_hex(vmm_get_physical(test_virt));
    serial_print("\n");

    /* ---- Test kmalloc ---- */
    serial_print("\n[test] kmalloc:\n");

    void *a = kmalloc(128);
    void *b = kmalloc(256);
    void *c = kmalloc(64);
    serial_print("  alloc 128: ");
    serial_print_hex((uint64_t)a);
    serial_print("\n  alloc 256: ");
    serial_print_hex((uint64_t)b);
    serial_print("\n  alloc  64: ");
    serial_print_hex((uint64_t)c);
    serial_print("\n");

    /* Write to allocated memory */
    *((uint64_t *)a) = 0xAAAAAAAAAAAAAAAAULL;
    *((uint64_t *)b) = 0xBBBBBBBBBBBBBBBBULL;
    *((uint64_t *)c) = 0xCCCCCCCCCCCCCCCCULL;
    serial_print("  write/read: ");
    serial_print_hex(*((uint64_t *)a));
    serial_print(" ");
    serial_print_hex(*((uint64_t *)b));
    serial_print(" ");
    serial_print_hex(*((uint64_t *)c));
    serial_print("\n");

    kfree(b);
    serial_print("  freed b, re-alloc 128: ");
    void *d = kmalloc(128);
    serial_print_hex((uint64_t)d);
    serial_print(d < c ? " (reused freed block!)\n" : " (new block)\n");

    /* Enable interrupts */
    serial_print("\n[init] Enabling interrupts... ");
    __asm__ volatile ("sti");
    serial_print("OK\n");

    /* VGA */
    vga_clear();
    vga_print("DNAOS64 v0.4", 0x0F);

    serial_print("\nAll subsystems initialized.\n");
    serial_print("Interrupts active. System running.\n\n");

    /* Idle loop */
    while (1) {
        __asm__ volatile ("hlt");
    }
}
