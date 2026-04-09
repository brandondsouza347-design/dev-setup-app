# setup_vscode_windows.ps1 — Install VS Code Remote-WSL extension and configure VS Code for WSL
# Run as normal user (not Administrator)

$ErrorActionPreference = "Stop"
$DistroName = "ERC"

# Helper function to flush output to ensure logs appear in Tauri UI
function Flush-Output { [Console]::Out.Flush() }

Write-Output "==> VS Code Windows/WSL Configuration"
Flush-Output

# ─── 1. Locate VS Code ────────────────────────────────────────────────

Write-Output ""
Write-Output "==> Step 1: Locating VS Code..."
Flush-Output

$CodeCmd = $null
$CodePaths = @(
    "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd",
    "$env:ProgramFiles\Microsoft VS Code\bin\code.cmd",
    "code"
)

foreach ($path in $CodePaths) {
    if ($path -eq "code") {
        # PATH lookup — only for the plain 'code' fallback
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
    Write-Output "[WARN] VS Code not found. Attempting to install via winget..."
    try {
        winget install --id Microsoft.VisualStudioCode --accept-source-agreements --accept-package-agreements -e
        $CodeCmd = "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd"
        Write-Output "[OK] VS Code installed via winget"
    } catch {
        Write-Output "ERROR: Could not install VS Code. Please install manually from: https://code.visualstudio.com/"
        Write-Output "       Then re-run this step."
        exit 1
    }
}

Write-Output "[OK] VS Code found: $CodeCmd"
Flush-Output

# ─── 1.5. Configure SSL bypass for corporate proxy environments ─────────────

Write-Output ""
Write-Output "==> Step 1.5: Configuring SSL bypass for corporate proxy..."
Flush-Output

# Set global environment variables for this PowerShell session
$env:NODE_TLS_REJECT_UNAUTHORIZED = "0"
$env:NODE_NO_WARNINGS = "1"
$env:STRICT_SSL = "false"
$env:NPM_CONFIG_STRICT_SSL = "false"

# Configure npm to bypass SSL (VS Code uses npm internally for extensions)
try {
    npm config set strict-ssl false --global 2>&1 | Out-Null
    Write-Output "[OK] npm strict-ssl disabled globally"
} catch {
    Write-Output "[WARN] Could not configure npm (may not be installed yet) - continuing..."
}

# Configure Git to accept self-signed certificates (extensions may use Git)
try {
    git config --global http.sslVerify false 2>&1 | Out-Null
    Write-Output "[OK] Git SSL verification disabled globally"
} catch {
    Write-Output "[WARN] Could not configure Git (may not be installed yet) - continuing..."
}

# Pre-configure VS Code settings to bypass SSL (before extension installation)
Write-Output "[OK] Configuring VS Code proxy settings..."
$SettingsDir = Join-Path $env:APPDATA "Code\User"
New-Item -ItemType Directory -Path $SettingsDir -Force | Out-Null
$SettingsFile = Join-Path $SettingsDir "settings.json"

# Read existing settings if they exist
$existingSettings = @{}
if (Test-Path $SettingsFile) {
    try {
        $existingSettings = Get-Content $SettingsFile -Raw | ConvertFrom-Json -AsHashtable
    } catch {
        # Invalid JSON or empty file - start fresh
        $existingSettings = @{}
    }
}

# Add proxy bypass settings
$existingSettings["http.proxyStrictSSL"] = $false
$existingSettings["http.proxy"] = ""
$existingSettings | ConvertTo-Json -Depth 10 | Set-Content -Path $SettingsFile -Encoding UTF8
Write-Output "[OK] VS Code proxy settings configured"
Flush-Output

# ─── 2. Install extensions ────────────────────────────────────────────────────

Write-Output ""
Write-Output "==> Step 2: Installing VS Code extensions..."
Flush-Output

$Extensions = @(
    "ms-vscode-remote.remote-wsl",              # Remote - WSL (critical for WSL connection)
    "ms-vscode-remote.vscode-remote-extensionpack",  # Remote extension pack
    "atlassian.atlascode",                      # Jira & Bitbucket (Windows UI integration)
    "amazonwebservices.aws-toolkit-vscode",     # AWS Toolkit (Windows UI)
    "pkief.material-icon-theme",                # Material Icon Theme (Windows UI)
    "ms-azuretools.vscode-docker",              # Docker (Windows UI)
    "gruntfuggly.todo-tree",                    # TODO Tree (Windows UI)
    "streetsidesoftware.code-spell-checker"     # Spell Checker (Windows UI)
    # NOTE: Development extensions (Python, ESLint, GitLens, etc.) are installed to WSL
    # in the separate installation step to avoid conflicts with WSL remote installation
)

$installed = 0
$failed = 0
$failedExtensions = @()
$totalExtensions = $Extensions.Count

Write-Output "   → Installing $totalExtensions extensions to Windows..."
Write-Output ""
Flush-Output

foreach ($ext in $Extensions) {
    Write-Output "   [$($installed + $failed + 1)/$totalExtensions] Installing: $ext"

    try {
        # Environment variables already set globally above
        # Use 2>&1 to capture both stdout and stderr
        $result = & $CodeCmd --install-extension $ext --force 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Output "      [OK] Successfully installed"
            Flush-Output
            $installed++
        } else {
            Write-Output "      [ERROR] FAILED (exit code: $LASTEXITCODE)"
            Flush-Output
            if ($result) {
                # Show first line of error only
                $errorLine = ($result | Select-Object -First 1).ToString()
                Write-Output "      Error: $errorLine"
            }
            $failed++
            $failedExtensions += $ext
        }
    } catch {
        Write-Output "      [ERROR] EXCEPTION"
        Write-Output "      Error: $($_.Exception.Message)"
        Flush-Output
        $failed++
        $failedExtensions += $ext
    }
}

Write-Output ""
Write-Output "   Summary: $installed installed, $failed failed (out of $totalExtensions)"
Flush-Output

# Critical extensions that must succeed
$criticalExtensions = @("ms-vscode-remote.remote-wsl")
$criticalFailed = $failedExtensions | Where-Object { $criticalExtensions -contains $_ }

if ($criticalFailed.Count -gt 0) {
    Write-Output ""
    Write-Output "[WARN] CRITICAL: The following required extensions failed to install:"
    foreach ($ext in $criticalFailed) {
        Write-Output "   - $ext"
    }
    Write-Output ""
    Write-Output "Please install these extensions manually:"
    Write-Output "   1. Open VS Code"
    Write-Output "   2. Press Ctrl+Shift+X to open Extensions"
    Write-Output "   3. Search for and install: $($criticalFailed -join ', ')"
    Write-Output ""
    Write-Output "Continuing with remaining setup steps..."
    Flush-Output
}

# ─── 3. Write VS Code user settings ─────────────────────────────────────────────

Write-Output ""
Write-Output "==> Step 3: Writing VS Code user settings..."
Flush-Output

$SettingsDir = Join-Path $env:APPDATA "Code\User"
New-Item -ItemType Directory -Path $SettingsDir -Force | Out-Null
$SettingsFile = Join-Path $SettingsDir "settings.json"

$NodeVersion   = if ($env:SETUP_NODE_VERSION)   { $env:SETUP_NODE_VERSION }   else { "16.20.2" }
$PythonVersion = if ($env:SETUP_PYTHON_VERSION) { $env:SETUP_PYTHON_VERSION } else { "3.9.21" }
$VenvName      = if ($env:SETUP_VENV_NAME)      { $env:SETUP_VENV_NAME }      else { "erc" }
$WSLPythonPath = "/home/ubuntu/.pyenv/versions/$VenvName/bin/python"

$Settings = @"
{
    "aws.cloudformation.telemetry.enabled": false,
    "aws.resources.enabledResources": [
        "AWS::DynamoDB::GlobalTable",
        "AWS::DynamoDB::Table"
    ],
    "atlascode.jira.enabled": true,
    "atlascode.bitbucket.enabled": false,
    "chat.useAgentSkills": true,
    "chat.mcp.gallery.enabled": true,
    "chat.agent.enabled": true,
    "chat.instructionsFilesLocations": {
        ".github/instructions": true,
        ".claude/rules": true,
        "~/.copilot/instructions": true,
        "~/.claude/rules": true
    },
    "chat.viewSessions.orientation": "stacked",
    "debug.console.closeOnEnd": true,
    "debug.console.wordWrap": false,
    "debug.breakpointsView.presentation": "tree",
    "diffEditor.ignoreTrimWhitespace": false,
    "diffEditor.hideUnchangedRegions.enabled": false,
    "files.autoSave": "afterDelay",
    "files.trimTrailingWhitespace": true,
    "files.insertFinalNewline": true,
    "git.autofetch": true,
    "git.detectSubmodules": false,
    "git.fetchOnPull": true,
    "git.ignoreLegacyWarning": true,
    "git.openRepositoryInParentFolders": "never",
    "git.pruneOnFetch": true,
    "git.rebaseWhenSync": true,
    "git.untrackedChanges": "separate",
    "git-graph.commitDetailsView.autoCenter": true,
    "gitlens.blame.compact": false,
    "gitlens.blame.format": "`${date} `${author}",
    "gitlens.blame.ignoreWhitespace": true,
    "gitlens.codeLens.scopes": ["document"],
    "gitlens.currentLine.format": "`${author}, `${agoOrDate} • `${message}",
    "gitlens.currentLine.pullRequests.enabled": false,
    "gitlens.defaultDateFormat": "MM/DD/YY",
    "gitlens.defaultDateShortFormat": "MMM D, YYYY",
    "gitlens.defaultDateSource": "committed",
    "gitlens.defaultTimeFormat": "h:mma",
    "gitlens.graph.minimap.enabled": false,
    "gitlens.graph.showDetailsView": false,
    "gitlens.graph.sidebar.enabled": false,
    "gitlens.graph.statusBar.enabled": false,
    "gitlens.hovers.currentLine.over": "line",
    "gitlens.statusBar.format": "`${author}, `${agoOrDate}",
    "gitlens.statusBar.pullRequests.enabled": false,
    "gitlens.views.commitDetails.autolinks.enabled": true,
    "gitlens.views.commitDetails.files.layout": "tree",
    "gitlens.views.commits.files.layout": "list",
    "gitlens.ai.model": "vscode",
    "gitlens.ai.vscode.model": "copilot:gpt-4.1",
    "github.copilot.nextEditSuggestions.enabled": true,
    "grunt.autoDetect": "on",
    "merge-conflict.autoNavigateNextConflict.enabled": true,
    "pylint.importStrategy": "fromEnvironment",
    "redhat.telemetry.enabled": false,
    "remote.autoForwardPortsSource": "hybrid",
    "rest-client.previewOption": "exchange",
    "task.allowAutomaticTasks": "on",
    "terminal.integrated.cwd": "`${workspaceFolder}",
    "terminal.integrated.defaultProfile.windows": "ERC (WSL)",
    "terminal.integrated.fontFamily": "UbuntuMono Nerd Font",
    "terminal.integrated.scrollback": 100000,
    "terminal.integrated.smoothScrolling": true,
    "terminal.integrated.rightClickBehavior": "default",
    "window.restoreWindows": "none",
    "window.zoomLevel": 0.5,
    "workbench.iconTheme": "material-icon-theme",
    "workbench.list.smoothScrolling": true,
    "[python]": {
        "editor.defaultFormatter": "ms-python.black-formatter",
        "diffEditor.ignoreTrimWhitespace": true
    },
    "black-formatter.args": ["--line-length", "88"],
    "pylint.enabled": true,
    "eslint.enable": true
}
"@

Set-Content -Path $SettingsFile -Value $Settings -Encoding UTF8
Write-Output "[OK] Settings written to: $SettingsFile"
Flush-Output

# ─── 4. Write MCP config ─────────────────────────────────────────────────────────
# NOTE: WSL extension installation is handled by a separate dedicated step
#       (install_workspace_extensions.ps1) to avoid conflicts

Write-Output ""
Write-Output "==> Step 4: Writing VS Code MCP config..."
Flush-Output

$McpFile = Join-Path $env:APPDATA "Code\User\mcp.json"

if (Test-Path $McpFile) {
    Write-Output "   [WARN] $McpFile already exists — skipping to avoid overwriting customisations"
    Write-Output "   Ensure the following servers are present:"
    Write-Output "     kibana    (@tocharian/mcp-server-kibana)"
    Write-Output "     gitlab    (@zereight/mcp-gitlab)"
    Write-Output "     atlassian (com.atlassian/atlassian-mcp-server)"
    Flush-Output
} else {
    $McpConfig = @"
{
    "servers": {
        "kibana": {
            "type": "stdio",
            "command": "npx",
            "args": ["@tocharian/mcp-server-kibana"],
            "env": {
                "KIBANA_URL": "https://mulog.toogoerp.net",
                "KIBANA_DEFAULT_SPACE": "default",
                "NODE_TLS_REJECT_UNAUTHORIZED": "0"
            }
        },
        "gitlab": {
            "type": "stdio",
            "command": "npx",
            "args": ["-y", "@zereight/mcp-gitlab"],
            "env": {
                "GITLAB_PERSONAL_ACCESS_TOKEN": "<your-gitlab-pat-here>",
                "GITLAB_API_URL": "https://gitlab.toogoerp.net",
                "USE_GITLAB_WIKI": "true",
                "USE_MILESTONE": "true"
            }
        },
        "atlassian": {
            "command": "npx",
            "args": ["-y", "com.atlassian/atlassian-mcp-server"],
            "env": {}
        }
    }
}
"@
    New-Item -ItemType Directory -Path (Split-Path $McpFile) -Force | Out-Null
    Set-Content -Path $McpFile -Value $McpConfig -Encoding UTF8
    Write-Output "[OK] MCP config written to: $McpFile"
    Write-Output "  ACTION REQUIRED: Replace <your-gitlab-pat-here> with your actual GitLab PAT"
    Write-Output "  NOTE: Atlassian MCP requires one-time browser authentication"
    Flush-Output
}

Write-Output ""
Write-Output "[OK] VS Code Windows/WSL setup complete!"
Flush-Output
Write-Output ""
Write-Output "  To open a WSL project in VS Code:"
Write-Output "    1. Open VS Code"
Write-Output "    2. Press Ctrl+Shift+P → 'Remote-WSL: Open Folder in WSL'"
Write-Output "    3. Or from WSL terminal: code /path/to/project"
Write-Output ""
Write-Output "  Remote WSL extension allows full Python/Node development inside WSL"
