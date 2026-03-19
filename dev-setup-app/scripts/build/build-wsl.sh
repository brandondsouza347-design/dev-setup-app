#!/usr/bin/env bash
# ============================================================
# build-wsl.sh — Build the Dev Setup app from WSL (Ubuntu)
#
# Outputs (written to src-tauri/target/release/bundle/):
#   AppImage  → appimage/dev-setup_*.AppImage  (portable, no install)
#   Deb       → deb/dev-setup_*.deb            (for Ubuntu/Debian)
#
# Windows MSI/EXE must still be built via:
#   - GitHub Actions (recommended): push a v* tag
#   - Native Windows: run scripts/build/build-windows.ps1
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
UBUNTU_MAJOR=$(lsb_release -rs 2>/dev/null | cut -d. -f1 || echo "0")

echo "╔══════════════════════════════════════════════════╗"
echo "║       Dev Setup App — WSL Linux Builder           ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "  App dir : $APP_DIR"
echo "  Ubuntu  : $(lsb_release -ds 2>/dev/null || echo unknown)"
echo ""

# ─── 1. Prerequisites check ──────────────────────────────────
echo "==> Checking prerequisites..."
PREREQ_OK=true

check() {
    if command -v "$1" &>/dev/null; then
        echo "  ✓ $1 — $($1 --version 2>&1 | head -1)"
    else
        echo "  ✗ $1 not found"
        PREREQ_OK=false
    fi
}

check rustc
check cargo
check node
check npm

# Tauri CLI
if cargo tauri --version &>/dev/null 2>&1; then
    echo "  ✓ tauri-cli — $(cargo tauri --version)"
else
    echo "  ✗ tauri-cli not found"
    PREREQ_OK=false
fi

if [ "$PREREQ_OK" = "false" ]; then
    echo ""
    echo "  ✗ Missing prerequisites. Run first:"
    echo "    bash scripts/build/install-build-deps-wsl.sh"
    exit 1
fi

# ─── 2. Ubuntu 24.04 webkit pkg-config shim ──────────────────
if [ "$UBUNTU_MAJOR" -ge 24 ]; then
    export PKG_CONFIG_PATH="/usr/lib/x86_64-linux-gnu/pkgconfig:${PKG_CONFIG_PATH:-}"
    if ! pkg-config --exists webkit2gtk-4.0 2>/dev/null; then
        echo ""
        echo "  ✗ webkit2gtk-4.0 not found via pkg-config."
        echo "    Run install-build-deps-wsl.sh first to create the compatibility shim."
        exit 1
    fi
    echo "  ✓ webkit2gtk-4.0 compat shim active (→ 4.1)"
fi

# ─── 3. Install frontend dependencies ────────────────────────
echo ""
echo "==> Installing frontend dependencies..."
cd "$APP_DIR"
npm ci

# ─── 4. Build ─────────────────────────────────────────────────
echo ""
echo "==> Building Tauri app..."
echo "    First build takes 5-15 minutes (Rust compiling)"
echo "    Subsequent builds are much faster (incremental)"
echo ""

# Set env vars needed for Ubuntu 24.04 Tauri v1 compatibility
export PKG_CONFIG_PATH="/usr/lib/x86_64-linux-gnu/pkgconfig:${PKG_CONFIG_PATH:-}"
export WEBKIT_DISABLE_DMABUF_RENDERER=1   # Prevents a WebKit crash in headless WSL
export DISPLAY="${DISPLAY:-:99}"          # Required by some GTK initialisation code

# Build (no display needed — this is compile-only, not run)
cargo tauri build 2>&1

# ─── 5. Find and report outputs ──────────────────────────────
BUNDLE="$APP_DIR/src-tauri/target/release/bundle"

echo ""
echo "══════════════════════════════════════════════════"
echo "  ✅ Build complete!"
echo ""

APPIMAGE=$(find "$BUNDLE/appimage" -name "*.AppImage" 2>/dev/null | head -1)
DEB=$(find      "$BUNDLE/deb"      -name "*.deb"      2>/dev/null | head -1)

if [ -n "$APPIMAGE" ]; then
    SIZE=$(du -sh "$APPIMAGE" | cut -f1)
    echo "  📦 AppImage : $APPIMAGE"
    echo "  📏 Size     : $SIZE"
    echo ""
    echo "  Share the .AppImage — users just chmod +x and run it:"
    echo "    chmod +x $(basename "$APPIMAGE")"
    echo "    ./$(basename "$APPIMAGE")"
fi

if [ -n "$DEB" ]; then
    SIZE=$(du -sh "$DEB" | cut -f1)
    echo ""
    echo "  📦 .deb     : $DEB"
    echo "  📏 Size     : $SIZE"
    echo ""
    echo "  Install on Ubuntu/Debian:"
    echo "    sudo dpkg -i $(basename "$DEB")"
fi

if [ -z "$APPIMAGE" ] && [ -z "$DEB" ]; then
    echo "  ⚠ No bundle outputs found."
    echo "    Check src-tauri/target/release/bundle/ manually."
    echo "    The raw binary is at src-tauri/target/release/dev-setup-app"
fi

echo ""
echo "  ℹ To build Windows MSI/EXE:"
echo "    Push a git tag to trigger GitHub Actions:"
echo "      git tag v1.0.0 && git push origin v1.0.0"
echo "══════════════════════════════════════════════════"
