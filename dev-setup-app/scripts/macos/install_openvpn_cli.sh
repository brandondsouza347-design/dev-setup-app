#!/usr/bin/env bash
# install_openvpn_cli.sh (macOS) — Install command-line OpenVPN via Homebrew
set -euo pipefail

# Ensure Homebrew is in PATH (check both Intel and Apple Silicon locations)
if ! command -v brew &>/dev/null; then
    if [ -x "/usr/local/bin/brew" ]; then
        export PATH="/usr/local/bin:$PATH"
    elif [ -x "/opt/homebrew/bin/brew" ]; then
        export PATH="/opt/homebrew/bin:$PATH"
    else
        echo "✗ Homebrew not found. Please install Homebrew first."
        exit 1
    fi
fi

SKIP_INSTALLED="${SETUP_SKIP_INSTALLED:-true}"

echo "→ Step 1/2: Checking OpenVPN CLI installation..."
if [ "$SKIP_INSTALLED" = "true" ] && brew list openvpn &>/dev/null 2>&1; then
    echo "✓ OpenVPN CLI is already installed — skipping."
elif brew list openvpn &>/dev/null 2>&1; then
    echo "→ OpenVPN CLI already installed but SKIP_INSTALLED=false — reinstalling..."
    brew reinstall openvpn
    echo "✓ OpenVPN CLI reinstalled."
else
    echo "→ Installing OpenVPN CLI via Homebrew..."
    brew install openvpn
    echo "✓ OpenVPN CLI installed."
fi

# Verify installation
echo "→ Verifying OpenVPN installation..."
if command -v openvpn &>/dev/null; then
    OPENVPN_VERSION=$(openvpn --version | head -n1)
    echo "✓ $OPENVPN_VERSION"
else
    echo "✗ OpenVPN command not found in PATH after installation"
    exit 1
fi

# Create config directory
echo "→ Step 2/2: Setting up OpenVPN configuration directory..."
CONFIG_DIR="$HOME/.openvpn"
mkdir -p "$CONFIG_DIR"
echo "✓ Config directory created: $CONFIG_DIR"

# Stage VPN config file
echo "→ Staging VPN config file..."
OVPN_SRC="${SETUP_OPENVPN_CONFIG_PATH:-}"
if [ -n "$OVPN_SRC" ] && [ -f "$OVPN_SRC" ]; then
    LEAF=$(basename "$OVPN_SRC")
    DEST="$CONFIG_DIR/$LEAF"

    if [ -f "$DEST" ]; then
        echo "  VPN config already exists: $DEST"
        echo "  Updating with current selection..."
    fi

    cp "$OVPN_SRC" "$DEST"
    echo "✓ VPN config copied: $OVPN_SRC → $DEST"

    # Store the config path for connect script to use
    echo "$DEST" > "$CONFIG_DIR/.current-config"
else
    echo "⚠ SETUP_OPENVPN_CONFIG_PATH not set or file not found."
    echo "  Source path: '$OVPN_SRC'"
    echo "  Copy your .ovpn file manually to: $CONFIG_DIR/"
fi

echo "✓ OpenVPN CLI installation complete."
echo ""
echo "Note: OpenVPN CLI requires administrator privileges to connect."
echo "You will be prompted for your password when establishing the VPN connection."
