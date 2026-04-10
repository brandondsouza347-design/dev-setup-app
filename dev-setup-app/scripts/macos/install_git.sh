#!/usr/bin/env bash
# install_git.sh — Install Git version control system on macOS
set -euo pipefail

SKIP_INSTALLED="${SETUP_SKIP_INSTALLED:-true}"

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║               Git Version Control Installation            ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "[1/3] Checking current installation..."

# Check if Git is already installed
if command -v git &>/dev/null; then
    GIT_VERSION=$(git --version 2>/dev/null || echo "unknown")
    GIT_PATH=$(which git 2>/dev/null || echo "unknown")

    if [ "$SKIP_INSTALLED" = "true" ]; then
        echo ""
        echo "✓ Git already installed"
        echo "  Version: $GIT_VERSION"
        echo "  Location: $GIT_PATH"
        exit 0
    else
        echo ""
        echo "✓ Git found (SKIP_INSTALLED=false, will attempt update)"
        echo "  Current version: $GIT_VERSION"
    fi
else
    echo "✗ Git not found in PATH"
fi

echo ""
echo "[2/3] Determining installation method..."

# Check if Homebrew is available
if command -v brew &>/dev/null; then
    echo "  → Homebrew detected: $(which brew)"
    echo "  → Installation method: Homebrew (preferred)"
    echo ""
    echo "[3/3] Installing Git via Homebrew..."
    echo "  This will download and install the latest stable Git version"
    echo ""

    if command -v git &>/dev/null; then
        # Git exists, try to upgrade it
        echo "  Running: brew upgrade git"
        brew upgrade git 2>&1 || {
            echo "  ℹ Git is already up-to-date"
            brew link --overwrite git 2>&1 || true
        }
    else
        # Fresh install
        echo "  Running: brew install git"
        brew install git 2>&1
    fi

    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "✓ Git installed successfully via Homebrew!"
    echo "  Version: $(git --version 2>/dev/null || echo 'Git installed')"
    echo "  Location: $(which git 2>/dev/null || echo '/opt/homebrew/bin/git or /usr/local/bin/git')"
    echo "═══════════════════════════════════════════════════════════"
    exit 0
fi

# Homebrew not available — fall back to Xcode Command Line Tools prompt
echo "  ✗ Homebrew not found"
echo "  → Installation method: Xcode Command Line Tools (fallback)"
echo ""
echo "[3/3] Installing Git via Xcode Command Line Tools..."
echo ""
echo "Git can be installed as part of Xcode Command Line Tools."
echo "This is a system-level installation that requires admin privileges."
echo ""

# Check if Xcode CLT is already installed
if xcode-select -p &>/dev/null; then
    XCODE_PATH=$(xcode-select -p)
    echo "✓ Xcode Command Line Tools already installed at: $XCODE_PATH"
    echo ""

    # Check if git is in the Xcode CLT path
    if [ -x "/usr/bin/git" ]; then
        echo "✓ Git found at /usr/bin/git (provided by Xcode CLT)"
        echo "  Version: $(/usr/bin/git --version)"
        echo ""
        echo "Git is installed but may not be in your PATH."
        echo "Try restarting your terminal or adding /usr/bin to PATH."
        exit 0
    else
        echo "⚠ Xcode CLT installed but Git not found at /usr/bin/git"
        echo "  This is unexpected. Try reinstalling Xcode Command Line Tools:"
        echo "    sudo rm -rf /Library/Developer/CommandLineTools"
        echo "    xcode-select --install"
        exit 1
    fi
fi

echo "⚠ Xcode Command Line Tools not installed."
echo ""
echo "ACTION REQUIRED:"
echo "  Option 1 (Recommended): Install Homebrew first, then install Git"
echo "    Run: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
echo "    Then: brew install git"
echo ""
echo "  Option 2: Install Xcode Command Line Tools (includes Git)"
echo "    1. A system dialog should appear asking to install"
echo "    2. Click 'Install' in the dialog"
echo "    3. Enter your admin password when prompted"
echo "    4. Wait for installation to complete (~500MB, 10-15 min)"
echo "    5. Return to Dev_Setup and re-run prerequisite checks"
echo ""
echo "Triggering Xcode Command Line Tools installer..."
xcode-select --install 2>&1 || echo "  (Dialog should appear if it's not already open)"
echo ""
echo "NOTE: After installation completes, restart your terminal and re-run the prerequisite checks."
exit 1
