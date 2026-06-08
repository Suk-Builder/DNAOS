/* ============================================================================
 * DNAOS Game Runtime — SDL2 bindings for DNAsm games
 * ============================================================================
 * With SDL2:  gcc -o game game_gen.c -lSDL2 -lm
 * Headless:   gcc -DNO_SDL -o game_test game_gen.c -lm
 * Windows:    gcc -o game.exe game_gen.c -I. -L. -lSDL2 -lm
 * ============================================================================ */

#ifndef GAME_RT_H
#define GAME_RT_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <math.h>

/* Key constants — same values for both modes */
#define DNA_KEY_W      119
#define DNA_KEY_S      115
#define DNA_KEY_UP     273
#define DNA_KEY_DOWN   274
#define DNA_KEY_SPACE  32
#define DNA_KEY_ESC    27

#ifdef NO_SDL
/* ========================================================================
 * Headless mode — for testing game logic without a display
 * ======================================================================== */
#include <time.h>

static int _gr_running = 1;
static uint64_t _gr_frame = 0;

static int dna_rt_init(const char *title, int w, int h) {
    (void)title; (void)w; (void)h;
    printf("[dna_rt] init: %s %dx%d\n", title, w, h);
    return 0;
}
static void dna_rt_quit(void) { printf("[dna_rt] quit\n"); }
static int dna_rt_poll(void) {
    _gr_frame++;
    return _gr_frame > 200;
}
static int dna_rt_running(void) { return _gr_running; }
static int dna_rt_key(int k) {
    /* Simulate SPACE pressed after frame 3 */
    if (k == DNA_KEY_SPACE && _gr_frame > 3) return 1;
    return 0;
}
static void dna_rt_clear(int r, int g, int b) { (void)r; (void)g; (void)b; }
static void dna_rt_present(void) { }
static void dna_rt_rect(int x, int y, int w, int h, int r, int g, int b) {
    (void)x; (void)y; (void)w; (void)h; (void)r; (void)g; (void)b;
}
static void dna_rt_text(int x, int y, const char *text, int r, int g, int b) {
    printf("[text %d,%d] %s\n", x, y, text);
}
static uint64_t dna_rt_ticks(void) { return _gr_frame * 16; }
static int dna_rt_rand(int max) { return max > 0 ? rand() % max : 0; }
static void dna_rt_srand(unsigned int s) { srand(s); }
static void dna_rt_draw_score(int val, int x, int y) {
    char buf[2] = {'0' + (char)(val % 10), 0};
    dna_rt_text(x, y, buf, 255, 255, 255);
}

#else /* Real SDL2 */
/* ========================================================================
 * SDL2 mode — real window, rendering, input
 * ======================================================================== */
#include <SDL2/SDL.h>

static SDL_Window *_gr_win = NULL;
static SDL_Renderer *_gr_ren = NULL;
static const uint8_t *_gr_keys = NULL;
static int _gr_running = 1;

static int dna_rt_init(const char *title, int w, int h) {
    if (SDL_Init(SDL_INIT_VIDEO) < 0) { fprintf(stderr, "SDL: %s\n", SDL_GetError()); return -1; }
    _gr_win = SDL_CreateWindow(title, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, w, h, 0);
    if (!_gr_win) { fprintf(stderr, "SDL: %s\n", SDL_GetError()); return -1; }
    _gr_ren = SDL_CreateRenderer(_gr_win, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!_gr_ren) { fprintf(stderr, "SDL: %s\n", SDL_GetError()); return -1; }
    _gr_keys = SDL_GetKeyboardState(NULL);
    return 0;
}

static void dna_rt_quit(void) {
    if (_gr_ren) SDL_DestroyRenderer(_gr_ren);
    if (_gr_win) SDL_DestroyWindow(_gr_win);
    SDL_Quit();
}

static int dna_rt_poll(void) {
    SDL_Event e;
    while (SDL_PollEvent(&e)) {
        if (e.type == SDL_QUIT) { _gr_running = 0; return 1; }
        if (e.type == SDL_KEYDOWN && e.key.keysym.sym == SDLK_ESCAPE) { _gr_running = 0; return 1; }
    }
    return 0;
}

static int dna_rt_running(void) { return _gr_running; }

/* Map DNA key constants to SDL scancodes for lookup */
static int dna_rt_key(int k) {
    switch (k) {
        case DNA_KEY_W:     return _gr_keys[SDL_SCANCODE_W];
        case DNA_KEY_S:     return _gr_keys[SDL_SCANCODE_S];
        case DNA_KEY_UP:    return _gr_keys[SDL_SCANCODE_UP];
        case DNA_KEY_DOWN:  return _gr_keys[SDL_SCANCODE_DOWN];
        case DNA_KEY_SPACE: return _gr_keys[SDL_SCANCODE_SPACE];
        case DNA_KEY_ESC:   return _gr_keys[SDL_SCANCODE_ESCAPE];
        default: return 0;
    }
}

static void dna_rt_clear(int r, int g, int b) {
    SDL_SetRenderDrawColor(_gr_ren, r, g, b, 255);
    SDL_RenderClear(_gr_ren);
}

static void dna_rt_present(void) { SDL_RenderPresent(_gr_ren); }

static void dna_rt_rect(int x, int y, int w, int h, int r, int g, int b) {
    SDL_SetRenderDrawColor(_gr_ren, r, g, b, 255);
    SDL_Rect rect = {x, y, w, h};
    SDL_RenderFillRect(_gr_ren, &rect);
}

/* 5x7 bitmap font */
static void dna_rt_text(int x, int y, const char *text, int r, int g, int b) {
    static const uint8_t font[128][7] = {
        ['A'] = {0x04,0x0A,0x11,0x1F,0x11,0x11,0x11},
        ['B'] = {0x1E,0x11,0x11,0x1E,0x11,0x11,0x1E},
        ['C'] = {0x0E,0x11,0x10,0x10,0x10,0x11,0x0E},
        ['D'] = {0x1C,0x12,0x11,0x11,0x11,0x12,0x1C},
        ['E'] = {0x1F,0x10,0x10,0x1E,0x10,0x10,0x1F},
        ['F'] = {0x1F,0x10,0x10,0x1E,0x10,0x10,0x10},
        ['G'] = {0x0E,0x11,0x10,0x17,0x11,0x11,0x0F},
        ['H'] = {0x11,0x11,0x11,0x1F,0x11,0x11,0x11},
        ['I'] = {0x0E,0x04,0x04,0x04,0x04,0x04,0x0E},
        ['K'] = {0x11,0x12,0x14,0x18,0x14,0x12,0x11},
        ['L'] = {0x10,0x10,0x10,0x10,0x10,0x10,0x1F},
        ['M'] = {0x11,0x1B,0x15,0x15,0x11,0x11,0x11},
        ['N'] = {0x11,0x19,0x15,0x13,0x11,0x11,0x11},
        ['O'] = {0x0E,0x11,0x11,0x11,0x11,0x11,0x0E},
        ['P'] = {0x1E,0x11,0x11,0x1E,0x10,0x10,0x10},
        ['R'] = {0x1E,0x11,0x11,0x1E,0x14,0x12,0x11},
        ['S'] = {0x0F,0x10,0x10,0x0E,0x01,0x01,0x1E},
        ['T'] = {0x1F,0x04,0x04,0x04,0x04,0x04,0x04},
        ['U'] = {0x11,0x11,0x11,0x11,0x11,0x11,0x0E},
        ['V'] = {0x11,0x11,0x11,0x11,0x0A,0x0A,0x04},
        ['W'] = {0x11,0x11,0x11,0x15,0x15,0x1B,0x11},
        ['X'] = {0x11,0x11,0x0A,0x04,0x0A,0x11,0x11},
        ['Y'] = {0x11,0x11,0x0A,0x04,0x04,0x04,0x04},
        ['0'] = {0x0E,0x11,0x13,0x15,0x19,0x11,0x0E},
        ['1'] = {0x04,0x0C,0x04,0x04,0x04,0x04,0x0E},
        ['2'] = {0x0E,0x11,0x01,0x06,0x08,0x10,0x1F},
        ['3'] = {0x0E,0x11,0x01,0x06,0x01,0x11,0x0E},
        ['4'] = {0x02,0x06,0x0A,0x12,0x1F,0x02,0x02},
        ['5'] = {0x1F,0x10,0x1E,0x01,0x01,0x11,0x0E},
        [':'] = {0x00,0x04,0x04,0x00,0x04,0x04,0x00},
        [' '] = {0x00,0x00,0x00,0x00,0x00,0x00,0x00},
        ['-'] = {0x00,0x00,0x00,0x1F,0x00,0x00,0x00},
        ['.'] = {0x00,0x00,0x00,0x00,0x00,0x0C,0x0C},
        ['!'] = {0x04,0x04,0x04,0x04,0x04,0x00,0x04},
    };
    SDL_SetRenderDrawColor(_gr_ren, r, g, b, 255);
    int cx = x;
    for (int i = 0; text[i]; i++) {
        unsigned char ch = (unsigned char)text[i];
        if (ch < 128) {
            for (int row = 0; row < 7; row++) {
                uint8_t bits = font[ch][row];
                for (int col = 0; col < 5; col++) {
                    if (bits & (0x10 >> col))
                        SDL_RenderDrawPoint(_gr_ren, cx + col, y + row);
                }
            }
        }
        cx += 6;
    }
}

static uint64_t dna_rt_ticks(void) { return SDL_GetTicks64(); }
static int dna_rt_rand(int max) { return max > 0 ? rand() % max : 0; }
static void dna_rt_srand(unsigned int s) { srand(s); }

static void dna_rt_draw_score(int val, int x, int y) {
    char buf[2] = {'0' + (char)(val % 10), 0};
    dna_rt_text(x, y, buf, 255, 255, 255);
}

#endif /* NO_SDL */

#endif /* GAME_RT_H */
