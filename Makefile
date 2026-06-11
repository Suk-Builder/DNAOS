# DNAOS v3.5 Root Makefile
# Delegate to submodule Makefiles

.PHONY: all simulator clean help

all: simulator

simulator:
	@echo "Building DNAOS simulator..."
	$(MAKE) -C simulator

clean:
	@echo "Cleaning..."
	$(MAKE) -C simulator clean

help:
	@echo "DNAOS v3.5 — available targets:"
	@echo "  make           — build simulator"
	@echo "  make clean     — remove build artifacts"
	@echo "  make simulator — same as make"
	@echo ""
	@echo "Quick start:"
	@echo "  cd simulator && make && ./dnaos2"