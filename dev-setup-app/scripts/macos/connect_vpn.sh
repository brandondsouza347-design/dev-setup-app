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

echo "→ Step 2/3: Launching Tunnelblick and connecting..."
open -a Tunnelblick 2>/dev/null || true

# Wait for Tunnelblick to launch
sleep 2

# Disconnect any existing connections first to avoid conflicts
echo "  Checking for existing connections..."
DISCONNECT_RESULT=$(osascript -e 'tell application "Tunnelblick"
    try
        set configCount to count configurations
        if configCount is 0 then
            return "NO_CONFIGS"
        end if

        set disconnectedAny to false
        repeat with cfg in configurations
            set cfgState to state of cfg
            if cfgState contains "CONNECTED" then
                disconnect cfg
                set disconnectedAny to true
            end if
        end repeat

        if disconnectedAny then
            return "DISCONNECTED_EXISTING"
        else
            return "NONE_CONNECTED"
        end if
    on error errMsg
        return "ERROR:" & errMsg
    end try
end tell' 2>/dev/null || echo "ERROR")

if [[ "$DISCONNECT_RESULT" == "DISCONNECTED_EXISTING" ]]; then
    echo "  ✓ Disconnected existing VPN connection"
    sleep 2  # Wait for disconnection to complete
elif [[ "$DISCONNECT_RESULT" == "NONE_CONNECTED" ]]; then
    echo "  ✓ No existing connections to disconnect"
fi

# Automatically connect to the first available configuration
echo "  Triggering VPN connection..."
CONNECT_RESULT=$(osascript -e 'tell application "Tunnelblick"
    try
        set configCount to count configurations
        if configCount is 0 then
            error "No configurations available"
        end if

        -- Connect to the first configuration
        connect (first configuration)
        return "CONNECTION_INITIATED"
    on error errMsg
        return "ERROR:" & errMsg
    end try
end tell' 2>/dev/null || echo "ERROR")

if [[ "$CONNECT_RESULT" == "CONNECTION_INITIATED" ]]; then
    echo "  ✓ Connection request sent to Tunnelblick"
else
    echo "  ⚠ Could not auto-connect via AppleScript (connection may need manual approval)"
fi

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
