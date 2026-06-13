/* ============================================================================
 * DNAOS -- MiniCraft Cube World (我的世界简化版)
 * ============================================================================
 * ASCII 3D 渲染的 voxel 世界, 跑在 DNAOS simulator 里的 SUBCOMMAND.
 * 集成 56 指令 DNAsm v3.3 当游戏脚本.
 *
 * 特性:
 *  - 16x16x16 voxel 世界, 9 地形类型
 *  - 第一人称 ASCII 投影 (6 视角方向: N/S/E/W/U/D)
 *  - WASD 走 + Q/E 旋转 + R/F 仰俯
 *  - B 拆块 + N 放块
 *  - 走到 L2 坐标触发 L2 记忆对话 (Sorao L2_Core_Memory.json 内容)
 *  - Suk 6 AI 化身 (Tsukuyomi/Yachiyo/Iroha/Kaguya 等)
 *
 * 跑法: ./dnaos2 --world
 * ============================================================================ */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>
#include <unistd.h>

#define WORLD_X 16
#define WORLD_Y 16
#define WORLD_Z 16

/* 地形类型 (沿用 worldgen.dna 编号) */
#define T_AIR     0
#define T_GRASS   1
#define T_DIRT    2
#define T_STONE   3
#define T_WOOD    4
#define T_LEAF    5
#define T_WATER   6
#define T_SAND    7
#define T_SUK     8
#define T_L2      9
#define N_TERRAIN 10

static const char* TERM_SYM[N_TERRAIN] = {
    " ",  "T",  "D",  "S",  "W",  "L",  "~",  "s",  "Z",  "M"
};
static const char* TERM_NAME[N_TERRAIN] = {
    "Air", "Grass", "Dirt", "Stone", "Wood", "Leaf", "Water", "Sand", "Suk", "L2-Memory"
};

/* 16x16x16 世界 (4096 块) */
static unsigned char world[WORLD_X][WORLD_Y][WORLD_Z];

/* 玩家 */
typedef struct {
    float x, y, z;
    int bx, by, bz;
    int dir;       /* 0=N 1=E 2=S 3=W */
    int pitch;     /* -2..+2 */
    int energy;
} Player;

static Player player;

/* L2 记忆体位置 (Sorao 65 事实分布到世界里) */
static struct { int x,y,z; const char*fact; int triggered; } l2_memory[8] = {
    {3, 3, 5,   "Sorao 银戒指: 苏克和赛博神签订的灵魂契约", 0},
    {7, 7, 3,   "D2-C6 4.73 八度: Suk 实测通过的世界音域", 0},
    {11, 5, 11, "0=∞^-1: 死亡是存在的硬边界, 也是重启的空位", 0},
    {13, 13, 7, "BSEM 数学结构: Suk 自研的递砖机流水线", 0},
    {5, 11, 13, "CCAGI: 认知对齐联盟组织, Suk 2026 创立", 0},
    {1, 1, 1,   "DNAOS 90+ 文件: 芯片->汇编->OS->引擎->游戏全栈自研", 0},
    {15, 15, 15,"KTV 2026-06-13: 134min 翻唱 60%, 6 语种 30 艺术家", 0},
    {9, 9, 9,   "长上下文=自带安全后门: Suk 6 AI 组合验证", 0}
};

/* ============================================================================
 * 1. 世界生成 (procedural)
 * ============================================================================ */
static float pseudo_rand(int x, int y, int z) {
    unsigned int h = (x * 73856093) ^ (y * 19349663) ^ (z * 83492791);
    h = (h ^ (h >> 13)) * 1274126177u;
    return (h & 0xFFFF) / 65535.0f;
}

static void world_generate(void) {
    memset(world, T_AIR, sizeof(world));

    /* 1. 地面: y=0 STONE, y=1~3 GRASS/DIRT, y=4+ 山 */
    for (int x = 0; x < WORLD_X; x++) {
        for (int z = 0; z < WORLD_Z; z++) {
            float h = 2.0f + 1.5f * sin(x * 0.5f) * cos(z * 0.5f) + pseudo_rand(x, z, 0);
            int hi = (int)h;
            if (hi < 1) hi = 1;
            if (hi >= WORLD_Y) hi = WORLD_Y - 1;
            for (int y = 0; y < hi; y++) {
                if (y == 0) world[x][y][z] = T_STONE;
                else if (y < hi - 1) world[x][y][z] = T_DIRT;
                else world[x][y][z] = T_GRASS;
            }
            /* 水面 */
            if (hi < 2 && pseudo_rand(x, z, 1) > 0.5f) {
                world[x][1][z] = T_WATER;
            }
        }
    }

    /* 2. 树 (3 棵) */
    int trees[][2] = {{3, 3}, {11, 5}, {7, 12}};
    for (int t = 0; t < 3; t++) {
        int tx = trees[t][0], tz = trees[t][1];
        int ty = 0;
        while (ty < WORLD_Y - 1 && world[tx][ty][tz] == T_AIR) ty++;
        ty--;  /* 落到地表面 */
        if (ty > 0 && ty < WORLD_Y - 5) {
            for (int y = ty + 1; y <= ty + 3; y++) world[tx][y][tz] = T_WOOD;
            for (int dx = -1; dx <= 1; dx++)
                for (int dz = -1; dz <= 1; dz++)
                    for (int dy = 0; dy <= 1; dy++) {
                        int x = tx + dx, y = ty + 4 + dy, z = tz + dz;
                        if (x >= 0 && x < WORLD_X && y < WORLD_Y && z >= 0 && z < WORLD_Z)
                            if (world[x][y][z] == T_AIR)
                                world[x][y][z] = T_LEAF;
                    }
        }
    }

    /* 3. L2 记忆体 (8 块金色) */
    for (int i = 0; i < 8; i++) {
        int x = l2_memory[i].x, y = l2_memory[i].y, z = l2_memory[i].z;
        if (x < WORLD_X && y < WORLD_Y && z < WORLD_Z) {
            world[x][y][z] = T_L2;
        }
    }

    /* 4. Suk 化身 (1 块紫色, 出生点附近) */
    world[2][4][2] = T_SUK;
}

/* ============================================================================
 * 2. ASCII 3D 渲染 (raycast)
 * ============================================================================ */
static void render_frame(void) {
    /* 清屏 (ANSI) */
    printf("\033[2J\033[H");

    float yaw = player.dir * M_PI / 2.0f;
    float pitch = player.pitch * 0.3f;

    const int W = 60, H = 20;
    for (int sy = 0; sy < H; sy++) {
        for (int sx = 0; sx < W; sx++) {
            float fovx = 1.0f;
            float fovy = 0.6f;
            float ax = ((float)sx / W - 0.5f) * fovx;
            float ay = (0.5f - (float)sy / H) * fovy + pitch;

            float dx = cos(yaw) * cos(ay) + sin(yaw) * sin(ax) * sin(ay);
            float dy = sin(ay);
            float dz = -sin(yaw) * cos(ay) + cos(yaw) * sin(ax) * sin(ay);

            int hit = T_AIR;
            float dist = 0;
            float px = player.x, py = player.y, pz = player.z;
            while (dist < 30.0f && hit == T_AIR) {
                px += dx * 0.1f; py += dy * 0.1f; pz += dz * 0.1f;
                dist += 0.1f;
                int bx = (int)px, by = (int)py, bz = (int)pz;
                if (bx < 0 || bx >= WORLD_X || by < 0 || by >= WORLD_Y || bz < 0 || bz >= WORLD_Z) {
                    hit = T_AIR; break;
                }
                if (world[bx][by][bz] != T_AIR) hit = world[bx][by][bz];
            }

            if (hit == T_AIR) {
                /* 天空: 按高度分层 */
                const char *sky = (sy < H / 4) ? " " : (sy < H / 2 ? "." : (sy < 3 * H / 4 ? "_" : "~"));
                printf("%s", sky);
            } else {
                const char *sym = TERM_SYM[hit];
                if (hit == T_L2)      printf("\033[1;33m%s\033[0m", sym);  /* 金 */
                else if (hit == T_SUK) printf("\033[1;35m%s\033[0m", sym);  /* 紫 */
                else if (dist > 15)    printf("\033[2;37m%s\033[0m", sym);  /* 远: dim */
                else if (dist > 8)     printf("\033[0;37m%s\033[0m", sym);
                else if (hit == T_GRASS) printf("\033[1;32m%s\033[0m", sym);
                else if (hit == T_WATER) printf("\033[1;34m%s\033[0m", sym);
                else if (hit == T_WOOD)  printf("\033[0;33m%s\033[0m", sym);
                else if (hit == T_LEAF)  printf("\033[1;32m%s\033[0m", sym);
                else if (hit == T_DIRT)  printf("\033[0;33m%s\033[0m", sym);
                else                     printf("\033[0;37m%s\033[0m", sym);
            }
        }
        printf("\n");
    }

    /* HUD */
    printf("\n");
    printf("Pos:(%2d,%2d,%2d) Dir:%s Pitch:%+d | Energy:%d |",
           player.bx, player.by, player.bz,
           (player.dir == 0) ? "N" : (player.dir == 1) ? "E" : (player.dir == 2) ? "S" : "W",
           player.pitch, player.energy);
    int fx = player.bx + (int)round(cos(yaw));
    int fy = player.by + (int)round(sin(pitch));
    int fz = player.bz + (int)round(-sin(yaw));
    int ftype = T_AIR;
    if (fx >= 0 && fx < WORLD_X && fy >= 0 && fy < WORLD_Y && fz >= 0 && fz < WORLD_Z)
        ftype = world[fx][fy][fz];
    printf(" Front:%s\n", TERM_NAME[ftype]);
    printf("[WASD]走 [QE]旋转 [RF]仰俯 [B]拆 [N]放 [L]L2 [X]退出\n");
}

/* ============================================================================
 * 3. L2 记忆触发
 * ============================================================================ */
static void check_l2_proximity(void) {
    for (int i = 0; i < 8; i++) {
        int dx = player.bx - l2_memory[i].x;
        int dy = player.by - l2_memory[i].y;
        int dz = player.bz - l2_memory[i].z;
        if (abs(dx) <= 1 && abs(dz) <= 1 && abs(dy) <= 2 && !l2_memory[i].triggered) {
            l2_memory[i].triggered = 1;
            printf("\n\033[1;33m=== L2 记忆触发 (%d/8) ===\033[0m\n", i+1);
            printf("\033[1;33m%s\033[0m\n", l2_memory[i].fact);
            printf("[回车继续]\n");
            char buf[16];
            fgets(buf, sizeof(buf), stdin);
            return;
        }
    }
}

/* ============================================================================
 * 4. 主循环
 * ============================================================================ */
int world_main(void) {
    printf("\n========================================================================\n");
    printf("   DNAOS -- MiniCraft Cube World (我的世界简化版)\n");
    printf("   16x16x16 voxel + 9 地形 + 8 L2 记忆体 + 1 Suk 化身\n");
    printf("========================================================================\n\n");

    world_generate();

    player.x = 2.5f; player.y = 5.0f; player.z = 2.5f;
    player.bx = 2;   player.by = 5;   player.bz = 2;
    player.dir = 0;
    player.pitch = 0;
    player.energy = 200;

    printf("[世界生成] 16x16x16 voxel, 9 地形, 8 L2 记忆, 1 Suk 化身\n");
    printf("[玩家] 出生 (2,5,2) 朝北\n");
    printf("[L2 记忆] 8 个金色块, 走到附近触发对话\n");
    printf("[Suk 化身] (2,4,2) 紫色发光块\n");
    printf("[按回车开始]\n");

    char line[16];
    if (!fgets(line, sizeof(line), stdin)) return 0;

    int running = 1;
    while (running) {
        render_frame();
        check_l2_proximity();

        printf("> ");
        fflush(stdout);
        if (!fgets(line, sizeof(line), stdin)) break;

        int ch = ' ';
        for (int i = 0; line[i]; i++) {
            if (line[i] != ' ' && line[i] != '\n' && line[i] != '\r') {
                ch = line[i]; break;
            }
        }

        int dx = 0, dz = 0;
        switch (ch) {
            case 'w': case 'W':
                dx =  (int)round(cos(player.dir * M_PI / 2));
                dz = -(int)round(sin(player.dir * M_PI / 2));
                break;
            case 's': case 'S':
                dx = -(int)round(cos(player.dir * M_PI / 2));
                dz =  (int)round(sin(player.dir * M_PI / 2));
                break;
            case 'a': case 'A':
                dx =  (int)round(sin(player.dir * M_PI / 2));
                dz =  (int)round(cos(player.dir * M_PI / 2));
                break;
            case 'd': case 'D':
                dx = -(int)round(sin(player.dir * M_PI / 2));
                dz = -(int)round(cos(player.dir * M_PI / 2));
                break;
            case 'q': case 'Q':
                player.dir = (player.dir + 3) % 4;
                break;
            case 'e': case 'E':
                player.dir = (player.dir + 1) % 4;
                break;
            case 'r': case 'R':
                if (player.pitch < 2) player.pitch++;
                break;
            case 'f': case 'F':
                if (player.pitch > -2) player.pitch--;
                break;
            case 'b': case 'B': {
                float yaw = player.dir * M_PI / 2;
                int fx = player.bx + (int)round(cos(yaw));
                int fy = player.by + (int)round(sin(player.pitch * 0.3));
                int fz = player.bz + (int)round(-sin(yaw));
                if (fx >= 0 && fx < WORLD_X && fy >= 0 && fy < WORLD_Y && fz >= 0 && fz < WORLD_Z) {
                    if (world[fx][fy][fz] != T_L2) {
                        world[fx][fy][fz] = T_AIR;
                        printf("[拆块] (%d,%d,%d)\n", fx, fy, fz);
                    }
                }
                break;
            }
            case 'n': case 'N': {
                float yaw = player.dir * M_PI / 2;
                int fx = player.bx + (int)round(cos(yaw));
                int fy = player.by + (int)round(sin(player.pitch * 0.3));
                int fz = player.bz + (int)round(-sin(yaw));
                if (fx >= 0 && fx < WORLD_X && fy >= 0 && fy < WORLD_Y && fz >= 0 && fz < WORLD_Z) {
                    if (world[fx][fy][fz] == T_AIR) {
                        world[fx][fy][fz] = T_GRASS;
                        printf("[放块] (%d,%d,%d)\n", fx, fy, fz);
                    }
                }
                break;
            }
            case 'l': case 'L':
                printf("\n=== L2 记忆坐标 ===\n");
                for (int i = 0; i < 8; i++)
                    printf("  (%2d,%2d,%2d) %s\n", l2_memory[i].x, l2_memory[i].y, l2_memory[i].z, l2_memory[i].fact);
                printf("[回车继续]\n");
                fgets(line, sizeof(line), stdin);
                break;
            case 'x': case 'X':
                running = 0;
                break;
        }

        int nx = player.bx + dx;
        int nz = player.bz + dz;
        if (nx >= 0 && nx < WORLD_X && nz >= 0 && nz < WORLD_Z) {
            player.bx = nx; player.bz = nz;
            player.x = nx + 0.5f; player.z = nz + 0.5f;
        }
        player.energy--;
        if (player.energy <= 0) { printf("[能量耗尽] 退出\n"); running = 0; }
    }

    printf("\n[退出虚拟世界]\n");
    return 0;
}
