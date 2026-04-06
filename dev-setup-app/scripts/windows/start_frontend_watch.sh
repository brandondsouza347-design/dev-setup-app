#!/bin/bash
# start_frontend_watch.sh — Build front-end assets for production
set -e

echo "🎨 Building front-end assets..."
echo ""
echo "🔍 Environment variables:"
env | grep '^SETUP_' || echo "   ⚠️  No SETUP_* variables found!"
echo ""

CLONE_DIR="${SETUP_CLONE_DIR}"

echo "📋 Configuration:"
echo "   Clone directory: ${CLONE_DIR:-<NOT SET>}"
echo ""

if [ -z "$CLONE_DIR" ]; then
    echo "❌ FATAL: SETUP_CLONE_DIR environment variable is not set"
    echo "   This should be set by the orchestrator (e.g., /home/ubuntu/VsCodeProjects/erc)"
    echo "   Check Settings screen -> GitLab Configuration -> Clone Directory"
    exit 1
fi

# Navigate to project directory
if [ ! -d "$CLONE_DIR" ]; then
    echo "❌ Error: Clone directory '$CLONE_DIR' does not exist"
    exit 1
fi

cd "$CLONE_DIR"

# Activate nvm and use the correct Node version
echo "🔧 Loading nvm and activating Node.js..."
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

if nvm use default 2>/dev/null; then
    echo "   Using default Node version"
elif nvm use node 2>/dev/null; then
    echo "   Using 'node' version"
else
    echo "⚠️  Warning: Could not activate nvm"
fi

echo "   Node: $(node --version 2>/dev/null || echo 'not found')"
echo "   npm: $(npm --version 2>/dev/null || echo 'not found')"
echo ""

# Check if client directory exists
if [ ! -d "client" ]; then
    echo "❌ Error: client directory not found in $CLONE_DIR"
    exit 1
fi

# Verify node_modules exists
if [ ! -d "client/node_modules" ]; then
    echo "❌ Error: client/node_modules not found"
    echo "   Please run 'Install Frontend Dependencies' step first (Step 23)"
    exit 1
fi

echo "✓ Client directory and node_modules found"
echo ""

# Run npm build (synchronous, waits for completion)
echo "🏗️  Running npm build (this may take several minutes)..."
if npm --prefix ./client run build; then
    echo ""
    echo "✅ SUCCESS: Front-end build completed!"
    echo "   Built files are in: $CLONE_DIR/client/build/"
    exit 0
else
    echo ""
    echo "❌ FAILURE: Front-end build failed"
    echo "   Check error messages above for details"
    exit 1
fi
