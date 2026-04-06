#!/usr/bin/env bash
# setup_nvm_wsl.sh — Install NVM v0.40.1 and Node.js v22.10.0 inside WSL Ubuntu
# Runs via: wsl bash /path/to/setup_nvm_wsl.sh
set -euo pipefail

NODE_VERSION="${SETUP_NODE_VERSION:-22.10.0}"
NVM_VERSION="0.40.1"
SKIP_INSTALLED="${SETUP_SKIP_INSTALLED:-true}"
SHELL_RC="$HOME/.bashrc"

echo "==> setup_nvm_wsl: NVM=$NVM_VERSION  Node=$NODE_VERSION"

# ─── Helper: idempotent line append ─────────────────────────────────────────
add_to_bashrc() {
    local content="$1"
    local marker="$2"
    if ! grep -qF "$marker" "$SHELL_RC" 2>/dev/null; then
        echo "" >> "$SHELL_RC"
        echo "# $marker" >> "$SHELL_RC"
        printf '%s\n' "$content" >> "$SHELL_RC"
        echo "  Added NVM config to $SHELL_RC"
    else
        echo "  NVM config already in $SHELL_RC"
    fi
}

# ─── 1. Install NVM ─────────────────────────────────────────────────────────
echo "==> Step 1: Installing NVM v$NVM_VERSION..."
export NVM_DIR="$HOME/.nvm"

if [ "$SKIP_INSTALLED" = "true" ] && [ -s "$NVM_DIR/nvm.sh" ]; then
    source "$NVM_DIR/nvm.sh"
    INSTALLED_NVM="$(nvm --version 2>/dev/null || echo '0')"
    if [ "$INSTALLED_NVM" = "$NVM_VERSION" ]; then
        echo "✓ NVM v$NVM_VERSION already installed — skipping"
    else
        echo "  Upgrading NVM from v$INSTALLED_NVM to v$NVM_VERSION..."
        # GIT_SSL_NO_VERIFY bypasses corporate CA for git operations inside install.sh
        export GIT_SSL_NO_VERIFY=1
        curl -fsSL --insecure "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" | bash
        source "$NVM_DIR/nvm.sh"
        echo "✓ NVM upgraded to v$NVM_VERSION"
    fi
elif [ -s "$NVM_DIR/nvm.sh" ]; then
    echo "→ NVM already installed but SKIP_INSTALLED=false — reinstalling..."
    source "$NVM_DIR/nvm.sh"
    export GIT_SSL_NO_VERIFY=1
    curl -fsSL --insecure "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" | bash
    source "$NVM_DIR/nvm.sh"
    echo "✓ NVM reinstalled to v$NVM_VERSION"
else
    echo "  Downloading and installing NVM v$NVM_VERSION..."
    export GIT_SSL_NO_VERIFY=1
    curl -fsSL --insecure "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" | bash
    source "$NVM_DIR/nvm.sh"
    echo "✓ NVM v$NVM_VERSION installed"
fi

# ─── 2. Shell integration ───────────────────────────────────────────────────
echo "==> Step 2: Configuring NVM in $SHELL_RC..."
NVM_BLOCK='export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"'

add_to_bashrc "$NVM_BLOCK" "NVM_DIR nvm.sh"
echo "✓ NVM shell integration configured"

# ─── 3. Install Node.js ─────────────────────────────────────────────────────
echo "==> Step 3: Installing Node.js v$NODE_VERSION..."
if [ "$SKIP_INSTALLED" = "true" ] && nvm ls "$NODE_VERSION" 2>/dev/null | grep -q "$NODE_VERSION"; then
    echo "✓ Node v$NODE_VERSION already installed — skipping"
elif nvm ls "$NODE_VERSION" 2>/dev/null | grep -q "$NODE_VERSION"; then
    echo "→ Node v$NODE_VERSION already installed but SKIP_INSTALLED=false — reinstalling..."
    nvm install "$NODE_VERSION"
    echo "✓ Node v$NODE_VERSION reinstalled"
else
    nvm install "$NODE_VERSION"
    echo "✓ Node v$NODE_VERSION installed"
fi

# ─── 4. Set as default ──────────────────────────────────────────────────────
echo "==> Step 4: Setting Node v$NODE_VERSION as default..."
nvm use "$NODE_VERSION"
nvm alias default "$NODE_VERSION"
echo "✓ Node v$NODE_VERSION set as default"

# ─── 5. Verify ──────────────────────────────────────────────────────────────
echo "==> Step 5: Verification..."
echo "  nvm --version : $(nvm --version)"
echo "  node -v       : $(node -v)"
echo "  npm --version : $(npm --version)"
echo ""
echo "✓ NVM v$NVM_VERSION + Node v$NODE_VERSION setup complete"
echo "NOTE: Restart WSL or run: source ~/.bashrc"
