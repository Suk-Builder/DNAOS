/*
 * ============================================================================
 * DNAOS - Virtual Memory Manager
 * ============================================================================
 * Maps virtual addresses to physical using 4-level paging:
 *   PML4 → PDPT → PD → PT → Page
 * 
 * Kernel mapped at higher half (0xFFFFFFFF80000000) in future.
 * For now, identity map first 4GB.
 * ============================================================================
 */

#ifndef VMM_H
#define VMM_H

#include <stdint.h>
#include "pmm.h"

/* Page table entry flags */
#define PTE_PRESENT     (1ULL << 0)
#define PTE_WRITABLE    (1ULL << 1)
#define PTE_USER        (1ULL << 2)
#define PTE_ACCESSED    (1ULL << 5)
#define PTE_DIRTY       (1ULL << 6)
#define PTE_HUGE        (1ULL << 7)  /* 2MB page in PD */
#define PTE_GLOBAL      (1ULL << 8)
#define PTE_NX          (1ULL << 63)

/* Virtual address bit fields (48-bit virtual) */
#define PML4_SHIFT      39
#define PDPT_SHIFT      30
#define PD_SHIFT        21
#define PT_SHIFT        12

#define PML4_INDEX(v)   (((v) >> PML4_SHIFT) & 0x1FF)
#define PDPT_INDEX(v)   (((v) >> PDPT_SHIFT) & 0x1FF)
#define PD_INDEX(v)     (((v) >> PD_SHIFT) & 0x1FF)
#define PT_INDEX(v)     (((v) >> PT_SHIFT) & 0x1FF)

/* Current PML4 (set during boot) */
static uint64_t *current_pml4 = (uint64_t *)0x1000; /* Will be set properly */

/* Get or create page table entry */
static uint64_t *vmm_get_or_create(uint64_t *table, int index, uint64_t flags) {
    if (table[index] & PTE_PRESENT) {
        return (uint64_t *)(table[index] & ~0xFFF);
    }
    
    /* Allocate new page table */
    uint64_t phys = pmm_alloc_page();
    if (!phys) return 0;
    
    /* Zero it */
    uint64_t *virt = (uint64_t *)phys; /* Identity mapped */
    for (int i = 0; i < 512; i++) virt[i] = 0;
    
    table[index] = phys | flags | PTE_PRESENT | PTE_WRITABLE;
    return virt;
}

/* Map virtual → physical with given flags */
static int vmm_map_page(uint64_t virt, uint64_t phys, uint64_t flags) {
    uint64_t *pml4 = current_pml4;
    
    uint64_t *pdpt = vmm_get_or_create(pml4, PML4_INDEX(virt), flags);
    if (!pdpt) return -1;
    
    uint64_t *pd = vmm_get_or_create(pdpt, PDPT_INDEX(virt), flags);
    if (!pd) return -1;
    
    /* Use 2MB huge pages for kernel space */
    if ((virt >= 0xFFFFFFFF80000000ULL) || (virt < 0x400000)) {
        pd[PD_INDEX(virt)] = phys | flags | PTE_PRESENT | PTE_WRITABLE | PTE_HUGE;
        return 0;
    }
    
    uint64_t *pt = vmm_get_or_create(pd, PD_INDEX(virt), flags);
    if (!pt) return -1;
    
    pt[PT_INDEX(virt)] = phys | flags | PTE_PRESENT | PTE_WRITABLE;
    return 0;
}

/* Unmap a virtual page */
static void vmm_unmap_page(uint64_t virt) {
    uint64_t *pml4 = current_pml4;
    
    if (!(pml4[PML4_INDEX(virt)] & PTE_PRESENT)) return;
    uint64_t *pdpt = (uint64_t *)(pml4[PML4_INDEX(virt)] & ~0xFFF);
    
    if (!(pdpt[PDPT_INDEX(virt)] & PTE_PRESENT)) return;
    uint64_t *pd = (uint64_t *)(pdpt[PDPT_INDEX(virt)] & ~0xFFF);
    
    if (pd[PD_INDEX(virt)] & PTE_HUGE) {
        pd[PD_INDEX(virt)] = 0;
        return;
    }
    
    if (!(pd[PD_INDEX(virt)] & PTE_PRESENT)) return;
    uint64_t *pt = (uint64_t *)(pd[PD_INDEX(virt)] & ~0xFFF);
    
    pt[PT_INDEX(virt)] = 0;
    
    /* Flush TLB */
    __asm__ volatile ("invlpg (%0)" :: "r"(virt) : "memory");
}

/* Map a range of pages */
static int vmm_map_range(uint64_t virt_start, uint64_t phys_start, 
                          uint64_t count, uint64_t flags) {
    for (uint64_t i = 0; i < count; i++) {
        if (vmm_map_page(virt_start + i * PAGE_SIZE, 
                         phys_start + i * PAGE_SIZE, flags) < 0) {
            return -1;
        }
    }
    return 0;
}

/* Allocate and map a new page at virtual address */
static uint64_t vmm_alloc_at(uint64_t virt, uint64_t flags) {
    uint64_t phys = pmm_alloc_page();
    if (!phys) return 0;
    
    if (vmm_map_page(virt, phys, flags) < 0) {
        pmm_free_page(phys);
        return 0;
    }
    
    /* Zero the page */
    uint8_t *p = (uint8_t *)virt;
    for (int i = 0; i < PAGE_SIZE; i++) p[i] = 0;
    
    return phys;
}

/* Initialize VMM - called after PMM */
static void vmm_init(uint64_t pml4_phys) {
    current_pml4 = (uint64_t *)pml4_phys;
    
    /* Identity map is already set up by boot.S */
    /* Future: map kernel at higher half, user space at lower half */
}

#endif /* VMM_H */
