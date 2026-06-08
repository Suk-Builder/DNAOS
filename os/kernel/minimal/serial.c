#include "serial.h"
#include "io.h"

#define COM1 0x3F8

void serial_init(void) {
    outb(COM1 + 1, 0x00);
    outb(COM1 + 3, 0x80);
    outb(COM1 + 0, 0x01);
    outb(COM1 + 1, 0x00);
    outb(COM1 + 3, 0x03);
    outb(COM1 + 2, 0xC7);
    outb(COM1 + 4, 0x0B);
}

void serial_putchar(char c) {
    while (!(inb(COM1 + 5) & 0x20));
    outb(COM1, (uint8_t)c);
}

void serial_print(const char *s) {
    while (*s) {
        if (*s == '\n') serial_putchar('\r');
        serial_putchar(*s++);
    }
}

void serial_print_hex(uint64_t val) {
    serial_print("0x");
    for (int i = 60; i >= 0; i -= 4) {
        int nibble = (val >> i) & 0xF;
        serial_putchar(nibble < 10 ? '0' + nibble : 'A' + nibble - 10);
    }
}

void serial_print_dec(int val) {
    if (val < 0) { serial_putchar('-'); val = -val; }
    char buf[12];
    int i = 0;
    if (val == 0) { serial_putchar('0'); return; }
    while (val > 0) { buf[i++] = '0' + (val % 10); val /= 10; }
    while (--i >= 0) serial_putchar(buf[i]);
}
