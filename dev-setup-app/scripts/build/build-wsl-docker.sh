#!/usr/bin/env bash
# ============================================================
# build-wsl-docker.sh
# Builds the app using Docker Desktop (from WSL terminal).
# This is the simplest WSL build path — no manual dep installs.
#
# Requirements:
#   - Docker Desktop for Windows with WSL2 integration enabled
#     https://docs.docker.com/desktop/wsl/
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
IMAGE="dev-setup-builder:latest"

echo "╔══════════════════════════════════════════════════╗"
echo "║    Dev Setup App — WSL Docker Builder             ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ─── Check Docker ────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    echo "  ✗ Docker not found in WSL."
    echo ""
    echo "  Install Docker Desktop for Windows, then enable WSL2 integration:"
    echo "  1. Download: https://www.docker.com/products/docker-desktop/"
    echo "  2. Settings → Resources → WSL Integration → Enable your distro"
    echo "  3. Re-open this WSL terminal and run this script again."
    echo ""
    echo "  Alternatively, use the direct WSL build (no Docker):"
    echo "    bash scripts/build/install-build-deps-wsl.sh"
    echo "    bash scripts/build/build-wsl.sh"
    exit 1
fi

echo "  ✓ Docker found: $(docker --version)"

if ! docker info &>/dev/null 2>&1; then
    echo "  ✗ Docker daemon not running. Start Docker Desktop first."
    exit 1
fi
echo "  ✓ Docker daemon running"
echo ""

# ─── Build Docker image ──────────────────────────────────────
echo "==> Building Docker image '$IMAGE'..."
echo "    (Ubuntu 22.04 + Rust + Node + Tauri CLI)"
echo "    First run downloads ~800 MB and compiles Rust — takes 10-20 min"
echo "    Subsequent runs use the layer cache and are much faster"
echo ""

docker build \
    --tag "$IMAGE" \
    --file "$APP_DIR/Dockerfile" \
    "$APP_DIR"

echo ""
echo "  ✓ Docker image built"

# ─── Copy outputs ────────────────────────────────────────────
echo ""
echo "==> Extracting build artifacts..."

BUNDLE_DIR="$APP_DIR/src-tauri/target/release/bundle"
mkdir -p "$BUNDLE_DIR"

# Run the container just long enough to copy outputs back to the host
docker run --rm \
    -v "$APP_DIR:/workspace" \
    "$IMAGE" \
    bash -c "cp -r /app/src-tauri/target/release/bundle/* /workspace/src-tauri/target/release/bundle/ 2>/dev/null || true"

# ─── Report ──────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════"
echo "  ✅ Docker build complete!"
echo ""

APPIMAGE=$(find "$BUNDLE_DIR/appimage" -name "*.AppImage" 2>/dev/null | head -1)
DEB=$(find      "$BUNDLE_DIR/deb"      -name "*.deb"      2>/dev/null | head -1)

if [ -n "$APPIMAGE" ]; then
    echo "  📦 AppImage : $APPIMAGE ($(du -sh "$APPIMAGE" | cut -f1))"
fi
if [ -n "$DEB" ]; then
    echo "  📦 .deb     : $DEB ($(du -sh "$DEB" | cut -f1))"
fi

echo ""
echo "  ℹ To build Windows MSI/EXE push a git tag:"
echo "    git tag v1.0.0 && git push origin v1.0.0"
echo "══════════════════════════════════════════════════"
