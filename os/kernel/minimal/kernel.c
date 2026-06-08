/* ============================================================================
 * DNAOS Kernel v0.3 — C
 * ============================================================================
 * Boot: boot.S (32→64) → kernel_main (C)
 * Features: Serial, VGA, GDT/TSS/IDT, PIC, PIT, Keyboard, PMM
 * ============================================================================ */

#include <stdint.h>
#include "serial.h"
#include "vga.h"
#include "idt.h"
#include "pmm.h"

void kernel_main(uint32_t mb1_magic, uint32_t mb1_info) {
    /* Serial first — so we can debug everything */
    serial_init();

    serial_print("\n========================================\n");
    serial_print("  DNAOS64 v0.3 — Quaternary OS\n");
    serial_print("  Boot: Multiboot → 32-bit → Long Mode\n");
    serial_print("  Kernel: C (freestanding, no stdlib)\n");
    serial_print("========================================\n\n");

    /* Initialize interrupt subsystems (GDT/TSS/IDT/PIC/PIT/Keyboard) */
    serial_print("[init] GDT/TSS/IDT/PIC/PIT/Keyboard... ");
    idt_setup_all();
    serial_print("OK\n");

    /* Initialize physical memory manager */
    serial_print("[init] PMM... ");
    pmm_init(mb1_magic, mb1_info);
    serial_print("OK\n");

    /* Test PMM */
    serial_print("[test] PMM alloc/free: ");
    void *p1 = pmm_alloc_page();
    void *p2 = pmm_alloc_page();
    void *p3 = pmm_alloc_page();
    serial_print("allocated 3 pages: ");
    serial_print_hex((uint64_t)p1); serial_print(" ");
    serial_print_hex((uint64_t)p2); serial_print(" ");
    serial_print_hex((uint64_t)p3); serial_print("\n");

    pmm_free_page(p2);
    serial_print("  freed ");
    serial_print_hex((uint64_t)p2);
    serial_print(", free: ");
    serial_print_dec((int)pmm_free_pages());
    serial_print("\n");

    void *p4 = pmm_alloc_page();
    serial_print("  re-allocated: ");
    serial_print_hex((uint64_t)p4);
    serial_print(p4 == p2 ? " (same page reused!)\n" : " (different page)\n");

    /* Enable interrupts */
    serial_print("[init] Enabling interrupts... ");
    __asm__ volatile ("sti");
    serial_print("OK\n");

    /* VGA */
    vga_clear();
    vga_print("DNAOS64 v0.3", 0x0F);

    serial_print("\nAll subsystems initialized.\n");
    serial_print("Interrupts active. System running.\n\n");

    /* Idle loop */
    while (1) {
        __asm__ volatile ("hlt");
    }
}
