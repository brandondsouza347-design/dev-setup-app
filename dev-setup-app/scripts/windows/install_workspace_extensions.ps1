# install_workspace_extensions.ps1 — Install all recommended extensions from
# Propello.code-workspace into the ERC WSL remote and the local Windows host.
# This step runs after setup_workspace so the workspace file is guaranteed to
# exist in the cloned repo.
$ErrorActionPreference = 'Stop'

$cloneDir = $env:SETUP_CLONE_DIR
if (-not $cloneDir) { $cloneDir = '/home/ubuntu/VsCodeProjects/erc' }

# ── Locate code.cmd ──────────────────────────────────────────────────────────
$codePath = $null
foreach ($p in ($env:PATH -split ';' | Where-Object { $_ -ne '' })) {
    $c = Join-Path $p 'code.cmd'
    if (Test-Path $c) { $codePath = $c; break }
}
if (-not $codePath) {
    foreach ($c in @(
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd",
        "$env:ProgramFiles\Microsoft VS Code\bin\code.cmd"
    )) {
        if (Test-Path $c) { $codePath = $c; break }
    }
}
if (-not $codePath) {
    Write-Output "✗ VS Code (code.cmd) not found on PATH."
    Write-Output "  Install VS Code and ensure it is on PATH, then retry this step."
    exit 1
}
Write-Output "✓ VS Code found: $codePath"

# ── Read Propello.code-workspace from WSL ────────────────────────────────────
Write-Output "→ Reading Propello.code-workspace from $cloneDir..."
$wsContent = (wsl -d ERC -- bash -c "cat '$cloneDir/Propello.code-workspace' 2>/dev/null") -join "`n"

if (-not $wsContent) {
    Write-Output "✗ Could not read Propello.code-workspace."
    Write-Output "  Ensure the 'Clone Project Repository' step completed successfully."
    exit 1
}

# Strip JSONC comments and trailing commas so ConvertFrom-Json can parse it
$stripped = $wsContent `
    -replace '(?m)//[^\r\n]*', '' `
    -replace ',(\s*[}\]])', '$1'

$extensions = @()
try {
    $ws = $stripped | ConvertFrom-Json
    $extensions = @($ws.extensions.recommendations)
} catch {
    Write-Output "✗ Failed to parse workspace JSON: $_"
    exit 1
}

if ($extensions.Count -eq 0) {
    Write-Output "⚠ No extensions found in workspace recommendations — nothing to install."
    exit 0
}

Write-Output "→ Found $($extensions.Count) recommended extension(s)."

# ── Install into WSL remote (ERC) ────────────────────────────────────────────
Write-Output ""
Write-Output "→ Installing into WSL remote (wsl+ERC)..."
$wslSuccess = 0
$wslFail    = 0
foreach ($ext in $extensions) {
    Write-Output "  [WSL] $ext"
    $result = & $codePath --remote "wsl+ERC" --install-extension $ext --force 2>&1
    $result | ForEach-Object { Write-Output "    $_" }
    if ($LASTEXITCODE -eq 0) { $wslSuccess++ } else { $wslFail++ }
}
Write-Output "  WSL remote: $wslSuccess installed, $wslFail failed."

# ── Install locally (Windows host) ──────────────────────────────────────────
Write-Output ""
Write-Output "→ Installing into local Windows VS Code..."
$localSuccess = 0
$localFail    = 0
foreach ($ext in $extensions) {
    Write-Output "  [local] $ext"
    $result = & $codePath --install-extension $ext --force 2>&1
    $result | ForEach-Object { Write-Output "    $_" }
    if ($LASTEXITCODE -eq 0) { $localSuccess++ } else { $localFail++ }
}
Write-Output "  Local: $localSuccess installed, $localFail failed."

Write-Output ""
if ($wslFail -gt 0 -or $localFail -gt 0) {
    Write-Output "⚠ Some extensions failed to install — check output above."
    Write-Output "  This is often a network issue. Retry this step once connected."
} else {
    Write-Output "✓ All $($extensions.Count) extensions installed successfully."
}
