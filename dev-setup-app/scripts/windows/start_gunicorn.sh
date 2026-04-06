#!/bin/bash
# start_gunicorn.sh — Start Gunicorn ASGI server with uvicorn worker
set -e

echo "🦄 Starting Gunicorn ASGI server..."
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
    echo "   SETUP_CLONE_DIR should be set (e.g., /home/ubuntu/VsCodeProjects/erc)"
    echo "   SETUP_VENV_NAME should be set (e.g., 'erc')"
    echo "   Check Settings screen configuration"
    exit 1
fi

# Navigate to project directory
if [ ! -d "$CLONE_DIR" ]; then
    echo "❌ Error: Clone directory '$CLONE_DIR' does not exist"
    exit 1
fi

cd "$CLONE_DIR"

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

# Kill any existing Gunicorn processes
echo "🛑 Checking for existing Gunicorn processes..."
if pgrep -f "gunicorn.*asgi:channel_layer" > /dev/null 2>&1; then
    echo "   Found running Gunicorn - stopping..."
    pkill -f "gunicorn.*asgi:channel_layer" 2>/dev/null || true
    sleep 2
    # Force kill if still running
    if pgrep -f "gunicorn.*asgi:channel_layer" > /dev/null 2>&1; then
        echo "   Force killing stubborn processes..."
        pkill -9 -f "gunicorn.*asgi:channel_layer" 2>/dev/null || true
        sleep 1
    fi
    echo "   ✓ Stopped existing Gunicorn processes"
else
    echo "   No existing Gunicorn processes found"
fi
echo ""

# Set all required environment variables
export PYTHONUNBUFFERED=1
export DB_PORT=5432
export DEBUG=True
export DEFERRED_PROCESSING_USES_DRAMATIQ=False
export DISABLE_SQL_SCHEMA_ANNOTATION=True
export DJANGO_SETTINGS_MODULE=toogo.dev_settings
export ENABLE_DEFERRED_PROCESSES=False
export ERC_DB_PORT=5432
export ERC_LOG_LEVEL=DEBUG
export ERC_TIMEOUT_BIN=/usr/bin/timeout
export KEEP_LOGGING=false
export LOCAL_PUBLIC_API_URL=""
export LOG_REQUEST_RESPONSE=true
export LOG_SQL_STATEMENTS=true
export MONKEY_PATCH_ASGIREF=false
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES
export OFFLINE_MODE=false
export PUBLIC_API_BROWSER=true
export PUBLISH_FULL_API=false
export PYTHONWARNINGS="ignore:invalid escape sequence '"
export REDIS_SERVER=127.0.0.1
export SAML_XMLSEC_BINARY=/usr/bin/xmlsec1
export THIRD_PARTY_LOG_LEVEL=WARNING
export USE_ASGI=true
export USE_REDIS=True
export WORKATO_STATIC_WEBHOOK_URL="https://webhooks.workato.com/users/4108671/cd094fb0abe5d2f2aa4db9a0b6373cb4b492b445cc0d442dd44b2cb19615abc6/webhooks/notify/6d5e7ee2-d98b-431f-8049-65b7425ac4af-propello_connector_with_static_webhook_connector_4108671_1727121171"
export XXXNEW_RELIC_ENVIRONMENT=development
# Use AWS credentials from Settings (if provided)
export S3_AWS_ACCESS_KEY="${SETUP_AWS_ACCESS_KEY_ID:-}"
export S3_AWS_SECRET_KEY="${SETUP_AWS_SECRET_ACCESS_KEY:-}"
export SNS_AWS_ACCESS_KEY="${SETUP_AWS_ACCESS_KEY_ID:-}"
export SNS_AWS_SECRET_KEY="${SETUP_AWS_SECRET_ACCESS_KEY:-}"
export PYTHONHTTPSVERIFY=0
export USE_FB_GATEWAY=true

# Start Gunicorn in the background
echo "🚀 Starting Gunicorn server (running in background)..."
echo "   Binding to: 0.0.0.0:8000"
echo "   Worker class: uvicorn_worker.Worker"
echo ""

nohup gunicorn \
    --bind 0.0.0.0:8000 \
    --timeout 0 \
    --forwarded-allow-ips '*' \
    --workers 1 \
    --threads 1 \
    --worker-class uvicorn_worker.Worker \
    asgi:channel_layer \
    > /tmp/gunicorn.log 2>&1 &

GUNICORN_PID=$!

# Wait for Gunicorn to fully start and respond to HTTP requests
echo "⏳ Waiting for Gunicorn to start (this may take 30-90 seconds)..."
SECONDS_WAITED=0
MAX_WAIT=90

while [ $SECONDS_WAITED -lt $MAX_WAIT ]; do
    # Check if process is still running
    if ! ps -p $GUNICORN_PID > /dev/null 2>&1; then
        echo ""
        echo "❌ ERROR: Gunicorn process died during startup"
        echo "   Last 50 lines of /tmp/gunicorn.log:"
        tail -50 /tmp/gunicorn.log 2>/dev/null || echo "   (log file not found)"
        exit 1
    fi

    # Check if server is responding to HTTP requests
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "404" ]; then
        echo ""
        echo "✅ SUCCESS: Gunicorn server is running and responding!"
        echo "   Process ID: $GUNICORN_PID"
        echo "   Server URL: http://localhost:8000"
        echo "   HTTP Status: $HTTP_CODE"
        echo "   Log file: /tmp/gunicorn.log"
        echo ""

        # Open browser to tenant URL
        TENANT_URL="http://${SETUP_TENANT_NAME}:8000/#"
        echo "🌐 Opening browser to: $TENANT_URL"
        cmd.exe /c start "$TENANT_URL" 2>/dev/null || {
            echo "   ⚠️  Could not auto-open browser"
            echo "   Please manually open: $TENANT_URL"
        }
        echo ""

        echo "   To stop: pkill -f 'gunicorn.*asgi:channel_layer'"
        echo "   To view logs: tail -f /tmp/gunicorn.log"
        exit 0
    fi

    # Still starting up - show progress every 10 seconds
    if [ $((SECONDS_WAITED % 10)) -eq 0 ] && [ $SECONDS_WAITED -gt 0 ]; then
        echo "   Still starting... ($SECONDS_WAITED seconds elapsed, HTTP: $HTTP_CODE)"
    fi

    sleep 2
    SECONDS_WAITED=$((SECONDS_WAITED + 2))
done

# Timeout reached
echo ""
echo "⚠️  WARNING: Gunicorn started but not responding after $MAX_WAIT seconds"
echo "   Process ID: $GUNICORN_PID (still running)"
echo "   This may indicate a configuration issue"
echo ""
echo "   Last 50 lines of /tmp/gunicorn.log:"
tail -50 /tmp/gunicorn.log 2>/dev/null || echo "   (log file not found)"
exit 1
    exit 1
fi
