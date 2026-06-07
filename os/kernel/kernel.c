/*
 * ============================================================================
 * DNAOS Kernel - Main (C)
 * ============================================================================
 * 
 * This is the C entry point, called from boot.S after switching to long mode.
 * 
 * Responsibilities:
 *   1. Parse multiboot2 info (framebuffer, memory map)
 *   2. Set up IDT (interrupt descriptor table)
 *   3. Initialize keyboard driver (PS/2)
 *   4. Initialize framebuffer console
 *   5. Set up physical memory manager
 *   6. Launch DNAOS shell
 * ============================================================================
 */

#include <stdint.h>
#include <stddef.h>

/* ============================================================================
 * Types
 * ============================================================================
 */
typedef uint64_t size_t;

/* ============================================================================
 * VGA Framebuffer (set by GRUB multiboot2 framebuffer tag)
 * ============================================================================
 */
static uint32_t *fb_base = (uint32_t *)0xE0000000;  /* Will be updated from multiboot */
static uint32_t fb_width = 1280;
static uint32_t fb_height = 720;
static uint32_t fb_pitch = 1280 * 4;  /* bytes per row */
static uint32_t fb_bpp = 32;

/* ============================================================================
 * Console state
 * ============================================================================
 */
static uint32_t cursor_x = 0;
static uint32_t cursor_y = 0;
static uint32_t char_w = 8;
static uint32_t char_h = 16;

/* ATCG theme colors */
#define COLOR_BG         0x0D1117
#define COLOR_FG         0xE6EDF3
#define COLOR_A_GREEN    0x4CAF50
#define COLOR_T_RED      0xF44336
#define COLOR_C_BLUE     0x2196F3
#define COLOR_G_YELLOW   0xFFEB3B
#define COLOR_MUTED      0x484F58
#define COLOR_WINDOW_BG  0x161B22
#define COLOR_TITLEBAR   0x1C2333
#define COLOR_BORDER     0x30363D

/* ============================================================================
 * Font (8x16 bitmap font - built-in)
 * ============================================================================
 */
/* Minimal font: just ASCII 32-127, 8x16 pixels each */
/* We'll use a simplified approach: draw characters pixel by pixel */
/* For now, a basic 8x16 font for printable ASCII */

extern const uint8_t font_data[96][16];  /* Defined in font.S */

/* ============================================================================
 * Port I/O
 * ============================================================================
 */
static inline void outb(uint16_t port, uint8_t val) {
    __asm__ volatile ("outb %0, %1" : : "a"(val), "Nd"(port));
}

static inline uint8_t inb(uint16_t port) {
    uint8_t ret;
    __asm__ volatile ("inb %1, %0" : "=a"(ret) : "Nd"(port));
    return ret;
}

static inline void io_wait(void) {
    outb(0x80, 0);
}

/* ============================================================================
 * Framebuffer Drawing
 * ============================================================================
 */
static void fb_put_pixel(uint32_t x, uint32_t y, uint32_t color) {
    if (x < fb_width && y < fb_height) {
        uint32_t *pixel = fb_base + y * (fb_pitch / 4) + x;
        *pixel = color;
    }
}

static void fb_fill_rect(uint32_t x, uint32_t y, uint32_t w, uint32_t h, uint32_t color) {
    for (uint32_t dy = 0; dy < h; dy++) {
        for (uint32_t dx = 0; dx < w; dx++) {
            fb_put_pixel(x + dx, y + dy, color);
        }
    }
}

static void fb_draw_char(char c, uint32_t x, uint32_t y, uint32_t fg, uint32_t bg) {
    if (c < 32 || c > 127) c = '?';
    const uint8_t *glyph = font_data[(uint8_t)c - 32];
    
    for (uint8_t row = 0; row < 16; row++) {
        uint8_t bits = glyph[row];
        for (uint8_t col = 0; col < 8; col++) {
            uint32_t color = (bits & (0x80 >> col)) ? fg : bg;
            fb_put_pixel(x + col, y + row, color);
        }
    }
}

/* ============================================================================
 * Console Output
 * ============================================================================
 */
static void console_scroll(void) {
    /* Scroll up by one line */
    uint32_t line_bytes = fb_pitch * char_h;
    uint32_t total = fb_pitch * fb_height;
    
    /* Copy everything up by one line */
    for (uint32_t i = 0; i < total - line_bytes; i++) {
        ((uint8_t *)fb_base)[i] = ((uint8_t *)fb_base)[i + line_bytes];
    }
    
    /* Clear last line */
    fb_fill_rect(0, fb_height - char_h, fb_width, char_h, COLOR_BG);
    cursor_y = fb_height - char_h;
}

static void console_putchar(char c, uint32_t fg) {
    if (c == '\n') {
        cursor_x = 0;
        cursor_y += char_h;
        if (cursor_y + char_h > fb_height) {
            console_scroll();
        }
        return;
    }
    
    if (c == '\r') {
        cursor_x = 0;
        return;
    }
    
    if (c == '\t') {
        cursor_x = (cursor_x + 64) & ~63;
        return;
    }
    
    fb_draw_char(c, cursor_x, cursor_y, fg, COLOR_BG);
    cursor_x += char_w;
    
    if (cursor_x + char_w > fb_width) {
        cursor_x = 0;
        cursor_y += char_h;
        if (cursor_y + char_h > fb_height) {
            console_scroll();
        }
    }
}

static void console_print(const char *str, uint32_t fg) {
    while (*str) {
        console_putchar(*str++, fg);
    }
}

static void console_print_atcg(const char *str) {
    /* Print with ATCG coloring */
    while (*str) {
        uint32_t fg;
        switch (*str) {
            case 'A': fg = COLOR_A_GREEN; break;
            case 'T': fg = COLOR_T_RED; break;
            case 'C': fg = COLOR_C_BLUE; break;
            case 'G': fg = COLOR_G_YELLOW; break;
            default:  fg = COLOR_FG; break;
        }
        console_putchar(*str++, fg);
    }
}

/* ============================================================================
 * IDT (Interrupt Descriptor Table)
 * ============================================================================
 */
struct idt_entry {
    uint16_t offset_low;
    uint16_t selector;
    uint8_t  ist;
    uint8_t  type_attr;
    uint16_t offset_mid;
    uint32_t offset_high;
    uint32_t reserved;
} __attribute__((packed));

struct idt_ptr {
    uint16_t limit;
    uint64_t base;
} __attribute__((packed));

static struct idt_entry idt[256];
static struct idt_ptr idt_pointer;

static void idt_set_gate(uint8_t num, void *handler, uint16_t selector, uint8_t type) {
    uint64_t offset = (uint64_t)handler;
    idt[num].offset_low  = offset & 0xFFFF;
    idt[num].offset_mid  = (offset >> 16) & 0xFFFF;
    idt[num].offset_high = (offset >> 32) & 0xFFFFFFFF;
    idt[num].selector    = selector;
    idt[num].ist         = 0;
    idt[num].type_attr   = type;
    idt[num].reserved    = 0;
}

static void idt_install(void) {
    idt_pointer.limit = sizeof(idt) - 1;
    idt_pointer.base  = (uint64_t)&idt;
    
    /* Clear all entries */
    for (int i = 0; i < 256; i++) {
        idt_set_gate(i, 0, 0, 0);
    }
    
    /* Load IDT */
    __asm__ volatile ("lidt %0" : : "m"(idt_pointer));
}

/* ============================================================================
 * Keyboard Driver (PS/2 - IRQ1)
 * ============================================================================
 */
#define KBD_DATA    0x60
#define KBD_STATUS  0x64

static volatile char kbd_buffer[256];
static volatile uint8_t kbd_head = 0;
static volatile uint8_t kbd_tail = 0;

/* US keyboard scancode to ASCII (set 1) */
static const char scancode_to_ascii[128] = {
    0, 27, '1','2','3','4','5','6','7','8','9','0','-','=', '\b',
    '\t','q','w','e','r','t','y','u','i','o','p','[',']','\n',
    0, 'a','s','d','f','g','h','j','k','l',';','\'','`',
    0, '\\','z','x','c','v','b','n','m',',','.','/', 0,
    '*', 0, ' ',
};

/* Keyboard interrupt handler - called from assembly */
void keyboard_handler(void) {
    uint8_t scancode = inb(KBD_DATA);
    
    if (scancode & 0x80) {
        /* Key release - ignore for now */
        return;
    }
    
    if (scancode < sizeof(scancode_to_ascii)) {
        char c = scancode_to_ascii[scancode];
        if (c) {
            kbd_buffer[kbd_head] = c;
            kbd_head = (kbd_head + 1) & 0xFF;
        }
    }
}

static char kbd_getchar(void) {
    if (kbd_head == kbd_tail) return 0;
    char c = kbd_buffer[kbd_tail];
    kbd_tail = (kbd_tail + 1) & 0xFF;
    return c;
}

/* ============================================================================
 * Quaternary Core (Kernel-level)
 * ============================================================================
 */
static const char base_names[4] = {'A', 'T', 'C', 'G'};

static uint8_t quat_min(uint8_t a, uint8_t b) { return a < b ? a : b; }
static uint8_t quat_max(uint8_t a, uint8_t b) { return a > b ? a : b; }
static uint8_t quat_not(uint8_t a) { return 3 - a; }

static uint8_t quat_and_byte(uint8_t a, uint8_t b) {
    uint8_t result = 0;
    for (int i = 0; i < 4; i++) {
        uint8_t ba = (a >> (i*2)) & 3;
        uint8_t bb = (b >> (i*2)) & 3;
        result |= quat_min(ba, bb) << (i*2);
    }
    return result;
}

static uint8_t quat_or_byte(uint8_t a, uint8_t b) {
    uint8_t result = 0;
    for (int i = 0; i < 4; i++) {
        uint8_t ba = (a >> (i*2)) & 3;
        uint8_t bb = (b >> (i*2)) & 3;
        result |= quat_max(ba, bb) << (i*2);
    }
    return result;
}

static uint8_t quat_not_byte(uint8_t a) {
    uint8_t result = 0;
    for (int i = 0; i < 4; i++) {
        result |= quat_not((a >> (i*2)) & 3) << (i*2);
    }
    return result;
}

static void print_quat_byte(uint8_t val) {
    for (int i = 3; i >= 0; i--) {
        uint8_t base = (val >> (i*2)) & 3;
        uint32_t fg;
        switch (base) {
            case 0: fg = COLOR_A_GREEN; break;
            case 1: fg = COLOR_T_RED; break;
            case 2: fg = COLOR_C_BLUE; break;
            case 3: fg = COLOR_G_YELLOW; break;
            default: fg = COLOR_FG; break;
        }
        console_putchar(base_names[base], fg);
    }
}

/* ============================================================================
 * ATP Engine (Kernel-level)
 * ============================================================================
 */
static uint64_t atp_budget = 10000000000ULL;
static uint64_t atp_remaining = 10000000000ULL;
static uint64_t atp_ops = 0;

static int atp_consume(uint64_t amount) {
    if (atp_remaining < amount) return 0;
    atp_remaining -= amount;
    atp_ops++;
    return 1;
}

/* ============================================================================
 * GUI Drawing
 * ============================================================================
 */
static void draw_atcg_strip(uint32_t x, uint32_t y, uint32_t w, uint32_t h) {
    uint32_t qw = w / 4;
    fb_fill_rect(x, y, qw, h, COLOR_A_GREEN);
    fb_fill_rect(x + qw, y, qw, h, COLOR_T_RED);
    fb_fill_rect(x + 2*qw, y, qw, h, COLOR_C_BLUE);
    fb_fill_rect(x + 3*qw, y, qw, h, COLOR_G_YELLOW);
}

static void draw_desktop(void) {
    /* Background */
    fb_fill_rect(0, 0, fb_width, fb_height, COLOR_BG);
    
    /* ATCG top strip */
    draw_atcg_strip(0, 0, fb_width, 4);
    
    /* Title bar */
    fb_fill_rect(0, 4, fb_width, 32, COLOR_TITLEBAR);
    
    /* Title text */
    cursor_x = 12; cursor_y = 10;
    console_print("DNAOS", COLOR_A_GREEN);
    cursor_x = 72; cursor_y = 10;
    console_print("Quaternary Operating System v3.5", COLOR_MUTED);
    
    /* ATP bar in title bar */
    uint32_t atp_x = fb_width - 200;
    fb_fill_rect(atp_x, 12, 120, 16, 0x0A0E1A);
    uint32_t atp_pct = (uint32_t)(atp_remaining * 100 / atp_budget);
    uint32_t bar_w = 120 * atp_pct / 100;
    uint32_t bar_color = atp_pct > 50 ? COLOR_A_GREEN : (atp_pct > 20 ? COLOR_G_YELLOW : COLOR_T_RED);
    fb_fill_rect(atp_x, 12, bar_w, 16, bar_color);
    
    cursor_x = atp_x + 124; cursor_y = 14;
    console_print("ATP", COLOR_MUTED);
    
    /* Clock area */
    cursor_x = fb_width - 60; cursor_y = 14;
    console_print("00:00", COLOR_MUTED);
    
    /* Main window */
    uint32_t win_x = 40, win_y = 60, win_w = fb_width - 80, win_h = fb_height - 120;
    
    /* Window border */
    fb_fill_rect(win_x - 1, win_y - 1, win_w + 2, win_h + 2, COLOR_BORDER);
    
    /* Window background */
    fb_fill_rect(win_x, win_y, win_w, win_h, COLOR_WINDOW_BG);
    
    /* Window title bar */
    fb_fill_rect(win_x, win_y, win_w, 28, COLOR_TITLEBAR);
    draw_atcg_strip(win_x, win_y + 26, win_w, 2);
    
    cursor_x = win_x + 12; cursor_y = win_y + 6;
    console_print("Terminal - DNAOS", COLOR_FG);
    
    /* Close button */
    fb_fill_rect(win_x + win_w - 28, win_y + 4, 24, 20, 0xDA3633);
    cursor_x = win_x + win_w - 20; cursor_y = win_y + 6;
    console_print("X", 0xFFFFFF);
    
    /* Bottom taskbar */
    uint32_t tb_y = fb_height - 40;
    fb_fill_rect(0, tb_y, fb_width, 40, COLOR_TITLEBAR);
    draw_atcg_strip(0, tb_y, fb_width, 2);
    
    /* Start button */
    fb_fill_rect(4, tb_y + 6, 80, 28, 0x1A1F2E);
    cursor_x = 16; cursor_y = tb_y + 12;
    console_print("DNAOS", COLOR_A_GREEN);
    
    /* Terminal area - set cursor to inside window */
    cursor_x = win_x + 8;
    cursor_y = win_y + 36;
}

/* ============================================================================
 * DNAsm Shell
 * ============================================================================
 */
static uint8_t reg_a = 0x1B;  /* ATCG */
static uint8_t reg_b = 0xE4;  /* GCTA */
static char input_buf[256];
static int input_pos = 0;

static void shell_prompt(void) {
    console_print("\n", COLOR_FG);
    console_print("DNAOS", COLOR_A_GREEN);
    console_print(" > ", COLOR_FG);
}

static void shell_execute(void) {
    input_buf[input_pos] = '\0';
    input_pos = 0;
    
    atp_consume(1);
    
    /* Parse command */
    char cmd = input_buf[0];
    
    switch (cmd) {
        case 'a': case 'A': { /* AND */
            uint8_t result = quat_and_byte(reg_a, reg_b);
            console_print("  ", COLOR_FG);
            print_quat_byte(reg_a);
            console_print(" AND ", COLOR_FG);
            print_quat_byte(reg_b);
            console_print(" = ", COLOR_FG);
            print_quat_byte(result);
            reg_a = result;
            console_print("\n", COLOR_FG);
            break;
        }
        case 'o': case 'O': { /* OR */
            uint8_t result = quat_or_byte(reg_a, reg_b);
            console_print("  ", COLOR_FG);
            print_quat_byte(reg_a);
            console_print(" OR ", COLOR_FG);
            print_quat_byte(reg_b);
            console_print(" = ", COLOR_FG);
            print_quat_byte(result);
            reg_a = result;
            console_print("\n", COLOR_FG);
            break;
        }
        case 'n': case 'N': { /* NOT */
            uint8_t result = quat_not_byte(reg_a);
            console_print("  NOT ", COLOR_FG);
            print_quat_byte(reg_a);
            console_print(" = ", COLOR_FG);
            print_quat_byte(result);
            reg_a = result;
            console_print("\n", COLOR_FG);
            break;
        }
        case '+': { /* ADD */
            uint8_t result = 0, carry = 0;
            for (int i = 0; i < 4; i++) {
                uint8_t a = (reg_a >> (i*2)) & 3;
                uint8_t b = (reg_b >> (i*2)) & 3;
                uint8_t s = a + b + carry;
                result |= (s % 4) << (i*2);
                carry = s / 4;
            }
            console_print("  ", COLOR_FG);
            print_quat_byte(reg_a);
            console_print(" + ", COLOR_FG);
            print_quat_byte(reg_b);
            console_print(" = ", COLOR_FG);
            print_quat_byte(result);
            reg_a = result;
            console_print("\n", COLOR_FG);
            break;
        }
        case 'r': case 'R': { /* Show registers */
            console_print("  A = ", COLOR_FG);
            print_quat_byte(reg_a);
            console_print("  B = ", COLOR_FG);
            print_quat_byte(reg_b);
            console_print("\n", COLOR_FG);
            break;
        }
        case 'p': case 'P': { /* ATP status */
            console_print("  ATP: ", COLOR_C_BLUE);
            /* Print number - simplified */
            uint32_t pct = (uint32_t)(atp_remaining * 100 / atp_budget);
            char pct_str[8];
            int i = 0;
            if (pct >= 100) { pct_str[i++] = '1'; pct_str[i++] = '0'; pct_str[i++] = '0'; }
            else if (pct >= 10) { pct_str[i++] = '0' + pct/10; pct_str[i++] = '0' + pct%10; }
            else { pct_str[i++] = '0' + pct; }
            pct_str[i] = '%'; pct_str[i+1] = '\0';
            console_print(pct_str, COLOR_C_BLUE);
            console_print("\n", COLOR_FG);
            break;
        }
        case 'h': case 'H': case '?': { /* Help */
            console_print("  Commands:\n", COLOR_G_YELLOW);
            console_print("  A - AND (min)   O - OR (max)   N - NOT\n", COLOR_MUTED);
            console_print("  + - ADD (carry) R - Registers  P - ATP\n", COLOR_MUTED);
            console_print("  H - Help\n", COLOR_MUTED);
            break;
        }
        default:
            console_print("  Unknown: ", COLOR_T_RED);
            console_putchar(cmd, COLOR_T_RED);
            console_print("\n", COLOR_FG);
            break;
    }
}

/* ============================================================================
 * Kernel Main
 * ============================================================================
 */
void kernel_main(void) {
    /* Initialize IDT */
    idt_install();
    
    /* Draw desktop */
    draw_desktop();
    
    /* Print banner */
    console_print("DNAOS v3.5 - Quaternary Operating System\n", COLOR_A_GREEN);
    console_print("ATCG Native | Booted from bare metal\n", COLOR_MUTED);
    console_print("Type H for help\n", COLOR_MUTED);
    
    /* Main loop */
    shell_prompt();
    
    while (1) {
        char c = kbd_getchar();
        if (c) {
            if (c == '\n') {
                shell_execute();
                shell_prompt();
            } else if (c == '\b') {
                if (input_pos > 0) {
                    input_pos--;
                    cursor_x -= char_w;
                    fb_draw_char(' ', cursor_x, cursor_y, COLOR_FG, COLOR_WINDOW_BG);
                }
            } else {
                if (input_pos < 255) {
                    input_buf[input_pos++] = c;
                    console_putchar(c, COLOR_FG);
                }
            }
        }
        
        /* HLT until next interrupt */
        __asm__ volatile ("hlt");
    }
}
