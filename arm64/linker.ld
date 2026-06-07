/* DNAOS ARM64 Linker Script - Snapdragon 845 */

ENTRY(_start)

SECTIONS
{
    /* Kernel load address (matches boot.img header) */
    . = 0x00008000;
    
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
        __bss_start = .;
        *(.bss*)
        *(COMMON)
        __bss_end = .;
    }
    
    /DISCARD/ : {
        *(.comment)
        *(.note*)
        *(.eh_frame*)
    }
}
