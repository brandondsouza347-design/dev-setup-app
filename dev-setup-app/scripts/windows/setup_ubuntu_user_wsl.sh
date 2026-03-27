#!/usr/bin/env bash
# setup_ubuntu_user_wsl.sh — Ensure an 'ubuntu' user exists inside WSL Ubuntu
# Runs via: wsl bash /path/to/setup_ubuntu_user_wsl.sh
set -euo pipefail

TARGET_USER="ubuntu"

echo "==> setup_ubuntu_user_wsl: checking for user '$TARGET_USER'..."

if id "$TARGET_USER" &>/dev/null; then
    echo "✓ User '$TARGET_USER' already exists — skipping"
    id "$TARGET_USER"
    exit 0
fi

echo "  User '$TARGET_USER' not found. Creating..."

# Create user with home directory and bash shell
sudo useradd -m -s /bin/bash "$TARGET_USER"

# Add to sudo group so they can run privileged commands
sudo usermod -aG sudo "$TARGET_USER"

# Set a default password (user should change this)
echo "${TARGET_USER}:ubuntu" | sudo chpasswd

# Add passwordless sudo for convenience in a dev environment
SUDOERS_LINE="$TARGET_USER ALL=(ALL) NOPASSWD:ALL"
SUDOERS_FILE="/etc/sudoers.d/$TARGET_USER"
echo "$SUDOERS_LINE" | sudo tee "$SUDOERS_FILE" > /dev/null
sudo chmod 0440 "$SUDOERS_FILE"

echo "✓ User '$TARGET_USER' created"
echo "  Home : $(eval echo ~$TARGET_USER)"
echo "  Shell: $(getent passwd $TARGET_USER | cut -d: -f7)"
echo "  Groups: $(groups $TARGET_USER)"
echo ""
echo "NOTE: Default password is 'ubuntu' — change it with: passwd ubuntu"
