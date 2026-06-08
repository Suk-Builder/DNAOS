#ifndef DNAOS_SERIAL_H
#define DNAOS_SERIAL_H

#include <stdint.h>

void serial_init(void);
void serial_putchar(char c);
void serial_print(const char *s);
void serial_print_hex(uint64_t val);
void serial_print_dec(int val);

#endif
