# install_workspace_extensions.ps1 — Install all recommended extensions from
# Propello.code-workspace with split architecture:
#   - Development tools (Python, ESLint, etc.) → WSL remote environment
#   - UI extensions (icon theme, Remote-WSL) → Windows host
# This step runs after setup_workspace so the workspace file is guaranteed to
# exist in the cloned repo.
$ErrorActionPreference = 'Stop'
# Prevent native-exe nonzero exit codes from triggering Stop in PS7+
if ($PSVersionTable.PSVersion.Major -ge 7) {
    $PSNativeCommandUseErrorActionPreference = $false
}

# In .NET / PS5.1, calling exit n directly invokes Environment.Exit() which does
# NOT flush stdout buffers — any Write-Output lines before the exit are silently
# discarded. Using throw instead lets the outer catch write the error and then
# calls [Console]::Out.Flush() before the final exit, ensuring all output is seen.
function Flush-Output { [Console]::Out.Flush() }

Write-Output "[diag] install_workspace_extensions.ps1 starting"
Write-Output "[diag] PowerShell : $($PSVersionTable.PSVersion)"
Write-Output "[diag] Running as : $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"

try {

$cloneDir = $env:SETUP_CLONE_DIR
if (-not $cloneDir) { $cloneDir = '/home/ubuntu/VsCodeProjects/erc' }
Write-Output "[diag] cloneDir   : $cloneDir"

# ── Locate code.cmd ──────────────────────────────────────────────────────────
Write-Output "[diag] Searching for code.cmd via Get-Command..."
$codePath = $null
try {
    $gcResult = Get-Command 'code.cmd' -ErrorAction SilentlyContinue
    if ($gcResult -and $gcResult.Source) {
        $codePath = $gcResult.Source
        Write-Output "[diag] Get-Command found: $codePath"
    } else {
        Write-Output "[diag] Get-Command returned but no Source property"
    }
} catch {
    Write-Output "[diag] Get-Command threw exception: $($_.Exception.Message)"
}

if (-not $codePath) {
    Write-Output "[diag] Not on PATH — checking known install locations..."
    foreach ($c in @(
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd",
        "$env:ProgramFiles\Microsoft VS Code\bin\code.cmd",
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code Insiders\bin\code-insiders.cmd"
    )) {
        Write-Output "[diag] Checking: $c"
        if (Test-Path -LiteralPath $c) { $codePath = $c; break }
    }
}

if (-not $codePath) {
    throw "VS Code (code.cmd) not found on PATH or known locations. Install VS Code and ensure it is on PATH, then retry this step."
}

Write-Output "[diag] Code path resolved: $codePath"
Flush-Output

# ── Configure SSL bypass for corporate proxy environments ───────────────────
Write-Output "[diag] Configuring SSL bypass for corporate proxy..."

# Set global environment variables for this PowerShell session
$env:NODE_TLS_REJECT_UNAUTHORIZED = "0"
$env:NODE_NO_WARNINGS = "1"
$env:STRICT_SSL = "false"
$env:NPM_CONFIG_STRICT_SSL = "false"
Write-Output "[diag] Environment variables set for SSL bypass"

# Configure npm to bypass SSL (VS Code uses npm internally for extensions)
try {
    npm config set strict-ssl false --global 2>&1 | Out-Null
    Write-Output "[diag] npm strict-ssl disabled globally"
} catch {
    Write-Output "[diag] Could not configure npm (may not be installed) - continuing anyway..."
}

# Configure Git to accept self-signed certificates
try {
    git config --global http.sslVerify false 2>&1 | Out-Null
    Write-Output "[diag] Git SSL verification disabled globally"
} catch {
    Write-Output "[diag] Could not configure Git (may not be installed) - continuing anyway..."
}

# Ensure VS Code proxy settings are configured
Write-Output "[diag] Ensuring VS Code proxy settings..."
$SettingsDir = Join-Path $env:APPDATA "Code\User"
New-Item -ItemType Directory -Path $SettingsDir -Force | Out-Null
$SettingsFile = Join-Path $SettingsDir "settings.json"

if (Test-Path $SettingsFile) {
    try {
        # Read existing settings as JSON object (not hashtable to preserve structure)
        $settingsJson = Get-Content $SettingsFile -Raw
        $settings = $settingsJson | ConvertFrom-Json

        # Add or update SSL bypass settings
        if ($null -eq $settings.'http.proxyStrictSSL') {
            $settings | Add-Member -NotePropertyName 'http.proxyStrictSSL' -NotePropertyValue $false -Force
        } else {
            $settings.'http.proxyStrictSSL' = $false
        }

        if ($null -eq $settings.'http.proxy') {
            $settings | Add-Member -NotePropertyName 'http.proxy' -NotePropertyValue "" -Force
        } else {
            $settings.'http.proxy' = ""
        }

        # Write back as properly formatted JSON
        $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $SettingsFile -Encoding UTF8
        Write-Output "[OK] VS Code Windows user settings updated with SSL bypass"
    } catch {
        Write-Output "[WARN] Could not update VS Code settings: $($_.Exception.Message)"
        Write-Output "[WARN] SSL bypass may not work - continuing anyway..."
    }
} else {
    Write-Output "[WARN] VS Code settings.json not found at $SettingsFile"
}

Write-Output "[diag] SSL bypass configuration complete"
Flush-Output

# ── Check WSL distros ────────────────────────────────────────────────────────
Write-Output "[diag] Checking WSL distros..."
try {
    $wslDistros = wsl --list --quiet 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Output "[diag] WSL distros: $($wslDistros -join ', ')"
    } else {
        Write-Output "[diag] WSL command returned exit code $LASTEXITCODE"
    }
} catch {
    Write-Output "[diag] WSL list command failed: $($_.Exception.Message)"
}

# ── Read Propello.code-workspace from WSL ────────────────────────────────────
Write-Output "[diag] Reading Propello.code-workspace from $cloneDir..."
$wsContent = ""
try {
    $wsContent = (wsl -d ERC -- bash -c "cat '$cloneDir/Propello.code-workspace' 2>/dev/null") -join "`n"
    Write-Output "[diag] Workspace bytes read: $($wsContent.Length)"
} catch {
    Write-Output "[diag] Failed to read workspace: $($_.Exception.Message)"
}
Flush-Output

if (-not $wsContent) {
    throw "Could not read Propello.code-workspace from '$cloneDir'. Ensure the 'Clone Project Repository' step completed successfully, then retry."
}

# Strip JSONC comments and trailing commas so ConvertFrom-Json can parse it
$stripped = $wsContent `
    -replace '(?m)//[^\r\n]*', '' `
    -replace ',(\s*[}\]])', '$1'

$extensions = @()

# Try JSON parsing first
try {
    $ws = $stripped | ConvertFrom-Json
    $extensions = @($ws.extensions.recommendations)
    Write-Output "[diag] Successfully parsed full workspace JSON"
} catch {
    Write-Output "[diag] Full JSON parse failed: $($_.Exception.Message)"
    Write-Output "[diag] Attempting regex extraction of extensions.recommendations..."

    # Fallback: Extract just the extensions.recommendations array using regex
    # This handles workspace files with malformed JSON in other sections
    if ($wsContent -match '"extensions"\s*:\s*\{[^}]*"recommendations"\s*:\s*\[([^\]]+)\]') {
        $recBlock = $matches[1]
        # Extract quoted strings from the recommendations array
        $extensions = @([regex]::Matches($recBlock, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
        Write-Output "[diag] Regex extraction found $($extensions.Count) extension(s)"
    } else {
        Write-Output "[diag] Regex extraction also failed"
    }
}

if ($extensions.Count -eq 0) {
    throw "No extensions found in workspace recommendations. The Propello.code-workspace file may be corrupted or missing the extensions section."
}

Write-Output "→ Found $($extensions.Count) recommended extension(s)."

# ── Categorize extensions: UI (Windows) vs Dev Tools (WSL) ──────────────────
Write-Output ""
Write-Output "→ Categorizing extensions..."

# UI-only extensions that should be installed on Windows host
$uiExtensions = @(
    'ms-vscode-remote.remote-wsl',
    'ms-vscode-remote.vscode-remote-extensionpack',
    'pkief.material-icon-theme',
    'gruntfuggly.todo-tree',
    'streetsidesoftware.code-spell-checker'
)

# Copilot extensions should be installed in both Windows and WSL
$copilotExtensions = @(
    'github.copilot',
    'github.copilot-chat'
)

# Split extensions into WSL (dev tools) and Windows (UI only)
$wslExtensions = @()
$windowsExtensions = @()

foreach ($ext in $extensions) {
    if ($uiExtensions -contains $ext) {
        $windowsExtensions += $ext
        Write-Output "  [Windows] $ext"
    } elseif ($copilotExtensions -contains $ext) {
        # Install Copilot to both environments
        $wslExtensions += $ext
        $windowsExtensions += $ext
        Write-Output "  [Both] $ext"
    } else {
        # All other extensions go to WSL
        $wslExtensions += $ext
        Write-Output "  [WSL] $ext"
    }
}

Write-Output ""
Write-Output "  WSL extensions    : $($wslExtensions.Count)"
Write-Output "  Windows extensions: $($windowsExtensions.Count)"

# ── Verify ERC WSL distro exists ─────────────────────────────────────────────
Write-Output ""
Write-Output "→ Verifying ERC WSL distro..."
Flush-Output

$ercExists = $false
try {
    # WSL output can contain null bytes and BOM markers - clean and split properly
    $rawDistros = wsl --list --quiet 2>&1
    # Convert to string array, removing null bytes and empty entries
    $distros = @()
    foreach ($line in $rawDistros) {
        $cleaned = $line -replace '\x00', '' -replace '\uFEFF', '' -replace '^\s+|\s+$', ''
        if ($cleaned -and $cleaned.Length -gt 0) {
            $distros += $cleaned
            Write-Output "  [diag] Cleaned distro: '$cleaned' (Length: $($cleaned.Length), Bytes: $([System.Text.Encoding]::UTF8.GetBytes($cleaned) -join ','))"
        }
    }

    Write-Output "  [diag] Found $($distros.Count) WSL distro(s): $($distros -join ', ')"
    Write-Output "  [diag] Checking if array contains 'ERC'..."
    Flush-Output

    # Check each distro explicitly for debugging
    foreach ($d in $distros) {
        $match = $d -eq 'ERC'
        Write-Output "  [diag] Distro '$d' == 'ERC': $match"
        if ($match) {
            $ercExists = $true
            Write-Output "  [diag] Set ercExists = true"
        }
    }

    Write-Output "  [diag] After foreach, ercExists = $ercExists"

    if ($ercExists) {
        Write-Output "  [OK] ERC distro found"
        Flush-Output
    } else {
        Write-Output "  [ERROR] ERC distro not found in WSL list"
        Write-Output "  Available distros: $($distros -join ', ')"
        Flush-Output
    }
} catch {
    Write-Output "  [ERROR] Failed to check WSL distros: $($_.Exception.Message)"
    Flush-Output
}

if (-not $ercExists) {
    Flush-Output
    throw "ERC WSL distro not found. Ensure WSL setup steps completed successfully, then retry."
}

# ── Configure SSL bypass inside WSL environment ─────────────────────────────
Write-Output ""
Write-Output "→ Configuring SSL bypass for VS Code Server inside WSL..."
Flush-Output

try {
    # VS Code Server runs inside WSL and needs SSL bypass configured there
    # Create VS Code Server settings directory and configure SSL bypass

    wsl -d ERC -- bash -c "mkdir -p ~/.vscode-server/data/Machine"

    # Create settings.json using PowerShell here-string (avoids bash quoting issues)
    $vscodeSettings = @'
{
  "http.proxyStrictSSL": false,
  "http.proxy": ""
}
'@

    $vscodeSettings | wsl -d ERC -- bash -c "cat > ~/.vscode-server/data/Machine/settings.json"

    # Add environment variables to .bashrc for npm/git
    wsl -d ERC -- bash -c "grep -q 'NODE_TLS_REJECT_UNAUTHORIZED' ~/.bashrc || echo 'export NODE_TLS_REJECT_UNAUTHORIZED=0' >> ~/.bashrc"
    wsl -d ERC -- bash -c "grep -q 'NPM_CONFIG_STRICT_SSL' ~/.bashrc || echo 'export NPM_CONFIG_STRICT_SSL=false' >> ~/.bashrc"

    # Configure npm and git inside WSL
    wsl -d ERC -- bash -c "npm config set strict-ssl false --global 2>/dev/null || true"
    wsl -d ERC -- bash -c "git config --global http.sslVerify false 2>/dev/null || true"

    Write-Output "[diag] VS Code Server settings.json created with SSL bypass"
    Write-Output "[diag] Environment variables added to ~/.bashrc"
    Write-Output "[diag] npm and git configured to bypass SSL"
    Flush-Output
} catch {
    Write-Output "[WARN] Could not configure WSL SSL bypass - continuing anyway..."
    Write-Output "[diag] Error: $($_.Exception.Message)"
    Flush-Output
}

# ── Install extensions to WSL remote environment ─────────────────────────────
Write-Output ""
Write-Output "→ Installing extensions to WSL remote environment (ERC)..."
Write-Output "  (Using same pattern as check-extensions.sh - runs inside WSL with code CLI)"
Flush-Output

$wslSuccess = 0
$wslFail = 0

# Calculate total count for use in bash script
$wslExtCount = $wslExtensions.Count

# Build a bash script using the same reliable pattern as check-extensions.sh
# This runs entirely inside WSL and uses the same code CLI detection logic
$installScript = @"
#!/usr/bin/env bash
set -uo pipefail

# ── Find the 'code' CLI (same logic as check-extensions.sh) ──────────────────
CODE_BIN=""

# First try simple command lookup
if command -v code &>/dev/null; then
    CODE_BIN="code"
else
    # Try known paths including VS Code server locations
    for candidate in /usr/bin/code /usr/local/bin/code `$HOME/.vscode-server/bin/*/bin/remote-cli/code `$HOME/.vscode-server/cli/bin/code; do
        for expanded in `$candidate; do
            if [[ -x "`$expanded" ]]; then
                CODE_BIN="`$expanded"
                break 2
            fi
        done
    done
fi

if [[ -z "`$CODE_BIN" ]]; then
    echo "[ERROR] 'code' CLI not found in WSL environment"
    exit 1
fi

echo "[diag] Using VS Code CLI: `$CODE_BIN"

# Get currently installed extensions
installed_output="`$(`$CODE_BIN --list-extensions --show-versions 2>/dev/null || true)"

SUCCESS=0
FAILED=0

"@

# Add each extension to install
foreach ($ext in $wslExtensions) {
    $installScript += @"

# Install $ext
echo "[WSL] $ext"
installed_version=`$(echo "`$installed_output" | grep -i "^$ext@" | head -1 | cut -d'@' -f2)

if [[ -z "`$installed_version" ]]; then
    echo "  → Installing (not currently installed)..."
    if "`$CODE_BIN" --install-extension "$ext" --force >/dev/null 2>&1; then
        echo "  [OK] Installed successfully"
        ((SUCCESS++))
    else
        echo "  [ERROR] Installation failed"
        ((FAILED++))
    fi
else
    # Try to update anyway (--force reinstalls if newer version available)
    if "`$CODE_BIN" --install-extension "$ext" --force >/dev/null 2>&1; then
        new_version=`$("`$CODE_BIN" --list-extensions --show-versions 2>/dev/null | grep -i "^$ext@" | head -1 | cut -d'@' -f2)
        if [[ "`$new_version" == "`$installed_version" ]]; then
            echo "  [OK] Already installed @ `$installed_version"
        else
            echo "  [OK] Updated `$installed_version → `$new_version"
        fi
        ((SUCCESS++))
    else
        echo "  [ERROR] Installation/update failed"
        ((FAILED++))
    fi
fi

"@
}

$installScript += @"

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  WSL Extensions: `$SUCCESS/$wslExtCount installed, `$FAILED failed"
echo "════════════════════════════════════════════════════════════"

exit `$FAILED
"@

# Execute the bash script inside WSL (same as check-extensions.sh runs)
try {
    Write-Output "[diag] Executing extension installation script inside WSL..."
    Write-Output ""
    Flush-Output

    # Convert to Unix line endings and pipe to bash
    $installScriptUnix = $installScript.Replace("`r`n", "`n")
    $result = $installScriptUnix | wsl -d ERC -- bash -s 2>&1

    # Display output and count results
    $result | ForEach-Object {
        $line = $_.ToString()
        Write-Output $line
        if ($line -match '\[OK\]') {
            $wslSuccess++
        } elseif ($line -match '\[ERROR\]') {
            $wslFail++
        }
        Flush-Output
    }

    Write-Output ""
    Flush-Output
} catch {
    Write-Output "[ERROR] Failed to execute WSL installation script: $($_.Exception.Message)"
    Flush-Output
    $wslFail = $wslExtensions.Count
}

# ── Final report ─────────────────────────────────────────────────────────────
Write-Output ""
Write-Output "═══════════════════════════════════════════════════════════"
Write-Output "  WSL Extensions: $wslSuccess/$($wslExtensions.Count) installed, $wslFail failed"
Write-Output "═══════════════════════════════════════════════════════════"
Write-Output ""
Write-Output "NOTE: Windows extensions (ms-vscode-remote.remote-wsl, pkief.material-icon-theme)"
Write-Output "      are installed by the 'Configure VS Code for Windows' step."
Write-Output "      This step only installs development tools to the WSL environment."
Write-Output ""

if ($wslFail -gt 0) {
    Write-Output ""
    Write-Output "[WARN] Some extensions failed to install to WSL."
    Write-Output ""
    Write-Output "  To manually install to WSL, run from inside WSL terminal:"
    Write-Output "    wsl -d ERC"
    Write-Output "    code --install-extension <extension-id> --force"
    Write-Output ""
    Write-Output "  Or use VS Code Extensions panel:"
    Write-Output "    1. Open VS Code connected to WSL: File → Connect to WSL"
    Write-Output "    2. Go to Extensions panel (Ctrl+Shift+X)"
    Write-Output "    3. Click the blue 'Install in WSL: ERC' button for each missing extension"
} else {
    Write-Output ""
    Write-Output "[OK] All WSL extensions installed successfully!"
    Write-Output ""
    Write-Output "  Development tools are now in WSL remote environment."
    Write-Output ""
    Write-Output "  To verify installed extensions from inside WSL:"
    Write-Output "    wsl -d ERC"
    Write-Output "    code --list-extensions"
}

# ═════════════════════════════════════════════════════════════════════════════
# Write MCP Configuration (Kibana, GitLab, Atlassian) to Windows + WSL
# ═════════════════════════════════════════════════════════════════════════════
Write-Output ""
Write-Output "→ Writing MCP configuration (Kibana + GitLab + Atlassian) to Windows and WSL..."

$pat = if ($env:SETUP_GITLAB_PAT) { $env:SETUP_GITLAB_PAT } else { '' }

# Build MCP JSON with all three servers (including Atlassian)
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
        'atlassian' = [ordered]@{
            command = 'npx'
            args    = @('-y', 'com.atlassian/atlassian-mcp-server')
            env     = @{}
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

# Write to WSL /root/.vscode-server/data/User/mcp.json
$wslNewMcp  = '/mnt/c/Users/Public/DevSetupAgent/mcp_new.json'
$wslPyScript = '/mnt/c/Users/Public/DevSetupAgent/merge_mcp.py'
$wslMcpDest  = '/root/.vscode-server/data/User/mcp.json'
wsl -d ERC --user root -- bash -c "python3 '$wslPyScript' '$wslNewMcp' '$wslMcpDest'"
Write-Output "  [OK] WSL MCP config written to: $wslMcpDest"

# Write to Windows %APPDATA%\Code\User\mcp.json
$windowsMcpPath = Join-Path $env:APPDATA "Code\User\mcp.json"
Write-Output "  → Writing to Windows: $windowsMcpPath"
$mergePsScript = @"
`$newPath = '$newMcpPath'
`$targetPath = '$windowsMcpPath'
`$new = Get-Content `$newPath -Raw | ConvertFrom-Json
`$existing = if (Test-Path `$targetPath) { Get-Content `$targetPath -Raw | ConvertFrom-Json } else { @{} }
if (-not `$existing.servers) { `$existing | Add-Member -NotePropertyName 'servers' -NotePropertyValue @{} -Force }
`$new.servers.PSObject.Properties | ForEach-Object { `$existing.servers | Add-Member -NotePropertyName `$_.Name -NotePropertyValue `$_.Value -Force }
`$targetDir = Split-Path `$targetPath
if (-not (Test-Path `$targetDir)) { New-Item -ItemType Directory -Path `$targetDir -Force | Out-Null }
`$existing | ConvertTo-Json -Depth 10 | Set-Content `$targetPath -Encoding UTF8
Write-Output "MCP config written to `$targetPath"
"@
$mergePsScriptPath = Join-Path $ipcDir 'merge_mcp_windows.ps1'
[System.IO.File]::WriteAllText($mergePsScriptPath, $mergePsScript, $utf8NoBom)
& powershell.exe -ExecutionPolicy Bypass -File $mergePsScriptPath
Write-Output "  [OK] Windows MCP config written to: $windowsMcpPath"

# Update WSL settings.json to include MCP gallery enabled setting
Write-Output "  → Updating WSL settings.json with MCP gallery enabled..."
$cloneDir = if ($env:SETUP_CLONE_DIR) { $env:SETUP_CLONE_DIR } else { '/home/ubuntu/VsCodeProjects/erc' }
$wslSettingsPath = '/root/.vscode-server/data/User/settings.json'
$settingsScript = @"
import json, os
settings_path = '$wslSettingsPath'
workspace_dir = '$cloneDir'

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

# Add workspace trust settings
settings['security.workspace.trust.untrustedFiles'] = 'open'
settings['security.workspace.trust.emptyWindow'] = False

# Ensure directory exists
os.makedirs(os.path.dirname(settings_path), exist_ok=True)

# Write settings
with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)

print(f'VS Code settings configured (MCP gallery + workspace trust) for {workspace_dir}')
"@
$settingsScriptPath = Join-Path $ipcDir 'update_settings.py'
[System.IO.File]::WriteAllText($settingsScriptPath, $settingsScript, $utf8NoBom)
$wslSettingsScript = '/mnt/c/Users/Public/DevSetupAgent/update_settings.py'
wsl -d ERC --user root -- bash -c "python3 '$wslSettingsScript'"
Write-Output "  ✓ WSL settings.json updated with MCP gallery enabled"

Write-Output ""
Write-Output "✓ MCP configuration complete!"
Write-Output "  • Kibana MCP: Ready for log search"
Write-Output "  • GitLab MCP: Ready with configured PAT"
Write-Output "  • Atlassian MCP: Available (requires browser authentication)"
Write-Output ""
Write-Output "  Note: Atlassian MCP requires one-time browser authentication:"
Write-Output "    1. VS Code will prompt to connect to mcp.atlassian.com"
Write-Output "    2. Browser opens → Select Jira → Click Approve → Accept"

} catch {
    Write-Output "✗ Unhandled exception: $($_.Exception.Message)"
    Write-Output "  Type : $($_.Exception.GetType().FullName)"
    Write-Output "  Stack: $($_.ScriptStackTrace)"
    [Console]::Out.Flush()
    exit 1
}
