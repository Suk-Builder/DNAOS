CC = gcc
CFLAGS = -O3 -Wall -I.
LDFLAGS = -lgmp -lm

SRCS = boot.c genome/charter.c genome/d1d4.c \
       kernel/kernel.c \
       transcript/transcript.c transcript/esv.c transcript/atp.c \
       protein/protein.c protein/mersenne_ll.c protein/sieve.c
OBJS = $(SRCS:.c=.o)
TARGET = dnaos2

.PHONY: all clean test

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(OBJS) -o $@ $(LDFLAGS)

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(OBJS) $(TARGET)

test: $(TARGET)
	./$(TARGET)
