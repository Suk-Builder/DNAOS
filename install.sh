#!/bin/bash
# DNAOS v2.0 Genesis -- One-Click Installer
# Usage: ./install.sh
# After install, type 'dnaos' to start

set -e

echo "============================================================"
echo "     DNAOS v2.0 Genesis -- Charter Operating System"
echo "     AI Metabolism Architecture"
echo "============================================================"
echo ""

INSTALL_DIR="${HOME}/.dnaos"
BIN_DIR="${HOME}/.local/bin"

# ---- Check OS ----
OS="unknown"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
elif [ "$(uname)" = "Darwin" ]; then
    OS="macOS"
fi
echo "[1/5] OS: $OS"

# ---- Check deps ----
echo "[2/5] Checking dependencies..."
MISSING=""

if ! command -v gcc >/dev/null 2>&1; then
    MISSING="$MISSING gcc"
fi
if ! command -v make >/dev/null 2>&1; then
    MISSING="$MISSING make"
fi

GMP_OK=0
if printf '#include <gmp.h>\nint main(){return 0;}' | gcc -x c - -lgmp -o /dev/null 2>/dev/null; then
    GMP_OK=1
fi

if [ $GMP_OK -eq 0 ]; then
    MISSING="$MISSING libgmp-dev"
fi

if [ -n "$MISSING" ]; then
    echo ""
    echo "MISSING:$MISSING"
    echo ""
    echo "Install with:"
    if echo "$OS" | grep -qi "ubuntu\|debian"; then
        echo "  sudo apt-get update && sudo apt-get install -y gcc make libgmp-dev"
    elif echo "$OS" | grep -qi "centos\|rhel\|fedora"; then
        echo "  sudo yum install -y gcc make gmp-devel"
    elif echo "$OS" | grep -qi "arch"; then
        echo "  sudo pacman -S gcc make gmp"
    elif [ "$OS" = "macOS" ]; then
        echo "  brew install gmp"
        echo "  (If gcc missing: xcode-select --install)"
    fi
    echo ""
    echo "Then re-run: ./install.sh"
    exit 1
fi
echo "      All OK (gcc, make, gmp)"

# ---- Install ----
echo "[3/5] Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR" "$BIN_DIR"

# Copy all files
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp -r "$SCRIPT_DIR"/* "$SCRIPT_DIR"/Makefile "$INSTALL_DIR/" 2>/dev/null || true

# Build
echo "[4/5] Compiling DNAOS..."
cd "$INSTALL_DIR"
make clean >/dev/null 2>&1
make 2>&1 | tail -5

# Create launcher
echo "[5/5] Creating launcher..."
cat > "$BIN_DIR/dnaos" << 'LAUNCHER'
#!/bin/bash
exec "$HOME/.dnaos/dnaos2" "$@"
LAUNCHER
chmod +x "$BIN_DIR/dnaos"

# Add to PATH
if ! echo "$PATH" | grep -q "$BIN_DIR"; then
    SHELL_RC=""
    if [ -f "$HOME/.bashrc" ]; then SHELL_RC="$HOME/.bashrc"
    elif [ -f "$HOME/.zshrc" ]; then SHELL_RC="$HOME/.zshrc"
    fi
    
    if [ -n "$SHELL_RC" ]; then
        echo "export PATH=\"$BIN_DIR:\$PATH\"" >> "$SHELL_RC"
        echo ""
        echo "Added to PATH. Run: source $SHELL_RC"
    fi
fi

# Done
echo ""
echo "============================================================"
echo "     DNAOS v2.0 Installed!"
echo "============================================================"
echo ""
echo "Start DNAOS:        dnaos"
echo "GitHub:             https://github.com/Suk-Builder/DNAOS"
echo "Source:             $INSTALL_DIR"
echo ""
echo "The United Nations Charter of All Universes"
echo "is now hardcoded in your system."
echo ""

# Ask to run
printf "Start DNAOS now? [Y/n] "
read -r answer
if [ -z "$answer" ] || echo "$answer" | grep -qi "^y"; then
    exec "$BIN_DIR/dnaos"
fi
