#!/usr/bin/env bash
# pyenv_local.sh — Set pyenv local version to the ERC virtualenv inside the cloned repo
set -euo pipefail

CLONE_DIR="${SETUP_CLONE_DIR:-/home/ubuntu/VsCodeProjects/erc}"
VENV_NAME="${SETUP_VENV_NAME:-erc}"

# Activate pyenv
export PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"
export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"
eval "$(pyenv init -)" 2>/dev/null || true

echo "→ Clone directory: $CLONE_DIR"
echo "→ Virtualenv name: $VENV_NAME"

if [ ! -d "$CLONE_DIR" ]; then
    echo "✗ Clone directory not found: $CLONE_DIR"
    echo "  Run the 'Clone Project Repository' step first."
    exit 1
fi

# Verify the virtualenv exists in pyenv.
# pyenv versions --bare can prefix entries with spaces on some versions,
# so strip whitespace before comparing.
if ! pyenv versions --bare 2>/dev/null | sed 's/^[[:space:]]*//' | grep -qx "$VENV_NAME"; then
    echo "⚠ pyenv version '$VENV_NAME' not found."
    echo "  Available pyenv versions:"
    pyenv versions --bare 2>/dev/null || echo "  (none)"
    echo "  Ensure the 'Install pyenv + Python' step completed successfully."
    exit 1
fi

echo "→ Setting pyenv local version to '$VENV_NAME' in $CLONE_DIR..."
cd "$CLONE_DIR"
pyenv local "$VENV_NAME"
echo "✓ .python-version written: $(cat .python-version)"

python --version
echo "✓ Python interpreter confirmed."
