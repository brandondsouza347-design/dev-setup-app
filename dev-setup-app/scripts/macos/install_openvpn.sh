#!/usr/bin/env bash
# install_openvpn.sh (macOS) — Install Tunnelblick and stage the .ovpn config
set -euo pipefail

echo "→ Step 1/2: Checking Tunnelblick installation..."
if brew list --cask tunnelblick &>/dev/null 2>&1; then
    echo "✓ Tunnelblick is already installed — skipping."
else
    echo "→ Installing Tunnelblick via Homebrew..."
    brew install --cask tunnelblick
    echo "✓ Tunnelblick installed."
fi

echo "→ Step 2/2: Staging VPN config file..."
OVPN_SRC="${SETUP_OPENVPN_CONFIG_PATH:-}"
if [ -n "$OVPN_SRC" ] && [ -f "$OVPN_SRC" ]; then
    CONFIGS_DIR="$HOME/Library/Application Support/Tunnelblick/Configurations"
    mkdir -p "$CONFIGS_DIR"
    LEAF=$(basename "$OVPN_SRC")
    DEST="$CONFIGS_DIR/$LEAF"
    if [ -f "$DEST" ]; then
        echo "✓ VPN config already in place: $DEST"
    else
        cp "$OVPN_SRC" "$DEST"
        echo "✓ VPN config copied: $OVPN_SRC → $DEST"
    fi
else
    echo "⚠ SETUP_OPENVPN_CONFIG_PATH not set or file not found."
    echo "  Copy your .ovpn file manually to:"
    echo "  $HOME/Library/Application Support/Tunnelblick/Configurations/"
fi

echo "✓ install_openvpn complete."
