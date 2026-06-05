/* tube_battle.c -- DNA浓度对战游戏
 * 两个玩家各控制一个试管，通过ADD/COPY/SUB操作
 * 先把对手浓度归零者获胜
 * 用ASCII可视化DNA浓度
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define TUBE_A 0
#define TUBE_B 1
#define MAX_CONC 1000

typedef struct {
    int conc;           /* 浓度值 */
    int atp;            /* ATP能量 */
    char name[16];
} Tube;

static Tube tubes[2];
static int round_num = 1;

/* ASCII浓度条 */
void draw_bar(int val, int max, int width) {
    int filled = (val * width) / max;
    printf("[");
    for(int i = 0; i < width; i++) {
        if(i < filled) {
            /* DNA碱基字符 */
            const char* bases = "ATCG";
            printf("\033[3%dm%c\033[0m", (i % 4) + 1, bases[i % 4]);
        } else {
            printf(" ");
        }
    }
    printf("] %4d", val);
}

/* 绘制游戏画面 */
void draw_screen(void) {
    system("clear 2>/dev/null || printf '\033[2J\033[H'");
    
    printf("\033[36m");
    printf("=====================================================\n");
    printf("           TUBE BATTLE -- DNA浓度对战\n");
    printf("=====================================================\033[0m\n\n");
    
    /* 玩家A */
    printf("  \033[32m[%s]\033[0m  ATP:%3d  ", tubes[TUBE_A].name, tubes[TUBE_A].atp);
    draw_bar(tubes[TUBE_A].conc, MAX_CONC, 30);
    printf("\n\n");
    
    /* VS */
    printf("             \033[33m<<< ROUND %d >>>\033[0m\n\n", round_num);
    
    /* 玩家B */
    printf("  \033[31m[%s]\033[0m  ATP:%3d  ", tubes[TUBE_B].name, tubes[TUBE_B].atp);
    draw_bar(tubes[TUBE_B].conc, MAX_CONC, 30);
    printf("\n\n");
    
    printf("-----------------------------------------------------\n");
    printf("  Commands:\n");
    printf("    \033[33m1\033[0m = ADD (transfer 10%% conc to opponent, cost 10 ATP)\n");
    printf("    \033[33m2\033[0m = COPY (PCR: double your conc, cost 30 ATP)\n");
    printf("    \033[33m3\033[0m = SUB (absorb 5%% opponent conc, cost 20 ATP)\n");
    printf("    \033[33m4\033[0m = PASS (skip turn)\n");
    printf("-----------------------------------------------------\n");
}

/* 执行操作 */
int do_action(int player, int cmd) {
    Tube*t = &tubes[player];
    Tube*opp = &tubes[1 - player];
    
    switch(cmd) {
        case 1: /* ADD: 给对手10% */
            if(t->atp < 10) return 0;
            { int transfer = t->conc / 10;
              if(transfer < 1) transfer = 1;
              t->conc -= transfer;
              opp->conc += transfer;
              t->atp -= 10;
              printf("  >> %s transfers %d conc to %s!\n", t->name, transfer, opp->name);
            }
            break;
        case 2: /* COPY: PCR翻倍 */
            if(t->atp < 30) return 0;
            if(t->conc > MAX_CONC / 2) {
                printf("  >> Overflow protection! Cannot exceed %d\n", MAX_CONC);
                return 0;
            }
            t->conc *= 2;
            t->atp -= 30;
            printf("  >> %s PCR amplification! Concentration doubled!\n", t->name);
            break;
        case 3: /* SUB: 吸收对手5% */
            if(t->atp < 20) return 0;
            { int absorb = opp->conc / 20;
              if(absorb < 1) absorb = 1;
              opp->conc -= absorb;
              t->conc += absorb;
              t->atp -= 20;
              printf("  >> %s absorbs %d conc from %s!\n", t->name, absorb, opp->name);
            }
            break;
        case 4: /* PASS */
            printf("  >> %s passes.\n", t->name);
            break;
        default:
            return 0;
    }
    /* 每回合恢复5 ATP */
    t->atp += 5;
    if(t->atp > 100) t->atp = 100;
    
    /* 边界检查 */
    if(t->conc < 0) t->conc = 0;
    if(opp->conc < 0) opp->conc = 0;
    if(t->conc > MAX_CONC) t->conc = MAX_CONC;
    if(opp->conc > MAX_CONC) opp->conc = MAX_CONC;
    
    return 1;
}

/* AI对手 */
int ai_move(void) {
    Tube*ai = &tubes[TUBE_B];
    Tube*pl = &tubes[TUBE_A];
    
    if(ai->conc > 400 && ai->atp >= 30) return 2; /* COPY if strong */
    if(pl->conc > 300 && ai->atp >= 20) return 3; /* SUB if player strong */
    if(ai->conc > 50 && ai->atp >= 10) return 1;  /* ADD */
    return 4; /* PASS */
}

int main(void) {
    srand(time(NULL));
    
    strcpy(tubes[TUBE_A].name, "PLAYER");
    strcpy(tubes[TUBE_B].name, "AI-BOT");
    tubes[TUBE_A].conc = 100;
    tubes[TUBE_B].conc = 100;
    tubes[TUBE_A].atp = 100;
    tubes[TUBE_B].atp = 100;
    
    printf("Welcome to TUBE BATTLE!\n");
    printf("Use DNA concentration operations to defeat AI-BOT.\n");
    printf("Press ENTER to start...");
    getchar();
    
    while(1) {
        draw_screen();
        
        /* Player turn */
        printf("  Your move (1-4): ");
        fflush(stdout);
        char buf[8];
        if(!fgets(buf, sizeof(buf), stdin)) break;
        int cmd = atoi(buf);
        
        if(cmd < 1 || cmd > 4) {
            printf("  Invalid! Press ENTER...");
            getchar();
            continue;
        }
        
        if(!do_action(TUBE_A, cmd)) {
            printf("  Not enough ATP! Press ENTER...");
            getchar();
            continue;
        }
        
        /* Check win */
        if(tubes[TUBE_B].conc <= 0) {
            draw_screen();
            printf("\n  \033[32m>>> YOU WIN! AI-BOT concentration depleted! <<<\033[0m\n\n");
            break;
        }
        if(tubes[TUBE_A].conc <= 0) {
            draw_screen();
            printf("\n  \033[31m>>> YOU LOSE! Your concentration depleted! <<<\033[0m\n\n");
            break;
        }
        
        /* AI turn */
        printf("  AI-BOT thinking...\n");
        usleep(800000);
        int ai_cmd = ai_move();
        do_action(TUBE_B, ai_cmd);
        
        /* Check win */
        if(tubes[TUBE_A].conc <= 0) {
            draw_screen();
            printf("\n  \033[31m>>> YOU LOSE! Your concentration depleted! <<<\033[0m\n\n");
            break;
        }
        if(tubes[TUBE_B].conc <= 0) {
            draw_screen();
            printf("\n  \033[32m>>> YOU WIN! AI-BOT concentration depleted! <<<\033[0m\n\n");
            break;
        }
        
        round_num++;
        printf("  Press ENTER to continue...");
        getchar();
    }
    
    return 0;
}
