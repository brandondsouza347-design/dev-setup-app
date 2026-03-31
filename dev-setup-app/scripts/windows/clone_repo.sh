#!/usr/bin/env bash
# clone_repo.sh — Clone or update the ERC repository in WSL
set -euo pipefail

REPO_URL="${SETUP_GITLAB_REPO_URL:-git@gitlab.toogoerp.net:root/erc.git}"
CLONE_DIR="${SETUP_CLONE_DIR:-/home/ubuntu/VsCodeProjects/erc}"

echo "→ Repository: $REPO_URL"
echo "→ Destination: $CLONE_DIR"

mkdir -p "$(dirname "$CLONE_DIR")"

if [ -d "$CLONE_DIR/.git" ]; then
    echo "✓ Repository already cloned at $CLONE_DIR"
    echo "→ Running git pull to update..."
    git -C "$CLONE_DIR" pull --ff-only 2>&1 || {
        echo "⚠ git pull failed (possible local changes or non-fast-forward). Leaving repo as-is."
    }
    echo "✓ Repository is up to date."
else
    echo "→ Cloning repository..."
    git clone "$REPO_URL" "$CLONE_DIR"
    echo "✓ Repository cloned successfully to $CLONE_DIR"
fi
