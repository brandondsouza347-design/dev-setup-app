#!/usr/bin/env bash
# connect_vpn_cli.sh (macOS) — Connect to VPN using OpenVPN CLI daemon
set -euo pipefail

VPN_TARGET="gitlab.toogoerp.net"
VPN_PORT="443"
MAX_ATTEMPTS=36
RETRY_INTERVAL=5
CONFIG_DIR="$HOME/.openvpn"
PID_FILE="/tmp/openvpn-dev-setup.pid"
LOG_FILE="/tmp/openvpn-dev-setup.log"

echo "→ Checking VPN connectivity..."

# Fast path — already connected
if nc -z -w 3 "$VPN_TARGET" "$VPN_PORT" 2>/dev/null; then
    echo "✓ Already connected to VPN ($VPN_TARGET:$VPN_PORT is reachable)"
    exit 0
fi

echo "  VPN not currently connected. Starting OpenVPN daemon..."

# Find the OpenVPN config file
if [ -f "$CONFIG_DIR/.current-config" ]; then
    CONFIG_PATH=$(cat "$CONFIG_DIR/.current-config")
else
    # Fallback: find first .ovpn or .conf file
    CONFIG_PATH=$(find "$CONFIG_DIR" -type f \( -name "*.ovpn" -o -name "*.conf" \) -print -quit)
fi

if [ -z "$CONFIG_PATH" ] || [ ! -f "$CONFIG_PATH" ]; then
    echo "✗ No OpenVPN config file found in $CONFIG_DIR"
    echo "  Please run install_openvpn_cli.sh first or specify SETUP_OPENVPN_CONFIG_PATH"
    exit 1
fi

echo "→ Using config: $CONFIG_PATH"

# Check if OpenVPN is already running
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if ps -p "$OLD_PID" &>/dev/null; then
        echo "→ OpenVPN daemon already running (PID: $OLD_PID)"
        echo "  Stopping existing process..."
        sudo kill "$OLD_PID" 2>/dev/null || true
        sleep 2
    fi
    rm -f "$PID_FILE"
fi

# Start OpenVPN daemon with sudo
echo "→ Starting OpenVPN daemon..."
echo "  This requires administrator privileges."

# Create log file
: > "$LOG_FILE"

# Start OpenVPN in background and capture PID
# Use --daemon to run as background service, but start without --daemon first to get PID
sudo openvpn --config "$CONFIG_PATH" \
    --daemon \
    --writepid "$PID_FILE" \
    --log "$LOG_FILE" \
    --verb 3

# Wait a moment for daemon to start and write PID
sleep 2

# Verify PID file was created
if [ ! -f "$PID_FILE" ]; then
    echo "✗ Failed to start OpenVPN daemon (PID file not created)"
    echo "  Check log file: $LOG_FILE"
    tail -n 20 "$LOG_FILE" 2>/dev/null || true
    exit 1
fi

OPENVPN_PID=$(cat "$PID_FILE")
echo "✓ OpenVPN daemon started (PID: $OPENVPN_PID)"

# Poll for VPN connectivity
echo "→ Waiting for VPN connection (polling $VPN_TARGET:$VPN_PORT every ${RETRY_INTERVAL}s, max ${MAX_ATTEMPTS} attempts)..."

for i in $(seq 1 $MAX_ATTEMPTS); do
    if nc -z -w 3 "$VPN_TARGET" "$VPN_PORT" 2>/dev/null; then
        echo "✓ VPN connected successfully ($VPN_TARGET:$VPN_PORT is reachable)"
        echo "✓ OpenVPN daemon running in background (PID: $OPENVPN_PID)"
        echo ""
        echo "To disconnect, run: disconnect_vpn_cli.sh"
        echo "To view logs, run: tail -f $LOG_FILE"
        exit 0
    fi

    # Check if OpenVPN process is still alive
    if ! ps -p "$OPENVPN_PID" &>/dev/null; then
        echo "✗ OpenVPN daemon unexpectedly stopped"
        echo "  Last 20 lines of log:"
        tail -n 20 "$LOG_FILE" 2>/dev/null || true
        rm -f "$PID_FILE"
        exit 1
    fi

    echo "  Attempt $i/$MAX_ATTEMPTS — not yet reachable, retrying in ${RETRY_INTERVAL}s..."
    sleep $RETRY_INTERVAL
done

echo "✗ VPN connection timeout after $((MAX_ATTEMPTS * RETRY_INTERVAL)) seconds"
echo "  OpenVPN daemon is running but $VPN_TARGET:$VPN_PORT not reachable"
echo "  Check log file: $LOG_FILE"
echo "  To stop the daemon, run: disconnect_vpn_cli.sh"
exit 1
