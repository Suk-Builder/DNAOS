#!/bin/bash
set -e
cd /workspace/dnaos_check/simulator

echo "=== Building ==="
for f in \
    genome/charter.c \
    genome/d1d4.c \
    transcript/transcript.c \
    transcript/esv.c \
    transcript/atp.c \
    protein/protein.c \
    protein/mersenne_ll.c \
    protein/sieve.c \
    nsm_backend.c \
    av_math.c \
    dna_hal.c \
    dnasm_exec.c \
    boot.c; do
    echo "  $f"
    gcc -O3 -Wall -g -I.. -c "$f" -o "${f%.c}.o" 2>&1 | grep -v "^$"
done

echo ""
echo "=== Linking ==="
gcc -O3 \
    boot.o genome/charter.o genome/d1d4.o \
    transcript/transcript.o transcript/esv.o transcript/atp.o \
    protein/protein.o protein/mersenne_ll.o protein/sieve.o \
    nsm_backend.o av_math.o dna_hal.o dnasm_exec.o \
    -lgmp -lm -o dnaos2

echo ""
echo "=== Running ==="
./dnaos2