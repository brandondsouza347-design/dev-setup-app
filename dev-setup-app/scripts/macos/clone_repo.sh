#!/usr/bin/env bash
# clone_repo.sh (macOS) — Clone or update the ERC repository
set -euo pipefail

REPO_URL="${SETUP_GITLAB_REPO_URL:-git@gitlab.toogoerp.net:root/erc.git}"
CLONE_DIR="${SETUP_CLONE_DIR:-$HOME/VsCodeProjects/erc}"

echo "→ Repository: $REPO_URL"
echo "→ Destination: $CLONE_DIR"

mkdir -p "$(dirname "$CLONE_DIR")"

if [ -d "$CLONE_DIR/.git" ]; then
    echo "✓ Repository already cloned at $CLONE_DIR"
    echo "→ Running git pull to update..."
    git -C "$CLONE_DIR" pull --ff-only 2>&1 || {
        echo "⚠ git pull failed (possible local changes or non-fast-forward). Leaving repo as-is."
    }
    echo "✓ Repository is up to date."
else
    echo "→ Cloning repository (live progress below)..."
    echo "  ℹ For large repositories (1M+ objects), this may take 15-30 minutes"
    echo "  ℹ Progress updates will be shown every 15 seconds if git output is silent"

    # Start background job to print periodic progress updates (every 15 seconds)
    # This prevents the user from thinking the process is stuck during long transfers
    (
        SECONDS_ELAPSED=0
        while true; do
            sleep 15  # 15 seconds
            SECONDS_ELAPSED=$((SECONDS_ELAPSED + 15))
            MINUTES=$((SECONDS_ELAPSED / 60))
            SECS=$((SECONDS_ELAPSED % 60))
            echo "  ⏳ Clone in progress... ${MINUTES}m ${SECS}s elapsed (this is normal for large repos)"
        done
    ) &
    PROGRESS_PID=$!

    # Clone with progress output
    GIT_EXIT=0
    git clone --progress "$REPO_URL" "$CLONE_DIR" 2>&1 | \
        while IFS= read -r line; do
            # git uses \r to overwrite percentage lines — split on \r and print last chunk
            last="$(printf '%s' "$line" | tr '\r' '\n' | grep -v '^$' | tail -1)"
            [ -n "$last" ] && echo "  $last"
        done || GIT_EXIT=${PIPESTATUS[0]}

    # Stop the progress update background job
    kill $PROGRESS_PID 2>/dev/null || true
    wait $PROGRESS_PID 2>/dev/null || true

    if [ "$GIT_EXIT" -ne 0 ]; then
        echo "✗ git clone failed (exit $GIT_EXIT) — check SSH key and network connectivity."
        exit "$GIT_EXIT"
    fi
    echo "✓ Repository cloned successfully to $CLONE_DIR"
fi
