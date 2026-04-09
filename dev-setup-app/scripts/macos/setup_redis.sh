#!/usr/bin/env bash
# setup_redis.sh — Install Redis via Homebrew and start as a service
set -euo pipefail

# Ensure Homebrew is in PATH
if ! command -v brew &>/dev/null; then
    if [ -x "/usr/local/bin/brew" ]; then
        export PATH="/usr/local/bin:$PATH"
    elif [ -x "/opt/homebrew/bin/brew" ]; then
        export PATH="/opt/homebrew/bin:$PATH"
    fi
fi

SKIP_INSTALLED="${SETUP_SKIP_INSTALLED:-true}"

echo "==> Redis Setup"

# ─── Check if already running ───────────────────────────────────────────────

if [ "$SKIP_INSTALLED" = "true" ] && pgrep -x redis-server >/dev/null 2>&1; then
    if redis-cli ping 2>/dev/null | grep -q "PONG"; then
        echo "✓ Redis is already running and responding to PING"
        REDIS_PID=$(pgrep -x redis-server)
        echo "   PID: $REDIS_PID"
        echo ""
        echo "✓ Redis setup complete (already running)"
        exit 0
    fi
fi

# Also check if port 6379 is in use
if [ "$SKIP_INSTALLED" = "true" ] && lsof -Pi :6379 -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "✓ Redis appears to be running (port 6379 in use)"
    echo "   Skipping setup to avoid disruption"
    exit 0
fi

# ─── 1. Install ─────────────────────────────────────────────────────────────

echo "==> Step 1: Installing Redis..."

if [ "$SKIP_INSTALLED" = "true" ] && command -v redis-server &>/dev/null; then
    echo "✓ Redis already installed: $(redis-server --version)"
elif command -v redis-server &>/dev/null; then
    echo "→ Redis already installed but SKIP_INSTALLED=false — upgrading..."
    brew upgrade redis 2>/dev/null || brew install redis
    echo "✓ Redis upgraded: $(redis-server --version)"
else
    brew install redis
    echo "✓ Redis installed"
fi

# ─── 2. Start service ───────────────────────────────────────────────────────

echo "==> Step 2: Starting Redis service..."

# Check if already running before attempting start
if pgrep -x redis-server >/dev/null 2>&1 && redis-cli ping 2>/dev/null | grep -q "PONG"; then
    echo "✓ Redis already running"
    REDIS_PID=$(pgrep -x redis-server)
    echo "   PID: $REDIS_PID"
else
    brew services start redis
    echo "✓ Redis service started"
fi

# ─── 3. Verify ──────────────────────────────────────────────────────────────

echo "==> Step 3: Verifying Redis..."

# Retry verification with timeout
for i in {1..5}; do
    if redis-cli ping 2>/dev/null | grep -q "PONG"; then
        echo "✓ Redis is responding to PING (after ${i}s)"
        REDIS_PID=$(pgrep -x redis-server 2>/dev/null || echo "unknown")
        echo "   PID: $REDIS_PID"
        break
    fi
    if [ "$i" -lt 5 ]; then
        sleep 1
    else
        echo "⚠ Redis ping verification timed out — it may need more time to start"
    fi
done

echo ""
echo "✓ Redis setup complete!"
echo "  Version : $(redis-server --version)"
echo "  Port    : 6379 (default)"
echo ""
echo "  Service commands:"
echo "    Start : brew services start redis"
echo "    Stop  : brew services stop redis"
echo "    CLI   : redis-cli"
