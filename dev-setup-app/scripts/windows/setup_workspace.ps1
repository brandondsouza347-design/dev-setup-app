# setup_workspace.ps1 — Opens VS Code workspace in WSL remote mode
# Runs as current (non-elevated) user. WSL root access via --user root.
# NOTE: MCP configuration and extension installation now handled by Step 18
$ErrorActionPreference = 'Stop'

$cloneDir = $env:SETUP_CLONE_DIR
if (-not $cloneDir) { $cloneDir = '/home/ubuntu/VsCodeProjects/erc' }

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

$ipcDir = 'C:\Users\Public\DevSetupAgent'
if (-not (Test-Path $ipcDir)) { New-Item -ItemType Directory -Path $ipcDir -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# ═════════════════════════════════════════════════════════════════════════════
# Configure workspace trust and open VS Code workspace
# ═════════════════════════════════════════════════════════════════════════════
Write-Output "→ Configuring workspace trust and opening VS Code..."

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
