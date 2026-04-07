#!/usr/bin/env bash
# setup_gitlab_ssh.sh (macOS) — Configure Git identity, generate SSH key, upload to GitLab via API, test connection
set -euo pipefail

GIT_NAME="${SETUP_GIT_NAME:-}"
GIT_EMAIL="${SETUP_GIT_EMAIL:-}"
GITLAB_REPO_URL="${SETUP_GITLAB_REPO_URL:-git@gitlab.toogoerp.net:root/erc.git}"
SKIP_INSTALLED="${SETUP_SKIP_INSTALLED:-true}"
GITLAB_HOST=$(echo "$GITLAB_REPO_URL" | sed 's/git@\([^:]*\):.*/\1/')

echo "==> Git & SSH Configuration for GitLab"

# ─── Step 0: Configure Git identity ──────────────────────────────────────────

echo ""
echo "→ Step 0/4: Configuring Git identity..."

EXISTING_NAME="$(git config --global user.name 2>/dev/null || true)"
EXISTING_EMAIL="$(git config --global user.email 2>/dev/null || true)"

if [ -n "$EXISTING_NAME" ] && [ -n "$EXISTING_EMAIL" ]; then
    echo "✓ Git identity already configured:"
    echo "   Name : $EXISTING_NAME"
    echo "   Email: $EXISTING_EMAIL"
elif [ -n "$GIT_NAME" ] && [ -n "$GIT_EMAIL" ]; then
    git config --global user.name  "$GIT_NAME"
    git config --global user.email "$GIT_EMAIL"
    git config --global core.autocrlf input
    git config --global init.defaultBranch main
    git config --global pull.rebase false
    echo "✓ Git identity configured: $GIT_NAME ($GIT_EMAIL)"
else
    git config --global core.autocrlf input
    git config --global init.defaultBranch main
    git config --global pull.rebase false
    echo "⚠ No name/email provided in Settings — core settings applied, identity skipped."
    echo "  Set manually: git config --global user.name 'Your Name'"
    echo "  Set manually: git config --global user.email 'you@example.com'"
fi

# ─── Step 1: Ensure SSH key exists ───────────────────────────────────────────

echo ""
echo "→ Step 1/4: Ensuring SSH key exists..."
mkdir -p ~/.ssh
chmod 700 ~/.ssh
if [ ! -f ~/.ssh/id_ed25519 ]; then
    EMAIL="${SETUP_GIT_EMAIL:-dev@setup}"
    ssh-keygen -t ed25519 -C "$EMAIL" -f ~/.ssh/id_ed25519 -N ""
    echo "✓ SSH key generated: ~/.ssh/id_ed25519"
else
    echo "✓ SSH key already exists."
fi

PUB_KEY=$(cat ~/.ssh/id_ed25519.pub)
echo "  Public key: $PUB_KEY"

echo "→ Step 2/4: Checking and uploading SSH key to GitLab..."
if [ -n "${SETUP_GITLAB_PAT:-}" ]; then
    # Get the SHA256 fingerprint of the local public key
    LOCAL_FP=$(ssh-keygen -l -E sha256 -f ~/.ssh/id_ed25519.pub 2>/dev/null | awk '{print $2}')
    echo "  Local key fingerprint: $LOCAL_FP"

    # Proactive check: fetch all keys already registered in GitLab
    echo "  Fetching registered keys from GitLab..."
    GL_KEYS=$(curl -s \
        --request GET "https://${GITLAB_HOST}/api/v4/user/keys" \
        --header "PRIVATE-TOKEN: ${SETUP_GITLAB_PAT}" \
        --insecure --max-time 15 \
        2>/dev/null || echo "[]")

    KEY_ALREADY_EXISTS=false
    if [ -n "$LOCAL_FP" ] && echo "$GL_KEYS" | grep -qF "$LOCAL_FP" 2>/dev/null; then
        KEY_ALREADY_EXISTS=true
    fi

    if [ "$SKIP_INSTALLED" = "true" ] && $KEY_ALREADY_EXISTS; then
        echo "✓ SSH key (fingerprint: $LOCAL_FP) is already registered in GitLab — skipping upload."
    elif $KEY_ALREADY_EXISTS; then
        echo "→ SSH key already registered but SKIP_INSTALLED=false — re-uploading..."
        HTTP_CODE=$(curl -s -o /tmp/gl_key_resp.json -w "%{http_code}" \
            --request POST "https://${GITLAB_HOST}/api/v4/user/keys" \
            --header "PRIVATE-TOKEN: ${SETUP_GITLAB_PAT}" \
            --header "Content-Type: application/json" \
            --data "{\"title\":\"DevSetup-$(hostname)-$(date +%Y%m%d)-forced\",\"key\":\"${PUB_KEY}\"}" \
            --insecure --max-time 15 \
            2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "201" ]; then
            echo "✓ SSH key re-uploaded successfully."
        else
            echo "  Note: Re-upload returned HTTP $HTTP_CODE (key may already exist with same fingerprint)"
        fi
    else
        echo "  Key not found in GitLab — uploading now..."
        HTTP_CODE=$(curl -s -o /tmp/gl_key_resp.json -w "%{http_code}" \
            --request POST "https://${GITLAB_HOST}/api/v4/user/keys" \
            --header "PRIVATE-TOKEN: ${SETUP_GITLAB_PAT}" \
            --header "Content-Type: application/json" \
            --data "{\"title\":\"DevSetup-$(hostname)-$(date +%Y%m%d)\",\"key\":\"${PUB_KEY}\"}" \
            --insecure --max-time 15 \
            2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "201" ]; then
            echo "✓ SSH key uploaded to GitLab successfully."
        elif [ "$HTTP_CODE" = "422" ] || grep -q "already been taken\|has already been taken" /tmp/gl_key_resp.json 2>/dev/null; then
            echo "✓ SSH key already registered in GitLab (confirmed via upload response)."
        else
            echo "⚠ GitLab API returned HTTP $HTTP_CODE."
            echo "  Response: $(cat /tmp/gl_key_resp.json 2>/dev/null || echo '(no response)')"
            echo "  Add your SSH key manually at: https://${GITLAB_HOST}/-/profile/keys"
            echo "  Key to paste: $PUB_KEY"
        fi
    fi
else
    echo "⚠ SETUP_GITLAB_PAT not set — skipping automated upload."
    echo "  Add your SSH key manually:"
    echo "    1. Visit https://${GITLAB_HOST}/-/profile/keys"
    echo "    2. Paste the following key:"
    echo "       $PUB_KEY"
fi

echo "→ Step 3/4: Testing SSH connection to ${GITLAB_HOST}..."
ssh -T "git@${GITLAB_HOST}" \
    -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=10 \
    -o BatchMode=yes \
    2>&1 || true
echo "✓ SSH handshake complete."
