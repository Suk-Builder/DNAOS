/*
 * ============================================================================
 * DNAOS - Window Manager
 * ============================================================================
 * 
 * Software-rendered windowing system on top of framebuffer.
 * No GPU needed. Pure CPU rendering.
 *
 * Features:
 *   - Multiple overlapping windows
 *   - Title bars with close/minimize/maximize buttons
 *   - Drag to move windows
 *   - Z-order management
 *   - DNA-themed decorations
 *   - ATCG color scheme
 *   - Taskbar with start menu
 *   - Desktop icons
 *
 * Input: PS/2 mouse + keyboard
 * ============================================================================
 */

#ifndef WM_H
#define WM_H

#include <stdint.h>

/* ============================================================================
 * Theme
 * ============================================================================
 */
#define WM_COLOR_DESKTOP    0xFF0E1621  /* Dark blue-black */
#define WM_COLOR_WINDOW     0xFF1A1F2E  /* Dark window bg */
#define WM_COLOR_TITLEBAR   0xFF2D333B  /* Title bar */
#define WM_COLOR_TITLEBAR_A 0xFF4CAF50  /* Active title bar accent */
#define WM_COLOR_TASKBAR    0xFF0D1117  /* Taskbar */
#define WM_COLOR_TEXT       0xFFE6EDF3  /* Primary text */
#define WM_COLOR_TEXT_DIM   0xFF8B949E  /* Muted text */
#define WM_COLOR_A          0xFF4CAF50  /* Adenine green */
#define WM_COLOR_T          0xFFF44336  /* Thymine red */
#define WM_COLOR_C          0xFF2196F3  /* Cytosine blue */
#define WM_COLOR_G          0xFFFFEB3B  /* Guanine yellow */
#define WM_COLOR_BORDER     0xFF30363D  /* Window border */
#define WM_COLOR_BUTTON     0xFF21262D  /* Button */
#define WM_COLOR_HOVER      0xFF30363D  /* Hover state */
#define WM_COLOR_START      0xFF238636  /* Start button green */

/* ============================================================================
 * Window structure
 * ============================================================================
 */
#define WM_MAX_WINDOWS      16
#define WM_TITLEBAR_HEIGHT  28
#define WM_TASKBAR_HEIGHT   36
#define WM_BORDER_WIDTH     1

typedef enum {
    WIN_HIDDEN = 0,
    WIN_NORMAL,
    WIN_MINIMIZED,
    WIN_MAXIMIZED
} win_state_t;

typedef enum {
    WIN_TYPE_TERMINAL = 0,
    WIN_TYPE_FILEMANAGER,
    WIN_TYPE_EDITOR,
    WIN_TYPE_SETTINGS,
    WIN_TYPE_MONITOR,
    WIN_TYPE_ENCODER,
    WIN_TYPE_ABOUT,
    WIN_TYPE_GENERIC
} win_type_t;

typedef struct window {
    int             id;
    win_type_t      type;
    win_state_t     state;
    char            title[64];
    int             x, y;           /* Position */
    int             w, h;           /* Size */
    int             saved_x, saved_y, saved_w, saved_h; /* For maximize restore */
    int             z_order;        /* Higher = on top */
    int             has_focus;
    int             needs_redraw;
    
    /* Window content buffer (software rendering) */
    uint32_t       *content;        /* ARGB pixel buffer */
    int             content_w;
    int             content_h;
    
    /* Scroll state */
    int             scroll_x;
    int             scroll_y;
    
    /* App-specific data */
    void           *app_data;
    
    /* Callbacks */
    void (*on_draw)(struct window *win);
    void (*on_key)(struct window *win, uint8_t scancode);
    void (*on_click)(struct window *win, int x, int y);
    void (*on_close)(struct window *win);
} window_t;

/* ============================================================================
 * Mouse state
 * ============================================================================
 */
typedef struct {
    int     x, y;
    int     buttons;        /* bit 0 = left, bit 1 = right, bit 2 = middle */
    int     delta_x, delta_y;
    int     packet_state;   /* PS/2 mouse packet parser state */
    uint8_t packet[4];
} mouse_t;

/* ============================================================================
 * Global state
 * ============================================================================
 */
static window_t    wm_windows[WM_MAX_WINDOWS];
static int         wm_window_count = 0;
static int         wm_next_id = 1;
static int         wm_active_window = -1;
static mouse_t     wm_mouse;
static uint32_t   *wm_fb;           /* Framebuffer pointer */
static int         wm_fb_w;
static int         wm_fb_h;
static int         wm_fb_pitch;     /* Bytes per row */

/* Start menu state */
static int         wm_start_menu_open = 0;

/* ============================================================================
 * Drawing primitives
 * ============================================================================
 */

/* Draw a single pixel */
static inline void wm_draw_pixel(int x, int y, uint32_t color) {
    if (x < 0 || x >= wm_fb_w || y < 0 || y >= wm_fb_h) return;
    wm_fb[y * (wm_fb_pitch / 4) + x] = color;
}

/* Draw a filled rectangle */
static void wm_draw_rect(int x, int y, int w, int h, uint32_t color) {
    for (int dy = 0; dy < h; dy++) {
        for (int dx = 0; dx < w; dx++) {
            wm_draw_pixel(x + dx, y + dy, color);
        }
    }
}

/* Draw a rectangle outline */
static void wm_draw_rect_outline(int x, int y, int w, int h, uint32_t color) {
    for (int dx = 0; dx < w; dx++) {
        wm_draw_pixel(x + dx, y, color);
        wm_draw_pixel(x + dx, y + h - 1, color);
    }
    for (int dy = 0; dy < h; dy++) {
        wm_draw_pixel(x, y + dy, color);
        wm_draw_pixel(x + w - 1, y + dy, color);
    }
}

/* Draw a line (Bresenham) */
static void wm_draw_line(int x0, int y0, int x1, int y1, uint32_t color) {
    int dx = x1 > x0 ? x1 - x0 : x0 - x1;
    int dy = y1 > y0 ? y1 - y0 : y0 - y1;
    int sx = x0 < x1 ? 1 : -1;
    int sy = y0 < y1 ? 1 : -1;
    int err = dx - dy;
    
    while (1) {
        wm_draw_pixel(x0, y0, color);
        if (x0 == x1 && y0 == y1) break;
        int e2 = 2 * err;
        if (e2 > -dy) { err -= dy; x0 += sx; }
        if (e2 < dx)  { err += dx; y0 += sy; }
    }
}

/* Draw a character (8x16 font) - uses font_data from font.S */
extern uint8_t font_data[];
static void wm_draw_char(char c, int x, int y, uint32_t fg, uint32_t bg) {
    if ((uint8_t)c < 32 || (uint8_t)c > 127) c = '?';
    uint8_t *glyph = &font_data[((uint8_t)c - 32) * 16];
    
    for (int row = 0; row < 16; row++) {
        uint8_t bits = glyph[row];
        for (int col = 0; col < 8; col++) {
            if (bits & (0x80 >> col)) {
                wm_draw_pixel(x + col, y + row, fg);
            } else if (bg != 0xFF000000) { /* Transparent marker */
                wm_draw_pixel(x + col, y + row, bg);
            }
        }
    }
}

/* Draw a string */
static void wm_draw_string(const char *s, int x, int y, uint32_t fg, uint32_t bg) {
    while (*s) {
        wm_draw_char(*s, x, y, fg, bg);
        x += 8;
        s++;
    }
}

/* Draw string with length limit */
static void wm_draw_string_n(const char *s, int len, int x, int y, 
                              uint32_t fg, uint32_t bg) {
    for (int i = 0; i < len && s[i]; i++) {
        wm_draw_char(s[i], x, y, fg, bg);
        x += 8;
    }
}

/* ============================================================================
 * Desktop background - DNA helix pattern
 * ============================================================================
 */
static void wm_draw_desktop(void) {
    /* Fill with dark background */
    wm_draw_rect(0, 0, wm_fb_w, wm_fb_h - WM_TASKBAR_HEIGHT, WM_COLOR_DESKTOP);
    
    /* Draw DNA double helix */
    int cx = wm_fb_w / 2;
    int cy = (wm_fb_h - WM_TASKBAR_HEIGHT) / 2;
    
    for (int y = 0; y < wm_fb_h - WM_TASKBAR_HEIGHT; y++) {
        float t = (float)y / 40.0f;
        int x1 = cx + (int)(80.0f * sin(t));
        int x2 = cx - (int)(80.0f * sin(t));
        
        /* Draw with ATCG colors cycling */
        uint32_t colors[] = {WM_COLOR_A, WM_COLOR_T, WM_COLOR_C, WM_COLOR_G};
        uint32_t c = colors[(y / 20) % 4];
        
        /* Dim the helix */
        uint32_t dim = (c & 0xFF000000) | 
                       (((c & 0x00FF0000) >> 1) & 0x00FF0000) |
                       (((c & 0x0000FF00) >> 1) & 0x0000FF00) |
                       (((c & 0x000000FF) >> 1) & 0x000000FF);
        
        wm_draw_pixel(x1, y, dim);
        wm_draw_pixel(x2, y, dim);
        
        /* Rungs connecting the two strands */
        if (y % 8 == 0) {
            int left = x1 < x2 ? x1 : x2;
            int right = x1 < x2 ? x2 : x1;
            for (int x = left + 2; x < right - 2; x += 4) {
                wm_draw_pixel(x, y, dim);
            }
        }
    }
    
    /* DNAOS text in center */
    const char *title = "DNAOS";
    int title_x = cx - 20;
    int title_y = cy - 8;
    wm_draw_string(title, title_x, title_y, WM_COLOR_A, 0xFF000000);
    
    const char *sub = "Quaternary Operating System";
    int sub_x = cx - 108;
    wm_draw_string(sub, sub_x, title_y + 20, WM_COLOR_TEXT_DIM, 0xFF000000);
}

/* ============================================================================
 * Window rendering
 * ============================================================================
 */

/* Draw a single window */
static void wm_draw_window(window_t *win) {
    if (win->state == WIN_HIDDEN || win->state == WIN_MINIMIZED) return;
    
    int x = win->x, y = win->y, w = win->w, h = win->h;
    
    /* Shadow */
    wm_draw_rect(x + 4, y + 4, w, h, 0xFF000000);
    
    /* Window background */
    wm_draw_rect(x, y, w, h, WM_COLOR_WINDOW);
    
    /* Border */
    wm_draw_rect_outline(x, y, w, h, WM_COLOR_BORDER);
    
    /* Title bar */
    uint32_t title_color = win->has_focus ? WM_COLOR_TITLEBAR_A : WM_COLOR_TITLEBAR;
    wm_draw_rect(x + 1, y + 1, w - 2, WM_TITLEBAR_HEIGHT, title_color);
    
    /* Title text */
    wm_draw_string(win->title, x + 8, y + 6, WM_COLOR_TEXT, 0xFF000000);
    
    /* Close button (X) */
    int btn_x = x + w - 24;
    int btn_y = y + 4;
    wm_draw_rect(btn_x, btn_y, 20, 20, WM_COLOR_BUTTON);
    wm_draw_string("X", btn_x + 6, btn_y + 2, WM_COLOR_T, 0xFF000000);
    
    /* Minimize button (_) */
    btn_x -= 24;
    wm_draw_rect(btn_x, btn_y, 20, 20, WM_COLOR_BUTTON);
    wm_draw_string("_", btn_x + 4, btn_y + 2, WM_COLOR_TEXT, 0xFF000000);
    
    /* Maximize button (□) */
    btn_x -= 24;
    wm_draw_rect(btn_x, btn_y, 20, 20, WM_COLOR_BUTTON);
    wm_draw_string("[]", btn_x + 2, btn_y + 2, WM_COLOR_TEXT, 0xFF000000);
    
    /* ATCG color strip at bottom of title bar */
    int strip_y = y + WM_TITLEBAR_HEIGHT - 3;
    wm_draw_rect(x + 1, strip_y, w / 4, 3, WM_COLOR_A);
    wm_draw_rect(x + 1 + w/4, strip_y, w / 4, 3, WM_COLOR_T);
    wm_draw_rect(x + 1 + w/2, strip_y, w / 4, 3, WM_COLOR_C);
    wm_draw_rect(x + 1 + 3*w/4, strip_y, w / 4, 3, WM_COLOR_G);
    
    /* Window content area */
    int content_y = y + WM_TITLEBAR_HEIGHT;
    int content_h = h - WM_TITLEBAR_HEIGHT;
    
    /* Call app draw callback */
    if (win->on_draw) {
        win->on_draw(win);
    } else {
        /* Default: empty content */
        wm_draw_rect(x + 1, content_y, w - 2, content_h, WM_COLOR_WINDOW);
    }
}

/* ============================================================================
 * Taskbar
 * ============================================================================
 */
static void wm_draw_taskbar(void) {
    int tb_y = wm_fb_h - WM_TASKBAR_HEIGHT;
    
    /* Background */
    wm_draw_rect(0, tb_y, wm_fb_w, WM_TASKBAR_HEIGHT, WM_COLOR_TASKBAR);
    
    /* Top border */
    wm_draw_line(0, tb_y, wm_fb_w, tb_y, WM_COLOR_BORDER);
    
    /* Start button */
    wm_draw_rect(4, tb_y + 4, 80, WM_TASKBAR_HEIGHT - 8, WM_COLOR_START);
    wm_draw_string("DNAOS", 14, tb_y + 10, 0xFFFFFFFF, 0xFF000000);
    
    /* Window buttons in taskbar */
    int btn_x = 92;
    for (int i = 0; i < WM_MAX_WINDOWS; i++) {
        if (wm_windows[i].state == WIN_HIDDEN) continue;
        
        uint32_t color = wm_windows[i].has_focus ? WM_COLOR_HOVER : WM_COLOR_BUTTON;
        wm_draw_rect(btn_x, tb_y + 4, 120, WM_TASKBAR_HEIGHT - 8, color);
        wm_draw_string_n(wm_windows[i].title, 14, btn_x + 6, tb_y + 10, 
                         WM_COLOR_TEXT, 0xFF000000);
        btn_x += 124;
    }
    
    /* ATP meter (right side) */
    int atp_x = wm_fb_w - 200;
    wm_draw_string("ATP:", atp_x, tb_y + 10, WM_COLOR_TEXT_DIM, 0xFF000000);
    wm_draw_rect(atp_x + 36, tb_y + 8, 100, 16, WM_COLOR_BORDER);
    wm_draw_rect(atp_x + 37, tb_y + 9, 80, 14, WM_COLOR_A); /* ATP bar */
    
    /* Clock */
    int clock_x = wm_fb_w - 60;
    wm_draw_string("00:00", clock_x, tb_y + 10, WM_COLOR_TEXT, 0xFF000000);
}

/* ============================================================================
 * Start menu
 * ============================================================================
 */
static void wm_draw_start_menu(void) {
    if (!wm_start_menu_open) return;
    
    int menu_x = 4;
    int menu_y = wm_fb_h - WM_TASKBAR_HEIGHT - 280;
    int menu_w = 200;
    int menu_h = 280;
    
    /* Shadow */
    wm_draw_rect(menu_x + 4, menu_y + 4, menu_w, menu_h, 0x80000000);
    
    /* Background */
    wm_draw_rect(menu_x, menu_y, menu_w, menu_h, WM_COLOR_WINDOW);
    wm_draw_rect_outline(menu_x, menu_y, menu_w, menu_h, WM_COLOR_BORDER);
    
    /* Header */
    wm_draw_rect(menu_x + 1, menu_y + 1, menu_w - 2, 32, WM_COLOR_A);
    wm_draw_string("DNAOS", menu_x + 12, menu_y + 8, 0xFFFFFFFF, 0xFF000000);
    
    /* Menu items */
    const char *items[] = {
        "Terminal",
        "File Manager",
        "Text Editor",
        "ATCG Encoder",
        "System Monitor",
        "Settings",
        "About DNAOS",
        "-----------",
        "Restart",
        "Shutdown"
    };
    
    int item_y = menu_y + 40;
    for (int i = 0; i < 10; i++) {
        uint32_t color = (i % 2 == 0) ? WM_COLOR_WINDOW : WM_COLOR_HOVER;
        wm_draw_rect(menu_x + 2, item_y, menu_w - 4, 24, color);
        
        /* Icon color based on ATCG */
        uint32_t icon_colors[] = {WM_COLOR_A, WM_COLOR_C, WM_COLOR_T, 
                                  WM_COLOR_G, WM_COLOR_A, WM_COLOR_C,
                                  WM_COLOR_G, WM_COLOR_BORDER,
                                  WM_COLOR_T, WM_COLOR_T};
        wm_draw_rect(menu_x + 8, item_y + 4, 16, 16, icon_colors[i]);
        wm_draw_string(items[i], menu_x + 30, item_y + 4, WM_COLOR_TEXT, 0xFF000000);
        item_y += 24;
    }
}

/* ============================================================================
 * Full redraw
 * ============================================================================
 */
static void wm_redraw_all(void) {
    wm_draw_desktop();
    
    /* Draw windows in z-order (lowest first) */
    for (int z = 0; z < WM_MAX_WINDOWS; z++) {
        for (int i = 0; i < WM_MAX_WINDOWS; i++) {
            if (wm_windows[i].id && wm_windows[i].z_order == z) {
                wm_draw_window(&wm_windows[i]);
            }
        }
    }
    
    wm_draw_taskbar();
    wm_draw_start_menu();
    
    /* Draw mouse cursor */
    wm_draw_rect(wm_mouse.x, wm_mouse.y, 8, 12, WM_COLOR_TEXT);
    wm_draw_rect(wm_mouse.x + 1, wm_mouse.y + 1, 6, 10, WM_COLOR_A);
}

/* ============================================================================
 * Window management
 * ============================================================================
 */
static window_t *wm_create_window(const char *title, win_type_t type,
                                   int x, int y, int w, int h) {
    for (int i = 0; i < WM_MAX_WINDOWS; i++) {
        if (wm_windows[i].id == 0) {
            window_t *win = &wm_windows[i];
            win->id = wm_next_id++;
            win->type = type;
            win->state = WIN_NORMAL;
            
            for (int j = 0; j < 63 && title[j]; j++) win->title[j] = title[j];
            win->title[63] = '\0';
            
            win->x = x; win->y = y;
            win->w = w; win->h = h;
            win->z_order = wm_window_count;
            win->has_focus = 1;
            win->needs_redraw = 1;
            win->scroll_x = 0;
            win->scroll_y = 0;
            win->app_data = 0;
            win->on_draw = 0;
            win->on_key = 0;
            win->on_click = 0;
            win->on_close = 0;
            
            /* Unfocus other windows */
            for (int j = 0; j < WM_MAX_WINDOWS; j++) {
                if (j != i) wm_windows[j].has_focus = 0;
            }
            
            wm_active_window = i;
            wm_window_count++;
            return win;
        }
    }
    return 0;
}

/* Focus a window (bring to front) */
static void wm_focus_window(int idx) {
    if (idx < 0 || idx >= WM_MAX_WINDOWS) return;
    
    /* Increase z-order */
    int max_z = 0;
    for (int i = 0; i < WM_MAX_WINDOWS; i++) {
        if (wm_windows[i].id) {
            wm_windows[i].has_focus = 0;
            if (wm_windows[i].z_order > max_z) max_z = wm_windows[i].z_order;
        }
    }
    
    wm_windows[idx].has_focus = 1;
    wm_windows[idx].z_order = max_z + 1;
    wm_active_window = idx;
    wm_redraw_all();
}

/* Close a window */
static void wm_close_window(int idx) {
    if (idx < 0 || idx >= WM_MAX_WINDOWS) return;
    
    if (wm_windows[idx].on_close) {
        wm_windows[idx].on_close(&wm_windows[idx]);
    }
    
    wm_windows[idx].id = 0;
    wm_windows[idx].state = WIN_HIDDEN;
    wm_window_count--;
    
    /* Focus next window */
    wm_active_window = -1;
    for (int i = 0; i < WM_MAX_WINDOWS; i++) {
        if (wm_windows[i].id && wm_windows[i].state == WIN_NORMAL) {
            wm_focus_window(i);
            break;
        }
    }
    
    wm_redraw_all();
}

/* ============================================================================
 * Mouse handling
 * ============================================================================
 */
static int wm_dragging = 0;
static int wm_drag_win = -1;
static int wm_drag_off_x = 0;
static int wm_drag_off_y = 0;

static void wm_handle_mouse_click(int x, int y, int button) {
    if (button == 0) return; /* No button */
    
    /* Check start button */
    int tb_y = wm_fb_h - WM_TASKBAR_HEIGHT;
    if (x >= 4 && x <= 84 && y >= tb_y + 4 && y <= tb_y + WM_TASKBAR_HEIGHT - 4) {
        wm_start_menu_open = !wm_start_menu_open;
        wm_redraw_all();
        return;
    }
    
    /* Check start menu items */
    if (wm_start_menu_open) {
        int menu_x = 4;
        int menu_y = wm_fb_h - WM_TASKBAR_HEIGHT - 280;
        
        if (x >= menu_x && x <= menu_x + 200 && y >= menu_y + 40 && y <= menu_y + 280) {
            int item = (y - menu_y - 40) / 24;
            wm_start_menu_open = 0;
            
            /* Launch app based on item */
            switch (item) {
                case 0: /* Terminal */ break;
                case 1: /* File Manager */ break;
                case 2: /* Editor */ break;
                case 3: /* Encoder */ break;
                case 4: /* Monitor */ break;
                case 5: /* Settings */ break;
                case 6: /* About */ break;
                case 8: /* Restart */ break;
                case 9: /* Shutdown */ break;
            }
            
            wm_redraw_all();
            return;
        }
        
        wm_start_menu_open = 0;
        wm_redraw_all();
        return;
    }
    
    /* Check window title bars (reverse z-order for top-most first) */
    for (int z = WM_MAX_WINDOWS - 1; z >= 0; z--) {
        for (int i = 0; i < WM_MAX_WINDOWS; i++) {
            window_t *win = &wm_windows[i];
            if (!win->id || win->z_order != z) continue;
            if (win->state != WIN_NORMAL) continue;
            
            /* Check if click is in this window */
            if (x >= win->x && x < win->x + win->w &&
                y >= win->y && y < win->y + win->h) {
                
                wm_focus_window(i);
                
                /* Check title bar */
                if (y < win->y + WM_TITLEBAR_HEIGHT) {
                    /* Close button */
                    int close_x = win->x + win->w - 24;
                    if (x >= close_x && x <= close_x + 20) {
                        wm_close_window(i);
                        return;
                    }
                    
                    /* Start dragging */
                    wm_dragging = 1;
                    wm_drag_win = i;
                    wm_drag_off_x = x - win->x;
                    wm_drag_off_y = y - win->y;
                } else {
                    /* Click in content area */
                    if (win->on_click) {
                        win->on_click(win, x - win->x, y - win->y);
                    }
                }
                return;
            }
        }
    }
}

static void wm_handle_mouse_move(int x, int y) {
    wm_mouse.x = x;
    wm_mouse.y = y;
    
    if (wm_dragging && wm_drag_win >= 0) {
        wm_windows[wm_drag_win].x = x - wm_drag_off_x;
        wm_windows[wm_drag_win].y = y - wm_drag_off_y;
        wm_redraw_all();
    }
}

static void wm_handle_mouse_release(void) {
    wm_dragging = 0;
    wm_drag_win = -1;
}

/* ============================================================================
 * Initialize window manager
 * ============================================================================
 */
static void wm_init(uint32_t *fb, int width, int height, int pitch) {
    wm_fb = fb;
    wm_fb_w = width;
    wm_fb_h = height;
    wm_fb_pitch = pitch;
    
    wm_window_count = 0;
    wm_next_id = 1;
    wm_active_window = -1;
    wm_start_menu_open = 0;
    
    wm_mouse.x = width / 2;
    wm_mouse.y = height / 2;
    wm_mouse.buttons = 0;
    
    for (int i = 0; i < WM_MAX_WINDOWS; i++) {
        wm_windows[i].id = 0;
        wm_windows[i].state = WIN_HIDDEN;
    }
    
    /* Draw initial desktop */
    wm_redraw_all();
}

#endif /* WM_H */
