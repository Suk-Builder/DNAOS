/* ============================================================================
 * DNAOS Kernel v0.5 — C
 * ============================================================================
 * Boot: boot.S (32→64) → kernel_main (C)
 * Features: Serial, VGA, GDT/TSS/IDT, PIC, PIT, Keyboard, PMM, VMM, kmalloc,
 *           Process scheduler
 * ============================================================================ */

#include <stdint.h>
#include "serial.h"
#include "vga.h"
#include "idt.h"
#include "pmm.h"
#include "vmm.h"
#include "proc.h"

/* Test process A: counts and prints */
static void proc_a(void *arg) {
    (void)arg;
    for (int i = 0; i < 5; i++) {
        serial_print("[A:");
        serial_print_dec(i);
        serial_print("] ");
        proc_yield(); /* cooperative yield */
    }
    serial_print("[A:done]\n");
}

/* Test process B: counts and yields */
static void proc_b(void *arg) {
    (void)arg;
    for (int i = 0; i < 5; i++) {
        serial_print("[B:");
        serial_print_dec(i);
        serial_print("] ");
        proc_yield();
    }
    serial_print("[B:done]\n");
}

/* Test process C: quick counter */
static void proc_c(void *arg) {
    (void)arg;
    for (int i = 0; i < 8; i++) {
        serial_print("[C:");
        serial_print_dec(i);
        serial_print("] ");
        proc_yield();
    }
    serial_print("[C:done]\n");
}

void kernel_main(uint32_t mb1_magic, uint32_t mb1_info) {
    /* Serial first — so we can debug everything */
    serial_init();

    serial_print("\n========================================\n");
    serial_print("  DNAOS64 v0.5 — Quaternary OS\n");
    serial_print("  Boot: Multiboot → 32-bit → Long Mode\n");
    serial_print("  Kernel: C (freestanding, no stdlib)\n");
    serial_print("========================================\n\n");

    /* Initialize interrupt subsystems */
    serial_print("[init] GDT/TSS/IDT/PIC/PIT/Keyboard... ");
    idt_setup_all();
    serial_print("OK\n");

    /* Initialize PMM */
    serial_print("[init] PMM... ");
    pmm_init(mb1_magic, mb1_info);
    serial_print("OK\n");

    /* Initialize VMM */
    serial_print("[init] VMM... ");
    vmm_init();
    serial_print("OK\n");

    /* Initialize kmalloc */
    serial_print("[init] kmalloc... ");
    kmalloc_init();
    serial_print("OK\n");

    /* Initialize process scheduler */
    serial_print("[init] Process scheduler... ");
    proc_init();
    serial_print("OK\n");

    /* Create test processes */
    serial_print("\n[test] Creating processes...\n");
    pid_t pa = proc_create("counter_a", proc_a, 0);
    pid_t pb = proc_create("counter_b", proc_b, 0);
    pid_t pc = proc_create("counter_c", proc_c, 0);
    serial_print("[test] Created pids: ");
    serial_print_dec(pa); serial_print(", ");
    serial_print_dec(pb); serial_print(", ");
    serial_print_dec(pc); serial_print("\n");

    /* Enable interrupts — this also starts the scheduler */
    serial_print("\n[init] Enabling interrupts... ");
    __asm__ volatile ("sti");
    serial_print("OK\n");

    /* VGA */
    vga_clear();
    vga_print("DNAOS64 v0.5", 0x0F);

    serial_print("\nAll subsystems initialized.\n");
    serial_print("Processes running. Scheduler active.\n\n");

    /* Idle loop — yield to other processes */
    while (1) {
        proc_yield();
        __asm__ volatile ("hlt");
    }
}
