#!/usr/bin/env bash
# install_xcode_clt.sh — Install Xcode Command Line Tools (required for compiling software on macOS)
set -euo pipefail

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║      Xcode Command Line Tools Installation               ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "[1/4] Checking current installation status..."

if xcode-select -p &>/dev/null; then
    INSTALL_PATH=$(xcode-select -p)
    echo "✓ Xcode Command Line Tools already installed"
    echo "  Location: $INSTALL_PATH"
    echo "  Version: $(xcode-select --version)"
    exit 0
fi

echo "✗ Xcode Command Line Tools not found"
echo ""
echo "[2/4] Preparing installation..."
echo "  This process will:"
echo "    • Download ~500MB of development tools"
echo "    • Install compilers (clang, gcc)"
echo "    • Install SDK headers and libraries"
echo "    • Take approximately 5-15 minutes"
echo ""

# Trigger the install dialog or use the non-interactive approach
echo "[3/4] Querying macOS Software Update catalog..."
touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress

echo "  → Fetching available Command Line Tools packages..."
PROD=$(softwareupdate -l 2>/dev/null \
  | grep "\*.*Command Line" \
  | tail -1 \
  | sed 's/^[^:]*: //' \
  | tr -d '\n')

if [ -z "$PROD" ]; then
    echo ""
    echo "⚠ Could not find CLT in Software Update catalog"
    echo "  Falling back to interactive GUI installer..."
    echo ""
    echo "ACTION REQUIRED:"
    echo "  1. A system dialog should appear asking to install"
    echo "  2. Click 'Install' in the dialog"
    echo "  3. Enter your admin password when prompted"
    echo "  4. Wait for installation to complete (~10-15 min)"
    echo "  5. Return to Dev_Setup and re-run prerequisite checks"
    echo ""
    xcode-select --install 2>&1 || echo "  Dialog triggered (if one appeared, proceed with installation)"
    exit 1
fi

echo "  ✓ Found package: $PROD"
echo ""
echo "[4/4] Installing Xcode Command Line Tools..."
echo "  This will download and install the package"
echo "  Progress updates may be delayed - please be patient"
echo ""
softwareupdate -i "$PROD" --verbose 2>&1

rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "✓ Xcode Command Line Tools installed successfully!"
echo "  Location: $(xcode-select -p 2>/dev/null || echo '/Library/Developer/CommandLineTools')"
echo "  Compiler: $(gcc --version 2>/dev/null | head -1 || echo 'Available')"
echo "═══════════════════════════════════════════════════════════"
