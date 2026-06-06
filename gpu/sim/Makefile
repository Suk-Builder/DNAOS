# DNAOS v3.3 GA106 GPU Simulator Makefile
# 目标: AMD Ryzen 5 5500 + AVX2

AS      = nasm
ASFLAGS = -f elf64 -g
LD      = ld
LDFLAGS =

TARGET  = ga106_sim
SRC     = ga106_sim.asm
OBJ     = ga106_sim.o

.PHONY: all clean run test

all: $(TARGET)

$(TARGET): $(OBJ)
	$(LD) $(LDFLAGS) $(OBJ) -o $(TARGET)

$(OBJ): $(SRC)
	$(AS) $(ASFLAGS) $(SRC) -o $(OBJ)

run: $(TARGET)
	./$(TARGET)

test: $(TARGET)
	@echo "Testing GA106 Simulator..."
	./$(TARGET)
	@echo "Test complete."

clean:
	rm -f $(OBJ) $(TARGET)

# 验证CPU支持AVX2
check-cpu:
	@echo "Checking AVX2 support..."
	@cat /proc/cpuinfo | grep -q avx2 && echo "AVX2: YES" || echo "AVX2: NO - CPU not supported"

# 安装依赖 (Debian/Ubuntu)
install-deps:
	sudo apt-get update
	sudo apt-get install -y nasm binutils

# 反汇编查看
objdump: $(TARGET)
	objdump -d -M intel $(TARGET) | head -200

# 十六进制查看
hexdump: $(TARGET)
	objdump -d -M intel $(TARGET) > ga106_sim.lst
	@echo "Disassembly saved to ga106_sim.lst"
