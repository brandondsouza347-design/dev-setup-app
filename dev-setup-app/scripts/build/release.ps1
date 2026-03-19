# =============================================================================
# release.ps1 — Trigger a cross-platform build from Windows (native or WSL)
#
# Usage:
#   .\release.ps1                         # interactive prompts
#   .\release.ps1 -Version 1.2.3          # build all platforms, publish release
#   .\release.ps1 -Version 1.2.3 -Platforms windows-only
#   .\release.ps1 -Version 1.2.3 -Platforms macos-only
#   .\release.ps1 -Version 1.2.3 -Platforms all -NoRelease
#
# Requirements:  git, internet access
# Auto-installs: GitHub CLI (gh) if not present via winget
# =============================================================================

param(
    [string]$Version   = "",
    [ValidateSet("all","macos-only","windows-only","linux-only")]
    [string]$Platforms = "all",
    [switch]$NoRelease
)

$ErrorActionPreference = "Stop"

# ─── Helpers ─────────────────────────────────────────────────────────────────
function Write-Header($text) {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║$($text.PadLeft([Math]::Floor((50 + $text.Length)/2)).PadRight(50))║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Info($msg)    { Write-Host "  ➜  $msg" -ForegroundColor Cyan }
function Write-Ok($msg)      { Write-Host "  ✓  $msg" -ForegroundColor Green }
function Write-Warn($msg)    { Write-Host "  ⚠  $msg" -ForegroundColor Yellow }
function Write-Fail($msg)    { Write-Host "  ✗  $msg" -ForegroundColor Red; exit 1 }

Write-Header "   Dev Setup — Universal Release Tool   "
Write-Host "  Running on: Windows PowerShell $($PSVersionTable.PSVersion)" -ForegroundColor Cyan
Write-Host ""

# ─── Detect repo root ────────────────────────────────────────────────────────
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot   = Resolve-Path "$ScriptDir\..\..\..\.."
Set-Location $RepoRoot

# ─── Prompt for version ───────────────────────────────────────────────────────
if (-not $Version) {
    try {
        $lastTag = git describe --tags --abbrev=0 2>$null
        $lastTag = $lastTag -replace '^v', ''
        $parts   = $lastTag -split '\.'
        $suggested = "$($parts[0]).$($parts[1]).$([int]$parts[2] + 1)"
    } catch {
        $suggested = "1.0.0"
    }

    Write-Host "  Last release: v$lastTag" -ForegroundColor Yellow
    $Version = Read-Host "  Enter version to release [$suggested]"
    if (-not $Version) { $Version = $suggested }
}

$Version = $Version -replace '^v', ''

# ─── Prompt for platforms ─────────────────────────────────────────────────────
if ($MyInvocation.BoundParameters.Keys -notcontains 'Platforms') {
    Write-Host ""
    Write-Host "  Which platforms to build?"
    Write-Host "    1) all          - macOS DMG + Windows MSI/EXE + Linux AppImage"
    Write-Host "    2) macos-only   - macOS DMG only"
    Write-Host "    3) windows-only - Windows MSI + NSIS installer only"
    Write-Host "    4) linux-only   - Linux AppImage + deb only"
    $platChoice = Read-Host "  Choice [1]"
    switch ($platChoice) {
        "2" { $Platforms = "macos-only" }
        "3" { $Platforms = "windows-only" }
        "4" { $Platforms = "linux-only" }
        default { $Platforms = "all" }
    }

    Write-Host ""
    $pubChoice = Read-Host "  Publish as a GitHub Release? [Y/n]"
    if ($pubChoice -match "^[Nn]") { $NoRelease = $true }
}

$Publish = if ($NoRelease) { "false" } else { "true" }
$Tag     = "v$Version"

Write-Host ""
Write-Host "  Build plan:" -ForegroundColor White
Write-Host "    Version   : $Tag"   -ForegroundColor Green
Write-Host "    Platforms : $Platforms" -ForegroundColor Green
Write-Host "    Publish   : $Publish" -ForegroundColor Green
Write-Host ""

# ─── Check git remote ─────────────────────────────────────────────────────────
Write-Info "Checking git state..."

try {
    $remoteUrl = git remote get-url origin 2>&1
    if ($LASTEXITCODE -ne 0) { throw "no remote" }
} catch {
    Write-Fail "No git remote 'origin' found.`n`n  Add your GitHub repo first:`n    git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO.git`n    git push -u origin master"
}

Write-Ok "Remote: $remoteUrl"

# Commit uncommitted changes
$status = git status --porcelain 2>&1
if ($status) {
    Write-Warn "Uncommitted changes found — committing everything..."
    git add -A
    git commit -m "chore: prepare release $Tag" 2>&1 | Out-Null
}

$currentBranch = git rev-parse --abbrev-ref HEAD
Write-Info "Pushing branch '$currentBranch' to origin..."
git push origin $currentBranch
Write-Ok "Branch pushed"

# ─── Create and push tag ──────────────────────────────────────────────────────
Write-Info "Creating tag $Tag..."

$existingTag = git rev-parse $Tag 2>$null
if ($existingTag) {
    Write-Warn "Tag $Tag already exists."
    $retag = Read-Host "  Delete and recreate? [y/N]"
    if ($retag -match "^[Yy]") {
        git tag -d $Tag
        git push origin ":refs/tags/$Tag" 2>$null
    } else {
        Write-Host "  Aborting. Choose a different version."
        exit 1
    }
}

git tag -a $Tag -m "Release $Tag"
git push origin $Tag
Write-Ok "Tag $Tag pushed — GitHub Actions build triggered"

# ─── Install gh CLI ───────────────────────────────────────────────────────────
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Info "Installing GitHub CLI (gh) via winget..."
    try {
        winget install --id GitHub.cli --accept-source-agreements --accept-package-agreements -e
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path","User")
        Write-Ok "gh CLI installed"
    } catch {
        Write-Warn "Could not auto-install gh. Install manually: https://cli.github.com/"
        Write-Host ""
        Write-Host "  Watch your build at:"
        $repoPath = $remoteUrl -replace 'https://github.com/', '' -replace '\.git$', ''
        Write-Host "    https://github.com/$repoPath/actions" -ForegroundColor Blue
        exit 0
    }
}

# ─── Authenticate if needed ───────────────────────────────────────────────────
try {
    gh auth status 2>&1 | Out-Null
} catch {
    Write-Warn "GitHub CLI not authenticated. Opening browser login..."
    gh auth login --web --hostname github.com
}

# ─── Watch the build ─────────────────────────────────────────────────────────
Write-Host ""
Write-Info "Waiting for GitHub Actions to start..."
Start-Sleep -Seconds 8

# Find the run ID
$runId = $null
for ($i = 0; $i -lt 15; $i++) {
    try {
        $runs = gh run list --workflow build.yml --limit 5 --json databaseId,headBranch,status | ConvertFrom-Json
        $run  = $runs | Where-Object { $_.headBranch -eq $Tag } | Select-Object -First 1
        if ($run) { $runId = $run.databaseId; break }
    } catch {}
    Start-Sleep -Seconds 5
}

$repoPath = $remoteUrl -replace 'https://github.com/', '' -replace '\.git$', ''

if (-not $runId) {
    Write-Warn "Could not find workflow run. Check manually:"
    Write-Host "    https://github.com/$repoPath/actions" -ForegroundColor Blue
} else {
    Write-Ok "Found run ID: $runId"
    Write-Host ""
    Write-Info "Streaming live build output (Ctrl+C to detach — build continues in CI):"
    Write-Host ""

    gh run watch $runId --exit-status

    Write-Host ""
    Write-Host "══════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "  ✅ All builds complete!" -ForegroundColor Green
    Write-Host ""
    if ($Publish -eq "true") {
        Write-Host "  📦 Download from GitHub Release:"
        Write-Host "    https://github.com/$repoPath/releases/tag/$Tag" -ForegroundColor Blue
    } else {
        Write-Host "  📦 Download artifacts from Actions run:"
        Write-Host "    https://github.com/$repoPath/actions/runs/$runId" -ForegroundColor Blue
    }
    Write-Host "══════════════════════════════════════════════════" -ForegroundColor Green
}
