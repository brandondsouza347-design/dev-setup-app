#!/usr/bin/env bash
# setup_vscode.sh — Install VS Code extensions and configure VS Code settings on macOS
set -euo pipefail

echo "==> VS Code Configuration Setup"

# ─── 1. Ensure 'code' CLI is available ──────────────────────────────────────

echo "==> Step 1: Checking VS Code CLI..."

CODE_CMD=""
for candidate in \
    "code" \
    "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" \
    "$HOME/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"; do
    if command -v "$candidate" &>/dev/null || [ -x "$candidate" ]; then
        CODE_CMD="$candidate"
        break
    fi
done

if [ -z "$CODE_CMD" ]; then
    echo "⚠ VS Code CLI 'code' not found."
    echo "  Please install VS Code from: https://code.visualstudio.com/"
    echo "  Then run: Command Palette (⇧⌘P) → Shell Command: Install 'code' command in PATH"
    echo "  Re-run this step after VS Code is installed."
    exit 1
fi

echo "✓ VS Code CLI found: $CODE_CMD"
$CODE_CMD --version | head -1

# ─── 2. Install extensions ──────────────────────────────────────────────────

echo ""
echo "==> Step 2: Installing VS Code extensions..."

EXTENSIONS=(
    "atlassian.atlascode"           # Jira & Bitbucket
    "amazonwebservices.aws-toolkit-vscode"  # AWS Toolkit
    "ms-python.black-formatter"     # Black Formatter
    "dbaeumer.vscode-eslint"        # ESLint
    "mhutchie.git-graph"            # Git Graph
    "ms-python.pylint"              # Pylint
    "ms-python.python"              # Python
    "ms-python.debugpy"             # Python Debugger
    "humao.rest-client"             # REST Client
    "codeium.codeium"               # Windsurf/Codeium AI
    "redhat.vscode-yaml"            # YAML
    "ms-vscode-remote.remote-wsl"   # Remote WSL (useful even on Mac)
    "eamodio.gitlens"               # GitLens
)

INSTALLED=0
FAILED=0

for ext in "${EXTENSIONS[@]}"; do
    echo "   Installing: $ext"
    if $CODE_CMD --install-extension "$ext" --force 2>&1 | grep -qi "successfully installed\|already installed"; then
        echo "   ✓ $ext"
        ((INSTALLED++)) || true
    else
        echo "   ⚠ Failed: $ext"
        ((FAILED++)) || true
    fi
done

echo ""
echo "   Extensions: $INSTALLED installed, $FAILED failed"

# ─── 3. Configure VS Code user settings ────────────────────────────────────

echo ""
echo "==> Step 3: Writing VS Code user settings..."

VSCODE_SETTINGS_DIR="$HOME/Library/Application Support/Code/User"
mkdir -p "$VSCODE_SETTINGS_DIR"
SETTINGS_FILE="$VSCODE_SETTINGS_DIR/settings.json"

VENV_NAME="${SETUP_VENV_NAME:-erc}"
PYTHON_VERSION="${SETUP_PYTHON_VERSION:-3.9.21}"
PYTHON_PATH="$HOME/.pyenv/versions/$VENV_NAME/bin/python"

# Merge with existing settings if present, otherwise create fresh
cat > "$SETTINGS_FILE" << SETTINGS_JSON
{
    "editor.formatOnSave": true,
    "editor.tabSize": 4,
    "editor.insertSpaces": true,
    "editor.rulers": [88, 120],
    "editor.trimAutoWhitespace": true,
    "files.trimTrailingWhitespace": true,
    "files.insertFinalNewline": true,
    "terminal.integrated.defaultProfile.osx": "zsh",
    "terminal.integrated.env.osx": {
        "PATH": "\${env:PATH}:$HOME/.pyenv/bin:$HOME/.nvm/versions/node/${SETUP_NODE_VERSION:-16.20.2}/bin"
    },
    "python.defaultInterpreterPath": "${PYTHON_PATH}",
    "[python]": {
        "editor.defaultFormatter": "ms-python.black-formatter"
    },
    "black-formatter.args": ["--line-length", "88"],
    "pylint.enabled": true,
    "pylint.interpreter": ["${PYTHON_PATH}"],
    "eslint.enable": true,
    "git.autofetch": true,
    "git.confirmSync": false,
    "gitlens.hovers.currentLine.over": "line",
    "yaml.schemas": {},
    "workbench.colorTheme": "Default Dark Modern",
    "workbench.iconTheme": "vs-seti",
    "window.zoomLevel": 0
}
SETTINGS_JSON

echo "✓ Settings written to: $SETTINGS_FILE"

# ─── 4. Configure shell integration ────────────────────────────────────────

echo ""
echo "==> Step 4: Verifying shell integration for VS Code terminal..."

# Ensure zshrc sources pyenv and nvm so VS Code integrated terminal works
if ! grep -q "pyenv init" ~/.zshrc 2>/dev/null; then
    echo '# pyenv' >> ~/.zshrc
    echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.zshrc
    echo 'export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.zshrc
    echo 'eval "$(pyenv init --path)"' >> ~/.zshrc
    echo 'eval "$(pyenv init -)"' >> ~/.zshrc
    echo 'eval "$(pyenv virtualenv-init -)"' >> ~/.zshrc
    echo "   Added pyenv config to ~/.zshrc"
fi

if ! grep -q "NVM_DIR" ~/.zshrc 2>/dev/null; then
    echo '# nvm' >> ~/.zshrc
    echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.zshrc
    echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> ~/.zshrc
    echo "   Added nvm config to ~/.zshrc"
fi

echo ""
echo "✓ VS Code setup complete!"
echo ""
echo "  Next steps:"
echo "  1. Restart VS Code to pick up extensions"
echo "  2. Open your project: code /path/to/project"
echo "  3. Select Python interpreter: ⇧⌘P → Python: Select Interpreter"
echo "     → $PYTHON_PATH"
echo "  4. Save workspace: File → Save Workspace As → Propello.code-workspace"
