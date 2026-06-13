# Makefile — DNAOS v2.0 Genesis Simulator
CC      = gcc
CFLAGS  = -O3 -Wall -g -I..
LDFLAGS = -lgmp -lm
TARGET  = dnaos2

SRCS = \
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
	world/cube_world.c \
	boot.c

OBJS = $(SRCS:.c=.o)

.PHONY: all clean run

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(OBJS) $(LDFLAGS) -o $@
	@echo "Built: $(TARGET)"

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f genome/*.o transcript/*.o protein/*.o *.o $(TARGET)

run: $(TARGET)
	./$(TARGET)