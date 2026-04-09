#!/usr/bin/env bash
# setup_workspace.sh (macOS) — 3 sub-tasks: install extensions, MCP config, open workspace
set -euo pipefail

CLONE_DIR="${SETUP_CLONE_DIR:-$HOME/VsCodeProjects/erc}"
PAT="${SETUP_GITLAB_PAT:-}"

# ═════════════════════════════════════════════════════════════════════════════
# Configure SSL bypass for corporate proxy environments
# ═════════════════════════════════════════════════════════════════════════════
echo "→ Configuring SSL bypass for corporate proxy..."

export NODE_TLS_REJECT_UNAUTHORIZED="0"
export NODE_NO_WARNINGS="1"
export STRICT_SSL="false"
export NPM_CONFIG_STRICT_SSL="false"

# Configure npm and git if available
command -v npm &>/dev/null && npm config set strict-ssl false --global 2>/dev/null || true
command -v git &>/dev/null && git config --global http.sslVerify false 2>/dev/null || true

echo "✓ SSL bypass configured"

# ═════════════════════════════════════════════════════════════════════════════
# Sub-task 1/3: Install VS Code extensions from Propello.code-workspace
# ═════════════════════════════════════════════════════════════════════════════
echo "→ Sub-task 1/3: Installing VS Code extensions..."

WS_FILE="$CLONE_DIR/Propello.code-workspace"
if [ ! -f "$WS_FILE" ]; then
    echo "⚠ Workspace file not found: $WS_FILE"
    echo "  Ensure 'Clone Project Repository' completed first."
else
    # Parse JSONC (strip comments + trailing commas) and extract extension IDs
    EXTS=$(python3 - "$WS_FILE" <<'PYEOF'
import json, re, sys
raw = open(sys.argv[1]).read()
raw = re.sub(r'//[^\r\n]*', '', raw)
raw = re.sub(r',(\s*[}\]])', r'\1', raw)
ws = json.loads(raw)
recs = ws.get("extensions", {}).get("recommendations", [])
for ext in recs:
    print(ext)
PYEOF
)
    if [ -z "$EXTS" ]; then
        echo "⚠ No extensions found in workspace file."
    else
        EXT_COUNT=$(echo "$EXTS" | wc -l | tr -d ' ')
        echo "  Found $EXT_COUNT extension(s) to install."
        while IFS= read -r ext; do
            [ -z "$ext" ] && continue
            echo "  Installing: $ext"
            code --install-extension "$ext" --force 2>&1 || true
        done <<< "$EXTS"
        echo "✓ Extension installation complete."
    fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# Sub-task 2/3: Write MCP configuration (Kibana, GitLab, Atlassian)
# ═════════════════════════════════════════════════════════════════════════════
echo "→ Sub-task 2/3: Writing MCP configuration (Kibana + GitLab + Atlassian)..."

MCP_DIR="$HOME/Library/Application Support/Code/User"
MCP_PATH="$MCP_DIR/mcp.json"
mkdir -p "$MCP_DIR"

TEMP_MCP="/tmp/mcp_new_$$.json"

# Write new servers config (PAT substituted from env, Atlassian added)
python3 - "$TEMP_MCP" "$PAT" <<'PYEOF'
import json, sys
out_path, pat = sys.argv[1], sys.argv[2]
data = {
    "servers": {
        "kibana-mcp-server-dev": {
            "command": "npx",
            "args": ["@tocharian/mcp-server-kibana"],
            "env": {
                "KIBANA_URL": "https://mulog.toogoerp.net",
                "KIBANA_DEFAULT_SPACE": "default",
                "NODE_TLS_REJECT_UNAUTHORIZED": "0"
            }
        },
        "GitLab communication server": {
            "command": "npx",
            "args": ["-y", "@zereight/mcp-gitlab"],
            "env": {
                "GITLAB_PERSONAL_ACCESS_TOKEN": pat,
                "GITLAB_API_URL": "https://gitlab.toogoerp.net",
                "GITLAB_READ_ONLY_MODE": "false",
                "USE_GITLAB_WIKI": "false",
                "USE_MILESTONE": "false",
                "USE_PIPELINE": "false"
            },
            "type": "stdio"
        },
        "atlassian": {
            "command": "npx",
            "args": ["-y", "com.atlassian/atlassian-mcp-server"],
            "env": {}
        }
    }
}
json.dump(data, open(out_path, "w"), indent=2)
PYEOF

# Merge into existing mcp.json (preserves other entries)
python3 - "$TEMP_MCP" "$MCP_PATH" <<'PYEOF'
import json, os, sys
new_path, target_path = sys.argv[1], sys.argv[2]
new_data = json.load(open(new_path))
existing = json.load(open(target_path)) if os.path.exists(target_path) else {}
if "servers" not in existing:
    existing["servers"] = {}
existing["servers"].update(new_data.get("servers", {}))
with open(target_path, "w") as f:
    json.dump(existing, f, indent=2)
print("MCP config written to", target_path)
PYEOF

rm -f "$TEMP_MCP"
echo "✓ MCP configuration written."
echo "  • Kibana MCP: Ready for log search"
echo "  • GitLab MCP: Ready with configured PAT"
echo "  • Atlassian MCP: Available (requires browser authentication)"
echo ""
echo "  Note: Atlassian MCP requires one-time browser authentication:"
echo "    1. VS Code will prompt to connect to mcp.atlassian.com"
echo "    2. Browser opens → Select Jira → Click Approve → Accept"
echo ""

# ═════════════════════════════════════════════════════════════════════════════
# Sub-task 3/3: Configure VS Code settings (MCP gallery + workspace trust) and open workspace
# ═════════════════════════════════════════════════════════════════════════════
echo "→ Sub-task 3/3: Configuring VS Code settings and opening workspace..."

# Configure VS Code settings with MCP gallery enabled + workspace trust
SETTINGS_DIR="$HOME/Library/Application Support/Code/User"
SETTINGS_PATH="$SETTINGS_DIR/settings.json"
mkdir -p "$SETTINGS_DIR"

python3 - "$SETTINGS_PATH" "$CLONE_DIR" <<'PYEOF'
import json, os, sys
settings_path, workspace_dir = sys.argv[1], sys.argv[2]

# Load existing settings or create new
if os.path.exists(settings_path):
    with open(settings_path, 'r') as f:
        settings = json.load(f)
else:
    settings = {}

# Add MCP gallery enabled setting
settings['chat.mcp.gallery.enabled'] = True
settings['chat.useAgentSkills'] = True
settings['chat.agent.enabled'] = True

# Configure workspace trust settings
if 'security.workspace.trust.untrustedFiles' not in settings:
    settings['security.workspace.trust.untrustedFiles'] = 'open'

if 'security.workspace.trust.emptyWindow' not in settings:
    settings['security.workspace.trust.emptyWindow'] = False

# Write settings
with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)

print(f'VS Code settings configured (MCP gallery + workspace trust) for {workspace_dir}')
PYEOF

echo "  ✓ VS Code settings configured (MCP gallery enabled + workspace trust)"

WS_FILE="$CLONE_DIR/Propello.code-workspace"
if [ -f "$WS_FILE" ]; then
    code "$WS_FILE" &
    echo "✓ VS Code workspace opened: $WS_FILE"
else
    echo "⚠ Workspace file not found: $WS_FILE"
fi

echo "✓ setup_workspace complete."
