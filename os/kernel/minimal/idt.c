#include "idt.h"
#include "serial.h"
#include "io.h"

/* ---- GDT/TSS ---- */

extern uint64_t gdt64[];
extern uint8_t stack_top[];
extern uint8_t df_stack_top[];

struct tss_struct {
    uint32_t reserved0;
    uint64_t rsp[3];
    uint64_t reserved1;
    uint64_t ist[7];
    uint64_t reserved2;
    uint16_t reserved3;
    uint16_t iomap_base;
} __attribute__((packed));

extern struct tss_struct tss;

static void gdt_init(void) {
    uint64_t tss_base = (uint64_t)&tss;
    gdt64[3] = 0x00000068 | ((tss_base & 0xFFFF) << 16) |
               (((tss_base >> 16) & 0xFF) << 32) | ((uint64_t)0x89 << 40) |
               (((tss_base >> 24) & 0xFF) << 48);
    gdt64[4] = (tss_base >> 32) & 0xFFFFFFFF;
    tss.rsp[0] = (uint64_t)stack_top;
    tss.ist[0] = (uint64_t)df_stack_top;
    __asm__ volatile ("ltr %w0" : : "r"((uint16_t)0x18));
}

/* ---- IDT ---- */

/* ISR stub table from boot.S (48 entries: 32 ISR + 16 IRQ) */
extern uint64_t isr_stub_table[48];

/* IDT entries from boot.S BSS */
extern uint64_t idt[];
extern uint64_t idt_descriptor[];

static volatile int timer_ticks = 0;

static void idt_set_gate(int vec, uint64_t handler, uint16_t sel, uint8_t ist, uint8_t flags) {
    uint64_t *entry = &idt[vec * 2]; /* 16 bytes per entry = 2 × uint64_t */
    entry[0] = (handler & 0x0000FFFF) | ((uint64_t)sel << 16) |
               ((uint64_t)ist << 32) | ((uint64_t)flags << 40) |
               (((handler >> 16) & 0xFFFF) << 48);
    entry[1] = (handler >> 32);
}

static void pic_init(void) {
    /* Remap PIC: master IRQ 32-47, slave IRQ 40-47 */
    outb(0x20, 0x11); io_wait();
    outb(0xA0, 0x11); io_wait();
    outb(0x21, 0x20); io_wait(); /* Master offset 32 */
    outb(0xA1, 0x28); io_wait(); /* Slave offset 40 */
    outb(0x21, 0x04); io_wait();
    outb(0xA1, 0x02); io_wait();
    outb(0x21, 0x01); io_wait();
    outb(0xA1, 0x01); io_wait();
    outb(0x21, 0xFC); /* Enable IRQ 0 (timer) + IRQ 1 (keyboard) */
    outb(0xA1, 0xFF);
}

static void pit_init(void) {
    uint16_t divisor = 1193182 / 100; /* 100 Hz */
    outb(0x43, 0x36);
    outb(0x40, (uint8_t)(divisor & 0xFF));
    outb(0x40, (uint8_t)((divisor >> 8) & 0xFF));
}

static void keyboard_init(void) {
    /* Enable PS/2 keyboard — already enabled by default */
    outb(0x60, 0xF4); /* Enable scanning */
}

static void pic_eoi(int irq) {
    outb(0x20, 0x20);
    if (irq >= 8)
        outb(0xA0, 0x20);
}

static const char *exception_names[] = {
    "DE","DB","NMI","BP","OF","BR","UD","NM",
    "DF","??","TS","NP","SS","GP","PF","??",
    "MF","AC","MC","XM","VE","??","??","??",
    "??","??","??","??","??","??","??","??"
};

void idt_init(void) {
    /* Fill IDT with stub addresses from boot.S */
    for (int i = 0; i < 48; i++) {
        uint8_t flags = 0x8E; /* Present, interrupt gate, DPL=0 */
        uint8_t ist = 0;
        if (i == 8) ist = 1; /* Double fault uses IST1 */
        idt_set_gate(i, isr_stub_table[i], 0x08, ist, flags);
    }

    /* Load IDT */
    uint16_t limit = 48 * 16 - 1;
    uint64_t base = (uint64_t)idt;
    /* Write idt_descriptor: 2 bytes limit + 8 bytes base */
    *(uint16_t *)idt_descriptor = limit;
    *(uint64_t *)((uint8_t *)idt_descriptor + 2) = base;
    __asm__ volatile ("lidt (%0)" : : "r"((uint64_t)idt_descriptor));
}

/* Called from boot.S common ISR handler */
void isr_handler_c(struct int_frame *frame) {
    int vec = (int)frame->vec;

    /* Dispatch: IRQs (vec >= 32) go to irq_handler_c */
    if (vec >= 32 && vec < 48) {
        irq_handler_c(frame);
        return;
    }

    /* CPU exception — print and halt */
    serial_print("[EXC #");
    serial_print_dec(vec);
    serial_print(" ");
    serial_print(exception_names[vec < 32 ? vec : 31]);
    if (frame->err != 0) {
        serial_print(" err=");
        serial_print_hex(frame->err);
    }
    serial_print(" rip=");
    serial_print_hex(frame->rip);
    serial_print("]\n");
    while (1) __asm__ volatile ("cli; hlt");
}

void irq_handler_c(struct int_frame *frame) {
    int irq = (int)frame->vec - 32;

    if (irq == 0) {
        timer_ticks++;
        if (timer_ticks % 100 == 0) {
            serial_print("[tick ");
            serial_print_dec(timer_ticks / 100);
            serial_print("s] ");
        }
        /* Don't call proc_schedule from IRQ — cooperative scheduling only */
    } else if (irq == 1) {
        uint8_t scancode = inb(0x60);
        serial_print("[KEY 0x");
        serial_print_hex(scancode);
        serial_print("] ");
    }

    pic_eoi(irq);
}

/* Called from kernel_main to init all interrupt-related subsystems */
void idt_setup_all(void) {
    gdt_init();
    idt_init();
    pic_init();
    pit_init();
    keyboard_init();
}

int idt_get_ticks(void) {
    return timer_ticks;
}
