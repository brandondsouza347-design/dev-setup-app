# revert_vscode_windows.ps1
# Undo the VS Code Windows/WSL configuration applied by setup_vscode_windows.ps1.
# Removes the written settings.json, mcp.json (if ours), and uninstalls the
# extensions that were installed by the setup step.
# Run as normal user (not Administrator)

$ErrorActionPreference = "Stop"
$DistroName = "ERC"

Write-Host "==> Reverting VS Code Windows/WSL Configuration" -ForegroundColor Cyan

# ─── 1. Locate VS Code ──────────────────────────────────────────────────────

Write-Host "`n==> Step 1: Locating VS Code..."

$CodeCmd = $null
$CodePaths = @(
    "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd",
    "$env:ProgramFiles\Microsoft VS Code\bin\code.cmd",
    "code"
)

foreach ($path in $CodePaths) {
    if (Test-Path $path -ErrorAction SilentlyContinue) {
        $CodeCmd = $path
        break
    }
    try {
        Get-Command $path -ErrorAction Stop | Out-Null
        $CodeCmd = $path
        break
    } catch {}
}

if (-not $CodeCmd) {
    Write-Host "   ⚠ VS Code not found — skipping extension uninstall" -ForegroundColor Yellow
} else {
    Write-Host "✓ VS Code found: $CodeCmd"
}

# ─── 2. Uninstall Windows-side extensions ───────────────────────────────────

if ($CodeCmd) {
    Write-Host "`n==> Step 2: Uninstalling VS Code extensions (Windows-side)..."

    $Extensions = @(
        "ms-vscode-remote.remote-wsl",
        "ms-vscode-remote.vscode-remote-extensionpack",
        "atlassian.atlascode",
        "amazonwebservices.aws-toolkit-vscode",
        "ms-python.black-formatter",
        "dbaeumer.vscode-eslint",
        "mhutchie.git-graph",
        "ms-python.pylint",
        "ms-python.python",
        "ms-python.debugpy",
        "humao.rest-client",
        "GitHub.copilot",
        "GitHub.copilot-chat",
        "redhat.vscode-yaml",
        "eamodio.gitlens",
        "pkief.material-icon-theme",
        "cweijan.vscode-postgresql-client2",
        "liviuschera.noctis"
    )

    $removed = 0
    $skipped = 0
    foreach ($ext in $Extensions) {
        try {
            & $CodeCmd --uninstall-extension $ext 2>&1 | Out-Null
            Write-Host "   ✓ Uninstalled: $ext"
            $removed++
        } catch {
            Write-Host "   - Skipped (not installed): $ext"
            $skipped++
        }
    }
    Write-Host "`n   Extensions: $removed removed, $skipped skipped"
} else {
    Write-Host "`n==> Step 2: Skipped (VS Code not found)"
}

# ─── 3. Uninstall WSL-side extensions ───────────────────────────────────────

if ($CodeCmd) {
    Write-Host "`n==> Step 3: Uninstalling VS Code server extensions inside WSL..."

    $wslDistroExists = $false
    try {
        $wslList = wsl --list --quiet 2>&1 | Out-String
        if ($wslList -match $DistroName) { $wslDistroExists = $true }
    } catch {}

    if ($wslDistroExists) {
        $wslExtensions = @(
            "ms-python.python",
            "ms-python.black-formatter",
            "ms-python.pylint",
            "dbaeumer.vscode-eslint",
            "eamodio.gitlens"
        )
        foreach ($ext in $wslExtensions) {
            try {
                wsl -d $DistroName -- bash -c "code --uninstall-extension $ext --force 2>/dev/null || true"
                Write-Host "   ✓ WSL: $ext"
            } catch {
                Write-Host "   - WSL skipped: $ext"
            }
        }
    } else {
        Write-Host "   ⚠ WSL distro '$DistroName' not found — skipping WSL extension removal" -ForegroundColor Yellow
    }
}

# ─── 4. Remove VS Code settings.json ────────────────────────────────────────

Write-Host "`n==> Step 4: Removing VS Code user settings..."

$SettingsFile = Join-Path $env:APPDATA "Code\User\settings.json"
if (Test-Path $SettingsFile) {
    Remove-Item -Path $SettingsFile -Force
    Write-Host "✓ Removed: $SettingsFile"
} else {
    Write-Host "   - settings.json not found — nothing to remove"
}

# ─── 5. Remove mcp.json (only if it matches our template) ───────────────────

Write-Host "`n==> Step 5: Checking mcp.json..."

$McpFile = Join-Path $env:APPDATA "Code\User\mcp.json"
if (Test-Path $McpFile) {
    $mcpContent = Get-Content -Path $McpFile -Raw -ErrorAction SilentlyContinue
    # Only remove if it still has our template markers (both our known servers present)
    if ($mcpContent -match "tocharian/mcp-server-kibana" -and $mcpContent -match "zereight/mcp-gitlab") {
        Remove-Item -Path $McpFile -Force
        Write-Host "✓ Removed mcp.json (contained our template config)"
    } else {
        Write-Host "   ⚠ mcp.json has been customised — leaving it intact" -ForegroundColor Yellow
    }
} else {
    Write-Host "   - mcp.json not found — nothing to remove"
}

Write-Host "`n✓ VS Code Windows/WSL configuration reverted" -ForegroundColor Green
