#!/usr/bin/env bash
# setup_mac_hosts.sh — Add 127.0.0.1 tenant entries to /etc/hosts
# Requires sudo privileges
set -euo pipefail

HOSTS_PATH="/etc/hosts"

# Get tenant name from environment variable (fallback to erckinetic)
TENANT_NAME="${SETUP_TENANT_NAME:-}"
if [ -z "$TENANT_NAME" ]; then
    TENANT_NAME="erckinetic"
    echo "⚠ SETUP_TENANT_NAME not set, using default: $TENANT_NAME"
fi

echo "==> Using tenant name: $TENANT_NAME"

ENTRIES=(
    "127.0.0.1 t3582.local"
    "127.0.0.1 $TENANT_NAME"
    "127.0.0.1 localhost"
)

echo "==> setup_mac_hosts: checking $HOSTS_PATH..."

if [ ! -f "$HOSTS_PATH" ]; then
    echo "  Hosts file not found at $HOSTS_PATH — skipping"
    exit 0
fi

CURRENT_CONTENT=$(cat "$HOSTS_PATH")
ADDED_ANY=false

for ENTRY in "${ENTRIES[@]}"; do
    # Extract hostname to check for duplicates
    HOSTNAME=$(echo "$ENTRY" | awk '{print $2}')
    
    if echo "$CURRENT_CONTENT" | grep -qF "$HOSTNAME"; then
        echo "✓ '$HOSTNAME' already in hosts file — skipping"
    else
        echo "  Adding: $ENTRY"
        echo "$ENTRY" | sudo tee -a "$HOSTS_PATH" > /dev/null
        echo "✓ Added: $ENTRY"
        ADDED_ANY=true
    fi
done

if [ "$ADDED_ANY" = false ]; then
    echo "✓ All entries already present — no changes needed"
else
    echo "✓ Hosts file updated successfully"
fi

echo ""
echo "Current tenant entries in hosts file:"
grep -E "t3582\.local|$TENANT_NAME" "$HOSTS_PATH" || echo "  (none found)"
