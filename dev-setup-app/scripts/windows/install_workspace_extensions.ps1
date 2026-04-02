# install_workspace_extensions.ps1 — Install all recommended extensions from
# Propello.code-workspace into the ERC WSL remote and the local Windows host.
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

# ── Install into WSL remote (ERC) ────────────────────────────────────────────
Write-Output ""
Write-Output "→ Installing into WSL remote (wsl+ERC)..."
$wslSuccess = 0
$wslFail    = 0
foreach ($ext in $extensions) {
    Write-Output "  [WSL] $ext"
    $result = & $codePath --remote "wsl+ERC" --install-extension $ext --force 2>&1
    $result | ForEach-Object { Write-Output "    $_" }
    if ($LASTEXITCODE -eq 0) { $wslSuccess++ } else {
        Write-Output "    [exit $LASTEXITCODE]"
        $wslFail++
    }
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
    if ($LASTEXITCODE -eq 0) { $localSuccess++ } else {
        Write-Output "    [exit $LASTEXITCODE]"
        $localFail++
    }
}
Write-Output "  Local: $localSuccess installed, $localFail failed."

Write-Output ""
if ($wslFail -gt 0 -or $localFail -gt 0) {
    Write-Output "⚠ Some extensions failed to install — check output above."
    Write-Output "  This is often a network issue. Retry this step once connected."
} else {
    Write-Output "✓ All $($extensions.Count) extensions installed successfully."
}

} catch {
    Write-Output "✗ Unhandled exception: $($_.Exception.Message)"
    Write-Output "  Type : $($_.Exception.GetType().FullName)"
    Write-Output "  Stack: $($_.ScriptStackTrace)"
    [Console]::Out.Flush()
    exit 1
}
