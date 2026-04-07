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
TENANT_ID="${SETUP_TENANT_ID}"
CLUSTER_NAME="${SETUP_CLUSTER_NAME}"

echo "📋 Configuration:"
echo "   Clone directory: ${CLONE_DIR:-<NOT SET>}"
echo "   Virtual environment: ${VENV_NAME:-<NOT SET>}"
echo "   Tenant Name: ${TENANT_NAME:-<NOT SET>}"
echo "   Tenant ID: ${TENANT_ID:-<NOT SET>}"
echo "   Cluster: ${CLUSTER_NAME:-<NOT SET>}"
echo ""

if [ -z "$CLONE_DIR" ] || [ -z "$VENV_NAME" ] || [ -z "$TENANT_ID" ] || [ -z "$CLUSTER_NAME" ]; then
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

# Verify environment variables after pyenv activation
echo "🔍 Verifying variables after pyenv activation:"
echo "   TENANT_NAME='$TENANT_NAME' (display name)"
echo "   TENANT_ID='$TENANT_ID' (length: ${#TENANT_ID})"
echo "   CLUSTER_NAME='$CLUSTER_NAME' (length: ${#CLUSTER_NAME})"
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

echo "📋 Running copy_tenant with progress tracking..."
echo "   Cluster: $CLUSTER_NAME | Tenant ID: $TENANT_ID"
echo "   (This may take 3+ hours to download tenant data from remote...)"
echo ""

# Copy the progress tracker script to the project directory
TRACKER_SCRIPT="$CLONE_DIR/track_copy_tenant.py"
SCRIPTS_DIR="$(dirname "$0")"
if [ -f "$SCRIPTS_DIR/../django/track_copy_tenant.py" ]; then
    cp "$SCRIPTS_DIR/../django/track_copy_tenant.py" "$TRACKER_SCRIPT"
    chmod +x "$TRACKER_SCRIPT"
    echo "✓ Progress tracker installed"
else
    echo "⚠ Progress tracker not found, running without progress tracking"
    TRACKER_SCRIPT=""
fi
echo ""

# Start the copy_tenant command with or without progress tracking
start_time=$(date +%s)
last_log_time=$start_time

if [ -n "$TRACKER_SCRIPT" ]; then
    # Run with progress tracking
    python -u "$TRACKER_SCRIPT" --cluster "$CLUSTER_NAME" "$TENANT_ID" --skip-checks &
    COPY_PID=$!

    echo "🔄 Copy tenant process started (PID: $COPY_PID)"
    echo "🕒 Progress updates every 60 seconds..."
    echo ""

    # Monitor with progress file reading
    while kill -0 $COPY_PID 2>/dev/null; do
        sleep 60  # Check every minute
        current_time=$(date +%s)
        minutes_elapsed=$(( (current_time - start_time) / 60 ))

        # Log progress every 60 seconds
        if [ $(( (current_time - last_log_time) )) -ge 60 ]; then
            # Try to read progress file
            if [ -f /tmp/copy_tenant_progress.json ]; then
                phase=$(python -c "import json; print(json.load(open('/tmp/copy_tenant_progress.json')).get('phase', 'unknown'))" 2>/dev/null || echo "copying")
                elapsed_min=$(python -c "import json; print(json.load(open('/tmp/copy_tenant_progress.json')).get('elapsed_minutes', 0))" 2>/dev/null || echo "$minutes_elapsed")
                tables=$(python -c "import json; print(json.load(open('/tmp/copy_tenant_progress.json')).get('tables_copied', 0))" 2>/dev/null || echo "?")

                echo ""
                echo "⏳ [$elapsed_min min elapsed] Phase: $phase | Operations: $tables"
                echo "   ✅ Connection active - downloading tenant data from cluster"
                echo ""
            else
                echo ""
                echo "⏳ [$minutes_elapsed min elapsed] Copy tenant in progress..."
                echo "   ✅ Connection active - downloading tenant data from cluster"
                echo ""
            fi
            last_log_time=$current_time
        fi
    done

    # Wait for completion and get exit code
    wait $COPY_PID
    EXIT_CODE=$?
else
    # Fallback: run without progress tracking
    set -x
    python -u manage.py copy_tenant --cluster "$CLUSTER_NAME" "$TENANT_ID" --skip-checks &
    COPY_PID=$!
    set +x

    echo "🔄 Copy tenant process started (PID: $COPY_PID)"
    echo "🕒 Progress updates every 60 seconds..."
    echo ""

    while kill -0 $COPY_PID 2>/dev/null; do
        sleep 60
        current_time=$(date +%s)
        minutes_elapsed=$(( (current_time - start_time) / 60 ))

        if [ $(( (current_time - last_log_time) )) -ge 60 ]; then
            echo ""
            echo "⏳ [$minutes_elapsed min elapsed] Copy tenant in progress..."
            echo "   ✅ Connection active - downloading tenant data from cluster"
            echo ""
            last_log_time=$current_time
        fi
    done

    wait $COPY_PID
    EXIT_CODE=$?
fi

end_time=$(date +%s)
total_minutes=$(( (end_time - start_time) / 60 ))

if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo "✅ SUCCESS: Tenant data copied successfully!"
    echo "   Tenant: $TENANT_NAME ($TENANT_ID)"
    echo "   Cluster: $CLUSTER_NAME"
    echo "   Total time: $total_minutes minutes"
    exit 0
else
    echo ""
    echo "❌ FAILURE: copy_tenant failed (exit code: $EXIT_CODE)"
    echo "   Total time: $total_minutes minutes"
    exit $EXIT_CODE
fi
