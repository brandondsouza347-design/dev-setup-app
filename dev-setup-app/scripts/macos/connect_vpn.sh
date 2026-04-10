#!/usr/bin/env bash
# connect_vpn.sh (macOS) — Open Tunnelblick and poll until gitlab.toogoerp.net:443 is reachable
set -euo pipefail

test_gitlab() {
    nc -z -w 3 gitlab.toogoerp.net 443 2>/dev/null && return 0 || return 1
}

check_vpn_status() {
    bash "$(dirname "$0")/check_vpn_status.sh" 2>/dev/null && return 0 || return 1
}

echo "→ Step 1/3: Checking VPN connection status..."
if check_vpn_status; then
    echo "✓ VPN already connected. Verifying GitLab connectivity..."
    if test_gitlab; then
        echo "✓ GitLab is reachable. No action needed."
        exit 0
    else
        echo "⚠ VPN connected but GitLab not reachable. Check network routing."
        exit 1
    fi
fi

echo "→ Step 2/3: Opening Tunnelblick..."
open -a Tunnelblick 2>/dev/null || true

MAX=36
echo "→ Step 3/3: Waiting for VPN connection (up to $((MAX * 5))s)..."
for i in $(seq 1 $MAX); do
    sleep 5
    if check_vpn_status && test_gitlab; then
        echo "✓ VPN connected and GitLab is reachable ($((i * 5))s)."
        exit 0
    fi
    echo "  ⏳ Waiting... ($((i * 5))s / $((MAX * 5))s)"
done

echo "✗ VPN did not connect within 3 minutes. Connect manually and retry this step."
exit 1
