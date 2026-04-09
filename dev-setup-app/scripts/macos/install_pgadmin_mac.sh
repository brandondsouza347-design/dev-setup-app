#!/usr/bin/env bash
# install_pgadmin_mac.sh — Install pgAdmin 4 GUI for PostgreSQL database management
set -euo pipefail

echo "==> Installing pgAdmin 4..."

# Check if Homebrew is available
if ! command -v brew >/dev/null 2>&1; then
    echo "✗ Homebrew not found. Please install Homebrew first."
    exit 1
fi

# Check if pgAdmin is already installed
if [ -d "/Applications/pgAdmin 4.app" ]; then
    echo "✓ pgAdmin 4 is already installed"
    echo "  Location: /Applications/pgAdmin 4.app"
    exit 0
fi

# Install pgAdmin via Homebrew Cask
echo "→ Installing pgAdmin 4 via Homebrew..."
brew install --cask pgadmin4

if [ -d "/Applications/pgAdmin 4.app" ]; then
    echo "✓ pgAdmin 4 installed successfully"
    echo "  Launch from: /Applications/pgAdmin 4.app"
    echo "  Or run: open -a 'pgAdmin 4'"
    echo ""
    echo "  First-time setup:"
    echo "    1. Launch pgAdmin 4"
    echo "    2. Set master password"
    echo "    3. Right-click Servers → Register → Server"
    echo "    4. Name: localhost"
    echo "    5. Connection tab:"
    echo "       - Host: localhost"
    echo "       - Port: 5432"
    echo "       - Username: postgres"
    echo "       - Database: postgres"
else
    echo "✗ pgAdmin 4 installation failed"
    exit 1
fi
