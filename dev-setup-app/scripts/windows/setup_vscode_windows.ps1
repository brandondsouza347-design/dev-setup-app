# setup_vscode_windows.ps1 — Install VS Code Remote-WSL extension and configure VS Code for WSL
# Run as normal user (not Administrator)

$ErrorActionPreference = "Stop"
$DistroName = "ERC"

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

# ─── 2. Install extensions ──────────────────────────────────────────────────

Write-Host "`n==> Step 2: Installing VS Code extensions..."

$Extensions = @(
    "ms-vscode-remote.remote-wsl",              # Remote - WSL (critical)
    "ms-vscode-remote.vscode-remote-extensionpack",
    "atlassian.atlascode",                      # Jira & Bitbucket
    "amazonwebservices.aws-toolkit-vscode",     # AWS Toolkit
    "ms-python.black-formatter",                # Black Formatter
    "dbaeumer.vscode-eslint",                   # ESLint
    "mhutchie.git-graph",                       # Git Graph
    "ms-python.pylint",                         # Pylint
    "ms-python.python",                         # Python
    "ms-python.debugpy",                        # Python Debugger
    "humao.rest-client",                        # REST Client
    "GitHub.copilot",                           # GitHub Copilot
    "GitHub.copilot-chat",                      # GitHub Copilot Chat
    "redhat.vscode-yaml",                       # YAML
    "eamodio.gitlens",                          # GitLens
    "pkief.material-icon-theme",                # Material Icon Theme
    "cweijan.vscode-postgresql-client2",        # PostgreSQL Client
    "ms-azuretools.vscode-docker",              # Docker
    "gruntfuggly.todo-tree",                    # TODO Tree
    "streetsidesoftware.code-spell-checker"     # Spell Checker
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
    "python.defaultInterpreterPath": "$WSLPythonPath",
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

# ─── 5. Write MCP config ─────────────────────────────────────────────────────

Write-Host "`n==> Step 5: Writing VS Code MCP config..."

$McpFile = Join-Path $env:APPDATA "Code\User\mcp.json"

if (Test-Path $McpFile) {
    Write-Host "   ⚠ $McpFile already exists — skipping to avoid overwriting customisations"
    Write-Host "   Ensure the following servers are present:"
    Write-Host "     kibana  (@tocharian/mcp-server-kibana)"
    Write-Host "     gitlab  (@zereight/mcp-gitlab)"
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
        }
    }
}
"@
    New-Item -ItemType Directory -Path (Split-Path $McpFile) -Force | Out-Null
    Set-Content -Path $McpFile -Value $McpConfig -Encoding UTF8
    Write-Host "✓ MCP config written to: $McpFile"
    Write-Host "  ACTION REQUIRED: Replace <your-gitlab-pat-here> with your actual GitLab PAT"
}

Write-Host "`n✓ VS Code Windows/WSL setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "  To open a WSL project in VS Code:"
Write-Host "    1. Open VS Code"
Write-Host "    2. Press Ctrl+Shift+P → 'Remote-WSL: Open Folder in WSL'"
Write-Host "    3. Or from WSL terminal: code /path/to/project"
Write-Host ""
Write-Host "  Remote WSL extension allows full Python/Node development inside WSL"
