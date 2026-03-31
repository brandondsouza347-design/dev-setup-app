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
    if ($path -eq "code") {
        if (Get-Command "code" -ErrorAction SilentlyContinue) {
            $CodeCmd = "code"
            break
        }
    } elseif (Test-Path $path -ErrorAction SilentlyContinue) {
        $CodeCmd = $path
        break
    }
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

# ─── 3. Remove VS Code settings.json ────────────────────────────────────────

Write-Host "`n==> Step 3: Removing VS Code user settings..."

$SettingsFile = Join-Path $env:APPDATA "Code\User\settings.json"
if (Test-Path $SettingsFile) {
    Remove-Item -Path $SettingsFile -Force
    Write-Host "✓ Removed: $SettingsFile"
} else {
    Write-Host "   - settings.json not found — nothing to remove"
}

# ─── 4. Remove mcp.json (only if it matches our template) ───────────────────

Write-Host "`n==> Step 4: Checking mcp.json..."

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
