/* DNAOS Kernel - Linker Script (x86_64) */

ENTRY(_start)

SECTIONS
{
    /* Kernel loaded at 1MB by GRUB */
    . = 1M;
    
    /* Multiboot header must be in first 8KB */
    .multiboot : {
        *(.multiboot)
    }
    
    .text : {
        *(.text.boot)
        *(.text*)
    }
    
    .rodata : {
        *(.rodata*)
    }
    
    .data : {
        *(.data*)
    }
    
    .bss : {
        *(COMMON)
        *(.bss*)
    }
    
    /DISCARD/ : {
        *(.comment)
        *(.note*)
        *(.eh_frame*)
    }
}
