#!/usr/bin/env bash
# ============================================================
# build-local-mac.sh — Build the Dev Setup app locally on macOS
# Produces: src-tauri/target/release/bundle/dmg/*.dmg
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD_TARGET="${1:-universal}"  # "universal" | "x86_64" | "aarch64"

echo "╔══════════════════════════════════════════════════╗"
echo "║      Dev Setup App — Local macOS Builder          ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "  App dir : $APP_DIR"
echo "  Target  : $BUILD_TARGET"
echo ""

# ── 1. Check prerequisites ──────────────────────────────────────────────────

echo "==> Checking prerequisites..."

check_cmd() {
    if ! command -v "$1" &>/dev/null; then
        echo "  ✗ $1 not found"
        return 1
    fi
    echo "  ✓ $1 — $($1 --version 2>&1 | head -1)"
}

PREREQ_OK=true

check_cmd rustc  || PREREQ_OK=false
check_cmd cargo  || PREREQ_OK=false
check_cmd node   || PREREQ_OK=false
check_cmd npm    || PREREQ_OK=false

if ! command -v cargo-tauri &>/dev/null && ! cargo tauri --version &>/dev/null 2>&1; then
    echo "  ✗ Tauri CLI not found"
    PREREQ_OK=false
fi

if [ "$PREREQ_OK" = "false" ]; then
    echo ""
    echo "══════════════════════════════════════════════════"
    echo "  Missing prerequisites. Install them first:"
    echo ""
    echo "  1. Rust:"
    echo "     curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    echo "     source ~/.cargo/env"
    echo ""
    echo "  2. Tauri CLI:"
    echo "     cargo install tauri-cli"
    echo ""
    echo "  3. Node.js (via nvm):"
    echo "     curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash"
    echo "     source ~/.zshrc && nvm install 20 && nvm use 20"
    echo "══════════════════════════════════════════════════"
    exit 1
fi

# ── 2. Add Apple Silicon + Intel targets (for universal build) ───────────────

if [ "$BUILD_TARGET" = "universal" ]; then
    echo ""
    echo "==> Adding Rust targets for universal binary..."
    rustup target add aarch64-apple-darwin x86_64-apple-darwin
fi

# ── 3. Install frontend dependencies ────────────────────────────────────────

echo ""
echo "==> Installing frontend dependencies..."
cd "$APP_DIR"
npm ci

# ── 4. Build ─────────────────────────────────────────────────────────────────

echo ""
echo "==> Building Tauri app (target: $BUILD_TARGET)..."
echo "    This takes 5-15 minutes on first build (Rust compilation)"
echo ""

if [ "$BUILD_TARGET" = "universal" ]; then
    cargo tauri build --target universal-apple-darwin
elif [ "$BUILD_TARGET" = "aarch64" ]; then
    cargo tauri build --target aarch64-apple-darwin
else
    cargo tauri build --target x86_64-apple-darwin
fi

# ── 5. Find and report output ────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════════════"
echo "  ✅ Build complete!"
echo ""

DMG_PATH=$(find "$APP_DIR/src-tauri/target" -name "*.dmg" 2>/dev/null | head -1)
if [ -n "$DMG_PATH" ]; then
    SIZE=$(du -sh "$DMG_PATH" | cut -f1)
    echo "  📦 DMG  : $DMG_PATH"
    echo "  📏 Size : $SIZE"
    echo ""
    echo "  To distribute:"
    echo "  1. Upload the .dmg to GitHub Releases, Google Drive, or any file host"
    echo "  2. Users: double-click DMG → drag app to Applications → launch"
else
    echo "  DMG not found — check src-tauri/target/ for build output"
fi

APP_PATH=$(find "$APP_DIR/src-tauri/target" -name "*.app" -type d 2>/dev/null | head -1)
if [ -n "$APP_PATH" ]; then
    echo ""
    echo "  📂 .app : $APP_PATH"
fi

echo "══════════════════════════════════════════════════"
