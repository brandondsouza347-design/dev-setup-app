#!/usr/bin/env bash
# setup_ubuntu_user_wsl.sh — Ensure an 'ubuntu' user exists inside WSL Ubuntu
# Runs via: wsl bash /path/to/setup_ubuntu_user_wsl.sh
set -euo pipefail

TARGET_USER="ubuntu"

echo "==> setup_ubuntu_user_wsl: checking for user '$TARGET_USER'..."

if id "$TARGET_USER" &>/dev/null; then
    echo "✓ User '$TARGET_USER' already exists"
    id "$TARGET_USER"
else
    echo "  User '$TARGET_USER' not found. Creating..."

    # Create user with home directory and bash shell
    sudo useradd -m -s /bin/bash "$TARGET_USER"

    # Add to sudo group so they can run privileged commands
    sudo usermod -aG sudo "$TARGET_USER"

    # Set a default password (user should change this)
    echo "${TARGET_USER}:ubuntu" | sudo chpasswd

    echo "✓ User '$TARGET_USER' created"
    echo "  Home : $(eval echo ~$TARGET_USER)"
    echo "  Shell: $(getent passwd $TARGET_USER | cut -d: -f7)"
    echo "  Groups: $(groups $TARGET_USER)"
    echo ""
    echo "NOTE: Default password is 'ubuntu' — change it with: passwd ubuntu"
fi

# ─── Always ensure passwordless sudo is configured ───────────────────────────
# This must run even when the user already existed in the tar image, because
# the tar may not have a NOPASSWD sudoers entry. Without this, every subsequent
# script that calls sudo from the non-TTY Tauri process will fail with
# "sudo: a password is required".
SUDOERS_FILE="/etc/sudoers.d/${TARGET_USER}-nopasswd"

if [ ! -f "$SUDOERS_FILE" ] || ! grep -q "NOPASSWD" "$SUDOERS_FILE" 2>/dev/null; then
    echo "  Configuring passwordless sudo for '$TARGET_USER'..."
    # !requiretty allows sudo to work in non-TTY contexts (Tauri app processes)
    _content="$(printf 'Defaults:%s !requiretty\n%s ALL=(ALL) NOPASSWD:ALL\n' "$TARGET_USER" "$TARGET_USER")"
    if [ "$(id -u)" = "0" ]; then
        # Running as root — write directly, no sudo needed
        printf '%s\n' "$_content" > "$SUDOERS_FILE"
        chmod 0440 "$SUDOERS_FILE"
    else
        printf '%s\n' "$_content" | sudo tee "$SUDOERS_FILE" > /dev/null
        sudo chmod 0440 "$SUDOERS_FILE"
    fi
    echo "✓ Passwordless sudo configured at $SUDOERS_FILE"
else
    echo "✓ Passwordless sudo already configured at $SUDOERS_FILE"
fi

# ─── Set ubuntu as the permanent WSL default user ────────────────────────────
# /etc/wsl.conf persists across WSL restarts and ensures every subsequent
# `wsl -d ERC` session (without an explicit -u flag) runs as ubuntu, not root.
WSL_CONF="/etc/wsl.conf"
if grep -q "^\[user\]" "$WSL_CONF" 2>/dev/null; then
    echo "✓ /etc/wsl.conf already has [user] section"
else
    echo "  Setting default WSL user to '$TARGET_USER' in $WSL_CONF..."
    if [ "$(id -u)" = "0" ]; then
        printf '\n[user]\ndefault=%s\n' "$TARGET_USER" >> "$WSL_CONF"
    else
        printf '\n[user]\ndefault=%s\n' "$TARGET_USER" | sudo tee -a "$WSL_CONF" > /dev/null
    fi
    echo "✓ Default WSL user set to '$TARGET_USER'"
fi

echo "✓ Setup complete — subsequent WSL sessions will run as '$TARGET_USER'"
