#!/usr/bin/env bash
# install_homebrew.sh — Install Homebrew (macOS package manager)
set -euo pipefail

SKIP_INSTALLED="${SETUP_SKIP_INSTALLED:-true}"

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║           Homebrew Package Manager Installation          ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "[1/3] Checking current installation..."

# Detect architecture to set correct prefix
ARCH="$(uname -m)"
echo "  → Detected architecture: $ARCH"

if [ "$ARCH" = "arm64" ]; then
    BREW_PREFIX="/opt/homebrew"
    echo "  → Installation path: $BREW_PREFIX (Apple Silicon)"
else
    BREW_PREFIX="/usr/local"
    echo "  → Installation path: $BREW_PREFIX (Intel)"
fi

BREW_BIN="$BREW_PREFIX/bin/brew"

if [ "$SKIP_INSTALLED" = "true" ] && (command -v brew &>/dev/null || [ -x "$BREW_BIN" ]); then
    echo ""
    echo "✓ Homebrew already installed"
    echo "  Version: $(brew --version | head -1)"
    echo "  Location: $(which brew)"
    echo ""
    echo "[2/3] Updating Homebrew package database..."
    brew update --quiet 2>&1 || echo "  ⚠ Update skipped (may be offline)"
    echo "  ✓ Update complete"
    exit 0
elif command -v brew &>/dev/null || [ -x "$BREW_BIN" ]; then
    echo ""
    echo "✓ Homebrew found (SKIP_INSTALLED=false, updating...)"
    brew update 2>&1
    echo "  ✓ Updated: $(brew --version | head -1)"
    exit 0
fi

echo ""
echo "✗ Homebrew not found"
echo ""
echo "[2/3] Downloading Homebrew installer..."
echo "  Source: https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
echo "  This script will:"
echo "    • Create $BREW_PREFIX directory structure"
echo "    • Download Homebrew repository (~200MB)"
echo "    • Configure PATH and environment"
echo "    • Requires admin password (will prompt via dialog)"
echo ""

echo "[3/3] Running Homebrew installation script..."
echo "  (This may take 3-5 minutes — a password dialog will appear)"
echo "  → You'll be prompted for your admin password via macOS dialog"
echo ""

# Create a temporary script that will run the Homebrew installer
TEMP_SCRIPT=$(mktemp)
cat > "$TEMP_SCRIPT" << 'INSTALLER_EOF'
#!/bin/bash
set -e
export NONINTERACTIVE=1
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
INSTALLER_EOF

chmod +x "$TEMP_SCRIPT"

# Use osascript to run with admin privileges (triggers password dialog)
if osascript -e "do shell script \"'$TEMP_SCRIPT'\" with administrator privileges" 2>&1; then
    rm -f "$TEMP_SCRIPT"
    echo ""
    echo "  ✓ Homebrew core installation complete"
else
    rm -f "$TEMP_SCRIPT"
    echo ""
    echo "  ✗ Homebrew installation failed"
    echo ""
    echo "  Common issues:"
    echo "    • User cancelled password prompt"
    echo "    • Not an administrator account"
    echo "    • Network connectivity (check internet connection)"
    echo "    • Disk space (need ~1GB free)"
    echo ""
    echo "  Manual installation:"
    echo "    1. Open Terminal"
    echo "    2. Run: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    echo "    3. Follow prompts and enter password when asked"
    echo ""
    exit 1
fi

# Add Homebrew to PATH for Apple Silicon
if [ "$ARCH" = "arm64" ]; then
    echo ""
    echo "→ Configuring PATH for Apple Silicon..."
    if ! grep -q 'eval "$(/opt/homebrew/bin/brew shellenv)"' ~/.zprofile 2>/dev/null; then
        echo '' >> ~/.zprofile
        echo '# Homebrew' >> ~/.zprofile
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
        echo "  ✓ Added to ~/.zprofile"
    else
        echo "  ✓ Already configured in ~/.zprofile"
    fi
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

echo ""
echo "→ Running post-installation diagnostics..."
brew doctor 2>&1 || echo "  ⚠ Some warnings detected (usually non-fatal)"

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "✓ Homebrew installation complete!"
echo "  Version: $(brew --version 2>/dev/null | head -1)"
echo "  Location: $BREW_PREFIX"
echo "  Available commands: brew install, brew search, brew update"
echo "═══════════════════════════════════════════════════════════"
