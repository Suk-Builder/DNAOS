/* transcript/esv.c -- Environmental Signal Vector */
#include "../include/dnaos.h"

typedef struct { double temp, sound, light, load, latency; } ESV;
static ESV esv;

void esv_init(void) {
    esv.temp = 37.0;
    esv.sound = 0.0;
    esv.light = 100.0;
    esv.load = 0.0;
    esv.latency = 1.0;
    printf("[ESV] Sensor initialized\n");
}

void esv_sample(void) {
    /* Read system state as environmental signals */
    FILE*fp = fopen("/sys/class/thermal/thermal_zone0/temp", "r");
    if(fp) { int t; fscanf(fp, "%d", &t); esv.temp = t / 1000.0; fclose(fp); }
    
    fp = fopen("/proc/loadavg", "r");
    if(fp) { fscanf(fp, "%lf", &esv.load); fclose(fp); }
    
    esv.light = 50.0 + sin(time(NULL) / 60.0) * 50.0; /* Simulated */
}

void esv_dump(void) {
    printf("[ESV] temp=%.1fC sound=%.1f load=%.2f light=%.1f latency=%.1fms\n",
        esv.temp, esv.sound, esv.load, esv.light, esv.latency);
}
