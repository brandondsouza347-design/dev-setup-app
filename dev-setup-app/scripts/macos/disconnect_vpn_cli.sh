#!/usr/bin/env bash
# disconnect_vpn_cli.sh (macOS) — Disconnect OpenVPN CLI daemon
set -euo pipefail

PID_FILE="/tmp/openvpn-dev-setup.pid"
LOG_FILE="/tmp/openvpn-dev-setup.log"

echo "→ Disconnecting OpenVPN CLI daemon..."

if [ ! -f "$PID_FILE" ]; then
    echo "⚠ No PID file found ($PID_FILE)"
    echo "  OpenVPN daemon may not be running."
    exit 0
fi

OPENVPN_PID=$(cat "$PID_FILE")

if ! ps -p "$OPENVPN_PID" &>/dev/null; then
    echo "⚠ OpenVPN process (PID: $OPENVPN_PID) is not running"
    echo "  Cleaning up stale PID file..."
    rm -f "$PID_FILE"
    exit 0
fi

echo "→ Stopping OpenVPN daemon (PID: $OPENVPN_PID)..."
echo "  This requires administrator privileges."

# Kill the OpenVPN process
sudo kill "$OPENVPN_PID" 2>/dev/null || {
    echo "⚠ Failed to send kill signal (process may have already exited)"
}

# Wait for process to exit (max 5 seconds)
for i in {1..10}; do
    if ! ps -p "$OPENVPN_PID" &>/dev/null; then
        echo "✓ OpenVPN daemon stopped"
        break
    fi
    sleep 0.5
done

# Force kill if still running
if ps -p "$OPENVPN_PID" &>/dev/null; then
    echo "→ Process still running, sending SIGKILL..."
    sudo kill -9 "$OPENVPN_PID" 2>/dev/null || true
    sleep 1
fi

# Clean up files
rm -f "$PID_FILE"

echo "✓ VPN disconnected"
echo ""
echo "Log file preserved at: $LOG_FILE"
echo "To remove logs, run: rm $LOG_FILE"
