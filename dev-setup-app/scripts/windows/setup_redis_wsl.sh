#!/usr/bin/env bash
# setup_redis_wsl.sh — Install and start Redis inside WSL Ubuntu
# Runs via: wsl bash /path/to/setup_redis_wsl.sh
set -euo pipefail

echo "==> setup_redis_wsl: checking Redis..."

# ─── Check if already installed ─────────────────────────────────────────────
if command -v redis-cli &>/dev/null; then
    REDIS_VER="$(redis-cli --version 2>/dev/null | awk '{print $2}')"
    echo "✓ Redis $REDIS_VER already installed — checking service..."

    # Ensure it's running
    if redis-cli ping 2>/dev/null | grep -q "PONG"; then
        echo "✓ Redis is running — skipping install"
    else
        echo "  Redis not responding — starting service..."
        sudo service redis-server start
        sleep 1
        redis-cli ping && echo "✓ Redis is now running" || echo "  Warning: Redis started but ping failed"
    fi
    exit 0
fi

# ─── Install ─────────────────────────────────────────────────────────────────
echo "==> Step 1: Installing Redis..."
sudo apt-get update -q
sudo apt-get install -y -q redis-server
echo "✓ Redis installed"

# ─── Configure for development ───────────────────────────────────────────────
echo "==> Step 2: Configuring Redis..."
# Ensure supervised mode is compatible with WSL (no systemd)
REDIS_CONF="/etc/redis/redis.conf"
if [ -f "$REDIS_CONF" ]; then
    sudo sed -i 's/^supervised .*/supervised no/' "$REDIS_CONF"
    echo "  Set supervised=no for WSL compatibility"
fi

# ─── Start service ───────────────────────────────────────────────────────────
echo "==> Step 3: Starting Redis..."
sudo service redis-server start
sleep 1

# ─── Verify ──────────────────────────────────────────────────────────────────
echo "==> Step 4: Verification..."
if redis-cli ping 2>/dev/null | grep -q "PONG"; then
    echo "✓ Redis is running and responding to PING"
else
    echo "  Warning: Redis started but did not respond to PING — may need manual check"
fi

echo ""
echo "✓ Redis setup complete"
echo "  Version: $(redis-cli --version)"
