#!/bin/bash
# install_frontend_deps.sh — Install Node.js dependencies for frontend
set -e

echo "📦 Installing frontend dependencies..."
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

# Check if client directory exists
if [ ! -d "client" ]; then
    echo "❌ Error: client directory not found in $CLONE_DIR"
    exit 1
fi

echo "✓ Client directory found"
echo ""

# Activate nvm and use the correct Node version
echo "🔧 Loading nvm and activating Node.js..."
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Use default node version or fallback to 'node'
if nvm use default 2>/dev/null; then
    echo "   Using default Node version"
elif nvm use node 2>/dev/null; then
    echo "   Using 'node' version"
else
    echo "⚠️  Warning: Could not activate nvm, using system node"
fi

echo "   Node: $(node --version 2>/dev/null || echo 'not found')"
echo "   npm: $(npm --version 2>/dev/null || echo 'not found')"
echo ""

# Navigate to client directory
cd client

# Check if node_modules already exists
if [ -d "node_modules" ]; then
    echo "⚠️  node_modules already exists - cleaning and reinstalling..."
    rm -rf node_modules
fi

# Run npm install
echo "📥 Running npm install (this may take several minutes)..."
if npm install 2>&1; then
    echo ""
    echo "✅ SUCCESS: Frontend dependencies installed!"
    echo "   Location: $CLONE_DIR/client/node_modules"
    exit 0
else
    echo ""
    echo "❌ FAILURE: npm install failed"
    echo "   Check error messages above for details"
    exit 1
fi
