/* Stub game_rt.h for compilation testing */
#define DNA_KEY_W 119
#define DNA_KEY_S 115
#define DNA_KEY_UP 273
#define DNA_KEY_DOWN 274
#define DNA_KEY_SPACE 32
int dna_rt_init(const char *title, int w, int h);
void dna_rt_quit(void);
int dna_rt_poll(void);
int dna_rt_running(void);
int dna_rt_key(int key);
void dna_rt_clear(int r, int g, int b);
void dna_rt_present(void);
void dna_rt_rect(int x, int y, int w, int h, int r, int g, int b);
void dna_rt_text(int x, int y, const char *text, int r, int g, int b);
uint64_t dna_rt_ticks(void);
int dna_rt_rand(int max);
void dna_rt_srand(unsigned int seed);
void dna_rt_draw_score(int val, int x, int y);
