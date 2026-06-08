#ifndef DNAOS_VGA_H
#define DNAOS_VGA_H

#include <stdint.h>

void vga_putchar(int col, char c, uint8_t attr);
void vga_print(const char *s, uint8_t attr);
void vga_clear(void);

#endif
