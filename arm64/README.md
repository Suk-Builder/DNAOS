# DNAOS ARM64 - OnePlus 6T (Snapdragon 845)

Bare-metal quaternary OS for ARM64.

## Quick Start

```bash
# Install cross-compiler
sudo apt install gcc-aarch64-linux-gnu

# Build boot image
python3 build_img.py

# Flash to OnePlus 6T (fastboot mode: Vol Up + Power)
fastboot boot out/dnaos_arm64.img
```

## Hardware

| Component | Spec |
|-----------|------|
| SoC | Snapdragon 845 (SDM845) |
| CPU | 4x A75 @ 2.8GHz + 4x A55 @ 1.8GHz |
| RAM | 6/8GB LPDDR4X |
| Display | 1080x2340 AMOLED |
| UART | USB-C debug dongle, 115200 baud |
| Boot | Android ABL -> kernel @ 0x8000 |

## Architecture

```
ABL (Android Bootloader)
  └─> boot.S @ EL1
       ├─> UART1 (0xA84000) - serial console
       ├─> Framebuffer (DTB simplefb) - GUI
       ├─> DNAsm interpreter - quaternary commands
       └─> ATP metabolism - energy counter
```

## DNAsm Commands (via UART)

| Key | Action |
|-----|--------|
| A | Encode register as ATCG |
| T | Decode ATCG to register |
| C | AND (quaternary min) |
| G | OR (quaternary max) |
| N | NOT (complement) |
| + | ADD (with carry) |
| P | Print register |

## Files

- `boot.S` - ARM64 bare-metal kernel
- `linker.ld` - Linker script
- `build_img.py` - Boot image generator
