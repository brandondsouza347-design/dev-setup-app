#!/usr/bin/env bash
# python_interpreter.sh (macOS) — Trigger Python interpreter selection via VS Code Python extension
set -euo pipefail

VENV_NAME="${SETUP_VENV_NAME:-erc}"
WORKSPACE_DIR="${SETUP_CLONE_DIR:-~/VsCodeProjects/erc}"
PYTHON_PATH="$HOME/.pyenv/versions/$VENV_NAME/bin/python"

echo "═══════════════════════════════════════════════════════════"
echo " Configure Python Interpreter in VS Code"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "  Configuring interpreter via Python extension..."
echo "  Virtualenv: $VENV_NAME"
echo ""

# Verify the Python interpreter exists
if [ ! -f "$PYTHON_PATH" ]; then
    echo "✗ ERROR: Python interpreter not found at: $PYTHON_PATH"
    exit 1
fi

# Expand workspace directory
WORKSPACE_DIR=$(eval echo "$WORKSPACE_DIR")

# Configure interpreter in workspace settings (no new window)
VSCODE_DIR="$WORKSPACE_DIR/.vscode"
SETTINGS_FILE="$VSCODE_DIR/settings.json"

echo "  Configuring Python interpreter in workspace settings..."
echo "  Workspace: $WORKSPACE_DIR"
echo ""

# Create .vscode directory if it doesn't exist
mkdir -p "$VSCODE_DIR"

# Write Python interpreter to workspace settings using Python
python3 - "$SETTINGS_FILE" "$PYTHON_PATH" <<'PYEOF'
import json
import os
import sys

if len(sys.argv) != 3:
    print("Usage: script <settings_file> <python_path>", file=sys.stderr)
    sys.exit(1)

settings_path = sys.argv[1]
python_path = sys.argv[2]

# Load existing settings if file exists
if os.path.exists(settings_path):
    with open(settings_path, 'r') as f:
        settings = json.load(f)
else:
    settings = {}

# Set Python interpreter path
settings['python.defaultInterpreterPath'] = python_path

# Write back to file
with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)

print(f"\n✓ Python interpreter configured: {python_path}")
PYEOF

echo ""
echo "✓ Interpreter configured in workspace settings!"
echo ""
echo "  Setting: python.defaultInterpreterPath"
echo "  Value: $PYTHON_PATH"
echo "  Selected: Python 3.9.x ('$VENV_NAME': pyenv)"
echo ""
echo "  VS Code will automatically detect the interpreter when workspace is opened."
echo ""
echo "═══════════════════════════════════════════════════════════"
exit 0
