#!/usr/bin/env bash
# setup_redis.sh — Install Redis via Homebrew and start as a service
set -euo pipefail

echo "==> Redis Setup"

# ─── 1. Install ─────────────────────────────────────────────────────────────

echo "==> Step 1: Installing Redis..."

if command -v redis-server &>/dev/null; then
    echo "✓ Redis already installed: $(redis-server --version)"
else
    brew install redis
    echo "✓ Redis installed"
fi

# ─── 2. Start service ───────────────────────────────────────────────────────

echo "==> Step 2: Starting Redis service..."
brew services start redis
echo "✓ Redis service started"

# ─── 3. Verify ──────────────────────────────────────────────────────────────

echo "==> Step 3: Verifying Redis..."
sleep 2

if redis-cli ping 2>/dev/null | grep -q "PONG"; then
    echo "✓ Redis is responding to PING"
else
    echo "⚠ Redis ping failed — it may need a moment to start"
fi

echo ""
echo "✓ Redis setup complete!"
echo "  Version : $(redis-server --version)"
echo "  Port    : 6379 (default)"
echo ""
echo "  Service commands:"
echo "    Start : brew services start redis"
echo "    Stop  : brew services stop redis"
echo "    CLI   : redis-cli"
