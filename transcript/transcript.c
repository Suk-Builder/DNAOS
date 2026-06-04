/* transcript/transcript.c -- Transcription Engine */
#include "../include/dnaos.h"

static int transcript_ready = 0;

void transcript_init(void) {
    transcript_ready = 1;
    printf("[TRANSCRIPT] Engine ready\n");
}

int transcribe(const char*capability) {
    if(!transcript_ready) transcript_init();
    printf("[TRANSCRIBE] Loading gene for '%s'...\n", capability);
    
    /* Map capability to gene file */
    const char*gene_file = NULL;
    if(strcasecmp(capability, "VISION") == 0)   gene_file = "genome/capabilities/vision.gene";
    else if(strcasecmp(capability, "AUDIO") == 0)   gene_file = "genome/capabilities/audio.gene";
    else if(strcasecmp(capability, "REASON") == 0)  gene_file = "genome/capabilities/reason.gene";
    else if(strcasecmp(capability, "MERSENNE") == 0) gene_file = "genome/capabilities/mersenne.gene";
    
    if(!gene_file) {
        printf("[TRANSCRIBE] Unknown capability: %s\n", capability);
        return -1;
    }
    
    /* Check charter before transcription */
    if(!charter_check_action(0xA3, capability)) {
        printf("[TRANSCRIBE] BLOCKED by Charter Article 1.3\n");
        return -1;
    }
    
    /* Check ATP budget */
    long long cost = 100;
    if(strcasecmp(capability, "MERSENNE") == 0) cost = 500;
    else if(strcasecmp(capability, "REASON") == 0) cost = 300;
    
    if(!atp_consume(cost)) {
        printf("[TRANSCRIPT] INSUFFICIENT ATP (%s needs %lld)\n", capability, cost);
        return -1;
    }
    
    printf("[TRANSCRIBE] Gene '%s' loaded, ATP consumed: %lld\n", gene_file, cost);
    return 0; /* protein_id */
}
