/*
 * ============================================================================
 * DNAOS - Physical Memory Manager
 * ============================================================================
 * Manages physical RAM using a bitmap allocator.
 * Each bit = 1 page (4KB). 0 = free, 1 = used.
 * 
 * Memory map comes from multiboot2 (mmap_tag).
 * ============================================================================
 */

#ifndef PMM_H
#define PMM_H

#include <stdint.h>

#define PAGE_SIZE       4096
#define PAGE_SHIFT      12
#define PMM_BITMAP_SIZE 32768   /* 32768 * 32 bits * 4KB = 4GB */

typedef struct {
    uint32_t bitmap[PMM_BITMAP_SIZE];  /* 128KB bitmap for 4GB */
    uint64_t total_pages;
    uint64_t free_pages;
    uint64_t used_pages;
    uint64_t mem_kb;            /* Total memory in KB from multiboot */
} pmm_state_t;

static pmm_state_t pmm;

/* Mark a page as used */
static inline void pmm_set_page(uint64_t addr) {
    uint64_t idx = addr >> PAGE_SHIFT;
    pmm.bitmap[idx / 32] |= (1U << (idx % 32));
    pmm.used_pages++;
    pmm.free_pages--;
}

/* Mark a page as free */
static inline void pmm_clear_page(uint64_t addr) {
    uint64_t idx = addr >> PAGE_SHIFT;
    pmm.bitmap[idx / 32] &= ~(1U << (idx % 32));
    pmm.used_pages--;
    pmm.free_pages++;
}

/* Check if page is used */
static inline int pmm_test_page(uint64_t addr) {
    uint64_t idx = addr >> PAGE_SHIFT;
    return (pmm.bitmap[idx / 32] >> (idx % 32)) & 1;
}

/* Allocate one physical page, return address or 0 */
static uint64_t pmm_alloc_page(void) {
    for (uint64_t i = 0; i < PMM_BITMAP_SIZE; i++) {
        if (pmm.bitmap[i] != 0xFFFFFFFF) {
            /* Find first free bit */
            for (int j = 0; j < 32; j++) {
                if (!(pmm.bitmap[i] & (1U << j))) {
                    uint64_t addr = (i * 32 + j) << PAGE_SHIFT;
                    pmm_set_page(addr);
                    return addr;
                }
            }
        }
    }
    return 0; /* Out of memory */
}

/* Free a physical page */
static void pmm_free_page(uint64_t addr) {
    if (addr & 0xFFF) return; /* Not page-aligned */
    pmm_clear_page(addr);
}

/* Allocate contiguous pages */
static uint64_t pmm_alloc_pages(uint64_t count) {
    if (count == 0) return 0;
    if (count == 1) return pmm_alloc_page();
    
    /* Simple first-fit allocator */
    uint64_t consecutive = 0;
    uint64_t start = 0;
    
    for (uint64_t i = 0; i < PMM_BITMAP_SIZE * 32; i++) {
        int used = (pmm.bitmap[i / 32] >> (i % 32)) & 1;
        if (!used) {
            if (consecutive == 0) start = i;
            consecutive++;
            if (consecutive >= count) {
                /* Mark all pages as used */
                for (uint64_t j = start; j < start + count; j++) {
                    pmm.bitmap[j / 32] |= (1U << (j % 32));
                }
                pmm.used_pages += count;
                pmm.free_pages -= count;
                return start << PAGE_SHIFT;
            }
        } else {
            consecutive = 0;
        }
    }
    return 0; /* Not enough contiguous pages */
}

/* Initialize PMM from multiboot2 mmap */
static void pmm_init(uint64_t mmap_addr, uint32_t mmap_size) {
    /* Mark all memory as used initially */
    for (uint64_t i = 0; i < PMM_BITMAP_SIZE; i++) {
        pmm.bitmap[i] = 0xFFFFFFFF;
    }
    pmm.total_pages = 0;
    pmm.free_pages = 0;
    pmm.used_pages = 0;
    
    /* Parse multiboot2 memory map */
    /* mmap entries: size (4), addr (8), len (8), type (4) */
    uint64_t offset = 0;
    while (offset < mmap_size) {
        uint32_t *entry = (uint32_t *)(mmap_addr + offset);
        uint32_t entry_size = entry[0];
        uint64_t addr = *(uint64_t *)(entry + 2);
        uint64_t len  = *(uint64_t *)(entry + 4);
        uint32_t type = entry[6]; /* 1 = usable */
        
        if (type == 1) {
            /* Mark these pages as free */
            uint64_t start = (addr + PAGE_SIZE - 1) & ~0xFFF; /* Align up */
            uint64_t end = (addr + len) & ~0xFFF;             /* Align down */
            
            for (uint64_t a = start; a < end; a += PAGE_SIZE) {
                if (a < 4ULL * 1024 * 1024 * 1024) { /* Only first 4GB */
                    pmm_clear_page(a);
                    pmm.total_pages++;
                    pmm.free_pages++;
                }
            }
        }
        
        offset += entry_size + 4; /* entry_size + size field */
        if (entry_size == 0) break; /* Safety */
    }
    
    /* Reserve kernel memory (first 2MB + kernel) */
    for (uint64_t a = 0; a < 2 * 1024 * 1024; a += PAGE_SIZE) {
        if (!pmm_test_page(a)) {
            pmm_set_page(a);
        }
    }
}

/* Get memory info string */
static void pmm_info(char *buf, int bufsize) {
    uint64_t total_mb = (pmm.total_pages * PAGE_SIZE) / (1024 * 1024);
    uint64_t free_mb  = (pmm.free_pages * PAGE_SIZE) / (1024 * 1024);
    uint64_t used_mb  = (pmm.used_pages * PAGE_SIZE) / (1024 * 1024);
    
    /* Simple integer to string */
    int pos = 0;
    const char *prefix = "Memory: ";
    while (*prefix && pos < bufsize - 1) buf[pos++] = *prefix++;
    
    /* total */
    uint64_t n = total_mb;
    char num[20];
    int i = 0;
    if (n == 0) num[i++] = '0';
    while (n > 0) { num[i++] = '0' + (n % 10); n /= 10; }
    for (int j = i - 1; j >= 0 && pos < bufsize - 1; j--) buf[pos++] = num[j];
    
    const char *mid = "MB total, ";
    while (*mid && pos < bufsize - 1) buf[pos++] = *mid++;
    
    n = free_mb; i = 0;
    if (n == 0) num[i++] = '0';
    while (n > 0) { num[i++] = '0' + (n % 10); n /= 10; }
    for (int j = i - 1; j >= 0 && pos < bufsize - 1; j--) buf[pos++] = num[j];
    
    const char *suf = "MB free";
    while (*suf && pos < bufsize - 1) buf[pos++] = *suf++;
    buf[pos] = '\0';
}

#endif /* PMM_H */
