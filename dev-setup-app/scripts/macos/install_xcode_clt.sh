#!/usr/bin/env bash
# install_xcode_clt.sh — Install Xcode Command Line Tools (required for compiling software on macOS)
set -euo pipefail

echo "==> Checking Xcode Command Line Tools..."

if xcode-select -p &>/dev/null; then
    echo "✓ Xcode Command Line Tools already installed at: $(xcode-select -p)"
    exit 0
fi

echo "==> Installing Xcode Command Line Tools (this may take several minutes)..."

# Trigger the install dialog or use the non-interactive approach
touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress

PROD=$(softwareupdate -l 2>/dev/null \
  | grep "\*.*Command Line" \
  | tail -1 \
  | sed 's/^[^:]*: //' \
  | tr -d '\n')

if [ -z "$PROD" ]; then
    echo "⚠ Could not find CLT in Software Update. Falling back to interactive install..."
    xcode-select --install
    echo "Please complete the installation in the dialog that appeared, then re-run this setup."
    exit 1
fi

echo "==> Installing: $PROD"
softwareupdate -i "$PROD" --verbose

rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress

echo "✓ Xcode Command Line Tools installed successfully"
