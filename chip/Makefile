# ============================================================================
# DNAOS Quaternary Processor - Build & Simulate
# ============================================================================
# Requires: Icarus Verilog (iverilog) for simulation
# Install: apt install iverilog
# ============================================================================

.PHONY: sim clean

sim: dnaos_quat.vvp
	vvp dnaos_quat.vvp

dnaos_quat.vvp: dnaos_quat.v dnaos_quat_tb.v
	iverilog -o dnaos_quat.vvp dnaos_quat.v dnaos_quat_tb.v

clean:
	rm -f dnaos_quat.vvp dnaos_quat.vcd

# View waveform: gtkwave dnaos_quat.vcd
