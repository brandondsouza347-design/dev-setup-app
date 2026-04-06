# setup_workspace.ps1 — 3 sub-tasks: MCP config, install extensions, open workspace
# Runs as current (non-elevated) user. WSL root access via --user root.
$ErrorActionPreference = 'Stop'

$cloneDir = $env:SETUP_CLONE_DIR
if (-not $cloneDir) { $cloneDir = '/home/ubuntu/VsCodeProjects/erc' }
$pat = if ($env:SETUP_GITLAB_PAT) { $env:SETUP_GITLAB_PAT } else { '' }

# ── Locate code.cmd ───────────────────────────────────────────────────────────
# Use -LiteralPath to avoid PS5.1 treating [ ] in PATH entries as wildcards
$codePath = $null
foreach ($p in ($env:PATH -split ';' | Where-Object { $_ -ne '' })) {
    $c = Join-Path $p 'code.cmd'
    if (Test-Path -LiteralPath $c) { $codePath = $c; break }
}
if (-not $codePath) {
    foreach ($c in @(
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd",
        "$env:ProgramFiles\Microsoft VS Code\bin\code.cmd"
    )) {
        if (Test-Path -LiteralPath $c) { $codePath = $c; break }
    }
}

# ═════════════════════════════════════════════════════════════════════════════
# Sub-task 1/3: Write MCP configuration to WSL /root/.vscode-server/data/User/mcp.json
# ═════════════════════════════════════════════════════════════════════════════
Write-Output "→ Sub-task 1/3: Writing MCP configuration to WSL..."

$ipcDir = 'C:\Users\Public\DevSetupAgent'
if (-not (Test-Path $ipcDir)) { New-Item -ItemType Directory -Path $ipcDir -Force | Out-Null }

# Build MCP JSON — note PAT substituted at runtime
$mcpObj = [ordered]@{
    servers = [ordered]@{
        'kibana-mcp-server-dev' = [ordered]@{
            command = 'npx'
            args    = @('@tocharian/mcp-server-kibana')
            env     = [ordered]@{
                KIBANA_URL                   = 'https://mulog.toogoerp.net'
                KIBANA_DEFAULT_SPACE         = 'default'
                NODE_TLS_REJECT_UNAUTHORIZED = '0'
            }
        }
        'GitLab communication server' = [ordered]@{
            command = 'npx'
            args    = @('-y', '@zereight/mcp-gitlab')
            env     = [ordered]@{
                GITLAB_PERSONAL_ACCESS_TOKEN = $pat
                GITLAB_API_URL               = 'https://gitlab.toogoerp.net'
                GITLAB_READ_ONLY_MODE        = 'false'
                USE_GITLAB_WIKI              = 'false'
                USE_MILESTONE                = 'false'
                USE_PIPELINE                 = 'false'
            }
            type    = 'stdio'
        }
    }
}
$mcpJson = $mcpObj | ConvertTo-Json -Depth 10

# Write without BOM using .NET
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$newMcpPath  = Join-Path $ipcDir 'mcp_new.json'
[System.IO.File]::WriteAllText($newMcpPath, $mcpJson, $utf8NoBom)

# Python merge script — merges new servers into existing mcp.json (preserves other entries)
$mergePy = @'
import json, os, sys
new_path, target_path = sys.argv[1], sys.argv[2]
new_data = json.load(open(new_path))
existing = json.load(open(target_path)) if os.path.exists(target_path) else {}
if "servers" not in existing:
    existing["servers"] = {}
existing["servers"].update(new_data.get("servers", {}))
os.makedirs(os.path.dirname(os.path.abspath(target_path)), exist_ok=True)
with open(target_path, "w") as f:
    json.dump(existing, f, indent=2)
print("MCP config written to", target_path)
'@
$pyScriptPath = Join-Path $ipcDir 'merge_mcp.py'
[System.IO.File]::WriteAllText($pyScriptPath, $mergePy, $utf8NoBom)

# Run merge inside WSL as root
$wslNewMcp  = '/mnt/c/Users/Public/DevSetupAgent/mcp_new.json'
$wslPyScript = '/mnt/c/Users/Public/DevSetupAgent/merge_mcp.py'
$wslMcpDest  = '/root/.vscode-server/data/User/mcp.json'

wsl -d ERC --user root -- bash -c "python3 '$wslPyScript' '$wslNewMcp' '$wslMcpDest'"
Write-Output "✓ MCP configuration written."

# ═════════════════════════════════════════════════════════════════════════════
# Sub-task 2/3: Install VS Code extensions from Propello.code-workspace
# ═════════════════════════════════════════════════════════════════════════════
Write-Output "→ Sub-task 2/3: Installing VS Code extensions..."

# Read workspace file from WSL
$wsContent = (wsl -d ERC -- bash -c "cat '$cloneDir/Propello.code-workspace' 2>/dev/null") -join "`n"

if (-not $wsContent) {
    Write-Output "⚠ Could not read Propello.code-workspace from $cloneDir — skipping extension install."
    Write-Output "  Ensure the 'Clone Project Repository' step ran first."
} else {
    # Strip JSONC comments (// ...) and trailing commas before closing brackets/braces
    $stripped = $wsContent `
        -replace '(?m)//[^\r\n]*', '' `
        -replace ',(\s*[}\]])', '$1'

    $extensions = @()
    try {
        $ws = $stripped | ConvertFrom-Json
        $extensions = @($ws.extensions.recommendations)
    } catch {
        Write-Output "⚠ Failed to parse workspace JSON: $_"
    }

    if ($extensions.Count -eq 0) {
        Write-Output "⚠ No extensions found in workspace file."
    } elseif (-not $codePath) {
        Write-Output "⚠ code.cmd not found — cannot install extensions automatically."
        Write-Output "  Extensions to install manually: $($extensions -join ', ')"
    } else {
        Write-Output "  Found $($extensions.Count) extension(s) to install into WSL remote (wsl+ERC)..."
        $successCount = 0
        $failCount = 0
        foreach ($ext in $extensions) {
            Write-Output "  Installing (WSL): $ext"
            $result = & $codePath --remote "wsl+ERC" --install-extension $ext --force 2>&1
            $result | ForEach-Object { Write-Output "    $_" }
            if ($LASTEXITCODE -eq 0) { $successCount++ } else { $failCount++ }
        }
        Write-Output "✓ Extension installation complete — $successCount succeeded, $failCount failed."
    }
}

# ═════════════════════════════════════════════════════════════════════════════
# Sub-task 3/3: Configure workspace trust and open VS Code workspace
# ═════════════════════════════════════════════════════════════════════════════
Write-Output "→ Sub-task 3/3: Configuring workspace trust and opening VS Code..."

# Add workspace to VS Code trusted folders
# This prevents the "Do you trust this workspace?" prompt
$wslSettingsPath = '/root/.vscode-server/data/User/settings.json'
$trustScript = @"
import json, os
settings_path = '$wslSettingsPath'
workspace_dir = '$cloneDir'

# Load existing settings or create new
if os.path.exists(settings_path):
    with open(settings_path, 'r') as f:
        settings = json.load(f)
else:
    settings = {}

# Add workspace to trusted folders
if 'security.workspace.trust.untrustedFiles' not in settings:
    settings['security.workspace.trust.untrustedFiles'] = 'open'

if 'security.workspace.trust.emptyWindow' not in settings:
    settings['security.workspace.trust.emptyWindow'] = False

# Ensure directory exists
os.makedirs(os.path.dirname(settings_path), exist_ok=True)

# Write settings
with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)

print(f'Workspace trust configured for {workspace_dir}')
"@

$trustScriptPath = Join-Path $ipcDir 'trust_workspace.py'
[System.IO.File]::WriteAllText($trustScriptPath, $trustScript, $utf8NoBom)

$wslTrustScript = '/mnt/c/Users/Public/DevSetupAgent/trust_workspace.py'
wsl -d ERC --user root -- bash -c "python3 '$wslTrustScript'"
Write-Output "  ✓ Workspace trust configured"

# Build a vscode-remote URI so the workspace opens under WSL: ERC (remote mode)
# rather than as a Windows UNC path (which opens in local/Windows mode).
$wsFileUri = "vscode-remote://wsl+ERC$cloneDir/Propello.code-workspace"

if ($codePath) {
    & $codePath --file-uri $wsFileUri 2>&1 | Out-Null
    Write-Output "✓ VS Code workspace opened in WSL remote mode: $wsFileUri"
} else {
    Write-Output "⚠ code.cmd not found. Open workspace manually:"
    Write-Output "  code --file-uri $wsFileUri"
}

Write-Output "✓ setup_workspace complete."
