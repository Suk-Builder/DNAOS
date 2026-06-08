#include "vmm.h"
#include "pmm.h"
#include "serial.h"
#include "io.h"

/* ============================================================================
 * Virtual Memory Manager
 * ============================================================================
 * Manages 4-level page tables (P4→P3→P2→P1).
 * The first 1GB is identity-mapped by boot.S. VMM extends this with
 * dynamic mapping and a kernel heap.
 *
 * Page table layout (virtual addresses):
 *   P4[0] → P3[0] → P2[0..511] = first 1GB (identity mapped, 2MB pages)
 *   P4[0] → P3[1..511] = 1GB-512GB (available for mapping)
 *   P4[256] → kernel higher half (optional, not used yet)
 * ============================================================================ */

/* Current P4 table (from boot.S) */
static uint64_t *p4_table;

/* ---- Page table helpers ---- */

static inline void invlpg(uint64_t addr) {
    __asm__ volatile ("invlpg (%0)" : : "r"(addr) : "memory");
}

static inline void flush_tlb(void) {
    uint64_t cr3;
    __asm__ volatile ("mov %%cr3, %0" : "=r"(cr3));
    __asm__ volatile ("mov %0, %%cr3" : : "r"(cr3));
}

/* Get P4 table entry (index into current P4) */
static uint64_t *get_p4_entry(uint64_t virt) {
    return &p4_table[(virt >> 39) & 0x1FF];
}

/* Get or create P3 table for a virtual address */
static uint64_t *get_p3_table(uint64_t virt, int create) {
    uint64_t *p4e = get_p4_entry(virt);
    if (!(*p4e & VMM_PRESENT)) {
        if (!create) return (uint64_t *)0;
        /* Allocate a new P3 table */
        void *new_p3 = pmm_alloc_page();
        if (!new_p3) return (uint64_t *)0;
        /* Zero the new table */
        for (int i = 0; i < 512; i++)
            ((uint64_t *)new_p3)[i] = 0;
        *p4e = (uint64_t)new_p3 | VMM_PRESENT | VMM_WRITABLE;
    }
    return (uint64_t *)(*p4e & ~0xFFF);
}

/* Get or create P2 table for a virtual address */
static uint64_t *get_p2_table(uint64_t virt, int create) {
    uint64_t *p3 = get_p3_table(virt, create);
    if (!p3) return (uint64_t *)0;
    uint64_t *p3e = &p3[(virt >> 30) & 0x1FF];
    if (!(*p3e & VMM_PRESENT)) {
        if (!create) return (uint64_t *)0;
        void *new_p2 = pmm_alloc_page();
        if (!new_p2) return (uint64_t *)0;
        for (int i = 0; i < 512; i++)
            ((uint64_t *)new_p2)[i] = 0;
        *p3e = (uint64_t)new_p2 | VMM_PRESENT | VMM_WRITABLE;
    }
    return (uint64_t *)(*p3e & ~0xFFF);
}

/* Get or create P1 table for a virtual address */
static uint64_t *get_p1_table(uint64_t virt, int create) {
    uint64_t *p2 = get_p2_table(virt, create);
    if (!p2) return (uint64_t *)0;
    uint64_t *p2e = &p2[(virt >> 21) & 0x1FF];
    if (!(*p2e & VMM_PRESENT)) {
        if (!create) return (uint64_t *)0;
        /* Check if this is a 2MB huge page */
        if (*p2e & (1ULL << 7)) return (uint64_t *)0;
        void *new_p1 = pmm_alloc_page();
        if (!new_p1) return (uint64_t *)0;
        for (int i = 0; i < 512; i++)
            ((uint64_t *)new_p1)[i] = 0;
        *p2e = (uint64_t)new_p1 | VMM_PRESENT | VMM_WRITABLE;
    }
    return (uint64_t *)(*p2e & ~0xFFF);
}

/* ---- Public API ---- */

void vmm_init(void) {
    /* Get current P4 table from CR3 */
    uint64_t cr3;
    __asm__ volatile ("mov %%cr3, %0" : "=r"(cr3));
    p4_table = (uint64_t *)(cr3 & ~0xFFF);

    serial_print("[VMM] P4 table at ");
    serial_print_hex((uint64_t)p4_table);
    serial_print("\n");

    /* The first 1GB is already identity-mapped by boot.S with 2MB pages.
     * We can now dynamically map additional pages. */
}

void vmm_map_page(uint64_t virt, uint64_t phys, uint64_t flags) {
    /* Ensure flags include PRESENT */
    flags |= VMM_PRESENT;

    uint64_t *p1 = get_p1_table(virt, 1);
    if (!p1) {
        serial_print("[VMM] ERROR: failed to get P1 for ");
        serial_print_hex(virt);
        serial_print("\n");
        return;
    }

    uint64_t *p1e = &p1[(virt >> 12) & 0x1FF];
    *p1e = (phys & ~0xFFF) | flags;

    invlpg(virt);
}

void vmm_unmap_page(uint64_t virt) {
    uint64_t *p1 = get_p1_table(virt, 0);
    if (!p1) return;

    uint64_t *p1e = &p1[(virt >> 12) & 0x1FF];
    *p1e = 0;

    invlpg(virt);
}

uint64_t vmm_get_physical(uint64_t virt) {
    uint64_t *p1 = get_p1_table(virt, 0);
    if (!p1) {
        /* Check for 2MB huge page in P2 */
        uint64_t *p2 = get_p2_table(virt, 0);
        if (!p2) return 0;
        uint64_t p2e = p2[(virt >> 21) & 0x1FF];
        if (p2e & (1ULL << 7)) /* huge page */
            return (p2e & ~0x1FFFFF) + (virt & 0x1FFFFF);
        return 0;
    }

    uint64_t p1e = p1[(virt >> 12) & 0x1FF];
    if (!(p1e & VMM_PRESENT)) return 0;
    return (p1e & ~0xFFF) + (virt & 0xFFF);
}

uint64_t vmm_alloc_and_map(uint64_t virt, uint64_t flags) {
    void *phys = pmm_alloc_page();
    if (!phys) return 0;
    vmm_map_page(virt, (uint64_t)phys, flags);
    return virt;
}

/* ============================================================================
 * Kernel Heap Allocator
 * ============================================================================
 * Simple linked-list allocator. Each block has a header with size and
 * a "used" flag. Free blocks are merged on kfree.
 *
 * Heap starts at a fixed virtual address and grows by mapping new pages.
 * ============================================================================ */

#define HEAP_START   0xC0000000ULL   /* 3GB — start of kernel heap */
#define HEAP_INITIAL 0x400000ULL     /* 4MB initial heap */

struct heap_block {
    uint64_t size;          /* Size of data area (not including header) */
    int used;               /* 1 = allocated, 0 = free */
    struct heap_block *next;
};

static struct heap_block *heap_first = 0;
static uint64_t heap_brk = HEAP_START;  /* Current break (next unmapped address) */

/* Map pages for heap growth */
static void heap_grow(uint64_t needed) {
    /* Round up to page size */
    needed = (needed + PAGE_SIZE - 1) & ~((uint64_t)PAGE_SIZE - 1);

    for (uint64_t addr = heap_brk; addr < heap_brk + needed; addr += PAGE_SIZE) {
        void *phys = pmm_alloc_page();
        if (!phys) {
            serial_print("[heap] OUT OF MEMORY\n");
            return;
        }
        vmm_map_page(addr, (uint64_t)phys, VMM_PRESENT | VMM_WRITABLE);
        /* Zero the page */
        for (int i = 0; i < PAGE_SIZE / 8; i++)
            ((uint64_t *)addr)[i] = 0;
    }
    heap_brk += needed;
}

void kmalloc_init(void) {
    serial_print("[heap] Initializing at 0x");
    serial_print_hex(HEAP_START);
    serial_print("...\n");

    /* Map initial heap pages */
    heap_grow(HEAP_INITIAL);

    /* Set up first free block */
    heap_first = (struct heap_block *)HEAP_START;
    heap_first->size = HEAP_INITIAL - sizeof(struct heap_block);
    heap_first->used = 0;
    heap_first->next = 0;

    serial_print("[heap] ");
    serial_print_dec((int)(HEAP_INITIAL / 1024));
    serial_print(" KB available\n");
}

void *kmalloc(uint64_t size) {
    /* Align size to 16 bytes */
    size = (size + 15) & ~15ULL;

    /* First-fit search */
    struct heap_block *block = heap_first;
    while (block) {
        if (!block->used && block->size >= size) {
            /* Found a fit */
            /* Split if there's enough room for another block */
            if (block->size >= size + sizeof(struct heap_block) + 16) {
                struct heap_block *new_block = (struct heap_block *)
                    ((uint8_t *)block + sizeof(struct heap_block) + size);
                new_block->size = block->size - size - sizeof(struct heap_block);
                new_block->used = 0;
                new_block->next = block->next;
                block->next = new_block;
                block->size = size;
            }
            block->used = 1;
            return (void *)((uint8_t *)block + sizeof(struct heap_block));
        }
        block = block->next;
    }

    /* No free block found — grow heap */
    uint64_t needed = size + sizeof(struct heap_block);
    heap_grow(needed);

    /* Add new block at the end */
    struct heap_block *new_block = (struct heap_block *)(heap_brk - needed);
    new_block->size = needed - sizeof(struct heap_block);
    new_block->used = 0;
    new_block->next = 0;

    /* Link it */
    block = heap_first;
    while (block->next) block = block->next;
    block->next = new_block;

    /* Retry allocation */
    return kmalloc(size);
}

void kfree(void *ptr) {
    if (!ptr) return;

    struct heap_block *block = (struct heap_block *)
        ((uint8_t *)ptr - sizeof(struct heap_block));
    block->used = 0;

    /* Coalesce with next block if free */
    while (block->next && !block->next->used) {
        block->size += sizeof(struct heap_block) + block->next->size;
        block->next = block->next->next;
    }
}
