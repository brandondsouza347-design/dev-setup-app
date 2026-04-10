#!/usr/bin/env bash
# check_vpn_status.sh (macOS) — Check if VPN is actually connected (Tunnelblick or OpenVPN CLI)
set -euo pipefail

VPN_METHOD="${SETUP_VPN_METHOD:-tunnelblick}"

echo "→ Checking VPN connection status (method: $VPN_METHOD)..."

if [ "$VPN_METHOD" = "tunnelblick" ]; then
    # Check Tunnelblick connection via AppleScript
    if ! osascript -e 'application "Tunnelblick" is running' 2>/dev/null; then
        echo "✗ Tunnelblick is not running"
        exit 1
    fi

    # Query connection state
    STATE=$(osascript -e 'tell application "Tunnelblick"
        try
            set configCount to count of configurations
            if configCount is 0 then
                return "NO_CONFIGS"
            end if

            repeat with cfg in configurations
                set cfgState to state of cfg
                if cfgState contains "CONNECTED" then
                    return name of cfg & "|CONNECTED"
                end if
            end repeat
            return "DISCONNECTED"
        on error errMsg
            return "ERROR:" & errMsg
        end try
    end tell' 2>/dev/null || echo "ERROR")

    if [[ "$STATE" == *"|CONNECTED" ]]; then
        CONFIG_NAME="${STATE%|*}"
        echo "✓ VPN connected via Tunnelblick: $CONFIG_NAME"
        exit 0
    elif [[ "$STATE" == "NO_CONFIGS" ]]; then
        echo "✗ Tunnelblick has no configurations"
        exit 1
    elif [[ "$STATE" == "DISCONNECTED" ]]; then
        echo "✗ Tunnelblick is running but not connected"
        exit 1
    else
        echo "⚠ Could not determine Tunnelblick state: $STATE"
        exit 1
    fi

elif [ "$VPN_METHOD" = "openvpn-cli" ]; then
    # Check for OpenVPN CLI daemon process
    if pgrep -f "openvpn.*\.ovpn" >/dev/null 2>&1; then
        PID=$(pgrep -f "openvpn.*\.ovpn")
        echo "✓ VPN connected via OpenVPN CLI (PID: $PID)"
        exit 0
    else
        echo "✗ OpenVPN CLI daemon is not running"
        exit 1
    fi
else
    echo "⚠ Unknown VPN method: $VPN_METHOD"
    exit 1
fi
