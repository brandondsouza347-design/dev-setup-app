#!/bin/bash
# install_pip_requirements.sh — Install Python dependencies from requirements.txt
set -e

echo "📦 Installing pip requirements from requirements.txt..."
echo ""
echo "🔍 Environment variables received:"
env | grep '^SETUP_' || echo "   ⚠️  No SETUP_* variables found!"
echo ""

CLONE_DIR="${SETUP_CLONE_DIR}"
VENV_NAME="${SETUP_VENV_NAME}"

echo "📋 Configuration:"
echo "   Clone directory: ${CLONE_DIR:-<NOT SET>}"
echo "   Virtual environment: ${VENV_NAME:-<NOT SET>}"
echo ""

# Validate required variables
if [ -z "$CLONE_DIR" ]; then
    echo "❌ FATAL: SETUP_CLONE_DIR environment variable is not set"
    echo "   This should be set by the orchestrator (e.g., /home/ubuntu/VsCodeProjects/erc)"
    echo "   Check Settings screen -> GitLab Configuration -> Clone Directory"
    exit 1
fi

if [ -z "$VENV_NAME" ]; then
    echo "❌ FATAL: SETUP_VENV_NAME environment variable is not set"
    echo "   This should be set by the orchestrator (e.g., 'erc')"
    echo "   Check Settings screen -> Python -> Virtualenv Name"
    exit 1
fi

# Navigate to project directory
if [ ! -d "$CLONE_DIR" ]; then
    echo "❌ Error: Clone directory '$CLONE_DIR' does not exist"
    exit 1
fi

cd "$CLONE_DIR"

# Check if requirements.txt exists
if [ ! -f "requirements.txt" ]; then
    echo "❌ Error: requirements.txt not found in $CLONE_DIR"
    exit 1
fi

echo "✓ Found requirements.txt with $(wc -l < requirements.txt) entries"
echo ""

# Activate virtual environment via pyenv
echo "🔧 Activating virtual environment '$VENV_NAME'..."
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"

# Activate the virtualenv
pyenv activate "$VENV_NAME" 2>/dev/null || {
    echo "❌ Error: Failed to activate virtualenv '$VENV_NAME'"
    echo "   Make sure step 14 (Install pyenv + Python) completed successfully"
    exit 1
}

echo "✓ Virtual environment '$VENV_NAME' activated"
echo ""

# Upgrade pip first
echo "⬆️  Upgrading pip..."
pip install --upgrade pip --quiet
echo "✓ pip upgraded to latest version"
echo ""

echo ""
echo "📥 Installing requirements (this may take several minutes)..."
if pip install -r requirements.txt; then
    echo ""
    echo "✅ SUCCESS: All pip requirements installed successfully!"
    echo "   Location: $CLONE_DIR"
    echo "   Virtualenv: $VENV_NAME"
    exit 0
else
    echo ""
    echo "❌ FAILURE: pip install failed"
    echo "   Check the error messages above for details"
    echo "   Common issues: network problems, incompatible versions"
    exit 1
fi
