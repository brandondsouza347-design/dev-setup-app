#!/usr/bin/env bash
# setup_postgres_wsl.sh — Install and configure PostgreSQL inside WSL Ubuntu
# Runs via: wsl bash /path/to/setup_postgres_wsl.sh
set -euo pipefail

PG_PASSWORD="${SETUP_POSTGRES_PASSWORD:-postgres}"
PG_DB="${SETUP_POSTGRES_DB:-toogo_pos}"

echo "==> setup_postgres_wsl: checking PostgreSQL..."

# ─── Check if already installed ─────────────────────────────────────────────
if command -v psql &>/dev/null; then
    PG_VER="$(psql --version 2>/dev/null | awk '{print $3}')"
    echo "✓ PostgreSQL $PG_VER already installed — checking service..."

    # Ensure it's running
    if ! pg_isready -q 2>/dev/null; then
        echo "  PostgreSQL not running — starting..."
        sudo service postgresql start
    fi
    echo "✓ PostgreSQL is running — skipping install"
    exit 0
fi

# ─── Install ─────────────────────────────────────────────────────────────────
echo "==> Step 1: Installing PostgreSQL..."
sudo apt-get update -q
sudo apt-get install -y -q postgresql postgresql-contrib
echo "✓ PostgreSQL installed"

# ─── Start service ───────────────────────────────────────────────────────────
echo "==> Step 2: Starting PostgreSQL service..."
sudo service postgresql start
echo "✓ PostgreSQL started"

# ─── Set postgres superuser password ─────────────────────────────────────────
echo "==> Step 3: Configuring postgres role password..."
sudo -u postgres psql -c "ALTER USER postgres PASSWORD '${PG_PASSWORD}';" 2>/dev/null && \
    echo "✓ postgres role password set" || \
    echo "  Warning: could not set postgres role password (may already be set)"

# ─── Create project database ──────────────────────────────────────────────────
echo "==> Step 4: Creating database '$PG_DB'..."
DB_EXISTS="$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${PG_DB}'" 2>/dev/null || echo '')"
if [ "$DB_EXISTS" = "1" ]; then
    echo "✓ Database '$PG_DB' already exists — skipping"
else
    sudo -u postgres createdb "$PG_DB"
    echo "✓ Database '$PG_DB' created"
fi

# ─── Verify ──────────────────────────────────────────────────────────────────
echo "==> Step 5: Verification..."
sudo -u postgres psql -c "\l" 2>/dev/null | grep "$PG_DB" && echo "✓ Database visible in PostgreSQL" || true
echo ""
echo "✓ PostgreSQL setup complete"
echo "  Version : $(psql --version)"
echo "  Database: $PG_DB"
