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
        if timeout 30 sudo service redis-server start 2>&1; then
            echo "  service redis-server start returned"
        else
            local exit_code=$?
            if [ $exit_code -eq 124 ]; then
                echo "  WARNING: service start timed out after 30s"
            else
                echo "  WARNING: service start exited with code $exit_code"
            fi
        fi
        sleep 2
        if redis-cli ping 2>/dev/null | grep -q "PONG"; then
            echo "✓ Redis is now running"
        else
            echo "  Warning: Redis started but ping failed — checking status..."
            sudo service redis-server status || true
        fi
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
if timeout 30 sudo service redis-server start 2>&1; then
    echo "  service redis-server start returned"
else
    local exit_code=$?
    if [ $exit_code -eq 124 ]; then
        echo "  WARNING: service start timed out after 30s"
    else
        echo "  WARNING: service start exited with code $exit_code"
    fi
fi
sleep 2

# ─── Verify ──────────────────────────────────────────────────────────────────
echo "==> Step 4: Verification..."
if redis-cli ping 2>/dev/null | grep -q "PONG"; then
    echo "✓ Redis is running and responding to PING"
else
    echo "  ERROR: Redis did not respond to PING after startup"
    echo "  Checking service status..."
    sudo service redis-server status || true
    echo "  Checking if port 6379 is in use..."
    ss -ltnp | grep 6379 || echo "  Port 6379 is not listening"
    echo "  Last 20 lines of Redis log (if available)..."
    sudo tail -20 /var/log/redis/redis-server.log 2>/dev/null || echo "  No Redis log found"
    exit 1
fi

echo ""
echo "✓ Redis setup complete"
echo "  Version: $(redis-cli --version)"
