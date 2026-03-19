#!/usr/bin/env bash
# setup_nvm.sh — Install NVM, Node 16.20.2, and Gulp
set -euo pipefail

NODE_VERSION="${SETUP_NODE_VERSION:-16.20.2}"
NVM_VERSION="0.39.7"

# ─── Helpers ────────────────────────────────────────────────────────────────

add_to_zshrc() {
    local block_start="$1"
    local block_end="$2"
    local content="$3"
    local marker="$4"

    if ! grep -qF "$marker" ~/.zshrc 2>/dev/null; then
        echo "" >> ~/.zshrc
        echo "# $marker" >> ~/.zshrc
        printf '%s\n' "$content" >> ~/.zshrc
        echo "  Added NVM config to ~/.zshrc"
    else
        echo "  NVM config already in ~/.zshrc"
    fi
}

# ─── 1. Install NVM ─────────────────────────────────────────────────────────

echo "==> Step 1: Installing NVM v$NVM_VERSION..."

export NVM_DIR="$HOME/.nvm"

if [ -s "$NVM_DIR/nvm.sh" ]; then
    echo "✓ NVM already installed"
    source "$NVM_DIR/nvm.sh"
else
    echo "   Downloading and installing NVM..."
    curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" | bash
    source "$NVM_DIR/nvm.sh"
    echo "✓ NVM installed"
fi

# ─── 2. Configure NVM in ~/.zshrc ──────────────────────────────────────────

echo "==> Step 2: Configuring NVM in shell..."

NVM_ZSHRC_BLOCK='export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"'

add_to_zshrc "" "" "$NVM_ZSHRC_BLOCK" "NVM_DIR nvm.sh"

# ─── 3. Install Node.js ─────────────────────────────────────────────────────

echo "==> Step 3: Installing Node.js $NODE_VERSION..."

if nvm ls "$NODE_VERSION" 2>/dev/null | grep -q "$NODE_VERSION"; then
    echo "✓ Node $NODE_VERSION already installed"
else
    nvm install "$NODE_VERSION"
    echo "✓ Node $NODE_VERSION installed"
fi

nvm use "$NODE_VERSION"
nvm alias default "$NODE_VERSION"

echo "   Node version : $(node -v)"
echo "   NPM version  : $(npm -v)"

# ─── 4. Install / upgrade Gulp ──────────────────────────────────────────────

echo "==> Step 4: Installing Gulp CLI and Gulp 4..."

# Remove old gulp if present
npm rm --global gulp-cli gulp 2>/dev/null || true

npm install --global gulp-cli gulp@4.0.2

echo "✓ Gulp installed:"
gulp --version 2>/dev/null || echo "   (gulp available after shell restart)"

echo ""
echo "✓ NVM + Node setup complete!"
echo "  Node    : $(node -v)"
echo "  NPM     : $(npm -v)"
echo "  Default : $NODE_VERSION"
echo ""
echo "NOTE: Restart your terminal or run: source ~/.zshrc"
