#!/usr/bin/env bash
# install_tunnelblick_manual.sh (macOS) — Install Tunnelblick from local .dmg or .pkg file
set -euo pipefail

INSTALLER_PATH="${SETUP_TUNNELBLICK_INSTALLER_PATH:-}"

if [ -z "$INSTALLER_PATH" ] || [ ! -f "$INSTALLER_PATH" ]; then
    echo "✗ Error: SETUP_TUNNELBLICK_INSTALLER_PATH not set or file not found"
    echo "  Path provided: '$INSTALLER_PATH'"
    exit 1
fi

echo "→ Installing Tunnelblick from local file: $INSTALLER_PATH"

# Detect file type
FILE_EXT=$(echo "$INSTALLER_PATH" | awk -F . '{print tolower($NF)}')

case "$FILE_EXT" in
    dmg)
        echo "→ Step 1/3: Mounting DMG..."
        # Mount the DMG and capture the mount point
        MOUNT_OUTPUT=$(hdiutil attach "$INSTALLER_PATH" -nobrowse -noverify)
        MOUNT_POINT=$(echo "$MOUNT_OUTPUT" | grep "Volumes" | awk '{print $3}')

        if [ -z "$MOUNT_POINT" ]; then
            echo "✗ Failed to determine mount point"
            exit 1
        fi

        echo "✓ DMG mounted at: $MOUNT_POINT"

        # Find the .app bundle
        echo "→ Step 2/3: Locating Tunnelblick.app..."
        APP_PATH=$(find "$MOUNT_POINT" -name "Tunnelblick.app" -maxdepth 2 -print -quit)

        if [ -z "$APP_PATH" ]; then
            echo "✗ Tunnelblick.app not found in DMG"
            hdiutil detach "$MOUNT_POINT" -quiet || true
            exit 1
        fi

        echo "✓ Found: $APP_PATH"

        # Copy to Applications
        echo "→ Step 3/3: Installing to /Applications..."
        if [ -d "/Applications/Tunnelblick.app" ]; then
            echo "  Removing existing Tunnelblick installation..."
            rm -rf "/Applications/Tunnelblick.app"
        fi

        cp -R "$APP_PATH" /Applications/
        echo "✓ Tunnelblick installed to /Applications/"

        # Unmount DMG
        echo "→ Unmounting DMG..."
        hdiutil detach "$MOUNT_POINT" -quiet || true
        echo "✓ DMG unmounted"
        ;;

    pkg)
        echo "→ Installing PKG file..."
        echo "  This requires administrator privileges."

        # Install the PKG (requires sudo)
        sudo installer -pkg "$INSTALLER_PATH" -target / -verbose

        if [ $? -eq 0 ]; then
            echo "✓ PKG installation completed"
        else
            echo "✗ PKG installation failed"
            exit 1
        fi
        ;;

    *)
        echo "✗ Unsupported file format: .$FILE_EXT"
        echo "  Supported formats: .dmg, .pkg"
        exit 1
        ;;
esac

# Verify installation
echo "→ Verifying installation..."
if [ -d "/Applications/Tunnelblick.app" ]; then
    echo "✓ Tunnelblick.app found in /Applications"
else
    echo "✗ Installation verification failed — Tunnelblick.app not found"
    exit 1
fi

# Stage VPN config file
echo "→ Staging VPN config file..."
OVPN_SRC="${SETUP_OPENVPN_CONFIG_PATH:-}"
if [ -n "$OVPN_SRC" ] && [ -f "$OVPN_SRC" ]; then
    CONFIGS_DIR="$HOME/Library/Application Support/Tunnelblick/Configurations"
    mkdir -p "$CONFIGS_DIR"
    LEAF=$(basename "$OVPN_SRC")
    DEST="$CONFIGS_DIR/$LEAF"

    if [ -f "$DEST" ]; then
        echo "  VPN config already exists: $DEST"
        echo "  Updating with current selection..."
    fi

    cp "$OVPN_SRC" "$DEST"
    echo "✓ VPN config copied: $OVPN_SRC → $DEST"
else
    echo "⚠ SETUP_OPENVPN_CONFIG_PATH not set or file not found."
    echo "  Copy your .ovpn file manually to:"
    echo "  $HOME/Library/Application Support/Tunnelblick/Configurations/"
fi

echo "✓ Manual Tunnelblick installation complete."
