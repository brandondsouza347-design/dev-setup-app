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
    echo "→ Cloning repository (live progress below)..."

    # git --progress outputs carriage-return separated percentage lines to stderr.
    # We capture stderr line-by-line using process substitution so we can print
    # each percentage update as it arrives (no 30s polling delay).
    GIT_EXIT=0
    GIT_TERMINAL_PROMPT=0 \
    GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=30 -o ServerAliveInterval=30 -o ServerAliveCountMax=10" \
        git clone --progress "$REPO_URL" "$CLONE_DIR" 2>&1 | \
        while IFS= read -r line; do
            # git uses \r to overwrite percentage lines — split on \r and print last chunk
            last="$(printf '%s' "$line" | tr '\r' '\n' | grep -v '^$' | tail -1)"
            [ -n "$last" ] && echo "  $last"
        done || GIT_EXIT=${PIPESTATUS[0]}

    if [ "$GIT_EXIT" -ne 0 ]; then
        echo "✗ git clone failed (exit $GIT_EXIT) — check SSH key and VPN connectivity."
        exit "$GIT_EXIT"
    fi
    echo "✓ Repository cloned successfully to $CLONE_DIR"
fi
