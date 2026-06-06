/* 【protein/protein.c -- Protein Execution 层】 */
#include "../include/dnaos.h"

typedef struct { int id, active; char name[32]; } protein_t;
static protein_t proteins[MAX_PROTEINS];

void protein_init(void) {
    for(int i = 0; i < MAX_PROTEINS; i++) proteins[i].active = 0;
    printf("[PROTEIN] Pool: %d slots\n", MAX_PROTEINS);
}

int protein_create(const char*name, const char*gene) {
    (void)gene;
    for(int i = 0; i < MAX_PROTEINS; i++) {
        if(!proteins[i].active) {
            proteins[i].id = i;
            proteins[i].active = 1;
            strncpy(proteins[i].name, name, 31);
            printf("[PROTEIN] Created '%s' [slot %d]\n", name, i);
            return i;
        }
    }
    return -1;
}

void protein_hydrolyze(int pid) {
    if(pid < 0 || pid >= MAX_PROTEINS) return;
    if(proteins[pid].active) {
        printf("[PROTEIN] HYDROLYZED '%s' [slot %d] -- BURNED\n", proteins[pid].name, pid);
        proteins[pid].active = 0;
    }
}
