#include "vga.h"
#include "io.h"

static int vga_col = 0;
static int vga_row = 0;
static uint16_t *const vga_buf = (uint16_t *)0xB8000;

void vga_putchar(int col, char c, uint8_t attr) {
    if (c == '\n') { vga_col = 0; vga_row++; return; }
    if (vga_row >= 25) vga_row = 0;
    vga_buf[vga_row * 80 + col] = (uint16_t)c | ((uint16_t)attr << 8);
    vga_col = col + 1;
}

void vga_print(const char *s, uint8_t attr) {
    while (*s) {
        if (*s == '\n') { vga_col = 0; vga_row++; s++; continue; }
        if (vga_row >= 25) { vga_row = 0; }
        vga_buf[vga_row * 80 + vga_col] = (uint16_t)*s | ((uint16_t)attr << 8);
        vga_col++;
        if (vga_col >= 80) { vga_col = 0; vga_row++; }
        s++;
    }
    /* Update cursor */
    uint16_t pos = vga_row * 80 + vga_col;
    outb(0x3D4, 14);
    outb(0x3D5, (uint8_t)(pos >> 8));
    outb(0x3D4, 15);
    outb(0x3D5, (uint8_t)(pos & 0xFF));
}

void vga_clear(void) {
    for (int i = 0; i < 80 * 25; i++)
        vga_buf[i] = 0x0F20; /* space, white on black */
    vga_col = 0;
    vga_row = 0;
}
