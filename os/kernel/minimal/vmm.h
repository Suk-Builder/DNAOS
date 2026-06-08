#ifndef DNAOS_VMM_H
#define DNAOS_VMM_H

#include <stdint.h>

/* Page flags */
#define VMM_PRESENT  (1ULL << 0)
#define VMM_WRITABLE (1ULL << 1)
#define VMM_USER     (1ULL << 2)
#define VMM_NX       (1ULL << 63)  /* No execute */

/* Initialize VMM (called after PMM) */
void vmm_init(void);

/* Map virtual page to physical page with flags */
void vmm_map_page(uint64_t virt, uint64_t phys, uint64_t flags);

/* Unmap a virtual page */
void vmm_unmap_page(uint64_t virt);

/* Get physical address for a virtual address (0 if not mapped) */
uint64_t vmm_get_physical(uint64_t virt);

/* Allocate and map a new page at virt with given flags */
/* Returns the virtual address (same as virt on success, 0 on failure) */
uint64_t vmm_alloc_and_map(uint64_t virt, uint64_t flags);

/* Kernel heap allocator */
void  kmalloc_init(void);
void *kmalloc(uint64_t size);
void  kfree(void *ptr);

#endif
