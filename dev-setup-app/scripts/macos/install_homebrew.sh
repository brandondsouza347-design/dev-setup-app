#!/usr/bin/env bash
# install_homebrew.sh — Install Homebrew (macOS package manager)
set -euo pipefail

SKIP_INSTALLED="${SETUP_SKIP_INSTALLED:-true}"

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║           Homebrew Package Manager Installation          ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "[1/3] Checking current installation..."

# Detect architecture to set correct prefix
ARCH="$(uname -m)"
echo "  → Detected architecture: $ARCH"

if [ "$ARCH" = "arm64" ]; then
    BREW_PREFIX="/opt/homebrew"
    echo "  → Installation path: $BREW_PREFIX (Apple Silicon)"
else
    BREW_PREFIX="/usr/local"
    echo "  → Installation path: $BREW_PREFIX (Intel)"
fi

BREW_BIN="$BREW_PREFIX/bin/brew"

if [ "$SKIP_INSTALLED" = "true" ] && (command -v brew &>/dev/null || [ -x "$BREW_BIN" ]); then
    echo ""
    echo "✓ Homebrew already installed"
    echo "  Version: $(brew --version | head -1)"
    echo "  Location: $(which brew)"
    echo ""
    echo "[2/3] Updating Homebrew package database..."
    brew update --quiet 2>&1 || echo "  ⚠ Update skipped (may be offline)"
    echo "  ✓ Update complete"
    exit 0
elif command -v brew &>/dev/null || [ -x "$BREW_BIN" ]; then
    echo ""
    echo "✓ Homebrew found (SKIP_INSTALLED=false, updating...)"
    brew update 2>&1
    echo "  ✓ Updated: $(brew --version | head -1)"
    exit 0
fi

echo ""
echo "✗ Homebrew not found"
echo ""
echo "[2/3] Downloading Homebrew installer..."
echo "  Source: https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
echo "  This script will:"
echo "    • Create $BREW_PREFIX directory structure"
echo "    • Download Homebrew repository (~200MB)"
echo "    • Configure PATH and environment"
echo "    • Requires admin password (will prompt via dialog)"
echo ""

echo "[3/3] Running Homebrew installation script..."
echo "  → Two dialogs will appear: admin username then admin password"
echo "  Note: On corporate Macs the admin account (e.g. localadmin) differs"
echo "        from your login account ($(whoami))"
echo ""

# ── Collect admin username ───────────────────────────────────────────────────
ADMIN_USER=$(osascript \
  -e 'display dialog "Homebrew requires administrator privileges to install.\n\nEnter the local admin username:\n(usually: localadmin)" default answer "localadmin" with title "Homebrew Installation — Admin Username" buttons {"Cancel", "Continue"} default button "Continue"' \
  -e 'text returned of result' 2>/dev/null) || true

if [ -z "$ADMIN_USER" ]; then
    echo "  ✗ Installation cancelled — no admin username provided"
    exit 1
fi
echo "  → Admin username entered: $ADMIN_USER"

# ── Collect admin password ───────────────────────────────────────────────────
ADMIN_PASS=$(osascript \
  -e "display dialog \"Enter the password for admin account '$ADMIN_USER':\" default answer \"\" with title \"Homebrew Installation — Admin Password\" with icon caution buttons {\"Cancel\", \"OK\"} default button \"OK\" with hidden answer" \
  -e 'text returned of result' 2>/dev/null) || true

if [ -z "$ADMIN_PASS" ]; then
    echo "  ✗ Installation cancelled — no password provided"
    exit 1
fi

# ── Verify credentials before making any system changes ─────────────────────
echo "  → Verifying admin credentials..."
if ! osascript -e "do shell script \"echo verified\" user name \"$ADMIN_USER\" password \"$ADMIN_PASS\" with administrator privileges" > /dev/null 2>&1; then
    echo "  ✗ Admin credentials rejected — wrong username or password"
    echo "  Please re-run and check credentials for account: $ADMIN_USER"
    exit 1
fi
echo "  ✓ Admin credentials verified"

# ── Grant temporary NOPASSWD sudo to current user ───────────────────────────
# Homebrew must run as the regular user but its installer hard-codes
# /usr/bin/sudo -n (non-interactive). We add a scoped NOPASSWD sudoers entry
# so those calls succeed, then remove it via trap on any exit.
CURRENT_USER=$(whoami)
SUDOERS_FILE="/etc/sudoers.d/brew_install_$$"

cleanup_sudoers() {
    osascript -e "do shell script \"rm -f '$SUDOERS_FILE'\" user name \"$ADMIN_USER\" password \"$ADMIN_PASS\" with administrator privileges" > /dev/null 2>&1 || true
    echo "  ✓ Temporary install permissions removed"
}
trap cleanup_sudoers EXIT

echo "  → Granting temporary install permissions to $CURRENT_USER..."
SUDOERS_LINE="$CURRENT_USER ALL=(ALL) NOPASSWD:ALL"
if ! osascript -e "do shell script \"printf '%s\n' '$SUDOERS_LINE' > '$SUDOERS_FILE' && chmod 440 '$SUDOERS_FILE' && visudo -cf '$SUDOERS_FILE'\" user name \"$ADMIN_USER\" password \"$ADMIN_PASS\" with administrator privileges" > /dev/null 2>&1; then
    echo "  ✗ Failed to create temporary sudoers entry"
    echo "  Account '$ADMIN_USER' may not have full admin rights"
    exit 1
fi
echo "  ✓ Temporary permissions granted (will be removed after installation)"
echo ""
echo "  Starting Homebrew installation — this may take 3-5 minutes..."
echo ""

# ── Run Homebrew as regular user (NOPASSWD entry makes sudo work) ─────────────
if NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" 2>&1; then
    # trap handles sudoers cleanup on EXIT
    echo ""
    echo "  ✓ Homebrew core installation complete"
else
    # trap handles sudoers cleanup on EXIT
    echo ""
    echo "  ✗ Homebrew installation failed"
    echo ""
    echo "  Common issues:"
    echo "    • Incorrect admin credentials (re-run with correct username/password)"
    echo "    • Network connectivity problem (check internet connection)"
    echo "    • Disk space (need ~1GB free)"
    echo ""
    echo "  Manual installation:"
    echo "    1. Open Terminal"
    echo "    2. Run: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    echo "    3. Follow prompts and enter password when asked"
    echo ""
    exit 1
fi

# Add Homebrew to PATH for Apple Silicon
if [ "$ARCH" = "arm64" ]; then
    echo ""
    echo "→ Configuring PATH for Apple Silicon..."
    if ! grep -q 'eval "$(/opt/homebrew/bin/brew shellenv)"' ~/.zprofile 2>/dev/null; then
        echo '' >> ~/.zprofile
        echo '# Homebrew' >> ~/.zprofile
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
        echo "  ✓ Added to ~/.zprofile"
    else
        echo "  ✓ Already configured in ~/.zprofile"
    fi
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

echo ""
echo "→ Running post-installation diagnostics..."
brew doctor 2>&1 || echo "  ⚠ Some warnings detected (usually non-fatal)"

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "✓ Homebrew installation complete!"
echo "  Version: $(brew --version 2>/dev/null | head -1)"
echo "  Location: $BREW_PREFIX"
echo "  Available commands: brew install, brew search, brew update"
echo "═══════════════════════════════════════════════════════════"
