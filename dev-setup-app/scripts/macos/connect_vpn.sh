#!/usr/bin/env bash
# connect_vpn.sh (macOS) — Open Tunnelblick and poll until gitlab.toogoerp.net:443 is reachable
set -euo pipefail

test_gitlab() {
    nc -z -w 3 gitlab.toogoerp.net 443 2>/dev/null && return 0 || return 1
}

echo "→ Step 1/2: Checking VPN connectivity..."
if test_gitlab; then
    echo "✓ Already connected — gitlab.toogoerp.net is reachable. Skipping VPN launch."
    exit 0
fi

echo "→ Step 2/2: Opening Tunnelblick..."
open -a Tunnelblick 2>/dev/null || true

MAX=36
echo "  Waiting for VPN connection (up to $((MAX * 5))s)..."
for i in $(seq 1 $MAX); do
    sleep 5
    if test_gitlab; then
        echo "✓ VPN connected — gitlab.toogoerp.net is reachable ($((i * 5))s)."
        exit 0
    fi
    echo "  ⏳ Waiting... ($((i * 5))s / $((MAX * 5))s)"
done

echo "✗ VPN did not connect within 3 minutes. Connect manually and retry this step."
exit 1
