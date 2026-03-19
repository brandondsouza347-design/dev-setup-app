#!/usr/bin/env bash
# ============================================================
# install-build-deps-mac.sh
# Run this ONCE on a fresh Mac to install everything needed
# to build the Dev Setup app. After this, run build-mac.sh.
# ============================================================
set -euo pipefail

echo "╔══════════════════════════════════════════════════╗"
echo "║   Installing Build Dependencies (macOS)           ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ── Xcode CLT ────────────────────────────────────────────────
echo "==> [1/4] Xcode Command Line Tools..."
if xcode-select -p &>/dev/null; then
    echo "  ✓ Already installed"
else
    xcode-select --install
    echo "  Install the Xcode CLT in the dialog, then re-run this script."
    exit 0
fi

# ── Homebrew ─────────────────────────────────────────────────
echo ""
echo "==> [2/4] Homebrew..."
if command -v brew &>/dev/null; then
    echo "  ✓ Already installed: $(brew --version | head -1)"
else
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [ "$(uname -m)" = "arm64" ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    echo "  ✓ Homebrew installed"
fi

# ── Rust ─────────────────────────────────────────────────────
echo ""
echo "==> [3/4] Rust toolchain..."
if command -v rustc &>/dev/null; then
    echo "  ✓ Already installed: $(rustc --version)"
    rustup update stable --quiet
else
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    source "$HOME/.cargo/env"
    echo "  ✓ Rust installed: $(rustc --version)"
fi

# Add Rust Apple Silicon targets
echo "  Adding universal binary targets..."
rustup target add aarch64-apple-darwin x86_64-apple-darwin
source "$HOME/.cargo/env" 2>/dev/null || true

# ── Tauri CLI ─────────────────────────────────────────────────
echo ""
echo "==> [4/4] Tauri CLI..."
if cargo tauri --version &>/dev/null 2>&1; then
    echo "  ✓ Already installed: $(cargo tauri --version)"
else
    echo "  Installing (takes ~2-3 minutes)..."
    cargo install tauri-cli --locked
    echo "  ✓ Tauri CLI installed"
fi

# ── Node.js ───────────────────────────────────────────────────
echo ""
echo "==> Node.js..."
if command -v node &>/dev/null; then
    echo "  ✓ Node $(node -v) already installed"
else
    echo "  Installing Node.js via nvm..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    nvm install 20
    nvm use 20
    echo "  ✓ Node $(node -v) installed"
fi

echo ""
echo "══════════════════════════════════════════════════"
echo "  ✅ All build dependencies installed!"
echo ""
echo "  Next step — build the app:"
echo "    cd dev-setup-app"
echo "    bash scripts/build/build-mac.sh"
echo "══════════════════════════════════════════════════"
echo ""
echo "  NOTE: Run 'source ~/.zshrc' or open a new terminal first"
echo "        to pick up Rust and Node in your PATH."
