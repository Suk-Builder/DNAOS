/*
 * ============================================================================
 * DNAOS - PS/2 Mouse Driver
 * ============================================================================
 * 
 * Uses IRQ12 (mouse) + IRQ1 (keyboard) via PS/2 controller.
 * Standard 3-byte packet: [flags, dx, dy]
 * 
 * Initialization sequence:
 *   1. Enable auxiliary device (command 0xA8)
 *   2. Enable IRQ12 (command 0x20, set bit 1, command 0x60)
 *   3. Set defaults (command 0xF6 to aux)
 *   4. Enable streaming (command 0xF4 to aux)
 * ============================================================================
 */

#ifndef MOUSE_H
#define MOUSE_H

#include <stdint.h"

/* PS/2 Controller ports */
#define PS2_CTRL        0x64    /* Command/status register */
#define PS2_DATA        0x60    /* Data register */

/* PS/2 Controller commands */
#define PS2_READ_CFG    0x20    /* Read configuration byte */
#define PS2_WRITE_CFG   0x60    /* Write configuration byte */
#define PS2_DISABLE_AUX 0xA7    /* Disable auxiliary port */
#define PS2_ENABLE_AUX  0xA8    /* Enable auxiliary port */
#define PS2_AUX_TEST    0xA9    /* Test auxiliary port */
#define PS2_DISABLE_KBD 0xAD    /* Disable keyboard port */
#define PS2_ENABLE_KBD  0xAE    /* Enable keyboard port */

/* Mouse commands (sent to aux device) */
#define MOUSE_SET_DEFAULTS  0xF6
#define MOUSE_ENABLE_STREAM 0xF4
#define MOUSE_DISABLE_STREAM 0xF5
#define MOUSE_SET_SAMPLE    0xF3
#define MOUSE_SET_RESOLUTION 0xE8
#define MOUSE_SET_SCALING   0xE6
#define MOUSE_GET_ID        0xF2
#define MOUSE_ACK           0xFA

/* Mouse packet flags */
#define MOUSE_LEFT_BTN   0x01
#define MOUSE_RIGHT_BTN  0x02
#define MOUSE_MIDDLE_BTN 0x04
#define MOUSE_X_SIGN     0x10
#define MOUSE_Y_SIGN     0x20
#define MOUSE_X_OVERFLOW 0x40
#define MOUSE_Y_OVERFLOW 0x80

/* Wait for PS/2 controller ready */
static void ps2_wait_read(void) {
    int timeout = 100000;
    while (timeout-- && !(__inb(PS2_CTRL) & 0x01));
}

static void ps2_wait_write(void) {
    int timeout = 100000;
    while (timeout-- && (__inb(PS2_CTRL) & 0x02));
}

/* Read byte from PS/2 data port */
static uint8_t ps2_read(void) {
    ps2_wait_read();
    return __inb(PS2_DATA);
}

/* Write byte to PS/2 data port */
static void ps2_write(uint8_t data) {
    ps2_wait_write();
    __outb(PS2_DATA, data);
}

/* Send command to PS/2 controller */
static void ps2_cmd(uint8_t cmd) {
    ps2_wait_write();
    __outb(PS2_CTRL, cmd);
}

/* Send command to auxiliary (mouse) device */
static void mouse_cmd(uint8_t cmd) {
    ps2_cmd(0xD4);       /* Next byte goes to aux */
    ps2_write(cmd);
    ps2_read();          /* Read ACK */
}

/* Port I/O helpers (defined elsewhere) */
static inline uint8_t __inb(uint16_t port) {
    uint8_t ret;
    __asm__ volatile ("inb %1, %0" : "=a"(ret) : "Nd"(port));
    return ret;
}

static inline void __outb(uint16_t port, uint8_t val) {
    __asm__ volatile ("outb %0, %1" :: "a"(val), "Nd"(port));
}

/* Mouse state */
static int mouse_packet_idx = 0;
static uint8_t mouse_packet[3];
static int mouse_dx = 0, mouse_dy = 0;
static int mouse_btns = 0;

/* Initialize PS/2 mouse */
static void mouse_init(void) {
    /* Enable auxiliary device */
    ps2_cmd(PS2_ENABLE_AUX);
    
    /* Enable IRQ12 in PS/2 controller config */
    ps2_cmd(PS2_READ_CFG);
    uint8_t cfg = ps2_read();
    cfg |= 0x02;      /* Enable auxiliary interrupt (IRQ12) */
    cfg &= ~0x20;     /* Enable auxiliary clock */
    ps2_cmd(PS2_WRITE_CFG);
    ps2_write(cfg);
    
    /* Set mouse defaults */
    mouse_cmd(MOUSE_SET_DEFAULTS);
    
    /* Set sample rate to 60 */
    mouse_cmd(MOUSE_SET_SAMPLE);
    mouse_cmd(60);
    
    /* Enable streaming */
    mouse_cmd(MOUSE_ENABLE_STREAM);
    
    mouse_packet_idx = 0;
}

/* Process mouse IRQ12 */
static void mouse_irq_handler(void) {
    uint8_t data = ps2_read();
    
    if (mouse_packet_idx == 0 && !(data & 0x08)) {
        /* First byte must have bit 3 set */
        return;
    }
    
    mouse_packet[mouse_packet_idx++] = data;
    
    if (mouse_packet_idx >= 3) {
        mouse_packet_idx = 0;
        
        /* Parse packet */
        uint8_t flags = mouse_packet[0];
        int8_t dx = mouse_packet[1];
        int8_t dy = mouse_packet[2];
        
        /* Apply sign */
        if (flags & MOUSE_X_SIGN) dx |= 0xFFFFFF00; /* Sign extend */
        if (flags & MOUSE_Y_SIGN) dy |= 0xFFFFFF00;
        
        /* Apply overflow */
        if (flags & MOUSE_X_OVERFLOW) dx = 0;
        if (flags & MOUSE_Y_OVERFLOW) dy = 0;
        
        mouse_dx = dx;
        mouse_dy = -dy; /* Y is inverted */
        mouse_btns = flags & 0x07;
        
        /* Update window manager mouse */
        /* wm_handle_mouse_move and click would be called from main loop */
    }
}

#endif /* MOUSE_H */
