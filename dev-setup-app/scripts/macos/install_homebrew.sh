#!/usr/bin/env bash
# install_homebrew.sh — Install Homebrew (macOS package manager)
set -euo pipefail

SKIP_INSTALLED="${SETUP_SKIP_INSTALLED:-true}"

echo "==> Checking Homebrew..."

# Detect architecture to set correct prefix
ARCH="$(uname -m)"
if [ "$ARCH" = "arm64" ]; then
    BREW_PREFIX="/opt/homebrew"
else
    BREW_PREFIX="/usr/local"
fi

BREW_BIN="$BREW_PREFIX/bin/brew"

if [ "$SKIP_INSTALLED" = "true" ] && (command -v brew &>/dev/null || [ -x "$BREW_BIN" ]); then
    echo "✓ Homebrew already installed: $(brew --version | head -1)"
    echo "==> Updating Homebrew..."
    brew update --quiet
    exit 0
elif command -v brew &>/dev/null || [ -x "$BREW_BIN" ]; then
    echo "→ Homebrew already installed but SKIP_INSTALLED=false — updating..."
    brew update
    echo "✓ Homebrew updated: $(brew --version | head -1)"
    exit 0
fi

echo "==> Installing Homebrew..."
echo "    Architecture: $ARCH"
echo "    Expected prefix: $BREW_PREFIX"

/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Add Homebrew to PATH for Apple Silicon
if [ "$ARCH" = "arm64" ]; then
    echo "==> Configuring Homebrew in PATH for Apple Silicon..."
    if ! grep -q 'eval "$(/opt/homebrew/bin/brew shellenv)"' ~/.zprofile 2>/dev/null; then
        echo '' >> ~/.zprofile
        echo '# Homebrew' >> ~/.zprofile
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
    fi
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

echo "==> Running brew doctor..."
brew doctor || echo "⚠ brew doctor reported warnings (usually non-fatal)"

echo "✓ Homebrew installed: $(brew --version | head -1)"
