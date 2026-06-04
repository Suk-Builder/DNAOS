/* transcript/atp.c -- ATP Energy Budget Management */
#include "../include/dnaos.h"

static long long atp_budget = 0;
static long long atp_spent = 0;

void atp_init(long long budget) {
    atp_budget = budget;
    atp_spent = 0;
    printf("[ATP] Budget initialized: %lld ATP\n", budget);
}

int atp_consume(long long cost) {
    if(atp_spent + cost > atp_budget) return 0;
    atp_spent += cost;
    return 1;
}

long long atp_remaining(void) {
    return atp_budget - atp_spent;
}
