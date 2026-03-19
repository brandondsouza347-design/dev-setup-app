#!/usr/bin/env bash
# setup_pyenv.sh — Install pyenv, pyenv-virtualenv, Python 3.9.21, and create virtualenv
set -euo pipefail

PYTHON_VERSION="${SETUP_PYTHON_VERSION:-3.9.21}"
VENV_NAME="${SETUP_VENV_NAME:-erc}"
SKIP_INSTALLED="${SETUP_SKIP_INSTALLED:-true}"

# ─── Helpers ────────────────────────────────────────────────────────────────

add_to_zshrc() {
    local line="$1"
    local marker="$2"
    if ! grep -qF "$marker" ~/.zshrc 2>/dev/null; then
        echo "" >> ~/.zshrc
        echo "# $marker" >> ~/.zshrc
        echo "$line" >> ~/.zshrc
        echo "  Added to ~/.zshrc: $line"
    else
        echo "  Already present in ~/.zshrc: $marker"
    fi
}

# ─── 1. Install pyenv ───────────────────────────────────────────────────────

echo "==> Step 1: Installing pyenv..."

if command -v pyenv &>/dev/null; then
    echo "✓ pyenv already installed: $(pyenv --version)"
else
    if command -v brew &>/dev/null; then
        echo "   Installing pyenv via Homebrew..."
        brew install pyenv
    else
        echo "   Installing pyenv via git clone..."
        git clone https://github.com/pyenv/pyenv.git ~/.pyenv
        (cd ~/.pyenv && src/configure && make -C src) 2>/dev/null || true
    fi
    echo "✓ pyenv installed"
fi

# ─── 2. Configure pyenv in shell ────────────────────────────────────────────

echo "==> Step 2: Configuring pyenv shell integration..."

add_to_zshrc 'export PYENV_ROOT="$HOME/.pyenv"' "pyenv PYENV_ROOT"
add_to_zshrc 'export PATH="$PYENV_ROOT/bin:$PATH"' "pyenv PATH"
add_to_zshrc 'eval "$(pyenv init --path)"' "pyenv init --path"
add_to_zshrc 'eval "$(pyenv init -)"' "pyenv init -"

export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init --path)" 2>/dev/null || true
eval "$(pyenv init -)" 2>/dev/null || true

echo "✓ pyenv shell integration configured"

# ─── 3. Install pyenv-virtualenv ────────────────────────────────────────────

echo "==> Step 3: Installing pyenv-virtualenv..."

if pyenv commands 2>/dev/null | grep -q "virtualenv"; then
    echo "✓ pyenv-virtualenv already available"
else
    if command -v brew &>/dev/null; then
        brew install pyenv-virtualenv
    else
        git clone https://github.com/pyenv/pyenv-virtualenv.git \
            "$HOME/.pyenv/plugins/pyenv-virtualenv"
    fi
    echo "✓ pyenv-virtualenv installed"
fi

add_to_zshrc 'eval "$(pyenv virtualenv-init -)"' "pyenv virtualenv-init"
eval "$(pyenv virtualenv-init -)" 2>/dev/null || true

# ─── 4. Install required Python build dependencies ──────────────────────────

echo "==> Step 4: Installing Python build dependencies via Homebrew..."
brew install openssl readline sqlite3 xz zlib tcl-tk 2>/dev/null || true

# Export build flags for Apple Silicon / user-space brew
BREW_PREFIX="$(brew --prefix 2>/dev/null || echo /opt/homebrew)"
export LDFLAGS="-L$BREW_PREFIX/opt/openssl/lib -L$BREW_PREFIX/opt/readline/lib -L$BREW_PREFIX/opt/sqlite/lib -L$BREW_PREFIX/opt/zlib/lib"
export CPPFLAGS="-I$BREW_PREFIX/opt/openssl/include -I$BREW_PREFIX/opt/readline/include -I$BREW_PREFIX/opt/sqlite/include -I$BREW_PREFIX/opt/zlib/include"
export PKG_CONFIG_PATH="$BREW_PREFIX/opt/openssl/lib/pkgconfig:$BREW_PREFIX/opt/readline/lib/pkgconfig:$BREW_PREFIX/opt/sqlite/lib/pkgconfig"

# ─── 5. Install Python version ──────────────────────────────────────────────

echo "==> Step 5: Installing Python $PYTHON_VERSION via pyenv..."

if pyenv versions --bare 2>/dev/null | grep -q "^${PYTHON_VERSION}$"; then
    echo "✓ Python $PYTHON_VERSION already installed"
else
    echo "   This may take 5–10 minutes (compiling from source)..."
    pyenv install "$PYTHON_VERSION"
    echo "✓ Python $PYTHON_VERSION installed"
fi

# ─── 6. Create virtualenv ───────────────────────────────────────────────────

echo "==> Step 6: Creating virtualenv '$VENV_NAME' using Python $PYTHON_VERSION..."

if pyenv versions --bare 2>/dev/null | grep -q "^${VENV_NAME}$"; then
    echo "✓ Virtualenv '$VENV_NAME' already exists"
else
    pyenv virtualenv "$PYTHON_VERSION" "$VENV_NAME"
    echo "✓ Virtualenv '$VENV_NAME' created"
fi

# ─── 7. Verify ──────────────────────────────────────────────────────────────

echo "==> Verifying..."
pyenv activate "$VENV_NAME" 2>/dev/null || true
ACTIVE_PYTHON=$(python --version 2>&1 || echo "not active")
echo "   Active Python: $ACTIVE_PYTHON"
pyenv deactivate 2>/dev/null || true

echo ""
echo "✓ pyenv setup complete!"
echo "  Python version : $PYTHON_VERSION"
echo "  Virtualenv     : $VENV_NAME"
echo "  Activate with  : pyenv activate $VENV_NAME"
echo ""
echo "NOTE: Restart your terminal or run: source ~/.zshrc"
