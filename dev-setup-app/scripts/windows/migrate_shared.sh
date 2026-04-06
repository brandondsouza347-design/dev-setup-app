#!/bin/bash
# migrate_shared.sh — Run Django migrate_schemas --shared
set -e

echo "🗄️  Running Django migrate_schemas --shared..."
echo ""
echo "🔍 Environment variables:"
env | grep '^SETUP_' || echo "   ⚠️  No SETUP_* variables found!"
echo ""

CLONE_DIR="${SETUP_CLONE_DIR}"
VENV_NAME="${SETUP_VENV_NAME}"

echo "📋 Configuration:"
echo "   Clone directory: ${CLONE_DIR:-<NOT SET>}"
echo "   Virtual environment: ${VENV_NAME:-<NOT SET>}"
echo ""

if [ -z "$CLONE_DIR" ] || [ -z "$VENV_NAME" ]; then
    echo "❌ FATAL: Required environment variables not set"
    exit 1
fi

# Navigate to project directory
if [ ! -d "$CLONE_DIR" ]; then
    echo "❌ Error: Clone directory '$CLONE_DIR' does not exist"
    exit 1
fi

cd "$CLONE_DIR"

# Check if manage.py exists
if [ ! -f "manage.py" ]; then
    echo "❌ Error: manage.py not found in $CLONE_DIR"
    exit 1
fi

# Activate virtual environment via pyenv
echo "🔧 Activating virtual environment '$VENV_NAME'..."
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"

pyenv activate "$VENV_NAME" 2>/dev/null || {
    echo "❌ Error: Failed to activate virtualenv '$VENV_NAME'"
    exit 1
}

echo "✓ Virtual environment activated"
echo ""

# Set environment variables
export PYTHONUNBUFFERED=1
# Use AWS credentials from Settings (if provided)
export S3_AWS_ACCESS_KEY="${SETUP_AWS_ACCESS_KEY_ID:-}"
export S3_AWS_SECRET_KEY="${SETUP_AWS_SECRET_ACCESS_KEY:-}"
export SNS_AWS_ACCESS_KEY="${SETUP_AWS_ACCESS_KEY_ID:-}"
export SNS_AWS_SECRET_KEY="${SETUP_AWS_SECRET_ACCESS_KEY:-}"

echo "📋 Running migrate_schemas --shared --noinput --fake..."
if python manage.py migrate_schemas --settings=toogo.dev_settings --shared --noinput --fake; then
    echo ""
    echo "✅ SUCCESS: Shared schemas migrated successfully!"
    exit 0
else
    echo ""
    echo "❌ FAILURE: migrate_schemas failed"
    exit 1
fi
