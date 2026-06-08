; ============================================================================
; DNAOS - Linker Script
; ============================================================================
; Controls how the kernel is linked. Defines memory layout and sections.
; ============================================================================

ENTRY(kernel_main)

SECTIONS
{
    /* Kernel loaded at 1MB (standard for multiboot) */
    . = 1M;

    /* Multiboot header must be in first 8KB */
    .multiboot ALIGN(4K) :
    {
        *(.multiboot)
    }

    /* Code section */
    .text ALIGN(4K) :
    {
        *(.text)
        *(.text.*)
    }

    /* Read-only data */
    .rodata ALIGN(4K) :
    {
        *(.rodata)
        *(.rodata.*)
    }

    /* Initialized data */
    .data ALIGN(4K) :
    {
        *(.data)
        *(.data.*)
    }

    /* BSS (uninitialized data) */
    .bss ALIGN(4K) :
    {
        *(COMMON)
        *(.bss)
        *(.bss.*)
    }

    /* Stack */
    . = ALIGN(4K);
    . += 64K;

    /* Discard unwanted sections */
    /DISCARD/ :
    {
        *(.comment)
        *(.note.*)
        *(.eh_frame*)
    }
}
