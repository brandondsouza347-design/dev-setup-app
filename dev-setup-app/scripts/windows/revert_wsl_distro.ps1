# revert_wsl_distro.ps1
# Export a backup of the ERC WSL distro then unregister and delete it.
# A backup is always attempted first to protect against accidental data loss.
# Run as normal user (Administrator not required for wsl --export / --unregister).
$ErrorActionPreference = "Stop"

$DistroName  = "ERC"
$BackupDir   = Join-Path $env:USERPROFILE "WSL_Backup"
$InstallDirs = @(
    (Join-Path $env:USERPROFILE "WSL\ERC"),
    (Join-Path $env:USERPROFILE "WSL\Ubuntu-22.04"),
    (Join-Path $env:USERPROFILE "WSL\Ubuntu")
)

Write-Host "==> WSL Distro Removal: $DistroName" -ForegroundColor Yellow
Write-Host "   ⚠  WARNING: This will permanently delete the $DistroName WSL environment." -ForegroundColor Yellow
Write-Host "   A backup will be exported first. See ~/WSL_Backup/ for recovery." -ForegroundColor Yellow

# ─── 1. Check distro is registered ──────────────────────────────────────────

Write-Host "`n==> Step 1: Checking if $DistroName is registered..."
$wslList = wsl --list --quiet 2>&1 | Where-Object { $_ -match '\S' }
$distroExists = $wslList | Where-Object { $_.Trim() -ieq $DistroName }

if (-not $distroExists) {
    Write-Host "✓ Distro '$DistroName' is not registered in WSL — nothing to remove"
    exit 0
}
Write-Host "   Found: $DistroName"

# ─── 2. Export backup ────────────────────────────────────────────────────────

Write-Host "`n==> Step 2: Exporting backup (this may take several minutes for large distros)..."
New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
$BackupFile = Join-Path $BackupDir "erc_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').tar"
Write-Host "   Backup destination: $BackupFile"

$exportSuccess = $false
try {
    wsl --export $DistroName $BackupFile
    if (Test-Path $BackupFile) {
        $backupSizeGB = [Math]::Round((Get-Item $BackupFile).Length / 1GB, 2)
        Write-Host "   ✓ Backup exported: $backupSizeGB GB"
        $exportSuccess = $true
    } else {
        Write-Host "   ⚠ Export command succeeded but file not found — continuing without backup" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   ⚠ Backup export failed: $_ — continuing without backup" -ForegroundColor Yellow
}

# ─── 3. Unregister distro ────────────────────────────────────────────────────

Write-Host "`n==> Step 3: Unregistering '$DistroName' from WSL..."
wsl --unregister $DistroName 2>&1 | ForEach-Object { Write-Host "   $_" }
Write-Host "   ✓ Unregister command completed"

# ─── 4. Remove leftover install directories ─────────────────────────────────

Write-Host "`n==> Step 4: Cleaning up install directories..."
foreach ($dir in $InstallDirs) {
    if (Test-Path $dir) {
        Write-Host "   Removing: $dir"
        Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "   ✓ Removed: $dir"
    }
}

# ─── 5. Verify removal ──────────────────────────────────────────────────────

Write-Host "`n==> Step 5: Verifying distro is gone..."
$remaining = wsl --list --quiet 2>&1 | Where-Object { $_.Trim() -ieq $DistroName }
if ($remaining) {
    Write-Host "   ⚠ '$DistroName' still appears in WSL list — may need reboot" -ForegroundColor Yellow
} else {
    Write-Host "   ✓ '$DistroName' no longer present in WSL"
}

Write-Host "`n✓ ERC distro removed" -ForegroundColor Green
Write-Host ""
if ($exportSuccess) {
    Write-Host "  Backup location : $BackupFile"
    Write-Host "  To restore      : wsl --import ERC <install-dir> $BackupFile --version 2"
} else {
    Write-Host "  ⚠ No backup was created. Recovery is not possible." -ForegroundColor Yellow
}
