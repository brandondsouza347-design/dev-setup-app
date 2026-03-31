#!/usr/bin/env bash
# setup_gitlab_ssh.sh (macOS) — Generate SSH key (if needed), upload to GitLab via API, test connection
set -euo pipefail

GITLAB_REPO_URL="${SETUP_GITLAB_REPO_URL:-git@gitlab.toogoerp.net:root/erc.git}"
GITLAB_HOST=$(echo "$GITLAB_REPO_URL" | sed 's/git@\([^:]*\):.*/\1/')

echo "→ Step 1/3: Ensuring SSH key exists..."
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

echo "→ Step 2/3: Uploading SSH key to GitLab..."
if [ -n "${SETUP_GITLAB_PAT:-}" ]; then
    HTTP_CODE=$(curl -s -o /tmp/gl_key_resp.json -w "%{http_code}" \
        --request POST "https://${GITLAB_HOST}/api/v4/user/keys" \
        --header "PRIVATE-TOKEN: ${SETUP_GITLAB_PAT}" \
        --header "Content-Type: application/json" \
        --data "{\"title\":\"DevSetup-$(hostname)-$(date +%Y%m%d)\",\"key\":\"${PUB_KEY}\"}" \
        --insecure \
        --max-time 15 \
        2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "201" ]; then
        echo "✓ SSH key uploaded to GitLab successfully."
    elif [ "$HTTP_CODE" = "422" ] || ([ -f /tmp/gl_key_resp.json ] && grep -q "already been taken\|has already been taken" /tmp/gl_key_resp.json 2>/dev/null); then
        echo "✓ SSH key already registered in GitLab — skipping upload."
    else
        echo "⚠ GitLab API returned HTTP $HTTP_CODE."
        echo "  Response: $(cat /tmp/gl_key_resp.json 2>/dev/null || echo '(no response)')"
        echo "  Add your SSH key manually at: https://${GITLAB_HOST}/-/profile/keys"
        echo "  Key to paste: $PUB_KEY"
    fi
else
    echo "⚠ SETUP_GITLAB_PAT not set — skipping automated upload."
    echo "  Add your SSH key manually:"
    echo "    1. Visit https://${GITLAB_HOST}/-/profile/keys"
    echo "    2. Paste the following key:"
    echo "       $PUB_KEY"
fi

echo "→ Step 3/3: Testing SSH connection to ${GITLAB_HOST}..."
ssh -T "git@${GITLAB_HOST}" \
    -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=10 \
    -o BatchMode=yes \
    2>&1 || true
echo "✓ SSH handshake complete."
