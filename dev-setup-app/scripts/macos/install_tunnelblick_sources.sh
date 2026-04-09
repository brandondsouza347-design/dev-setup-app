#!/usr/bin/env bash
# install_tunnelblick_sources.sh (macOS) — Try multiple download sources for Tunnelblick
set -euo pipefail

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

SKIP_INSTALLED="${SETUP_SKIP_INSTALLED:-true}"

# Check if already installed
echo "→ Checking for existing Tunnelblick installation..."
if [ "$SKIP_INSTALLED" = "true" ] && [ -d "/Applications/Tunnelblick.app" ]; then
    echo "✓ Tunnelblick is already installed — skipping."
    exit 0
fi

echo "→ Attempting Tunnelblick installation from multiple sources..."
echo "  This may take several minutes."
echo ""

# Method 1: Homebrew (fastest, but may be blocked)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Method 1/3: Homebrew Cask"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Ensure Homebrew is in PATH
if ! command -v brew &>/dev/null; then
    if [ -x "/usr/local/bin/brew" ]; then
        export PATH="/usr/local/bin:$PATH"
    elif [ -x "/opt/homebrew/bin/brew" ]; then
        export PATH="/opt/homebrew/bin:$PATH"
    fi
fi

if command -v brew &>/dev/null; then
    echo "→ Attempting installation via Homebrew..."

    if timeout 90 brew install --cask tunnelblick 2>&1; then
        if [ -d "/Applications/Tunnelblick.app" ]; then
            echo "✓ Tunnelblick installed successfully via Homebrew!"
            echo ""
            exec bash "$(dirname "$0")/install_openvpn.sh"
        fi
    fi

    echo "✗ Homebrew installation failed or timed out"
    echo ""
else
    echo "⚠ Homebrew not found — skipping this method"
    echo ""
fi

# Method 2: GitHub Releases (direct download)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Method 2/3: GitHub Releases"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "→ Fetching latest release from GitHub..."

# Get latest release URL
GITHUB_API="https://api.github.com/repos/Tunnelblick/Tunnelblick/releases/latest"
RELEASE_JSON=$(curl -sL --max-time 30 "$GITHUB_API" 2>/dev/null || echo "")

if [ -n "$RELEASE_JSON" ]; then
    # Find the .dmg download URL
    DMG_URL=$(echo "$RELEASE_JSON" | grep -o 'https://github.com/Tunnelblick/Tunnelblick/releases/download/[^"]*\.dmg' | head -n1)

    if [ -n "$DMG_URL" ]; then
        echo "→ Found release: $DMG_URL"
        echo "→ Downloading DMG..."

        DMG_FILE="$TEMP_DIR/Tunnelblick.dmg"
        if curl -L --max-time 180 -o "$DMG_FILE" "$DMG_URL" 2>&1; then
            if [ -f "$DMG_FILE" ] && [ -s "$DMG_FILE" ]; then
                echo "✓ Download complete"
                echo "→ Installing from DMG..."

                # Use the manual install script
                export SETUP_TUNNELBLICK_INSTALLER_PATH="$DMG_FILE"
                if bash "$(dirname "$0")/install_tunnelblick_manual.sh"; then
                    echo "✓ Tunnelblick installed successfully from GitHub!"
                    exit 0
                else
                    echo "✗ Installation from GitHub DMG failed"
                fi
            else
                echo "✗ Downloaded file is empty or missing"
            fi
        else
            echo "✗ Download failed or timed out"
        fi
    else
        echo "✗ Could not find DMG in latest release"
    fi
else
    echo "✗ Could not fetch release information from GitHub"
fi

echo ""

# Method 3: SourceForge (alternative mirror)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Method 3/3: SourceForge Mirror"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "→ Attempting download from SourceForge..."

# SourceForge uses redirects, let curl follow them
SF_URL="https://sourceforge.net/projects/tunnelblick/files/latest/download"
DMG_FILE="$TEMP_DIR/Tunnelblick-SF.dmg"

if curl -L --max-time 180 -o "$DMG_FILE" "$SF_URL" 2>&1; then
    if [ -f "$DMG_FILE" ] && [ -s "$DMG_FILE" ]; then
        echo "✓ Download complete"
        echo "→ Installing from DMG..."

        export SETUP_TUNNELBLICK_INSTALLER_PATH="$DMG_FILE"
        if bash "$(dirname "$0")/install_tunnelblick_manual.sh"; then
            echo "✓ Tunnelblick installed successfully from SourceForge!"
            exit 0
        else
            echo "✗ Installation from SourceForge DMG failed"
        fi
    else
        echo "✗ Downloaded file is empty or missing"
    fi
else
    echo "✗ Download failed or timed out"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✗ All installation methods failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Possible solutions:"
echo "  1. Download Tunnelblick manually from https://tunnelblick.net"
echo "  2. Use 'Install from File' option in the app"
echo "  3. Use OpenVPN CLI as alternative (automatic fallback)"
echo ""
exit 1
