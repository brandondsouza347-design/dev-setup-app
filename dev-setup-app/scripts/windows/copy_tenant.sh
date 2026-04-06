#!/bin/bash
# copy_tenant.sh — Run Django copy_tenant command
set -e

echo "👥 Running copy_tenant command..."
echo ""
echo "🔍 Environment variables:"
env | grep '^SETUP_' || echo "   ⚠️  No SETUP_* variables found!"
echo ""

CLONE_DIR="${SETUP_CLONE_DIR}"
VENV_NAME="${SETUP_VENV_NAME}"
TENANT_NAME="${SETUP_TENANT_NAME}"
CLUSTER_NAME="${SETUP_CLUSTER_NAME}"

echo "📋 Configuration:"
echo "   Clone directory: ${CLONE_DIR:-<NOT SET>}"
echo "   Virtual environment: ${VENV_NAME:-<NOT SET>}"
echo "   Tenant: ${TENANT_NAME:-<NOT SET>}"
echo "   Cluster: ${CLUSTER_NAME:-<NOT SET>}"
echo ""

if [ -z "$CLONE_DIR" ] || [ -z "$VENV_NAME" ] || [ -z "$TENANT_NAME" ] || [ -z "$CLUSTER_NAME" ]; then
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
export DEFERRED_PROCESSING_USES_DRAMATIQ=false
export DJANGO_SETTINGS_MODULE=toogo.dev_settings
export ERC_LOG_LEVEL=DEBUG
export THIRD_PARTY_LOG_LEVEL=WARNING
export KEEP_LOGGING=true
export RUNNING_IN_AWS_CONTAINER=true
# Use AWS credentials from Settings (if provided)
export S3_AWS_ACCESS_KEY="${SETUP_AWS_ACCESS_KEY_ID:-}"
export S3_AWS_SECRET_KEY="${SETUP_AWS_SECRET_ACCESS_KEY:-}"
export SNS_AWS_ACCESS_KEY="${SETUP_AWS_ACCESS_KEY_ID:-}"
export SNS_AWS_SECRET_KEY="${SETUP_AWS_SECRET_ACCESS_KEY:-}"

echo "📋 Running copy_tenant --cluster $CLUSTER_NAME $TENANT_NAME --skip-checks..."
echo "   (This may take several minutes...)"
echo ""

if python manage.py copy_tenant --cluster "$CLUSTER_NAME" "$TENANT_NAME" --skip-checks; then
    echo ""
    echo "✅ SUCCESS: Tenant data copied successfully!"
    echo "   Tenant: $TENANT_NAME"
    echo "   Cluster: $CLUSTER_NAME"
    exit 0
else
    echo ""
    echo "❌ FAILURE: copy_tenant failed"
    exit 1
fi
