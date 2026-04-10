#!/usr/bin/env bash
# disconnect_vpn_tunnelblick.sh — Disconnect Tunnelblick VPN
set -euo pipefail

echo "→ Disconnecting Tunnelblick VPN..."

if ! osascript -e 'application "Tunnelblick" is running' 2>/dev/null; then
    echo "⚠ Tunnelblick is not running"
    exit 0
fi

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
            return "DISCONNECTED"
        else
            return "NONE_CONNECTED"
        end if
    on error errMsg
        return "ERROR:" & errMsg
    end try
end tell' 2>/dev/null || echo "ERROR")

if [[ "$DISCONNECT_RESULT" == "DISCONNECTED" ]]; then
    echo "✓ Disconnected all Tunnelblick connections"
    exit 0
elif [[ "$DISCONNECT_RESULT" == "NONE_CONNECTED" ]]; then
    echo "⚠ No active Tunnelblick connections to disconnect"
    exit 0
elif [[ "$DISCONNECT_RESULT" == "NO_CONFIGS" ]]; then
    echo "⚠ Tunnelblick has no configurations"
    exit 0
else
    echo "✗ Failed to disconnect: $DISCONNECT_RESULT"
    exit 1
fi
