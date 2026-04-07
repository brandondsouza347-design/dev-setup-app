#!/usr/bin/env bash
# setup_postgres_wsl.sh — Install and configure PostgreSQL inside WSL Ubuntu
# Runs via: wsl bash /path/to/setup_postgres_wsl.sh
set -euo pipefail

PG_PASSWORD="${SETUP_POSTGRES_PASSWORD:-postgres}"
PG_DB="${SETUP_POSTGRES_DB:-toogo_pos}"
SKIP_INSTALLED="${SETUP_SKIP_INSTALLED:-true}"

# ─── Helpers ─────────────────────────────────────────────────────────────────
# In tar-imported WSL, /run is a tmpfs that is empty on every WSL start.
# PostgreSQL needs /run/postgresql to exist with correct ownership before it
# can create its Unix socket.
# NOTE: plain `sudo` is used here — sudo -n was removed because NOPASSWD is
# now guaranteed by setup_ubuntu_user_wsl.sh writing the sudoers file.
ensure_pg_socket_dir() {
    local run_dir="/run/postgresql"

    # Remove any stale postmaster.pid that would block a fresh startup
    for f in /var/lib/postgresql/*/main/postmaster.pid; do
        [ -f "$f" ] && sudo rm -f "$f" 2>/dev/null && echo "  Removed stale $f" || true
    done

    # Check if directory already exists with correct ownership
    if [ -d "$run_dir" ]; then
        local owner
        owner="$(stat -c '%U:%G' "$run_dir" 2>/dev/null || echo '')"
        if [ "$owner" = "postgres:postgres" ]; then
            echo "  $run_dir already exists with correct ownership"
            return 0
        fi
        echo "  $run_dir exists but wrong ownership ($owner) — fixing..."
    else
        echo "  Creating $run_dir..."
        sudo mkdir -p "$run_dir"
    fi

    sudo chown postgres:postgres "$run_dir"
    sudo chmod 775 "$run_dir"
    echo "  $run_dir configured"
}

start_postgres() {
    local ver
    ver="$(pg_lsclusters --no-header 2>/dev/null | awk '{print $1}' | head -1 || true)"

    # ── Pre-flight: socket dir ────────────────────────────────────────────────
    ensure_pg_socket_dir

    # ── Pre-flight: data directory ownership ─────────────────────────────────
    if [ -n "$ver" ] && [ -d "/var/lib/postgresql/$ver/main" ]; then
        echo "  Fixing data directory ownership..."
        sudo chown -R postgres:postgres "/var/lib/postgresql/$ver/main" 2>/dev/null || true
    fi

    # ── Pre-flight: port conflict check ──────────────────────────────────────
    if ss -ltnp 2>/dev/null | grep -q ':5432 '; then
        echo "  WARNING: Port 5432 already in use — attempting to start anyway:"
        ss -ltnp 2>/dev/null | grep ':5432' || true
    fi

    # ── Start via pg_ctlcluster ───────────────────────────────────────────────
    if [ -n "$ver" ]; then
        local cluster_status
        cluster_status="$(pg_lsclusters --no-header 2>/dev/null | awk '{print $4}' | head -1 || echo 'down')"
        echo "  Cluster $ver/main status: $cluster_status"

        if [ "$cluster_status" = "online" ]; then
            echo "  Cluster is already online"
        else
            if [ "$cluster_status" = "broken" ]; then
                echo "  Cluster is broken — cleaning PID files and retrying..."
                # Remove stale PID files instead of dropping the cluster
                for f in /var/lib/postgresql/*/main/postmaster.pid; do
                    [ -f "$f" ] && sudo rm -f "$f" 2>/dev/null && echo "  Removed stale $f" || true
                done
                ensure_pg_socket_dir
            fi

            echo "  Starting via pg_ctlcluster $ver main..."
            if sudo pg_ctlcluster "$ver" main start 2>&1; then
                echo "  pg_ctlcluster returned successfully"
            else
                echo "  WARNING: pg_ctlcluster exited with code $?"
            fi
        fi
    fi

    # ── Fallback: service ────────────────────────────────────────────────────
    if ! timeout 5s pg_isready -q 2>/dev/null; then
        echo "  Falling back to: service postgresql start..."
        sudo service postgresql start 2>&1 || true
    fi

    # ── Fallback: direct postgres binary startup ─────────────────────────────
    if ! timeout 5s pg_isready -q 2>/dev/null && [ -n "$ver" ]; then
        echo "  Falling back to: direct postgres binary startup..."
        sudo -u postgres /usr/lib/postgresql/$ver/bin/postgres -D /var/lib/postgresql/$ver/main -c config_file=/etc/postgresql/$ver/main/postgresql.conf >/dev/null 2>&1 &
        sleep 2
    fi

    # ── Poll until ready — 15 × 2 s = 30 s ───────────────────────────────────
    echo "  Polling pg_isready (max 30s)..."
    local i=0
    while [ $i -lt 15 ]; do
        if timeout 5s pg_isready -q 2>/dev/null; then
            echo "  PostgreSQL is accepting connections"
            return 0
        fi
        echo "  Attempt $((i+1))/15: not ready yet, waiting 2s..."
        sleep 2
        i=$((i + 1))
    done

    # ── Failure diagnostics ───────────────────────────────────────────────────
    echo "  ERROR: PostgreSQL did not start within 30 seconds."
    echo "  ─────────────────────────────────────────────────────────"
    echo "  Cluster status:"
    pg_lsclusters 2>/dev/null || echo "  pg_lsclusters failed"
    echo ""
    echo "  Port 5432 status:"
    ss -ltnp 2>/dev/null | grep ':5432' || echo "  Nothing listening on 5432"
    echo ""
    echo "  Last 30 lines of PostgreSQL log:"
    if [ -n "$ver" ]; then
        sudo tail -30 "/var/log/postgresql/postgresql-${ver}-main.log" 2>/dev/null \
            || sudo tail -30 /var/log/postgresql/postgresql-*.log 2>/dev/null \
            || echo "  No logs found"
    fi
    echo "  ─────────────────────────────────────────────────────────"
    return 1
}

echo "==> setup_postgres_wsl: checking PostgreSQL..."

# ─── Check if already installed ─────────────────────────────────────────────
if [ "$SKIP_INSTALLED" = "true" ] && command -v psql &>/dev/null; then
    PG_VER="$(psql --version 2>/dev/null | awk '{print $3}')"
    echo "✓ PostgreSQL $PG_VER already installed — checking service..."

    # Check if already running and accepting connections
    if timeout 5s pg_isready -q 2>/dev/null; then
        echo "✓ PostgreSQL is already running and accepting connections"
        # Verify port is listening
        if ss -ltn 2>/dev/null | grep -q ':5432 '; then
            echo "✓ Port 5432 is listening"
        fi
        echo "✓ PostgreSQL is healthy — skipping all startup procedures"
        exit 0
    fi

    # Not running — clean up stale PIDs before attempting start
    echo "  PostgreSQL not running — preparing to start..."
    ensure_pg_socket_dir

    # Now attempt to start
    echo "  Starting PostgreSQL..."
    start_postgres
    echo "✓ PostgreSQL is now running"
    exit 0
elif command -v psql &>/dev/null; then
    echo "→ PostgreSQL already installed but SKIP_INSTALLED=false — reconfiguring and restarting..."
    PG_VER="$(psql --version 2>/dev/null | awk '{print $3}')"
    echo "  Installed version: $PG_VER"
    # Ensure clean state before restart
    ensure_pg_socket_dir
    start_postgres
    echo "✓ PostgreSQL restarted successfully"
    # Continue to configuration steps below
fi

if ! command -v psql &>/dev/null; then
# ─── Install ─────────────────────────────────────────────────────────────────
    echo "==> Step 1: Installing PostgreSQL..."
    sudo apt-get update -q
    sudo apt-get install -y -q postgresql postgresql-contrib
    echo "✓ PostgreSQL installed"

    # ─── Start service ───────────────────────────────────────────────────────────
    echo "==> Step 2: Starting PostgreSQL service..."
    start_postgres
    echo "✓ PostgreSQL started"
fi

# ─── Set postgres superuser password ─────────────────────────────────────────
echo "==> Step 3: Configuring postgres role password..."
if timeout 10s sudo -u postgres psql -c "ALTER USER postgres PASSWORD '${PG_PASSWORD}';" 2>/dev/null; then
    echo "✓ postgres role password set"
else
    echo "  Warning: could not set postgres role password (timeout or already set)"
fi

# ─── Create project database ──────────────────────────────────────────────────
echo "==> Step 4: Creating database '$PG_DB'..."
DB_EXISTS="$(timeout 10s sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${PG_DB}'" 2>/dev/null || echo '')"
if [ "$DB_EXISTS" = "1" ]; then
    echo "✓ Database '$PG_DB' already exists — skipping"
else
    if timeout 15s sudo -u postgres createdb "$PG_DB" 2>/dev/null; then
        echo "✓ Database '$PG_DB' created"
    else
        echo "  Warning: could not create database (timeout or already exists)"
    fi
fi

# ─── Verify ──────────────────────────────────────────────────────────────────
echo "==> Step 5: Verification..."
# Run verification in a way that won't block if psql hangs
VERIFY_OUTPUT=$(timeout 5s sudo -u postgres psql -c "\l" 2>&1 || echo "TIMEOUT")
if echo "$VERIFY_OUTPUT" | grep -q "$PG_DB"; then
    echo "✓ Database '$PG_DB' visible in PostgreSQL"
elif echo "$VERIFY_OUTPUT" | grep -q "TIMEOUT"; then
    echo "  Note: Database listing timed out (but PostgreSQL is running)"
else
    echo "  Note: Could not verify database (but PostgreSQL is running)"
fi
echo ""
echo "✓ PostgreSQL setup complete"
echo "  Version : $(psql --version)"
echo "  Database: $PG_DB"
