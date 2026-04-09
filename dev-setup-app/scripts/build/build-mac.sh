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
else
    echo "  ✓ Tauri CLI — $(cargo tauri --version 2>&1 | head -1)"
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
if [ $? -ne 0 ]; then
    echo ""
    echo "══════════════════════════════════════════════════"
    echo "  ❌ Build failed! See errors above."
    echo "══════════════════════════════════════════════════"
    exit 1
fi
elif [ "$BUILD_TARGET" = "aarch64" ]; then
    cargo tauri build --target aarch64-apple-darwin
    if [ $? -ne 0 ]; then echo "  ❌ Build failed!"; exit 1; fi
else
    cargo tauri build --target x86_64-apple-darwin
    if [ $? -ne 0 ]; then echo "  ❌ Build failed!"; exit 1; fi
fi

# ── 5. Find and report output ────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════════════"
echo "  ✅ Build complete!"
echo ""

DMG_PATH=$(find "$APP_DIR/src-tauri/target" -name "*.dmg" 2>/dev/null | head -1)
APP_PATH=$(find "$APP_DIR/src-tauri/target" -name "*.app" -type d 2>/dev/null | head -1)

if [ -n "$DMG_PATH" ]; then
    SIZE=$(du -sh "$DMG_PATH" | cut -f1)
    echo "  📦 DMG  : $DMG_PATH"
    echo "  📏 Size : $SIZE"
fi

if [ -n "$APP_PATH" ]; then
    echo "  📂 .app : $APP_PATH"
fi

# ── 6. Bundle installer script into DMG ──────────────────────────────────────

if [ -n "$DMG_PATH" ] && [ -f "$APP_DIR/scripts/macos/install_app.sh" ]; then
    echo ""
    echo "══════════════════════════════════════════════════"
    echo "  📝 Bundling installer script into DMG..."
    echo ""

    # Create temporary directory for DMG contents
    TEMP_DMG_DIR="$APP_DIR/src-tauri/target/dmg-bundle"
    mkdir -p "$TEMP_DMG_DIR"

    # Mount the original DMG
    echo "  → Mounting original DMG..."
    MOUNT_POINT=$(hdiutil attach "$DMG_PATH" -nobrowse -readonly | grep "/Volumes" | awk '{print $NF}')

    if [ -z "$MOUNT_POINT" ]; then
        echo "  ⚠️  Could not mount DMG, skipping installer bundling"
    else
        echo "  → Copying contents..."
        cp -R "$MOUNT_POINT"/* "$TEMP_DMG_DIR/"

        # Copy installer script
        echo "  → Adding install_app.sh..."
        cp "$APP_DIR/scripts/macos/install_app.sh" "$TEMP_DMG_DIR/"
        chmod +x "$TEMP_DMG_DIR/install_app.sh"

        # Copy installation guide
        if [ -f "$APP_DIR/docs/INSTALLATION_GUIDE.md" ]; then
            echo "  → Adding installation guide..."
            cp "$APP_DIR/docs/INSTALLATION_GUIDE.md" "$TEMP_DMG_DIR/"
        fi

        # Unmount original DMG
        echo "  → Unmounting original DMG..."
        hdiutil detach "$MOUNT_POINT" -quiet

        # Create new DMG with installer script
        NEW_DMG_PATH="${DMG_PATH%.dmg}_with_installer.dmg"
        echo "  → Creating enhanced DMG..."

        # Remove old DMG
        rm -f "$DMG_PATH"

        # Create new DMG with installer
        hdiutil create -volname "Dev_Setup" \
                       -srcfolder "$TEMP_DMG_DIR" \
                       -ov -format UDZO \
                       "$NEW_DMG_PATH" > /dev/null 2>&1

        if [ $? -eq 0 ]; then
            # Rename back to original name
            mv "$NEW_DMG_PATH" "$DMG_PATH"

            echo "  ✅ Enhanced DMG created successfully"
            echo ""
            echo "  DMG now contains:"
            echo "    • Dev_Setup.app (the application)"
            echo "    • install_app.sh (automated installer)"
            echo "    • INSTALLATION_GUIDE.md (user documentation)"
        else
            echo "  ⚠️  Could not create enhanced DMG"
            # Restore from temp if available
            if [ -f "$NEW_DMG_PATH" ]; then
                mv "$NEW_DMG_PATH" "$DMG_PATH"
            fi
        fi

        # Cleanup
        rm -rf "$TEMP_DMG_DIR"
    fi
fi

echo ""
echo "══════════════════════════════════════════════════"
if [ -n "$DMG_PATH" ]; then
    echo ""
    echo "  📦 Final DMG: $DMG_PATH"
    echo ""
    echo "  Distribution Instructions:"
    echo "  ─────────────────────────────────────────────"
    echo "  1. Upload DMG to internal file server/GitHub Releases"
    echo "  2. Users download and mount the DMG"
    echo "  3. Users run: cd /Volumes/Dev_Setup && ./install_app.sh"
    echo "  4. Or share docs/INSTALLATION_GUIDE.md for full instructions"
    echo ""
    echo "  The DMG includes:"
    echo "    ✓ Application bundle (universal binary)"
    echo "    ✓ Automated installer script"
    echo "    ✓ Installation guide (Markdown)"
else
    echo "  DMG not found — check src-tauri/target/ for build output"
fi

echo "══════════════════════════════════════════════════"
