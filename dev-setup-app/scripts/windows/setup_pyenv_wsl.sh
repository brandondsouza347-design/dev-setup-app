#!/usr/bin/env bash
# setup_pyenv_wsl.sh — Install pyenv, Python 3.9.21, and create erc virtualenv inside WSL Ubuntu
# Runs via: wsl bash /path/to/setup_pyenv_wsl.sh
set -euo pipefail

PYTHON_VERSION="${SETUP_PYTHON_VERSION:-3.9.21}"
VENV_NAME="${SETUP_VENV_NAME:-erc}"
SKIP_INSTALLED="${SETUP_SKIP_INSTALLED:-true}"
SHELL_RC="$HOME/.bashrc"

echo "==> setup_pyenv_wsl: Python=$PYTHON_VERSION  venv=$VENV_NAME"

# ─── Helper: idempotent line append ─────────────────────────────────────────
add_to_bashrc() {
    local line="$1"
    local marker="$2"
    if ! grep -qF "$marker" "$SHELL_RC" 2>/dev/null; then
        echo "" >> "$SHELL_RC"
        echo "# $marker" >> "$SHELL_RC"
        echo "$line" >> "$SHELL_RC"
        echo "  Added to $SHELL_RC: $line"
    else
        echo "  Already present in $SHELL_RC: $marker"
    fi
}

# ─── 1. System build deps ────────────────────────────────────────────────────
echo "==> Step 1: Installing build dependencies..."
sudo apt-get update -q
sudo apt-get install -y -q \
    build-essential libssl-dev zlib1g-dev libbz2-dev \
    libreadline-dev libsqlite3-dev curl libncursesw5-dev \
    xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev git
echo "✓ Build dependencies installed"

# ─── 2. Install pyenv ───────────────────────────────────────────────────────
echo "==> Step 2: Installing pyenv via curl..."
if command -v pyenv &>/dev/null && [ -d "$HOME/.pyenv" ]; then
    echo "✓ pyenv already installed: $(pyenv --version)"
else
    curl -fsSL https://pyenv.run | bash
    echo "✓ pyenv installed"
fi

# ─── 3. Shell integration ───────────────────────────────────────────────────
echo "==> Step 3: Configuring pyenv in $SHELL_RC..."
add_to_bashrc 'export PYENV_ROOT="$HOME/.pyenv"'           "pyenv PYENV_ROOT"
add_to_bashrc 'export PATH="$PYENV_ROOT/bin:$PATH"'        "pyenv PATH"
add_to_bashrc 'eval "$(pyenv init --path)"'                "pyenv init --path"
add_to_bashrc 'eval "$(pyenv init -)"'                     "pyenv init -"
add_to_bashrc 'eval "$(pyenv virtualenv-init -)"'          "pyenv virtualenv-init"

# Activate for this session
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init --path)" 2>/dev/null || true
eval "$(pyenv init -)"       2>/dev/null || true
eval "$(pyenv virtualenv-init -)" 2>/dev/null || true
echo "✓ pyenv shell integration configured"

# ─── 4. Install Python ──────────────────────────────────────────────────────
echo "==> Step 4: Installing Python $PYTHON_VERSION..."
if pyenv versions --bare 2>/dev/null | grep -qx "$PYTHON_VERSION"; then
    echo "✓ Python $PYTHON_VERSION already installed"
else
    pyenv install "$PYTHON_VERSION"
    echo "✓ Python $PYTHON_VERSION installed"
fi

# ─── 5. Create virtualenv ───────────────────────────────────────────────────
echo "==> Step 5: Creating virtualenv '$VENV_NAME'..."
if pyenv virtualenvs --bare 2>/dev/null | grep -qx "$VENV_NAME"; then
    if [ "$SKIP_INSTALLED" = "true" ]; then
        echo "✓ Virtualenv '$VENV_NAME' already exists — skipping"
    else
        pyenv virtualenv-delete -f "$VENV_NAME" && pyenv virtualenv "$PYTHON_VERSION" "$VENV_NAME"
        echo "✓ Virtualenv '$VENV_NAME' recreated"
    fi
else
    pyenv virtualenv "$PYTHON_VERSION" "$VENV_NAME"
    echo "✓ Virtualenv '$VENV_NAME' created"
fi

# ─── 6. Verify ──────────────────────────────────────────────────────────────
echo "==> Step 6: Verification..."
PYENV_VERSION="$VENV_NAME" python --version
PYENV_VERSION="$VENV_NAME" which python
echo ""
echo "✓ pyenv + Python $PYTHON_VERSION + venv '$VENV_NAME' setup complete"
echo "NOTE: Restart WSL or run: source ~/.bashrc"
