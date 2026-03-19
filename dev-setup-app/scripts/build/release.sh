#!/usr/bin/env bash
# =============================================================================
# release.sh — Trigger a cross-platform build from ANY machine
#              (WSL / macOS / Linux)
#
# Usage:
#   bash release.sh                    # prompts for version + targets
#   bash release.sh 1.2.3              # build all platforms, publish release
#   bash release.sh 1.2.3 all          # same
#   bash release.sh 1.2.3 macos-only   # macOS DMG only
#   bash release.sh 1.2.3 windows-only # Windows MSI/EXE only
#   bash release.sh 1.2.3 linux-only   # Linux AppImage/deb only
#   bash release.sh 1.2.3 all --no-release  # build but don't publish a release
#
# Requirements:  git, internet access
# Auto-installs: GitHub CLI (gh) if not present
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# ─── Colours ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${CYAN}  ➜  $*${NC}"; }
success() { echo -e "${GREEN}  ✓  $*${NC}"; }
warn()    { echo -e "${YELLOW}  ⚠  $*${NC}"; }
error()   { echo -e "${RED}  ✗  $*${NC}"; exit 1; }

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║        Dev Setup — Universal Release Tool         ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Running on: ${CYAN}$(uname -s) $(uname -m)${NC}"
echo ""

# ─── Parse args ──────────────────────────────────────────────────────────────
VERSION="${1:-}"
PLATFORMS="${2:-all}"
PUBLISH="true"
if [[ "${*}" == *"--no-release"* ]]; then PUBLISH="false"; fi

# ─── Prompt for version if not given ─────────────────────────────────────────
if [ -z "$VERSION" ]; then
    # Suggest next patch version based on latest tag
    LAST_TAG=$(git -C "$REPO_ROOT" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "0.0.0")
    IFS='.' read -r MAJOR MINOR PATCH <<< "$LAST_TAG"
    SUGGESTED="${MAJOR}.${MINOR}.$((PATCH + 1))"
    echo -e "  Last release: ${YELLOW}v${LAST_TAG}${NC}"
    read -rp "  Enter version to release [${SUGGESTED}]: " VERSION
    VERSION="${VERSION:-$SUGGESTED}"
fi

# Strip leading 'v' if user typed it
VERSION="${VERSION#v}"

# ─── Prompt for platforms if not given via arg ────────────────────────────────
if [ "$#" -eq 0 ]; then
    echo ""
    echo "  Which platforms do you want to build?"
    echo "    1) all          — macOS DMG + Windows MSI/EXE + Linux AppImage"
    echo "    2) macos-only   — macOS DMG only"
    echo "    3) windows-only — Windows MSI + NSIS installer only"
    echo "    4) linux-only   — Linux AppImage + deb only"
    read -rp "  Choice [1]: " PLAT_CHOICE
    case "${PLAT_CHOICE:-1}" in
        2) PLATFORMS="macos-only" ;;
        3) PLATFORMS="windows-only" ;;
        4) PLATFORMS="linux-only" ;;
        *) PLATFORMS="all" ;;
    esac

    echo ""
    read -rp "  Publish as a GitHub Release? [Y/n]: " PUB_CHOICE
    [[ "${PUB_CHOICE:-Y}" =~ ^[Nn] ]] && PUBLISH="false" || PUBLISH="true"
fi

TAG="v${VERSION}"

echo ""
echo -e "  ${BOLD}Build plan:${NC}"
echo -e "    Version   : ${GREEN}${TAG}${NC}"
echo -e "    Platforms : ${GREEN}${PLATFORMS}${NC}"
echo -e "    Publish   : ${GREEN}${PUBLISH}${NC}"
echo ""

# ─── 1. Check git state ───────────────────────────────────────────────────────
info "Checking git state..."

cd "$REPO_ROOT"

if ! git remote get-url origin &>/dev/null; then
    error "No git remote 'origin' found.\n\n  Add your GitHub repo first:\n    git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO.git\n    git push -u origin master"
fi

REMOTE_URL=$(git remote get-url origin)
success "Remote: $REMOTE_URL"

# Warn about uncommitted changes
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    warn "You have uncommitted changes. Committing everything now..."
    git add -A
    git commit -m "chore: prepare release ${TAG}" || true
fi

# Push current branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
info "Pushing branch '${CURRENT_BRANCH}' to origin..."
git push origin "$CURRENT_BRANCH"
success "Branch pushed"

# ─── 2. Create and push the tag ───────────────────────────────────────────────
info "Creating tag ${TAG}..."

if git rev-parse "$TAG" &>/dev/null; then
    warn "Tag ${TAG} already exists."
    read -rp "  Delete and recreate it? [y/N]: " RETAG
    if [[ "${RETAG:-N}" =~ ^[Yy] ]]; then
        git tag -d "$TAG"
        git push origin ":refs/tags/${TAG}" 2>/dev/null || true
    else
        echo "  Aborting. Choose a different version."
        exit 1
    fi
fi

git tag -a "$TAG" -m "Release ${TAG}"
git push origin "$TAG"
success "Tag ${TAG} pushed — GitHub Actions build triggered"

# ─── 3. Install gh CLI if needed ─────────────────────────────────────────────
install_gh() {
    info "Installing GitHub CLI (gh)..."
    OS="$(uname -s)"
    if [ "$OS" = "Darwin" ]; then
        if command -v brew &>/dev/null; then
            brew install gh
        else
            error "Install gh manually: https://cli.github.com/"
        fi
    else
        # Linux / WSL
        type -p curl >/dev/null || sudo apt-get install -y curl
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
            | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
        sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
            | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
        sudo apt-get update -q
        sudo apt-get install -y gh
    fi
    success "gh CLI installed"
}

if ! command -v gh &>/dev/null; then
    install_gh
fi

# ─── 4. Authenticate gh if needed ────────────────────────────────────────────
if ! gh auth status &>/dev/null; then
    echo ""
    warn "GitHub CLI not authenticated. Opening browser login..."
    echo "  (If browser doesn't open, follow the URL shown)"
    gh auth login --web --hostname github.com
fi

# ─── 5. Watch the workflow run ────────────────────────────────────────────────
echo ""
info "Waiting for GitHub Actions to start..."
sleep 8   # give GitHub a moment to register the tag push

# Get the run ID for our tag
RUN_ID=""
for i in $(seq 1 15); do
    RUN_ID=$(gh run list \
        --workflow build.yml \
        --limit 5 \
        --json databaseId,headBranch,status \
        --jq ".[] | select(.headBranch == \"${TAG}\") | .databaseId" \
        2>/dev/null | head -1 || true)
    if [ -n "$RUN_ID" ]; then break; fi
    sleep 5
done

if [ -z "$RUN_ID" ]; then
    warn "Could not find the workflow run ID. Check status manually:"
    echo ""
    REPO_PATH=$(echo "$REMOTE_URL" | sed -E 's|https://github.com/||;s|git@github.com:||;s|\.git$||')
    echo -e "    ${BLUE}https://github.com/${REPO_PATH}/actions${NC}"
    echo ""
else
    success "Found run ID: ${RUN_ID}"
    echo ""
    info "Streaming live build output (Ctrl+C to detach — build continues):"
    echo ""
    gh run watch "$RUN_ID" --exit-status || true

    echo ""
    echo -e "${BOLD}══════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ✅ All builds complete!${NC}"
    echo ""

    REPO_PATH=$(echo "$REMOTE_URL" | sed -E 's|https://github.com/||;s|git@github.com:||;s|\.git$||')

    if [ "$PUBLISH" = "true" ]; then
        echo -e "  📦 Download installers from the GitHub Release:"
        echo -e "    ${BLUE}https://github.com/${REPO_PATH}/releases/tag/${TAG}${NC}"
    else
        echo -e "  📦 Download artifacts from the Actions run:"
        echo -e "    ${BLUE}https://github.com/${REPO_PATH}/actions/runs/${RUN_ID}${NC}"
    fi
    echo -e "${BOLD}══════════════════════════════════════════════════${NC}"
fi
