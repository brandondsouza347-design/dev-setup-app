#!/usr/bin/env bash
# setup_postgres.sh — Install PostgreSQL 16 via Homebrew, initialise cluster, create roles and databases
set -euo pipefail

# Ensure Homebrew is in PATH
if ! command -v brew &>/dev/null; then
    if [ -x "/usr/local/bin/brew" ]; then
        export PATH="/usr/local/bin:$PATH"
    elif [ -x "/opt/homebrew/bin/brew" ]; then
        export PATH="/opt/homebrew/bin:$PATH"
    fi
fi

PG_VERSION="16"
PG_PASSWORD="${SETUP_POSTGRES_PASSWORD:-postgres}"
PG_DB="${SETUP_POSTGRES_DB:-dev_db}"
SKIP_INSTALLED="${SETUP_SKIP_INSTALLED:-true}"
CURRENT_USER="$(whoami)"
ARCH="$(uname -m)"

# ─── Detect Homebrew prefix ─────────────────────────────────────────────────

if [ "$ARCH" = "arm64" ]; then
    BREW_PREFIX="/opt/homebrew"
else
    # Try default, then user-space
    if [ -d "/usr/local/opt/postgresql@${PG_VERSION}" ]; then
        BREW_PREFIX="/usr/local"
    else
        BREW_PREFIX="${HOME}/homebrew/.linuxbrew"
    fi
fi

PG_BIN="$BREW_PREFIX/opt/postgresql@${PG_VERSION}/bin"
PG_DATA="$BREW_PREFIX/var/postgresql@${PG_VERSION}"

echo "==> PostgreSQL Setup"
echo "    Version   : $PG_VERSION"
echo "    Brew      : $BREW_PREFIX"
echo "    Binaries  : $PG_BIN"
echo "    Data dir  : $PG_DATA"

# ─── Check if already running ───────────────────────────────────────────────

if [ "$SKIP_INSTALLED" = "true" ] && command -v "$PG_BIN/pg_isready" &>/dev/null && "$PG_BIN/pg_isready" -q 2>/dev/null; then
    echo "✓ PostgreSQL is already running and accepting connections"
    echo "   $("$PG_BIN/pg_isready")"
    echo ""
    echo "✓ PostgreSQL setup complete (already running)"
    exit 0
fi

# Also check if port 5432 is in use
if [ "$SKIP_INSTALLED" = "true" ] && lsof -Pi :5432 -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "✓ PostgreSQL appears to be running (port 5432 in use)"
    echo "   Skipping setup to avoid disruption"
    exit 0
fi

# ─── 1. Install PostgreSQL ──────────────────────────────────────────────────

echo ""
echo "==> Step 1: Installing postgresql@${PG_VERSION} via Homebrew..."

if command -v "$PG_BIN/psql" &>/dev/null; then
    echo "✓ PostgreSQL $PG_VERSION already installed"
else
    brew install "postgresql@${PG_VERSION}"
    echo "✓ PostgreSQL $PG_VERSION installed"
fi

# Add to PATH
if ! echo "$PATH" | grep -q "$PG_BIN"; then
    export PATH="$PG_BIN:$PATH"
    echo "export PATH=\"$PG_BIN:\$PATH\"" >> ~/.zshrc
    echo "   Added $PG_BIN to PATH in ~/.zshrc"
fi

# ─── 2. Initialise database cluster ─────────────────────────────────────────

echo ""
echo "==> Step 2: Initialising database cluster..."

if [ -f "$PG_DATA/PG_VERSION" ]; then
    echo "✓ Database cluster already initialised at $PG_DATA"
else
    echo "   Running initdb..."
    "$PG_BIN/initdb" --locale=en_US.UTF-8 -E UTF8 "$PG_DATA"
    echo "✓ Database cluster initialised"
fi

# ─── 3. Start PostgreSQL service ─────────────────────────────────────────────

echo ""
echo "==> Step 3: Starting PostgreSQL service..."

# Check if already running before attempting start
if "$PG_BIN/pg_isready" -q 2>/dev/null; then
    echo "✓ PostgreSQL already running and ready"
else
    # Clean up stale PIDs that might block startup
    if [ -f "$PG_DATA/postmaster.pid" ]; then
        PID=$(head -n 1 "$PG_DATA/postmaster.pid" 2>/dev/null || echo "")
        if [ -n "$PID" ] && ! kill -0 "$PID" 2>/dev/null; then
            echo "   Removing stale PID file..."
            rm -f "$PG_DATA/postmaster.pid"
        fi
    fi

    # Try brew services first; fall back to pg_ctl if LaunchAgent issues
    if brew services start "postgresql@${PG_VERSION}" 2>&1 | grep -qi "error\|bootstrap failed"; then
        echo "⚠ brew services failed, trying pg_ctl directly..."
        rm -f "$HOME/Library/LaunchAgents/homebrew.mxcl.postgresql@${PG_VERSION}.plist" 2>/dev/null || true
        LC_ALL="en_US.UTF-8" "$PG_BIN/pg_ctl" -D "$PG_DATA" -l "$PG_DATA/server.log" start || true
    else
        echo "✓ PostgreSQL service started via brew services"
    fi

    # Wait for server to be ready with retry logic
    echo "   Waiting for PostgreSQL to accept connections..."
    for i in {1..15}; do
        if "$PG_BIN/pg_isready" -q 2>/dev/null; then
            echo "✓ PostgreSQL is ready (after ${i}s)"
            break
        fi
        if [ "$i" -eq 15 ]; then
            echo "⚠ PostgreSQL may need more time to start"
        fi
        sleep 1
    done
fi

# Confirm readiness
sleep 3

# ─── 4. Create roles and databases ──────────────────────────────────────────

echo ""
echo "==> Step 4: Creating PostgreSQL roles and databases..."

# Create postgres superuser role if it doesn't exist
"$PG_BIN/psql" -U "$CURRENT_USER" -d postgres -tc \
    "SELECT 1 FROM pg_roles WHERE rolname = 'postgres'" \
    2>/dev/null | grep -q 1 \
    || "$PG_BIN/psql" -U "$CURRENT_USER" -d postgres -c \
       "CREATE ROLE postgres WITH LOGIN SUPERUSER PASSWORD '${PG_PASSWORD}';" \
    && echo "✓ Role 'postgres' created" \
    || echo "  Role 'postgres' already exists"

# Create a database for the current macOS user (needed for default psql connections)
"$PG_BIN/psql" -U "$CURRENT_USER" -d postgres -tc \
    "SELECT 1 FROM pg_database WHERE datname = '${CURRENT_USER}'" \
    2>/dev/null | grep -q 1 \
    || "$PG_BIN/psql" -U "$CURRENT_USER" -d postgres -c \
       "CREATE DATABASE \"${CURRENT_USER}\";" \
    && echo "✓ Database '${CURRENT_USER}' created" \
    || echo "  Database '${CURRENT_USER}' already exists"

# Create the project database
"$PG_BIN/psql" -U "$CURRENT_USER" -d postgres -tc \
    "SELECT 1 FROM pg_database WHERE datname = '${PG_DB}'" \
    2>/dev/null | grep -q 1 \
    || "$PG_BIN/psql" -U "$CURRENT_USER" -d postgres -c \
       "CREATE DATABASE ${PG_DB} OWNER postgres;" \
    && echo "✓ Database '${PG_DB}' created" \
    || echo "  Database '${PG_DB}' already exists"

# Grant privileges
"$PG_BIN/psql" -U "$CURRENT_USER" -d postgres -c \
    "GRANT ALL PRIVILEGES ON DATABASE ${PG_DB} TO \"${CURRENT_USER}\";" \
    2>/dev/null || true

# ─── 5. Verify ──────────────────────────────────────────────────────────────

echo ""
echo "==> Step 5: Verifying PostgreSQL..."
"$PG_BIN/psql" --version
"$PG_BIN/psql" -U "$CURRENT_USER" -d postgres -c "\l" 2>/dev/null || true

echo ""
echo "✓ PostgreSQL setup complete!"
echo "  Version  : $("$PG_BIN/psql" --version)"
echo "  Data dir : $PG_DATA"
echo "  Connect  : psql -U postgres -d ${PG_DB}"
echo ""
echo "  Service commands:"
echo "    Start : brew services start postgresql@${PG_VERSION}"
echo "    Stop  : brew services stop postgresql@${PG_VERSION}"
echo "    Status: brew services list"
