#include "pmm.h"
#include "serial.h"

/* ============================================================================
 * Physical Memory Manager — bitmap allocator
 * ============================================================================
 * Uses a bitmap (1 bit per 4KB page) to track free/used physical pages.
 * The bitmap is placed right after the kernel in memory.
 *
 * Memory map comes from Multiboot1 info structure (mmap_* fields).
 * Pages below 1MB and kernel pages are marked used at init.
 * ============================================================================ */

/* Multiboot1 info structure (from multiboot spec) */
struct mb1_info {
    uint32_t flags;         /* offset 0 */
    uint32_t mem_lower;     /* offset 4 */
    uint32_t mem_upper;     /* offset 8 */
    uint32_t boot_device;   /* offset 12 */
    uint32_t cmdline;       /* offset 16 */
    uint32_t mods_count;    /* offset 20 */
    uint32_t mods_addr;     /* offset 24 */
    uint32_t syms[4];       /* offset 28-43: aout/ELF section header info */
    uint32_t mmap_length;   /* offset 44 */
    uint32_t mmap_addr;     /* offset 48 */
} __attribute__((packed));

struct mb1_mmap_entry {
    uint32_t size;
    uint32_t addr_low;
    uint32_t addr_high;
    uint32_t len_low;
    uint32_t len_high;
    uint32_t type;
} __attribute__((packed));

/* Bitmap: 1 = used, 0 = free */
static uint32_t *pmm_bitmap;
static uint32_t pmm_bitmap_size;    /* in uint32_t entries */
static uint64_t pmm_total;          /* total usable pages */
static uint64_t pmm_free_count;     /* free pages */

/* Kernel end symbol (defined in linker script) */
extern char _kernel_end[];

/* ---- Bitmap helpers ---- */

static inline void bitmap_set(uint64_t page) {
    pmm_bitmap[page / 32] |= (1U << (page % 32));
}

static inline void bitmap_clear(uint64_t page) {
    pmm_bitmap[page / 32] &= ~(1U << (page % 32));
}

static inline int bitmap_test(uint64_t page) {
    return (pmm_bitmap[page / 32] >> (page % 32)) & 1;
}

/* ---- Mark a range of pages as used ---- */
static void mark_used(uint64_t addr, uint64_t len) {
    uint64_t start = addr / PAGE_SIZE;
    uint64_t end = (addr + len + PAGE_SIZE - 1) / PAGE_SIZE;
    for (uint64_t i = start; i < end; i++) {
        if (!bitmap_test(i)) {
            bitmap_set(i);
            pmm_free_count--;
        }
    }
}

/* ---- Mark a range of pages as free ---- */
static void mark_free(uint64_t addr, uint64_t len) {
    uint64_t start = addr / PAGE_SIZE;
    uint64_t end = (addr + len + PAGE_SIZE - 1) / PAGE_SIZE;
    for (uint64_t i = start; i < end; i++) {
        if (bitmap_test(i)) {
            bitmap_clear(i);
            pmm_free_count++;
        }
    }
}

/* ---- Init ---- */
void pmm_init(uint32_t mb1_magic, uint32_t mb1_info_addr) {
    serial_print("[PMM] Initializing...\n");

    /* Default: assume 128MB if no multiboot info */
    uint64_t mem_bytes = 128 * 1024 * 1024;
    uint64_t kernel_end_addr = (uint64_t)_kernel_end;

    if (mb1_magic == 0x2BADB002 && mb1_info_addr) {
        struct mb1_info *info = (struct mb1_info *)(uint64_t)mb1_info_addr;
        if (info->flags & (1 << 0)) {
            /* mem_lower/mem_upper available */
            mem_bytes = ((uint64_t)info->mem_upper + 1024) * 1024;
            serial_print("[PMM] mem_upper=");
            serial_print_dec(info->mem_upper);
            serial_print(" KB → ");
            serial_print_dec((int)(mem_bytes / (1024 * 1024)));
            serial_print(" MB\n");
        }

        /* Parse mmap if available */
        if (info->flags & (1 << 6)) {
            serial_print("[PMM] Parsing mmap...\n");
            uint32_t mmap_addr = info->mmap_addr;
            uint32_t mmap_end = mmap_addr + info->mmap_length;
            while (mmap_addr < mmap_end) {
                struct mb1_mmap_entry *entry = (struct mb1_mmap_entry *)(uint64_t)mmap_addr;
                uint64_t base = (uint64_t)entry->addr_low | ((uint64_t)entry->addr_high << 32);
                uint64_t length = (uint64_t)entry->len_low | ((uint64_t)entry->len_high << 32);
                serial_print("  [");
                serial_print_hex(base);
                serial_print(" - ");
                serial_print_hex(base + length);
                serial_print("] type=");
                serial_print_dec(entry->type);
                serial_print(entry->type == 1 ? " (usable)\n" : "\n");
                mmap_addr += entry->size + 4;
            }
        }
    }

    /* Calculate bitmap size */
    uint64_t total_pages = mem_bytes / PAGE_SIZE;
    pmm_bitmap_size = (total_pages + 31) / 32;
    uint64_t bitmap_bytes = pmm_bitmap_size * sizeof(uint32_t);

    /* Place bitmap after kernel */
    pmm_bitmap = (uint32_t *)(((uint64_t)_kernel_end + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1));

    serial_print("[PMM] Bitmap at ");
    serial_print_hex((uint64_t)pmm_bitmap);
    serial_print(", ");
    serial_print_dec((int)bitmap_bytes);
    serial_print(" bytes, ");
    serial_print_dec((int)total_pages);
    serial_print(" pages\n");

    /* Mark everything as used initially */
    pmm_total = total_pages;
    pmm_free_count = 0;
    for (uint64_t i = 0; i < pmm_bitmap_size; i++)
        pmm_bitmap[i] = 0xFFFFFFFF;

    /* Free usable memory regions (type 1 from mmap, or just above 1MB) */
    if (mb1_magic == 0x2BADB002 && mb1_info_addr) {
        struct mb1_info *info = (struct mb1_info *)(uint64_t)mb1_info_addr;
        if (info->flags & (1 << 6)) {
            uint32_t mmap_addr = info->mmap_addr;
            uint32_t mmap_end = mmap_addr + info->mmap_length;
            while (mmap_addr < mmap_end) {
                struct mb1_mmap_entry *entry = (struct mb1_mmap_entry *)(uint64_t)mmap_addr;
                if (entry->type == 1) {
                    uint64_t base = (uint64_t)entry->addr_low | ((uint64_t)entry->addr_high << 32);
                    uint64_t length = (uint64_t)entry->len_low | ((uint64_t)entry->len_high << 32);
                    mark_free(base, length);
                }
                mmap_addr += entry->size + 4;
            }
        } else {
            /* No mmap — just free memory above 1MB */
            mark_free(0x100000, mem_bytes - 0x100000);
        }
    } else {
        mark_free(0x100000, mem_bytes - 0x100000);
    }

    /* Re-mark kernel + bitmap as used */
    uint64_t used_start = 0x100000;
    uint64_t used_end = (uint64_t)pmm_bitmap + bitmap_bytes;
    used_end = (used_end + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1);
    mark_used(used_start, used_end - used_start);

    /* Mark first 1MB as used (BIOS, VGA, etc.) */
    mark_used(0, 0x100000);

    serial_print("[PMM] Total: ");
    serial_print_dec((int)(pmm_total * PAGE_SIZE / (1024 * 1024)));
    serial_print(" MB, Free: ");
    serial_print_dec((int)(pmm_free_count * PAGE_SIZE / (1024 * 1024)));
    serial_print(" MB, Used: ");
    serial_print_dec((int)((pmm_total - pmm_free_count) * PAGE_SIZE / (1024 * 1024)));
    serial_print(" MB\n");
}

/* ---- Allocate a physical page ---- */
void *pmm_alloc_page(void) {
    for (uint64_t i = 0; i < pmm_bitmap_size; i++) {
        if (pmm_bitmap[i] == 0xFFFFFFFF) continue;
        /* Find first zero bit */
        for (int j = 0; j < 32; j++) {
            if (!(pmm_bitmap[i] & (1U << j))) {
                uint64_t page = i * 32 + j;
                bitmap_set(page);
                pmm_free_count--;
                return (void *)(page * PAGE_SIZE);
            }
        }
    }
    return (void *)0; /* Out of memory */
}

/* ---- Free a physical page ---- */
void pmm_free_page(void *page) {
    uint64_t p = (uint64_t)page / PAGE_SIZE;
    if (p >= pmm_total) return;
    if (!bitmap_test(p)) return; /* double free */
    bitmap_clear(p);
    pmm_free_count++;
}

/* ---- Stats ---- */
uint64_t pmm_total_pages(void) { return pmm_total; }
uint64_t pmm_free_pages(void)  { return pmm_free_count; }
uint64_t pmm_used_pages(void)  { return pmm_total - pmm_free_count; }
