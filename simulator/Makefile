# Makefile — DNAOS v2.0 Genesis Simulator
# Compile all genome/transcript/protein/NSM source into dnaos2 binary

CC      = gcc
CFLAGS  = -O3 -Wall -g -I..
LDFLAGS = -lgmp -lm
TARGET  = dnaos2

# All .c files (boot last — defines main())
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
	rm -f $(OBJS) $(TARGET)

run: $(TARGET)
	./$(TARGET)