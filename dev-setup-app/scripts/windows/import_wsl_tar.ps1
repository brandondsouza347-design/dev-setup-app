# import_wsl_tar.ps1 — Import ERC Ubuntu from a TAR file into WSL2
# Run as normal user (not Administrator required)

$ErrorActionPreference = "Stop"

$TarPath     = $env:SETUP_WSL_TAR_PATH
$InstallDir  = $env:SETUP_WSL_INSTALL_DIR
$DistroName  = "ERC"

# Default paths if not provided via environment
if (-not $TarPath) {
    $TarPath = Join-Path $env:USERPROFILE "ubuntu_22.04_modified.tar"
}
if (-not $InstallDir) {
    $InstallDir = Join-Path $env:USERPROFILE "WSL\Ubuntu-22.04"
}

Write-Host "==> WSL ERC Ubuntu Import" -ForegroundColor Cyan
Write-Host "    TAR file     : $TarPath"
Write-Host "    Install dir  : $InstallDir"
Write-Host "    Distro name  : $DistroName"

# ─── 1. Check TAR file ──────────────────────────────────────────────────────

Write-Host "`n==> Step 1: Verifying TAR file..."
if (-not (Test-Path $TarPath)) {
    Write-Host "ERROR: TAR file not found at: $TarPath" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please place the Ubuntu 22.04 TAR file at one of these locations:" -ForegroundColor Yellow
    Write-Host "  - $($env:USERPROFILE)\ubuntu_22.04_modified.tar" -ForegroundColor Yellow
    Write-Host "  - Or configure the path in the Settings screen." -ForegroundColor Yellow
    exit 1
}

$TarSize = (Get-Item $TarPath).Length / 1GB
Write-Host "✓ TAR file found: $([Math]::Round($TarSize, 2)) GB"

# ─── 2. Check if distro already imported ────────────────────────────────────

Write-Host "`n==> Step 2: Checking for existing distro..."
$existingDistros = wsl --list --quiet 2>$null | Where-Object { $_ -match $DistroName }
if ($existingDistros) {
    Write-Host "✓ $DistroName is already registered in WSL"
    Write-Host "   Skipping import. Use 'wsl -d $DistroName' to access it."
    exit 0
}
Write-Host "   Distro not yet imported, proceeding..."

# ─── 3. Create install directory ────────────────────────────────────────────

Write-Host "`n==> Step 3: Creating installation directory..."
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Write-Host "✓ Created: $InstallDir"
} else {
    Write-Host "✓ Directory exists: $InstallDir"
}

# ─── 4. Import the TAR ──────────────────────────────────────────────────────

Write-Host "`n==> Step 4: Importing Ubuntu 22.04 (this may take 5-15 minutes)..."
Write-Host "    Source : $TarPath"
Write-Host "    Target : $InstallDir"

$importStart = Get-Date
wsl --import $DistroName $InstallDir $TarPath --version 2
$importEnd = Get-Date
$importDuration = [Math]::Round(($importEnd - $importStart).TotalMinutes, 1)

Write-Host "✓ Import completed in $importDuration minutes"

# ─── 5. Set WSL2 version ────────────────────────────────────────────────────

Write-Host "`n==> Step 5: Ensuring distro runs on WSL2..."
wsl --set-version $DistroName 2
Write-Host "✓ $DistroName set to WSL2"

# ─── 6. Set as default distribution ─────────────────────────────────────────

Write-Host "`n==> Step 6: Setting $DistroName as default WSL distribution..."
wsl --set-default $DistroName
Write-Host "✓ $DistroName set as default WSL distro"

# ─── 7. Initial boot & user setup ──────────────────────────────────────────

Write-Host "`n==> Step 7: Running initial boot check..."
$bootResult = wsl -d $DistroName -- echo "WSL is running" 2>&1
if ($bootResult -match "WSL is running") {
    Write-Host "✓ WSL distro boots successfully"
} else {
    Write-Host "⚠ Could not verify boot. Try: wsl -d $DistroName" -ForegroundColor Yellow
}

# ─── 8. Verify ──────────────────────────────────────────────────────────────

Write-Host "`n==> WSL Distros registered:"
wsl --list --verbose

Write-Host "`n✓ ERC Ubuntu import complete!" -ForegroundColor Green
Write-Host ""
Write-Host "  Access with   : wsl -d $DistroName"
Write-Host "  Or just       : wsl  (it's the default)"
Write-Host "  Install dir   : $InstallDir"
