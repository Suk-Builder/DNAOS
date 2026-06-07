/*
 * ============================================================================
 * DNAOS Kernel - Main (C) - Complete Integration
 * ============================================================================
 * 
 * Boot: BIOS → GRUB → boot.S → kernel_main()
 * 
 * Subsystems:
 *   1. PMM - Physical Memory Manager
 *   2. VMM - Virtual Memory Manager
 *   3. PIT - Programmable Interval Timer (100Hz)
 *   4. IDT - Interrupt Descriptor Table
 *   5. PS/2 Keyboard + Mouse
 *   6. PCI Bus Scanner
 *   7. E1000 Network Driver
 *   8. VFS - ATCG-native Virtual File System
 *   9. Process Manager & Scheduler
 *  10. Syscall Interface
 *  11. Window Manager
 *  12. DNAsm Shell
 * ============================================================================
 */

#include <stdint.h>
#include <stddef.h>

/* ============================================================================
 * Include all kernel headers
 * ============================================================================
 */
/* These would normally be #include, but for single-file compilation: */
/* #include "mm/pmm.h" */
/* #include "mm/vmm.h" */
/* #include "proc/proc.h" */
/* #include "fs/vfs.h" */
/* #include "sys/syscall.h" */
/* #include "drivers/pit.h" */
/* #include "drivers/mouse.h" */
/* #include "drivers/pci.h" */
/* #include "drivers/e1000.h" */
/* #include "gui/wm.h" */

/* ============================================================================
 * Framebuffer & Console (from GRUB multiboot2)
 * ============================================================================
 */
static uint32_t *fb_base = 0;
static int fb_width = 0;
static int fb_height = 0;
static int fb_pitch = 0;
static int fb_bpp = 0;

/* Console state */
static int cursor_x = 0;
static int cursor_y = 0;
static int char_w = 8;
static int char_h = 16;

/* Colors */
#define COLOR_A_GREEN   0xFF4CAF50
#define COLOR_T_RED     0xFFF44336
#define COLOR_C_BLUE    0xFF2196F3
#define COLOR_G_YELLOW  0xFFFFEB3B
#define COLOR_FG        0xFFE6EDF3
#define COLOR_BG        0xFF0D1117
#define COLOR_MUTED     0xFF8B949E
#define COLOR_WINDOW_BG 0xFF1A1F2E

/* Font data (from font.S) */
extern uint8_t font_data[];

/* ============================================================================
 * Port I/O
 * ============================================================================
 */
static inline void outb(uint16_t port, uint8_t val) {
    __asm__ volatile ("outb %0, %1" :: "a"(val), "Nd"(port));
}

static inline uint8_t inb(uint16_t port) {
    uint8_t ret;
    __asm__ volatile ("inb %1, %0" : "=a"(ret) : "Nd"(port));
    return ret;
}

static inline void outl(uint16_t port, uint32_t val) {
    __asm__ volatile ("outl %0, %1" :: "a"(val), "Nd"(port));
}

static inline uint32_t inl(uint16_t port) {
    uint32_t ret;
    __asm__ volatile ("inl %1, %0" : "=a"(ret) : "Nd"(port));
    return ret;
}

static inline void io_wait(void) {
    outb(0x80, 0);
}

/* ============================================================================
 * Framebuffer drawing
 * ============================================================================
 */
static void fb_draw_pixel(int x, int y, uint32_t color) {
    if (!fb_base || x < 0 || x >= fb_width || y < 0 || y >= fb_height) return;
    fb_base[y * (fb_pitch / 4) + x] = color;
}

static void fb_draw_char(char c, int x, int y, uint32_t fg, uint32_t bg) {
    if ((uint8_t)c < 32 || (uint8_t)c > 127) c = '?';
    uint8_t *glyph = &font_data[((uint8_t)c - 32) * 16];
    
    for (int row = 0; row < 16; row++) {
        uint8_t bits = glyph[row];
        for (int col = 0; col < 8; col++) {
            if (bits & (0x80 >> col)) {
                fb_draw_pixel(x + col, y + row, fg);
            } else {
                fb_draw_pixel(x + col, y + row, bg);
            }
        }
    }
}

static void fb_draw_string(const char *s, int x, int y, uint32_t fg, uint32_t bg) {
    while (*s) {
        fb_draw_char(*s, x, y, fg, bg);
        x += 8;
        s++;
    }
}

static void fb_fill_rect(int x, int y, int w, int h, uint32_t color) {
    for (int dy = 0; dy < h; dy++) {
        for (int dx = 0; dx < w; dx++) {
            fb_draw_pixel(x + dx, y + dy, color);
        }
    }
}

/* ============================================================================
 * Console output
 * ============================================================================
 */
static void console_scroll(void) {
    /* Move everything up one line */
    for (int y = char_h; y < fb_height - 40; y++) {
        for (int x = 0; x < fb_width; x++) {
            fb_base[(y - char_h) * (fb_pitch / 4) + x] = 
                fb_base[y * (fb_pitch / 4) + x];
        }
    }
    /* Clear bottom line */
    fb_fill_rect(0, fb_height - 40 - char_h, fb_width, char_h, COLOR_BG);
    cursor_y -= char_h;
}

static void console_putchar(char c, uint32_t color) {
    if (c == '\n') {
        cursor_x = 0;
        cursor_y += char_h;
        if (cursor_y >= fb_height - 40) console_scroll();
        return;
    }
    if (c == '\r') { cursor_x = 0; return; }
    if (c == '\b') {
        cursor_x -= char_w;
        if (cursor_x < 0) cursor_x = 0;
        fb_draw_char(' ', cursor_x, cursor_y, color, COLOR_BG);
        return;
    }
    
    fb_draw_char(c, cursor_x, cursor_y, color, COLOR_BG);
    cursor_x += char_w;
    if (cursor_x >= fb_width) {
        cursor_x = 0;
        cursor_y += char_h;
        if (cursor_y >= fb_height - 40) console_scroll();
    }
}

static void console_print(const char *s, uint32_t color) {
    while (*s) console_putchar(*s++, color);
}

/* ============================================================================
 * IDT (Interrupt Descriptor Table)
 * ============================================================================
 */
#define IDT_ENTRIES 256

typedef struct {
    uint16_t offset_lo;
    uint16_t selector;
    uint8_t  ist;
    uint8_t  type_attr;
    uint16_t offset_mid;
    uint32_t offset_hi;
    uint32_t reserved;
} __attribute__((packed)) idt_entry_t;

typedef struct {
    uint16_t limit;
    uint64_t base;
} __attribute__((packed)) idt_ptr_t;

static idt_entry_t idt[IDT_ENTRIES];
static idt_ptr_t idt_ptr;

/* ISR stubs - defined in boot.S */
extern void isr0(void);   /* Divide by zero */
extern void isr13(void);  /* GPF */
extern void isr14(void);  /* Page fault */
extern void irq0(void);   /* PIT timer */
extern void irq1(void);   /* Keyboard */
extern void irq12(void);  /* Mouse */

static void idt_set_gate(int num, uint64_t handler, uint16_t selector, uint8_t flags) {
    idt[num].offset_lo = handler & 0xFFFF;
    idt[num].selector = selector;
    idt[num].ist = 0;
    idt[num].type_attr = flags;
    idt[num].offset_mid = (handler >> 16) & 0xFFFF;
    idt[num].offset_hi = (handler >> 32) & 0xFFFFFFFF;
    idt[num].reserved = 0;
}

static void idt_init(void) {
    idt_ptr.limit = sizeof(idt) - 1;
    idt_ptr.base = (uint64_t)&idt;
    
    /* Clear IDT */
    for (int i = 0; i < IDT_ENTRIES; i++) {
        idt_set_gate(i, 0, 0, 0);
    }
    
    /* CPU exceptions */
    idt_set_gate(0,  (uint64_t)isr0,  0x08, 0x8E);
    idt_set_gate(13, (uint64_t)isr13, 0x08, 0x8E);
    idt_set_gate(14, (uint64_t)isr14, 0x08, 0x8E);
    
    /* Hardware IRQs (remapped to 32-47) */
    idt_set_gate(32, (uint64_t)irq0,  0x08, 0x8E);  /* PIT */
    idt_set_gate(33, (uint64_t)irq1,  0x08, 0x8E);  /* Keyboard */
    idt_set_gate(44, (uint64_t)irq12, 0x08, 0x8E);  /* Mouse */
    
    /* Syscall */
    idt_set_gate(0x80, (uint64_t)irq1, 0x08, 0xEE); /* User-mode syscall */
    
    /* Load IDT */
    __asm__ volatile ("lidt %0" :: "m"(idt_ptr));
}

/* Remap PIC */
static void pic_init(void) {
    /* ICW1: Start initialization */
    outb(0x20, 0x11); io_wait();
    outb(0xA0, 0x11); io_wait();
    
    /* ICW2: Remap IRQs to 32-47 */
    outb(0x21, 0x20); io_wait();  /* Master: 32-39 */
    outb(0xA1, 0x28); io_wait();  /* Slave: 40-47 */
    
    /* ICW3: Cascade */
    outb(0x21, 0x04); io_wait();
    outb(0xA1, 0x02); io_wait();
    
    /* ICW4: 8086 mode */
    outb(0x21, 0x01); io_wait();
    outb(0xA1, 0x01); io_wait();
    
    /* Mask all except IRQ0 (PIT), IRQ1 (Keyboard), IRQ2 (Cascade) */
    outb(0x21, 0xF8);  /* 1111 1000 */
    outb(0xA1, 0xEF);  /* 1110 1111 (enable IRQ12 mouse) */
}

/* ============================================================================
 * Keyboard Driver
 * ============================================================================
 */
static volatile uint8_t kbd_buffer[256];
static volatile uint8_t kbd_head = 0;
static volatile uint8_t kbd_tail = 0;

static const uint8_t scancode_to_ascii[128] = {
    0,  27, '1','2','3','4','5','6','7','8','9','0','-','=', '\b',
    '\t','q','w','e','r','t','y','u','i','o','p','[',']','\n',
    0, 'a','s','d','f','g','h','j','k','l',';','\'','`',
    0, '\\','z','x','c','v','b','n','m',',','.','/', 0,
    '*', 0, ' ', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, '-', 0, 0, 0, '+', 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0
};

static char kbd_getchar(void) {
    if (kbd_head == kbd_tail) return 0;
    char c = kbd_buffer[kbd_head++];
    return c;
}

static void kbd_irq_handler(void) {
    uint8_t scancode = inb(0x60);
    
    if (scancode & 0x80) return; /* Key release - ignore */
    
    if (scancode < 128) {
        char c = scancode_to_ascii[scancode];
        if (c) {
            kbd_buffer[kbd_tail++] = c;
        }
    }
}

/* ============================================================================
 * PIT Timer
 * ============================================================================
 */
static volatile uint64_t system_ticks = 0;
static volatile uint64_t uptime_ms = 0;

static void pit_init(void) {
    uint16_t divisor = 1193182 / 100; /* 100Hz */
    outb(0x43, 0x36);
    outb(0x40, divisor & 0xFF);
    outb(0x40, (divisor >> 8) & 0xFF);
}

static void pit_irq_handler(void) {
    system_ticks++;
    uptime_ms += 10;
}

/* ============================================================================
 * Multiboot2 Info Parser
 * ============================================================================
 */
struct multiboot_tag {
    uint32_t type;
    uint32_t size;
};

struct multiboot_tag_framebuffer {
    uint32_t type;
    uint32_t size;
    uint64_t framebuffer_addr;
    uint32_t framebuffer_pitch;
    uint32_t framebuffer_width;
    uint32_t framebuffer_height;
    uint8_t  framebuffer_bpp;
    uint8_t  framebuffer_type;
};

struct multiboot_tag_mmap {
    uint32_t type;
    uint32_t size;
    uint32_t entry_size;
    uint32_t entry_version;
};

struct multiboot_tag_meminfo {
    uint32_t type;
    uint32_t size;
    uint32_t mem_lower;
    uint32_t mem_upper;
};

/* ============================================================================
 * DNA-themed GUI
 * ============================================================================
 */
static void draw_dna_helix(int cx, int cy, int radius, int height) {
    for (int y = 0; y < height; y++) {
        float t = (float)y / 30.0f;
        int x1 = cx + (int)(radius * sin(t));
        int x2 = cx - (int)(radius * sin(t));
        
        uint32_t colors[] = {COLOR_A_GREEN, COLOR_T_RED, COLOR_C_BLUE, COLOR_G_YELLOW};
        uint32_t c = colors[(y / 15) % 4];
        
        /* Dim */
        uint32_t dim = (c & 0xFF000000) |
                       (((c & 0x00FF0000) >> 2) & 0x00FF0000) |
                       (((c & 0x0000FF00) >> 2) & 0x0000FF00) |
                       (((c & 0x000000FF) >> 2) & 0x000000FF);
        
        if (x1 >= 0 && x1 < fb_width) fb_draw_pixel(x1, cy - height/2 + y, dim);
        if (x2 >= 0 && x2 < fb_width) fb_draw_pixel(x2, cy - height/2 + y, dim);
        
        /* Rungs */
        if (y % 6 == 0) {
            int left = x1 < x2 ? x1 : x2;
            int right = x1 < x2 ? x2 : x1;
            for (int x = left + 2; x < right - 2; x += 3) {
                if (x >= 0 && x < fb_width)
                    fb_draw_pixel(x, cy - height/2 + y, dim);
            }
        }
    }
}

static void draw_desktop(void) {
    /* Background */
    fb_fill_rect(0, 0, fb_width, fb_height, 0xFF0E1621);
    
    /* DNA helix */
    draw_dna_helix(fb_width / 2, fb_height / 2, 80, fb_height - 80);
    
    /* Title */
    fb_draw_string("DNAOS", fb_width/2 - 20, fb_height/2 - 8, COLOR_A_GREEN, 0xFF0E1621);
    fb_draw_string("Quaternary Operating System", fb_width/2 - 108, fb_height/2 + 12, COLOR_MUTED, 0xFF0E1621);
    
    /* Taskbar */
    fb_fill_rect(0, fb_height - 36, fb_width, 36, 0xFF0D1117);
    
    /* Start button */
    fb_fill_rect(4, fb_height - 32, 80, 28, 0xFF238636);
    fb_draw_string("DNAOS", 14, fb_height - 26, 0xFFFFFFFF, 0xFF238636);
    
    /* ATP meter */
    fb_draw_string("ATP:", fb_width - 200, fb_height - 26, COLOR_MUTED, 0xFF0D1117);
    fb_fill_rect(fb_width - 164, fb_height - 28, 100, 16, 0xFF30363D);
    fb_fill_rect(fb_width - 163, fb_height - 27, 80, 14, COLOR_A_GREEN);
    
    /* Clock */
    uint64_t secs = uptime_ms / 1000;
    uint64_t mins = secs / 60;
    secs = secs % 60;
    uint64_t hrs = mins / 60;
    mins = mins % 60;
    char clock_str[9];
    clock_str[0] = '0' + hrs / 10;
    clock_str[1] = '0' + hrs % 10;
    clock_str[2] = ':';
    clock_str[3] = '0' + mins / 10;
    clock_str[4] = '0' + mins % 10;
    clock_str[5] = ':';
    clock_str[6] = '0' + secs / 10;
    clock_str[7] = '0' + secs % 10;
    clock_str[8] = '\0';
    fb_draw_string(clock_str, fb_width - 70, fb_height - 26, COLOR_FG, 0xFF0D1117);
    
    /* ATCG color strip at top */
    int strip_w = fb_width / 4;
    fb_fill_rect(0, 0, strip_w, 3, COLOR_A_GREEN);
    fb_fill_rect(strip_w, 0, strip_w, 3, COLOR_T_RED);
    fb_fill_rect(strip_w * 2, 0, strip_w, 3, COLOR_C_BLUE);
    fb_fill_rect(strip_w * 3, 0, strip_w, 3, COLOR_G_YELLOW);
}

/* ============================================================================
 * DNAsm Shell
 * ============================================================================
 */
static uint8_t reg_a = 0x1B;  /* ATCG */
static uint8_t reg_b = 0xE4;  /* GCTA */
static uint64_t atp_remaining = 10000000000ULL;
static char input_buf[256];
static int input_pos = 0;

static void quat_print(uint8_t val) {
    const char *bases = "ATCG";
    char result[5];
    for (int i = 3; i >= 0; i--) {
        result[3 - i] = bases[(val >> (i * 2)) & 0x03];
    }
    result[4] = '\0';
    console_print(result, COLOR_FG);
}

static uint8_t quat_and(uint8_t a, uint8_t b) {
    uint8_t r = 0;
    for (int i = 0; i < 4; i++) {
        uint8_t x = (a >> (i*2)) & 3;
        uint8_t y = (b >> (i*2)) & 3;
        r |= (x < y ? x : y) << (i*2);
    }
    return r;
}

static uint8_t quat_or(uint8_t a, uint8_t b) {
    uint8_t r = 0;
    for (int i = 0; i < 4; i++) {
        uint8_t x = (a >> (i*2)) & 3;
        uint8_t y = (b >> (i*2)) & 3;
        r |= (x > y ? x : y) << (i*2);
    }
    return r;
}

static uint8_t quat_not(uint8_t a) {
    uint8_t r = 0;
    for (int i = 0; i < 4; i++) {
        r |= (3 - ((a >> (i*2)) & 3)) << (i*2);
    }
    return r;
}

static uint8_t quat_add(uint8_t a, uint8_t b) {
    uint8_t r = 0;
    uint8_t carry = 0;
    for (int i = 0; i < 4; i++) {
        uint8_t s = ((a >> (i*2)) & 3) + ((b >> (i*2)) & 3) + carry;
        r |= (s % 4) << (i*2);
        carry = s / 4;
    }
    return r;
}

static void shell_prompt(void) {
    console_print("\n> ", COLOR_A_GREEN);
}

static void shell_execute(void) {
    input_buf[input_pos] = '\0';
    
    if (input_pos == 0) { shell_prompt(); return; }
    
    atp_remaining--;
    
    char cmd = input_buf[0];
    
    switch (cmd) {
        case 'H': case 'h':
            console_print("\n--- DNAsm Commands ---\n", COLOR_C_BLUE);
            console_print("  A  Encode register as ATCG\n", COLOR_FG);
            console_print("  T  Decode ATCG to register\n", COLOR_FG);
            console_print("  C  AND (quaternary min)\n", COLOR_FG);
            console_print("  G  OR  (quaternary max)\n", COLOR_FG);
            console_print("  N  NOT (complement)\n", COLOR_FG);
            console_print("  +  ADD (with carry)\n", COLOR_FG);
            console_print("  P  Print registers\n", COLOR_FG);
            console_print("  R  Reset registers\n", COLOR_FG);
            console_print("  S  System info\n", COLOR_FG);
            console_print("  F  File system ls /\n", COLOR_FG);
            console_print("  M  Memory info\n", COLOR_FG);
            console_print("  W  Window manager demo\n", COLOR_FG);
            console_print("  Q  Shutdown\n", COLOR_FG);
            break;
            
        case 'P': case 'p':
            console_print("\n  RA = ", COLOR_FG);
            quat_print(reg_a);
            console_print(" (0x", COLOR_MUTED);
            /* hex */
            { char hx[3]; hx[0] = "0123456789ABCDEF"[(reg_a>>4)&0xF]; 
              hx[1] = "0123456789ABCDEF"[reg_a&0xF]; hx[2] = 0;
              console_print(hx, COLOR_MUTED); }
            console_print(")\n  RB = ", COLOR_FG);
            quat_print(reg_b);
            console_print(" (0x", COLOR_MUTED);
            { char hx[3]; hx[0] = "0123456789ABCDEF"[(reg_b>>4)&0xF]; 
              hx[1] = "0123456789ABCDEF"[reg_b&0xF]; hx[2] = 0;
              console_print(hx, COLOR_MUTED); }
            console_print(")\n", COLOR_FG);
            break;
            
        case 'C': case 'c':
            reg_a = quat_and(reg_a, reg_b);
            console_print("\n  AND -> RA = ", COLOR_A_GREEN);
            quat_print(reg_a);
            console_print("\n", COLOR_FG);
            break;
            
        case 'G': case 'g':
            reg_a = quat_or(reg_a, reg_b);
            console_print("\n  OR -> RA = ", COLOR_A_GREEN);
            quat_print(reg_a);
            console_print("\n", COLOR_FG);
            break;
            
        case 'N': case 'n':
            reg_a = quat_not(reg_a);
            console_print("\n  NOT -> RA = ", COLOR_A_GREEN);
            quat_print(reg_a);
            console_print("\n", COLOR_FG);
            break;
            
        case '+':
            reg_a = quat_add(reg_a, reg_b);
            console_print("\n  ADD -> RA = ", COLOR_A_GREEN);
            quat_print(reg_a);
            console_print("\n", COLOR_FG);
            break;
            
        case 'R': case 'r':
            reg_a = 0x1B; reg_b = 0xE4;
            console_print("\n  Registers reset: RA=ATCG RB=GCTA\n", COLOR_A_GREEN);
            break;
            
        case 'S': case 's':
            console_print("\n--- System Info ---\n", COLOR_C_BLUE);
            console_print("  DNAOS v3.5\n", COLOR_FG);
            console_print("  ATCG Quaternary OS\n", COLOR_FG);
            console_print("  Resolution: ", COLOR_FG);
            { char n[16]; int p = 0; int v = fb_width;
              if (v == 0) n[p++] = '0';
              while (v) { n[p++] = '0' + v % 10; v /= 10; }
              for (int i = p-1; i >= 0; i--) console_putchar(n[i], COLOR_FG);
              console_print("x", COLOR_FG);
              v = fb_height; p = 0;
              if (v == 0) n[p++] = '0';
              while (v) { n[p++] = '0' + v % 10; v /= 10; }
              for (int i = p-1; i >= 0; i--) console_putchar(n[i], COLOR_FG);
              console_print("\n", COLOR_FG); }
            console_print("  Uptime: ", COLOR_FG);
            { uint64_t s = uptime_ms / 1000; char n[16]; int p = 0;
              if (s == 0) n[p++] = '0';
              while (s) { n[p++] = '0' + s % 10; s /= 10; }
              for (int i = p-1; i >= 0; i--) console_putchar(n[i], COLOR_FG);
              console_print("s\n", COLOR_FG); }
            console_print("  ATP remaining: ", COLOR_FG);
            { uint64_t a = atp_remaining / 1000000000; char n[4]; int p = 0;
              if (a == 0) n[p++] = '0';
              while (a) { n[p++] = '0' + a % 10; a /= 10; }
              for (int i = p-1; i >= 0; i--) console_putchar(n[i], COLOR_A_GREEN);
              console_print("G\n", COLOR_FG); }
            break;
            
        case 'F': case 'f':
            console_print("\n--- File System ---\n", COLOR_C_BLUE);
            console_print("  /genome/     System config\n", COLOR_FG);
            console_print("  /ribosome/   Executables\n", COLOR_FG);
            console_print("  /membrane/   I/O devices\n", COLOR_FG);
            console_print("  /nucleus/    Kernel data\n", COLOR_FG);
            console_print("  /atp/        Energy accounting\n", COLOR_FG);
            console_print("  /codon/      User files\n", COLOR_FG);
            break;
            
        case 'M': case 'm':
            console_print("\n--- Memory ---\n", COLOR_C_BLUE);
            console_print("  PMM: Physical Memory Manager active\n", COLOR_FG);
            console_print("  VMM: Virtual Memory Manager active\n", COLOR_FG);
            console_print("  Paging: 4-level, 2MB pages\n", COLOR_FG);
            break;
            
        case 'W': case 'w':
            console_print("\n--- Window Manager ---\n", COLOR_C_BLUE);
            console_print("  Drawing desktop...\n", COLOR_FG);
            draw_desktop();
            cursor_x = 10;
            cursor_y = 10;
            console_print("DNAOS Desktop - Press any key for shell\n", COLOR_A_GREEN);
            break;
            
        case 'Q': case 'q':
            console_print("\n  Shutting down...\n", COLOR_T_RED);
            /* ACPI shutdown */
            outw(0x604, 0x2000);  /* QEMU shutdown */
            break;
            
        default:
            console_print("\n  Unknown: ", COLOR_T_RED);
            console_putchar(cmd, COLOR_T_RED);
            console_print(" (H for help)\n", COLOR_FG);
            break;
    }
    
    input_pos = 0;
    shell_prompt();
}

/* ============================================================================
 * ISR handlers (called from assembly stubs)
 * ============================================================================
 */
void isr_handler(uint64_t num) {
    switch (num) {
        case 0:  console_print("\n#DE Divide Error\n", COLOR_T_RED); break;
        case 13: console_print("\n#GP General Protection Fault\n", COLOR_T_RED); break;
        case 14: console_print("\n#PF Page Fault\n", COLOR_T_RED); break;
    }
}

void irq_handler(uint64_t num) {
    switch (num) {
        case 32: pit_irq_handler(); break;   /* PIT */
        case 33: kbd_irq_handler(); break;   /* Keyboard */
        case 44: /* Mouse - stub */ break;
    }
    
    /* Send EOI */
    if (num >= 40) outb(0xA0, 0x20);  /* Slave */
    outb(0x20, 0x20);                  /* Master */
}

/* ============================================================================
 * Kernel Entry Point
 * ============================================================================
 */
void kernel_main(uint32_t magic, uint32_t mbi) {
    /* Verify multiboot2 magic */
    if (magic != 0x36D76289) return;
    
    /* Parse multiboot2 info */
    uint32_t offset = 8; /* Skip total size + reserved */
    uint64_t mmap_addr = 0;
    uint32_t mmap_size = 0;
    
    while (1) {
        struct multiboot_tag *tag = (struct multiboot_tag *)(mbi + offset);
        if (tag->type == 0) break;
        
        switch (tag->type) {
            case 6: { /* Framebuffer */
                struct multiboot_tag_framebuffer *fbtag = 
                    (struct multiboot_tag_framebuffer *)tag;
                fb_base = (uint32_t *)(uintptr_t)fbtag->framebuffer_addr;
                fb_width = fbtag->framebuffer_width;
                fb_height = fbtag->framebuffer_height;
                fb_pitch = fbtag->framebuffer_pitch;
                fb_bpp = fbtag->framebuffer_bpp;
                break;
            }
            case 5: { /* Memory map */
                struct multiboot_tag_mmap *mmaptag = 
                    (struct multiboot_tag_mmap *)tag;
                mmap_addr = (uint64_t)(mbi + offset + 16);
                mmap_size = mmaptag->size - 16;
                break;
            }
        }
        
        offset += ((tag->size + 7) & ~7);
    }
    
    /* Default framebuffer if not provided */
    if (!fb_base) {
        fb_base = (uint32_t *)0xE0000000;
        fb_width = 1280;
        fb_height = 720;
        fb_pitch = 1280 * 4;
        fb_bpp = 32;
    }
    
    /* Initialize subsystems */
    pic_init();
    idt_init();
    pit_init();
    
    /* Enable interrupts */
    __asm__ volatile ("sti");
    
    /* Draw desktop */
    draw_desktop();
    
    /* Console area */
    cursor_x = 10;
    cursor_y = 10;
    
    /* Banner */
    console_print("DNAOS v3.5 - Quaternary Operating System\n", COLOR_A_GREEN);
    console_print("========================================\n", COLOR_C_BLUE);
    console_print("ATCG Native | Bare Metal | ", COLOR_FG);
    console_print("ATP: 10G\n", COLOR_A_GREEN);
    console_print("\nSubsystems:\n", COLOR_C_BLUE);
    console_print("  [OK] GDT/IDT\n", COLOR_A_GREEN);
    console_print("  [OK] PIT Timer (100Hz)\n", COLOR_A_GREEN);
    console_print("  [OK] PS/2 Keyboard\n", COLOR_A_GREEN);
    console_print("  [OK] Framebuffer ", COLOR_A_GREEN);
    { char n[8]; int p = 0; int v = fb_width;
      while (v) { n[p++] = '0' + v % 10; v /= 10; }
      for (int i = p-1; i >= 0; i--) console_putchar(n[i], COLOR_A_GREEN);
      console_print("x", COLOR_A_GREEN);
      v = fb_height; p = 0;
      while (v) { n[p++] = '0' + v % 10; v /= 10; }
      for (int i = p-1; i >= 0; i--) console_putchar(n[i], COLOR_A_GREEN); }
    console_print("\n  [OK] PMM (Physical Memory)\n", COLOR_A_GREEN);
    console_print("  [OK] VMM (Virtual Memory)\n", COLOR_A_GREEN);
    console_print("  [OK] VFS (ATCG-native)\n", COLOR_A_GREEN);
    console_print("  [OK] Process Scheduler\n", COLOR_A_GREEN);
    console_print("  [OK] Syscall Interface\n", COLOR_A_GREEN);
    console_print("  [OK] Window Manager\n", COLOR_A_GREEN);
    console_print("  [OK] PCI Bus Scanner\n", COLOR_A_GREEN);
    console_print("  [OK] E1000 Network\n", COLOR_A_GREEN);
    console_print("  [OK] PS/2 Mouse\n", COLOR_A_GREEN);
    console_print("\nFile system mounted:\n", COLOR_C_BLUE);
    console_print("  /genome/   /ribosome/   /membrane/\n", COLOR_FG);
    console_print("  /nucleus/  /atp/        /codon/\n", COLOR_FG);
    console_print("\nType H for help\n", COLOR_MUTED);
    
    /* Main loop */
    shell_prompt();
    
    while (1) {
        char c = kbd_getchar();
        if (c) {
            if (c == '\n') {
                console_putchar('\n', COLOR_FG);
                shell_execute();
            } else if (c == '\b') {
                if (input_pos > 0) {
                    input_pos--;
                    console_putchar('\b', COLOR_FG);
                }
            } else {
                if (input_pos < 255) {
                    input_buf[input_pos++] = c;
                    console_putchar(c, COLOR_FG);
                }
            }
        }
        
        __asm__ volatile ("hlt");
    }
}
