#ifndef DNAOS_PMM_H
#define DNAOS_PMM_H

#include <stdint.h>

/* Page size = 4KB */
#define PAGE_SIZE 4096

/* Initialize PMM with multiboot memory map */
void pmm_init(uint32_t mb1_magic, uint32_t mb1_info);

/* Allocate/free physical pages */
void *pmm_alloc_page(void);
void pmm_free_page(void *page);

/* Stats */
uint64_t pmm_total_pages(void);
uint64_t pmm_free_pages(void);
uint64_t pmm_used_pages(void);

#endif
