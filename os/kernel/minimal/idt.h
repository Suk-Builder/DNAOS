#ifndef DNAOS_IDT_H
#define DNAOS_IDT_H

#include <stdint.h>

/* Interrupt frame pushed by ISR stub + CPU */
struct int_frame {
    /* Saved by isr_common (push order, RSP-relative) */
    uint64_t r15, r14, r13, r12, r11, r10, r9, r8;
    uint64_t rdi, rsi, rbp, rdx, rcx, rbx, rax;
    uint64_t ds;        /* saved data segment */
    /* Pushed by ISR stub */
    uint64_t vec;
    uint64_t err;
    /* Pushed by CPU */
    uint64_t rip, cs, rflags, rsp, ss;
};

void idt_init(void);
void idt_setup_all(void);
int idt_get_ticks(void);
void isr_handler_c(struct int_frame *frame);
void irq_handler_c(struct int_frame *frame);

#endif
