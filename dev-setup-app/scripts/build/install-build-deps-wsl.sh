#!/usr/bin/env bash
# ============================================================
# install-build-deps-wsl.sh
# Run ONCE inside WSL (Ubuntu 22.04 or 24.04) to install
# everything needed to build the Dev Setup app.
# After this, run build-wsl.sh
# ============================================================
set -euo pipefail

echo "╔══════════════════════════════════════════════════╗"
echo "║  Installing Build Dependencies (WSL / Ubuntu)    ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ─── Detect Ubuntu version ───────────────────────────────────
UBUNTU_VERSION=$(lsb_release -rs 2>/dev/null || echo "0")
UBUNTU_MAJOR=$(echo "$UBUNTU_VERSION" | cut -d. -f1)
echo "  Detected: Ubuntu $UBUNTU_VERSION"
echo ""

# ─── 1. System packages ──────────────────────────────────────
echo "==> [1/5] Installing system packages..."
sudo apt-get update -q

# Core build tools
sudo apt-get install -y \
    build-essential \
    curl \
    wget \
    file \
    git \
    pkg-config \
    libssl-dev \
    libgtk-3-dev \
    libayatana-appindicator3-dev \
    librsvg2-dev \
    patchelf \
    squashfs-tools \
    libxdo-dev \
    libxcb1-dev \
    libxrandr-dev \
    libdbus-1-dev

# Ubuntu 24.04 (noble) uses webkit2gtk-4.1; Ubuntu 22.04 uses 4.0
if [ "$UBUNTU_MAJOR" -ge 24 ]; then
    echo "  Ubuntu 24.04+ detected — installing libwebkit2gtk-4.1-dev"
    sudo apt-get install -y libwebkit2gtk-4.1-dev libjavascriptcoregtk-4.1-dev

    # ── pkg-config compatibility shim ──────────────────────────
    # Tauri v1 looks for 'webkit2gtk-4.0' by name. We create symlinks
    # so pkg-config resolves 4.0 → 4.1 (API-compatible on Ubuntu 24.04).
    echo "  Creating webkit2gtk-4.0 → 4.1 pkg-config compatibility shims..."

    PKG_DIR="/usr/lib/x86_64-linux-gnu/pkgconfig"

    for pair in \
        "webkit2gtk-4.0.pc:webkit2gtk-4.1.pc" \
        "webkit2gtk-web-extension-4.0.pc:webkit2gtk-web-extension-4.1.pc" \
        "javascriptcoregtk-4.0.pc:javascriptcoregtk-4.1.pc"; do

        LINK="${PKG_DIR}/${pair%%:*}"
        TARGET="${PKG_DIR}/${pair##*:}"

        if [ -f "$TARGET" ] && [ ! -e "$LINK" ]; then
            sudo ln -sf "$TARGET" "$LINK"
            echo "    ✓ $LINK → $TARGET"
        elif [ -e "$LINK" ]; then
            echo "    ✓ $LINK already exists"
        else
            echo "    ⚠ Target not found: $TARGET"
        fi
    done

    # Also set the WEBKIT env var used by some Tauri versions
    echo 'export PKG_CONFIG_PATH="/usr/lib/x86_64-linux-gnu/pkgconfig:$PKG_CONFIG_PATH"' \
        >> ~/.bashrc

else
    echo "  Ubuntu 22.04 detected — installing libwebkit2gtk-4.0-dev"
    sudo apt-get install -y libwebkit2gtk-4.0-dev libjavascriptcoregtk-4.0-dev
fi

echo "  ✓ System packages installed"

# ─── 2. Rust (via rustup) ────────────────────────────────────
echo ""
echo "==> [2/5] Installing Rust toolchain..."

if command -v rustc &>/dev/null; then
    echo "  ✓ Rust already installed: $(rustc --version)"
    rustup update stable --quiet
else
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    source "$HOME/.cargo/env"
    echo "  ✓ Rust installed: $(rustc --version)"
fi

# Add cargo bin to PATH for this session + future sessions
export PATH="$HOME/.cargo/bin:$PATH"
if ! grep -q 'cargo/bin' ~/.bashrc 2>/dev/null; then
    echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc
fi

# ─── 3. Tauri CLI ────────────────────────────────────────────
echo ""
echo "==> [3/5] Installing Tauri CLI..."

if cargo tauri --version &>/dev/null 2>&1; then
    echo "  ✓ Already installed: $(cargo tauri --version)"
else
    echo "  Installing tauri-cli (takes 3-5 minutes)..."
    cargo install tauri-cli --version "^1.5" --locked
    echo "  ✓ Tauri CLI installed: $(cargo tauri --version)"
fi

# ─── 4. Node.js check ────────────────────────────────────────
echo ""
echo "==> [4/5] Checking Node.js..."

if command -v node &>/dev/null; then
    echo "  ✓ Node.js already installed: $(node --version)"
else
    echo "  Installing Node.js 20 via nvm..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    nvm install 20
    nvm alias default 20
    echo "  ✓ Node.js installed: $(node --version)"
fi

# ─── 5. Verify pkg-config can find webkit ────────────────────
echo ""
echo "==> [5/5] Verifying pkg-config can find webkit2gtk..."

export PKG_CONFIG_PATH="/usr/lib/x86_64-linux-gnu/pkgconfig:${PKG_CONFIG_PATH:-}"

if pkg-config --exists webkit2gtk-4.0 2>/dev/null; then
    WEBKIT_VER=$(pkg-config --modversion webkit2gtk-4.0)
    echo "  ✓ webkit2gtk-4.0 found (resolves to $WEBKIT_VER)"
else
    echo "  ✗ webkit2gtk-4.0 not found via pkg-config"
    echo "    Try: export PKG_CONFIG_PATH=/usr/lib/x86_64-linux-gnu/pkgconfig"
    echo "    Then re-run this script."
fi

if pkg-config --exists gtk+-3.0 2>/dev/null; then
    echo "  ✓ gtk+-3.0 found ($(pkg-config --modversion gtk+-3.0))"
fi

echo ""
echo "══════════════════════════════════════════════════"
echo "  ✅ Build dependencies ready!"
echo ""
echo "  IMPORTANT: Reload your shell before building:"
echo "    source ~/.bashrc"
echo "    # or open a new terminal tab"
echo ""
echo "  Then build the app:"
echo "    cd dev-setup-app"
echo "    bash scripts/build/build-wsl.sh"
echo "══════════════════════════════════════════════════"
