#!/bin/bash
# update_tenant_name.sh — Update domain_client and domain_domain tables with configured tenant name
set -e

echo "🔄 Updating tenant name in database..."
echo ""
echo "🔍 Environment variables:"
env | grep '^SETUP_' || echo "   ⚠️  No SETUP_* variables found!"
echo ""

CLONE_DIR="${SETUP_CLONE_DIR}"
VENV_NAME="${SETUP_VENV_NAME}"
TENANT_NAME="${SETUP_TENANT_NAME}"
TENANT_ID="${SETUP_TENANT_ID}"

echo "📋 Configuration:"
echo "   Clone directory: ${CLONE_DIR:-<NOT SET>}"
echo "   Virtual environment: ${VENV_NAME:-<NOT SET>}"
echo "   Tenant Name: ${TENANT_NAME:-<NOT SET>}"
echo "   Tenant ID: ${TENANT_ID:-<NOT SET>}"
echo ""

if [ -z "$CLONE_DIR" ] || [ -z "$VENV_NAME" ] || [ -z "$TENANT_NAME" ] || [ -z "$TENANT_ID" ]; then
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
export DJANGO_SETTINGS_MODULE=toogo.dev_settings

echo "📝 Updating domain_client.name where schema_name='$TENANT_ID'..."
python manage.py shell <<EOF
from domain.models import Client, Domain

# Update domain_client table
tenant_name = "$TENANT_NAME"
tenant_id = "$TENANT_ID"

try:
    # Find the client by schema_name (which matches tenant_id)
    client = Client.objects.filter(schema_name=tenant_id).first()
    if client:
        old_name = client.name
        client.name = tenant_name
        client.save()
        print(f"✓ Updated domain_client: '{old_name}' → '{tenant_name}' (schema_name={tenant_id})")
    else:
        print(f"⚠ No client found with schema_name='{tenant_id}'")

    # Update domain_domain table
    # Find domain records that belong to this tenant (using tenant_id field)
    domains = Domain.objects.filter(tenant_id=client.id) if client else []
    for domain in domains:
        old_domain = domain.domain
        domain.domain = tenant_name
        domain.save()
        print(f"✓ Updated domain_domain: '{old_domain}' → '{tenant_name}' (id={domain.id})")

    if not domains:
        print(f"⚠ No domain records found for tenant with schema_name='{tenant_id}'")

except Exception as e:
    print(f"❌ Error updating tenant name: {e}")
    import sys
    sys.exit(1)
EOF

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ SUCCESS: Tenant name updated in database"
    echo "   Tenant Name: $TENANT_NAME"
    echo "   Tenant ID: $TENANT_ID"
    exit 0
else
    echo ""
    echo "❌ FAILURE: Failed to update tenant name"
    exit 1
fi
