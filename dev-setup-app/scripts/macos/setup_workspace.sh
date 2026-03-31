#!/usr/bin/env bash
# setup_workspace.sh (macOS) — 3 sub-tasks: MCP config, install extensions, open workspace
set -euo pipefail

CLONE_DIR="${SETUP_CLONE_DIR:-$HOME/VsCodeProjects/erc}"
PAT="${SETUP_GITLAB_PAT:-}"

# ═════════════════════════════════════════════════════════════════════════════
# Sub-task 1/3: Write MCP configuration
# ═════════════════════════════════════════════════════════════════════════════
echo "→ Sub-task 1/3: Writing MCP configuration..."

MCP_DIR="$HOME/Library/Application Support/Code/User"
MCP_PATH="$MCP_DIR/mcp.json"
mkdir -p "$MCP_DIR"

TEMP_MCP="/tmp/mcp_new_$$.json"

# Write new servers config (PAT substituted from env)
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

# ═════════════════════════════════════════════════════════════════════════════
# Sub-task 2/3: Install VS Code extensions from Propello.code-workspace
# ═════════════════════════════════════════════════════════════════════════════
echo "→ Sub-task 2/3: Installing VS Code extensions..."

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
# Sub-task 3/3: Open VS Code workspace
# ═════════════════════════════════════════════════════════════════════════════
echo "→ Sub-task 3/3: Opening VS Code workspace..."
WS_FILE="$CLONE_DIR/Propello.code-workspace"
if [ -f "$WS_FILE" ]; then
    code "$WS_FILE" &
    echo "✓ VS Code workspace opened: $WS_FILE"
else
    echo "⚠ Workspace file not found: $WS_FILE"
fi

echo "✓ setup_workspace complete."
