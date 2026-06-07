/*
 * ============================================================================
 * DNAOS - PIT (Programmable Interval Timer) Driver
 * ============================================================================
 * 
 * Intel 8254 PIT, runs at 1.193182 MHz.
 * Channel 0: IRQ0 (system timer)
 * Channel 1: RAM refresh (unused)
 * Channel 2: PC speaker
 * 
 * We set channel 0 to 100Hz (10ms tick) for the scheduler.
 * ============================================================================
 */

#ifndef PIT_H
#define PIT_H

#include <stdint.h>

#define PIT_CH0_DATA     0x40
#define PIT_CH1_DATA     0x41
#define PIT_CH2_DATA     0x42
#define PIT_CMD          0x43

#define PIT_FREQ         1193182     /* Base frequency */
#define PIT_TARGET_HZ    100         /* 100 Hz = 10ms tick */

/* Command byte bits */
#define PIT_CMD_BINARY    0x00
#define PIT_CMD_BCD       0x01
#define PIT_CMD_LATCH     0x00
#define PIT_CMD_LOBYTE    0x10
#define PIT_CMD_HIBYTE    0x20
#define PIT_CMD_LOHI      0x30
#define PIT_CMD_CH0       0x00
#define PIT_CMD_CH1       0x40
#define PIT_CMD_CH2       0x80

/* Port I/O */
static inline void outb(uint16_t port, uint8_t val) {
    __asm__ volatile ("outb %0, %1" :: "a"(val), "Nd"(port));
}

static inline uint8_t inb(uint16_t port) {
    uint8_t ret;
    __asm__ volatile ("inb %1, %0" : "=a"(ret) : "Nd"(port));
    return ret;
}

/* Tick counter */
static volatile uint64_t pit_ticks = 0;
static volatile uint64_t pit_uptime_ms = 0;

/* Initialize PIT */
static void pit_init(void) {
    uint16_t divisor = PIT_FREQ / PIT_TARGET_HZ;
    
    /* Channel 0, lo/hi byte, binary mode, rate generator (mode 2) */
    outb(PIT_CMD, 0x36);
    
    /* Set divisor */
    outb(PIT_CH0_DATA, divisor & 0xFF);        /* Low byte */
    outb(PIT_CH0_DATA, (divisor >> 8) & 0xFF); /* High byte */
    
    pit_ticks = 0;
    pit_uptime_ms = 0;
}

/* PIT IRQ0 handler - called from IDT */
static void pit_irq_handler(void) {
    pit_ticks++;
    pit_uptime_ms += 10; /* 10ms per tick at 100Hz */
    
    /* Call scheduler */
    /* scheduler_tick(); */
}

/* Get uptime in milliseconds */
static uint64_t pit_get_uptime_ms(void) {
    return pit_uptime_ms;
}

/* Get tick count */
static uint64_t pit_get_ticks(void) {
    return pit_ticks;
}

/* Sleep for specified milliseconds (busy wait) */
static void pit_sleep_ms(uint64_t ms) {
    uint64_t target = pit_uptime_ms + ms;
    while (pit_uptime_ms < target) {
        __asm__ volatile ("hlt");
    }
}

/* Beep the PC speaker */
static void pit_beep(uint32_t freq, uint32_t duration_ms) {
    if (freq == 0) return;
    
    uint16_t divisor = PIT_FREQ / freq;
    
    /* Channel 2, lo/hi byte, binary mode, square wave (mode 3) */
    outb(PIT_CMD, 0xB6);
    outb(PIT_CH2_DATA, divisor & 0xFF);
    outb(PIT_CH2_DATA, (divisor >> 8) & 0xFF);
    
    /* Enable speaker */
    uint8_t tmp = inb(0x61);
    outb(0x61, tmp | 0x03);
    
    /* Wait */
    pit_sleep_ms(duration_ms);
    
    /* Disable speaker */
    outb(0x61, tmp & ~0x03);
}

#endif /* PIT_H */
