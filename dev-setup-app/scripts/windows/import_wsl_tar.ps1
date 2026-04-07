# import_wsl_tar.ps1 — Import ERC Ubuntu from a TAR file into WSL2
# Run as normal user (not Administrator required)

$ErrorActionPreference = "Stop"

$TarPath     = $env:SETUP_WSL_TAR_PATH
$InstallDir  = $env:SETUP_WSL_INSTALL_DIR
$DistroName  = "ERC"

# Default paths if not provided via environment
if (-not $TarPath) {
    $TarPath = Join-Path $env:USERPROFILE "erc_ubuntu.tar"
}
if (-not $InstallDir) {
    $InstallDir = Join-Path $env:USERPROFILE "WSL\ERC"
}

Write-Host "==> WSL ERC Ubuntu Import" -ForegroundColor Cyan
Write-Host "    TAR file     : $TarPath"
Write-Host "    Install dir  : $InstallDir"
Write-Host "    Distro name  : $DistroName"

# ─── 0. WSL version / kernel check ─────────────────────────────────────────

Write-Host "`n==> Step 0: WSL environment info..."
try {
    $wslVer = wsl --version 2>&1
    Write-Host ($wslVer | Out-String).Trim()
} catch {
    Write-Host "   (wsl --version not available on this build)" -ForegroundColor Yellow
}
Write-Host "   WSL feature list:"
wsl --list --verbose 2>&1 | ForEach-Object { Write-Host "   $_" }

# ─── 1. Check TAR file ──────────────────────────────────────────────────────

Write-Host "`n==> Step 1: Verifying TAR file..."
Write-Host "   Path to check : $TarPath"
Write-Host "   Current user  : $($env:USERNAME)"
Write-Host "   Process is elevated: $((New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"

$pathExists = $false
try {
    $pathExists = Test-Path -LiteralPath $TarPath -ErrorAction Stop
    Write-Host "   Test-Path result: $pathExists"
} catch {
    Write-Host "ERROR: Test-Path threw an exception — $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "   This usually means the process cannot access the path (UAC elevation / permissions)." -ForegroundColor Yellow
    Write-Host "   Try running the app as the same user who owns C:\Users\Brandon\, not as Administrator." -ForegroundColor Yellow
    exit 1
}

if (-not $pathExists) {
    Write-Host "ERROR: TAR file not found at: $TarPath" -ForegroundColor Red
    Write-Host ""
    Write-Host "   Parent directory exists: $(Test-Path (Split-Path $TarPath -Parent) -ErrorAction SilentlyContinue)" -ForegroundColor Yellow
    Write-Host "   USERPROFILE             : $($env:USERPROFILE)" -ForegroundColor Yellow
    Write-Host "   SETUP_WSL_TAR_PATH env  : '$($env:SETUP_WSL_TAR_PATH)'" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Please place the Ubuntu TAR file at the configured path or update it in the Settings screen." -ForegroundColor Yellow
    exit 1
}

$TarItem = $null
try {
    $TarItem = Get-Item -LiteralPath $TarPath -ErrorAction Stop
} catch {
    Write-Host "ERROR: File exists but Get-Item failed — $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
$TarSize = $TarItem.Length / 1GB
Write-Host "✓ TAR file found: $([Math]::Round($TarSize, 2)) GB"

# ─── 2. Check if distro already imported ────────────────────────────────────

Write-Host "`n==> Step 2: Checking for existing distro..."
$existingDistros = (wsl --list --quiet 2>$null) -replace '\0','' | Where-Object { $_ -match $DistroName }
if ($existingDistros) {
    Write-Host "   $DistroName is registered in WSL" -ForegroundColor Yellow

    # Verify the disk file actually exists
    $diskPath = Join-Path $InstallDir "ext4.vhdx"
    if (Test-Path $diskPath) {
        $diskSizeGB = [Math]::Round((Get-Item $diskPath).Length / 1GB, 2)
        Write-Host "✓ Disk file verified: $diskPath ($diskSizeGB GB)" -ForegroundColor Green
        Write-Host "   Skipping import. Use 'wsl -d $DistroName' to access it."
        exit 0
    } else {
        Write-Host "   ⚠ WARNING: Registration exists but disk file not found at: $diskPath" -ForegroundColor Yellow
        Write-Host "   This indicates a broken installation. Unregistering and proceeding with fresh import..." -ForegroundColor Yellow
        wsl --unregister $DistroName 2>&1 | ForEach-Object { Write-Host "     $_" }
        Write-Host "   ✓ Unregistered broken distro, will proceed with import" -ForegroundColor Green
    }
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

# Disk space check
$drive = Split-Path -Qualifier $InstallDir
try {
    $disk = Get-PSDrive ($drive.TrimEnd(':')) -ErrorAction Stop
    $freeGB = [Math]::Round($disk.Free / 1GB, 1)
    Write-Host "   Free disk space on ${drive}: ${freeGB} GB"
    if ($freeGB -lt 5) {
        Write-Host "WARNING: Less than 5 GB free — import may fail" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   (could not check disk space for $drive)" -ForegroundColor Yellow
}

# ─── 4. Import the TAR ──────────────────────────────────────────────────────

Write-Host "`n==> Step 4: Importing Ubuntu 22.04 (this may take 5-15 minutes)..."
Write-Host "    Source : $TarPath"
Write-Host "    Target : $InstallDir"
Write-Host "    Running: wsl --import $DistroName $InstallDir <tarpath> --version 2"

$importStart = Get-Date
$wslImportOutput = wsl --import $DistroName $InstallDir $TarPath --version 2 2>&1
$importExitCode = $LASTEXITCODE
$importEnd = Get-Date
$importDuration = [Math]::Round(($importEnd - $importStart).TotalMinutes, 1)

Write-Host "   wsl --import exit code : $importExitCode"
Write-Host "   wsl --import duration  : $importDuration min"
if ($wslImportOutput) {
    Write-Host "   wsl --import output:"
    $wslImportOutput | ForEach-Object { Write-Host "     $_" }
} else {
    Write-Host "   wsl --import produced no output"
}

Write-Host "`n   Install dir contents after import:"
try {
    $items = Get-ChildItem $InstallDir -ErrorAction Stop
    if ($items) {
        $items | ForEach-Object { Write-Host "     $($_.Name)  ($([Math]::Round($_.Length / 1MB, 1)) MB)" }
    } else {
        Write-Host "     (directory is empty — import likely failed)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "     (could not read directory: $_)" -ForegroundColor Yellow
}

Write-Host "`n   wsl --list --verbose after import:"
wsl --list --verbose 2>&1 | ForEach-Object { Write-Host "     $_" }

# Verify ext4.vhdx was created
$ext4Path = Join-Path $InstallDir "ext4.vhdx"
Write-Host "`n   Verifying disk file creation:"
if (Test-Path $ext4Path) {
    $diskSize = [Math]::Round((Get-Item $ext4Path).Length / 1GB, 2)
    Write-Host "   ✓ Disk file created: $ext4Path ($diskSize GB)" -ForegroundColor Green
} else {
    Write-Host "   ⚠ WARNING: ext4.vhdx not found at $ext4Path" -ForegroundColor Yellow
    Write-Host "   Import may have failed silently or disk is in unexpected location" -ForegroundColor Yellow
}

if ($importExitCode -ne 0) {
    Write-Host "ERROR: wsl --import failed with exit code $importExitCode" -ForegroundColor Red
    Write-Host "   Possible causes:" -ForegroundColor Yellow
    Write-Host "     - WSL2 kernel not installed (run: wsl --update)" -ForegroundColor Yellow
    Write-Host "     - Virtualisation not enabled in BIOS/UEFI" -ForegroundColor Yellow
    Write-Host "     - Insufficient disk space in $InstallDir" -ForegroundColor Yellow
    Write-Host "     - TAR file is corrupt or not a valid WSL rootfs" -ForegroundColor Yellow
    exit 1
}
Write-Host "✓ Import completed in $importDuration minutes"

# ─── 5. Set WSL2 version ────────────────────────────────────────────────────

Write-Host "`n==> Step 5: Ensuring distro runs on WSL2..."
wsl --set-version $DistroName 2
if ($LASTEXITCODE -ne 0) {
    Write-Host "WARNING: wsl --set-version returned $LASTEXITCODE — continuing anyway" -ForegroundColor Yellow
}
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

# ─── Wait until distro appears in WSL registry ───────────────────────────────
# wsl --import returns before the distro is fully committed to the registry.
# Spin until it shows up — no fixed sleep, exit as soon as it is confirmed.
Write-Host "`n==> Waiting until $DistroName is registered in WSL..."
$timeoutSecs = 120
$elapsed = 0
$found = $false
while ($elapsed -lt $timeoutSecs) {
    $rawList = (wsl --list --quiet 2>$null) -replace '\0',''
    $check = $rawList | Where-Object { $_ -match $DistroName }
    if ($check) { $found = $true; break }
    Start-Sleep -Seconds 1
    $elapsed++
    if ($elapsed % 5 -eq 0) {
        $visibleNames = ($rawList | Where-Object { $_ -match '\S' } | ForEach-Object { $_.Trim() }) -join ', '
        Write-Host "   Still waiting... (${elapsed}s) — wsl --list sees: [$visibleNames]"
    }
}
if ($found) {
    Write-Host "✓ $DistroName confirmed in WSL registry after ${elapsed}s"
} else {
    Write-Host "ERROR: $DistroName still not visible in WSL registry after ${timeoutSecs}s" -ForegroundColor Red
    Write-Host "   The import command succeeded but WSL did not register the distro." -ForegroundColor Yellow
    Write-Host "   Try running manually: wsl --list --verbose" -ForegroundColor Yellow
    exit 1
}

# ─── 8. Verify ──────────────────────────────────────────────────────────────

Write-Host "`n==> WSL Distros registered:"
wsl --list --verbose

Write-Host "`n✓ ERC Ubuntu import complete!" -ForegroundColor Green
Write-Host ""
Write-Host "  Access with   : wsl -d $DistroName"
Write-Host "  Or just       : wsl  (it's the default)"
Write-Host "  Install dir   : $InstallDir"
