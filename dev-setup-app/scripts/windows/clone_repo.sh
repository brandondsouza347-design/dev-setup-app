#!/usr/bin/env bash
# clone_repo.sh — Clone or update the ERC repository in WSL
set -euo pipefail

REPO_URL="${SETUP_GITLAB_REPO_URL:-git@gitlab.toogoerp.net:root/erc.git}"
CLONE_DIR="${SETUP_CLONE_DIR:-/home/ubuntu/VsCodeProjects/erc}"

echo "→ Repository: $REPO_URL"
echo "→ Destination: $CLONE_DIR"

# Pre-scan SSH host key to prevent interactive yes/no prompt (common cause of hang)
GITLAB_HOST=$(echo "$REPO_URL" | sed 's/git@\([^:]*\):.*/\1/')
echo "→ Pre-scanning SSH host key for $GITLAB_HOST..."
mkdir -p ~/.ssh && chmod 700 ~/.ssh
ssh-keyscan -H "$GITLAB_HOST" >> ~/.ssh/known_hosts 2>/dev/null || true
echo "✓ Host key accepted for $GITLAB_HOST."

mkdir -p "$(dirname "$CLONE_DIR")"

# Validate repo: .git dir must exist AND have at least one commit (catches partial/broken clones)
REPO_VALID=false
if [ -d "$CLONE_DIR/.git" ]; then
    if git -C "$CLONE_DIR" rev-parse --verify HEAD >/dev/null 2>&1; then
        REPO_VALID=true
    else
        echo "⚠ Found $CLONE_DIR/.git but repo has no commits — removing and re-cloning..."
        rm -rf "$CLONE_DIR"
    fi
fi

if $REPO_VALID; then
    echo "✓ Repository already cloned at $CLONE_DIR"
    echo "→ Running git pull to update..."

    # Stash any local changes so pull can proceed cleanly
    STASH_OUT=$(git -C "$CLONE_DIR" stash 2>&1 || true)
    STASHED=false
    if echo "$STASH_OUT" | grep -q 'Saved working directory'; then
        STASHED=true
        echo "  Local changes stashed: $STASH_OUT"
    fi

    GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes" \
        git -C "$CLONE_DIR" pull --ff-only 2>&1 || {
        echo "⚠ git pull failed (non-fast-forward or other error). Leaving repo as-is."
    }

    # Restore stashed changes
    if $STASHED; then
        echo "  Restoring stashed local changes..."
        git -C "$CLONE_DIR" stash pop 2>&1 || echo "  ⚠ Stash pop had conflicts — changes left in stash."
    fi

    echo "✓ Repository is up to date."
else
    echo "→ Cloning repository (progress reported every 30s)..."

    # Clone in background so we can print periodic progress
    GIT_LOG=$(mktemp)
    GIT_TERMINAL_PROMPT=0 \
    GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes" \
        git clone --progress "$REPO_URL" "$CLONE_DIR" >"$GIT_LOG" 2>&1 &
    GIT_PID=$!

    ELAPSED=0
    while kill -0 "$GIT_PID" 2>/dev/null; do
        sleep 30
        ELAPSED=$((ELAPSED + 30))
        RESOLVING=$(grep -oE 'Resolving deltas:[[:space:]]+[0-9]+%[^,]*' "$GIT_LOG" 2>/dev/null | tail -1 || true)
        PROGRESS=$(grep -oE 'Receiving objects:[[:space:]]+[0-9]+%[^,]*' "$GIT_LOG" 2>/dev/null | tail -1 || true)
        if [ -n "$RESOLVING" ]; then
            echo "  [${ELAPSED}s] $RESOLVING"
        elif [ -n "$PROGRESS" ]; then
            echo "  [${ELAPSED}s] $PROGRESS"
        else
            echo "  [${ELAPSED}s] Cloning in progress..."
        fi
    done

    wait "$GIT_PID"
    GIT_EXIT=$?
    cat "$GIT_LOG"
    rm -f "$GIT_LOG"

    if [ "$GIT_EXIT" -ne 0 ]; then
        echo "✗ git clone failed (exit code $GIT_EXIT). Check SSH key and VPN connectivity."
        exit "$GIT_EXIT"
    fi
    echo "✓ Repository cloned successfully to $CLONE_DIR"
fi
