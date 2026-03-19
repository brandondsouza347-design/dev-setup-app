# setup_vscode_windows.ps1 — Install VS Code Remote-WSL extension and configure VS Code for WSL
# Run as normal user (not Administrator)

$ErrorActionPreference = "Stop"
$DistroName = "Ubuntu-22.04"

Write-Host "==> VS Code Windows/WSL Configuration" -ForegroundColor Cyan

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
    Write-Host "⚠ VS Code not found. Attempting to install via winget..." -ForegroundColor Yellow
    try {
        winget install --id Microsoft.VisualStudioCode --accept-source-agreements --accept-package-agreements -e
        $CodeCmd = "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd"
        Write-Host "✓ VS Code installed via winget"
    } catch {
        Write-Host "ERROR: Could not install VS Code. Please install manually from: https://code.visualstudio.com/" -ForegroundColor Red
        Write-Host "       Then re-run this step." -ForegroundColor Red
        exit 1
    }
}

Write-Host "✓ VS Code found: $CodeCmd"
& $CodeCmd --version | Select-Object -First 1

# ─── 2. Install extensions ──────────────────────────────────────────────────

Write-Host "`n==> Step 2: Installing VS Code extensions..."

$Extensions = @(
    "ms-vscode-remote.remote-wsl",      # Remote - WSL (critical)
    "ms-vscode-remote.vscode-remote-extensionpack",
    "atlassian.atlascode",              # Jira & Bitbucket
    "amazonwebservices.aws-toolkit-vscode",
    "ms-python.black-formatter",
    "dbaeumer.vscode-eslint",
    "mhutchie.git-graph",
    "ms-python.pylint",
    "ms-python.python",
    "ms-python.debugpy",
    "humao.rest-client",
    "codeium.codeium",
    "redhat.vscode-yaml",
    "eamodio.gitlens"
)

$installed = 0
$failed = 0
foreach ($ext in $Extensions) {
    Write-Host "   Installing: $ext"
    try {
        & $CodeCmd --install-extension $ext --force 2>&1 | Out-Null
        Write-Host "   ✓ $ext"
        $installed++
    } catch {
        Write-Host "   ⚠ Failed: $ext"
        $failed++
    }
}

Write-Host "`n   Extensions: $installed installed, $failed failed"

# ─── 3. Write VS Code user settings ─────────────────────────────────────────

Write-Host "`n==> Step 3: Writing VS Code user settings..."

$SettingsDir = Join-Path $env:APPDATA "Code\User"
New-Item -ItemType Directory -Path $SettingsDir -Force | Out-Null
$SettingsFile = Join-Path $SettingsDir "settings.json"

$NodeVersion   = if ($env:SETUP_NODE_VERSION)   { $env:SETUP_NODE_VERSION }   else { "16.20.2" }
$PythonVersion = if ($env:SETUP_PYTHON_VERSION) { $env:SETUP_PYTHON_VERSION } else { "3.9.21" }
$VenvName      = if ($env:SETUP_VENV_NAME)      { $env:SETUP_VENV_NAME }      else { "erc" }
$WSLPythonPath = "/home/$DistroName/.pyenv/versions/$VenvName/bin/python"

$Settings = @"
{
    "editor.formatOnSave": true,
    "editor.tabSize": 4,
    "editor.insertSpaces": true,
    "editor.rulers": [88, 120],
    "editor.trimAutoWhitespace": true,
    "files.trimTrailingWhitespace": true,
    "files.insertFinalNewline": true,
    "terminal.integrated.defaultProfile.windows": "Ubuntu-22.04 (WSL)",
    "python.defaultInterpreterPath": "$WSLPythonPath",
    "[python]": {
        "editor.defaultFormatter": "ms-python.black-formatter"
    },
    "black-formatter.args": ["--line-length", "88"],
    "pylint.enabled": true,
    "eslint.enable": true,
    "git.autofetch": true,
    "git.confirmSync": false,
    "remote.WSL.fileWatcher.polling": true,
    "workbench.colorTheme": "Default Dark Modern",
    "workbench.iconTheme": "vs-seti",
    "window.zoomLevel": 0
}
"@

Set-Content -Path $SettingsFile -Value $Settings -Encoding UTF8
Write-Host "✓ Settings written to: $SettingsFile"

# ─── 4. Install extensions inside WSL ────────────────────────────────────────

Write-Host "`n==> Step 4: Installing VS Code server extensions inside WSL..."

$wslExtensions = @(
    "ms-python.python",
    "ms-python.black-formatter",
    "ms-python.pylint",
    "dbaeumer.vscode-eslint",
    "eamodio.gitlens"
)

foreach ($ext in $wslExtensions) {
    try {
        wsl -d $DistroName -- bash -c "code --install-extension $ext --force 2>/dev/null || true"
        Write-Host "   ✓ WSL: $ext"
    } catch {
        Write-Host "   ⚠ Could not install in WSL: $ext"
    }
}

Write-Host "`n✓ VS Code Windows/WSL setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "  To open a WSL project in VS Code:"
Write-Host "    1. Open VS Code"
Write-Host "    2. Press Ctrl+Shift+P → 'Remote-WSL: Open Folder in WSL'"
Write-Host "    3. Or from WSL terminal: code /path/to/project"
Write-Host ""
Write-Host "  Remote WSL extension allows full Python/Node development inside WSL"
