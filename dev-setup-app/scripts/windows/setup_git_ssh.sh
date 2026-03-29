#!/usr/bin/env bash
# setup_git_ssh.sh — Configure Git identity and SSH keys inside WSL Ubuntu
# Runs via: wsl -d ERC bash /path/to/setup_git_ssh.sh
set -euo pipefail

GIT_NAME="${SETUP_GIT_NAME:-}"
GIT_EMAIL="${SETUP_GIT_EMAIL:-}"
SHELL_RC="$HOME/.bashrc"

echo "==> Git & SSH Configuration"

# ─── 1. Ensure Git is installed ──────────────────────────────────────────────
echo ""
echo "==> Step 1: Ensuring Git is installed..."
if command -v git >/dev/null 2>&1; then
    echo "Step 1 complete - Git already installed: $(git --version)"
else
    sudo apt-get update -q
    sudo apt-get install -y -q git
    echo "Step 1 complete - Git installed: $(git --version)"
fi

# ─── 2. Configure Git identity ───────────────────────────────────────────────
echo ""
echo "==> Step 2: Configuring Git identity..."

EXISTING_NAME="$(git config --global user.name 2>/dev/null || true)"
EXISTING_EMAIL="$(git config --global user.email 2>/dev/null || true)"

if [ -n "$EXISTING_NAME" ] && [ -n "$EXISTING_EMAIL" ]; then
    echo "Step 2 complete - Git identity already set:"
    echo "   Name : $EXISTING_NAME"
    echo "   Email: $EXISTING_EMAIL"
elif [ -n "$GIT_NAME" ] && [ -n "$GIT_EMAIL" ]; then
    git config --global user.name  "$GIT_NAME"
    git config --global user.email "$GIT_EMAIL"
    git config --global core.autocrlf input
    git config --global core.eol lf
    git config --global init.defaultBranch main
    git config --global pull.rebase false
    echo "Step 2 complete - Git identity configured: $GIT_NAME ($GIT_EMAIL)"
else
    git config --global core.autocrlf input
    git config --global core.eol lf
    git config --global init.defaultBranch main
    git config --global pull.rebase false
    echo "Step 2: No name/email provided - core settings applied, identity skipped."
    echo "  Set manually inside WSL: git config --global user.name 'Your Name'"
    echo "  Set manually inside WSL: git config --global user.email 'you@example.com'"
fi

# ─── 3. Generate SSH key ──────────────────────────────────────────────────────
echo ""
echo "==> Step 3: Setting up SSH key..."

SSH_DIR="$HOME/.ssh"
KEY_FILE="$SSH_DIR/id_ed25519"
SSH_EMAIL="${GIT_EMAIL:-$(git config --global user.email 2>/dev/null || echo dev@setup)}"

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

if [ -f "$KEY_FILE" ]; then
    echo "Step 3 complete - SSH key already exists: $KEY_FILE"
else
    ssh-keygen -t ed25519 -C "$SSH_EMAIL" -f "$KEY_FILE" -N ""
    echo "Step 3 complete - SSH key generated: $KEY_FILE"
fi

echo ""
echo "==> Your public SSH key (add this to GitHub / Bitbucket):"
echo "------------------------------------------------------------"
cat "$KEY_FILE.pub"
echo "------------------------------------------------------------"

# ─── 4. SSH agent auto-start in ~/.bashrc ────────────────────────────────────
echo ""
echo "==> Step 4: Configuring SSH agent auto-start in ~/.bashrc..."

MARKER="# SSH agent auto-start"
if ! grep -qF "$MARKER" "$SHELL_RC" 2>/dev/null; then
    printf '\n# SSH agent auto-start\n' >> "$SHELL_RC"
    printf 'if [ -z "$SSH_AUTH_SOCK" ]; then\n' >> "$SHELL_RC"
    printf '    eval "$(ssh-agent -s)" > /dev/null 2>&1\n' >> "$SHELL_RC"
    printf '    ssh-add ~/.ssh/id_ed25519 2>/dev/null || true\n' >> "$SHELL_RC"
    printf 'fi\n' >> "$SHELL_RC"
    echo "Step 4 complete - SSH agent auto-start added to $SHELL_RC"
else
    echo "Step 4 complete - SSH agent auto-start already present in $SHELL_RC"
fi

# ─── 5. Test GitHub connectivity ─────────────────────────────────────────────
echo ""
echo "==> Step 5: Testing SSH connectivity to GitHub..."
ssh_result="$(ssh -T git@github.com -o StrictHostKeyChecking=no 2>&1 || true)"
if echo "$ssh_result" | grep -q "successfully authenticated"; then
    echo "Step 5 complete - GitHub SSH authentication successful!"
else
    echo "Step 5: GitHub SSH not yet configured (expected until you add the key)."
    echo "  1. Copy the public key printed above"
    echo "  2. Go to: https://github.com/settings/ssh/new"
    echo "  3. Paste and save, then test: ssh -T git@github.com"
fi

echo ""
echo "Git and SSH setup complete!"
echo ""
echo "  Git config:"
git config --global --list 2>/dev/null | sed 's/^/    /' || echo "    (none set)"
echo ""
echo "  SSH key: $KEY_FILE.pub"