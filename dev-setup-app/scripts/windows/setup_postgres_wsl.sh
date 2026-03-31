#!/usr/bin/env bash
# setup_postgres_wsl.sh — Install and configure PostgreSQL inside WSL Ubuntu
# Runs via: wsl bash /path/to/setup_postgres_wsl.sh
set -euo pipefail

PG_PASSWORD="${SETUP_POSTGRES_PASSWORD:-postgres}"
PG_DB="${SETUP_POSTGRES_DB:-toogo_pos}"

# ─── Helpers ─────────────────────────────────────────────────────────────────
# In tar-imported WSL, /run is a tmpfs that is empty on every WSL start.
# PostgreSQL needs /run/postgresql to exist with correct ownership before it
# can create its Unix socket — this is the most common cause of startup hangs.
ensure_pg_socket_dir() {
    local run_dir="/run/postgresql"
    
    # Check if directory exists and has correct ownership
    if [ -d "$run_dir" ]; then
        local owner
        owner="$(stat -c '%U:%G' "$run_dir" 2>/dev/null || echo '')"
        if [ "$owner" = "postgres:postgres" ]; then
            echo "  $run_dir already exists with correct ownership"
            return 0
        fi
        echo "  $run_dir exists but has wrong ownership ($owner) — fixing..."
    fi
    
    # Create or fix the directory with timeout to prevent hangs
    # (mkdir/chown can hang in rare WSL edge cases with filesystem locks)
    if [ ! -d "$run_dir" ]; then
        echo "  Creating $run_dir..."
        if ! timeout 10 sudo mkdir -p "$run_dir" 2>&1; then
            echo "  WARNING: mkdir timed out or failed — attempting to continue anyway"
        fi
    fi
    
    # Set ownership and permissions with timeout
    if [ -d "$run_dir" ]; then
        if timeout 10 sudo chown postgres:postgres "$run_dir" 2>&1 && \
           timeout 10 sudo chmod 775 "$run_dir" 2>&1; then
            echo "  $run_dir configured successfully"
        else
            echo "  WARNING: chown/chmod timed out — attempting to continue anyway"
        fi
    else
        echo "  WARNING: $run_dir does not exist and could not be created"
    fi
    
    # Remove any stale postmaster.pid that would block a fresh startup
    for f in /var/lib/postgresql/*/main/postmaster.pid; do
        if [ -f "$f" ]; then
            timeout 5 sudo rm -f "$f" 2>&1 && echo "  Removed stale $f" || true
        fi
    done
}

start_postgres() {
    ensure_pg_socket_dir

    # Prefer pg_ctlcluster — it is more direct than init.d in non-systemd WSL
    local ver
    ver="$(pg_lsclusters --no-header 2>/dev/null | awk '{print $1}' | head -1 || true)"
    if [ -n "$ver" ]; then
        echo "  Starting via pg_ctlcluster $ver main..."
        # Run with timeout and capture stderr to diagnose hangs
        if timeout 30 sudo pg_ctlcluster "$ver" main start 2>&1; then
            echo "  pg_ctlcluster returned successfully"
        else
            local exit_code=$?
            if [ $exit_code -eq 124 ]; then
                echo "  WARNING: pg_ctlcluster timed out after 30s"
            else
                echo "  WARNING: pg_ctlcluster exited with code $exit_code"
            fi
        fi
    fi

    # Fallback to service if pg_ctlcluster did not bring it up
    if ! pg_isready -q 2>/dev/null; then
        echo "  Falling back to: service postgresql start..."
        if timeout 30 sudo service postgresql start 2>&1; then
            echo "  service postgresql start returned"
        else
            local exit_code=$?
            if [ $exit_code -eq 124 ]; then
                echo "  WARNING: service postgresql start timed out after 30s"
            else
                echo "  WARNING: service postgresql start exited with code $exit_code"
            fi
        fi
    fi

    # Poll until ready — 10 attempts × 2 s = 20 s maximum wait
    echo "  Polling pg_isready (max 20s)..."
    local i=0
    while [ $i -lt 10 ]; do
        if pg_isready -q 2>/dev/null; then
            echo "  PostgreSQL is accepting connections"
            return 0
        fi
        echo "  Attempt $((i+1))/10: not ready yet, waiting 2s..."
        sleep 2
        i=$((i + 1))
    done

    echo "  ERROR: PostgreSQL did not start within 20 seconds."
    echo "  Diagnostic information:"
    echo "  ─────────────────────────────────────────────────────────"
    sudo pg_lsclusters 2>/dev/null || echo "  pg_lsclusters failed"
    echo ""
    if [ -d /var/log/postgresql ]; then
        echo "  Last 20 lines of PostgreSQL log:"
        sudo tail -20 /var/log/postgresql/postgresql-*.log 2>/dev/null || echo "  No logs found"
    else
        echo "  /var/log/postgresql does not exist"
    fi
    echo "  ─────────────────────────────────────────────────────────"
    return 1
}

echo "==> setup_postgres_wsl: checking PostgreSQL..."

# ─── Check if already installed ─────────────────────────────────────────────
if command -v psql &>/dev/null; then
    PG_VER="$(psql --version 2>/dev/null | awk '{print $3}')"
    echo "✓ PostgreSQL $PG_VER already installed — checking service..."

    # Ensure it's running
    if ! pg_isready -q 2>/dev/null; then
        echo "  PostgreSQL not running — starting..."
        start_postgres
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
start_postgres
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
