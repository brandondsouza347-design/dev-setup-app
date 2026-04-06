#!/usr/bin/env bash
# setup_redis_wsl.sh — Install and start Redis inside WSL Ubuntu
# Runs via: wsl bash /path/to/setup_redis_wsl.sh
# WSL Note: Without systemd, uses 'service' command or direct redis-server daemonization
set -euo pipefail

SKIP_INSTALLED="${SETUP_SKIP_INSTALLED:-true}"

echo "==> setup_redis_wsl: checking Redis..."

# ─── Helper: Start Redis with fallback chain ────────────────────────────────
start_redis() {
    echo "  Attempting to start Redis..."

    # Detect redis-server location (handles apt, pyenv, custom installs)
    local redis_bin
    redis_bin="$(which redis-server 2>/dev/null || echo '/usr/bin/redis-server')"
    echo "  Redis binary detected at: $redis_bin"

    # Method 1: Try service command (works with apt-installed redis)
    echo "  Method 1: Trying 'sudo service redis-server start'..."
    if timeout 30 sudo service redis-server start 2>&1; then
        echo "  service redis-server start returned"
        sleep 2
        if redis-cli ping 2>/dev/null | grep -q "PONG"; then
            echo "✓ Redis started successfully via service command"
            return 0
        fi
    fi

    # Method 2: Try direct daemonization (works in WSL without systemd)
    echo "  Method 2: Trying direct daemonization..."
    if "$redis_bin" --daemonize yes 2>&1; then
        echo "  redis-server --daemonize yes executed"
        sleep 2
        if redis-cli ping 2>/dev/null | grep -q "PONG"; then
            echo "✓ Redis started successfully via direct daemonization"
            return 0
        fi
    fi

    # Method 3: Try with explicit config file
    if [ -f /etc/redis/redis.conf ]; then
        echo "  Method 3: Trying with explicit config..."
        if "$redis_bin" /etc/redis/redis.conf --daemonize yes 2>&1; then
            echo "  redis-server /etc/redis/redis.conf --daemonize yes executed"
            sleep 2
            if redis-cli ping 2>/dev/null | grep -q "PONG"; then
                echo "✓ Redis started successfully with config file"
                return 0
            fi
        fi
    fi

    echo "  WARNING: All Redis startup methods failed"
    return 1
}

# ─── Check if already installed ─────────────────────────────────────────────
if [ "$SKIP_INSTALLED" = "true" ] && command -v redis-cli &>/dev/null; then
    REDIS_VER="$(redis-cli --version 2>/dev/null | awk '{print $2}')"
    echo "✓ Redis $REDIS_VER already installed — checking service..."

    # Check if Redis is already running (process-based check + connectivity)
    if pgrep -x redis-server >/dev/null 2>&1; then
        echo "✓ Redis process is running (PID: $(pgrep -x redis-server | head -1))"
        if redis-cli ping 2>/dev/null | grep -q "PONG"; then
            echo "✓ Redis is responding to PING"
            # Verify port is listening
            if ss -ltn 2>/dev/null | grep -q ':6379 '; then
                echo "✓ Port 6379 is listening"
            fi
            echo "✓ Redis is healthy — skipping all startup procedures"
            exit 0
        else
            echo "  Warning: Redis process exists but not responding to PING"
        fi
    fi

    # Not running or not responding — attempt to start
    echo "  Redis not running properly — starting..."
    if start_redis; then
        echo "✓ Redis is now running"
    else
        echo "  ERROR: Failed to start Redis after trying all methods"
        echo "  Checking diagnostics..."
        sudo service redis-server status 2>&1 || true
        ss -ltnp 2>/dev/null | grep 6379 || echo "  Port 6379 is not listening"
        pgrep -a redis-server || echo "  No redis-server process found"
    fi
    exit 0
elif command -v redis-cli &>/dev/null; then
    REDIS_VER="$(redis-cli --version 2>/dev/null | awk '{print $2}')"
    echo "→ Redis $REDIS_VER already installed but SKIP_INSTALLED=false — restarting..."
    # Kill existing process if running
    if pgrep -x redis-server >/dev/null 2>&1; then
        echo "  Stopping existing Redis process..."
        pkill -x redis-server 2>/dev/null || true
        sleep 2
    fi
    # Restart Redis
    if start_redis; then
        echo "✓ Redis restarted successfully"
    else
        echo "  WARNING: Redis restart failed"
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
if start_redis; then
    echo "✓ Redis startup completed successfully"
else
    echo "  ERROR: Redis startup failed"
fi

# ─── Verify with retry ───────────────────────────────────────────────────────
echo "==> Step 4: Verification..."
echo "  Polling redis-cli ping (max 10s)..."
i=0
while [ $i -lt 5 ]; do
    if redis-cli ping 2>/dev/null | grep -q "PONG"; then
        echo "✓ Redis is running and responding to PING"
        # Show listening port
        if ss -ltn 2>/dev/null | grep -q ':6379 '; then
            echo "✓ Redis is listening on port 6379"
        fi
        # Show process info
        if pgrep -x redis-server >/dev/null 2>&1; then
            echo "✓ Redis process: PID $(pgrep -x redis-server | head -1)"
        fi
        break
    fi
    echo "  Attempt $((i+1))/5: not ready yet, waiting 2s..."
    sleep 2
    i=$((i + 1))
done

if ! redis-cli ping 2>/dev/null | grep -q "PONG"; then
    echo "  ERROR: Redis did not respond to PING after startup"
    echo "  Checking service status..."
    sudo service redis-server status 2>&1 || true
    echo "  Checking if port 6379 is in use..."
    ss -ltnp 2>/dev/null | grep 6379 || echo "  Port 6379 is not listening"
    echo "  Checking for redis-server process..."
    pgrep -a redis-server || echo "  No redis-server process found"
    echo "  Last 20 lines of Redis log (if available)..."
    sudo tail -20 /var/log/redis/redis-server.log 2>/dev/null || echo "  No Redis log found"
    exit 1
fi

echo ""
echo "✓ Redis setup complete"
echo "  Version: $(redis-cli --version)"
