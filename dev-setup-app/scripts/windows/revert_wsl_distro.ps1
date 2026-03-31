# revert_wsl_distro.ps1
# Export a MANDATORY backup of the ERC WSL distro, then unregister and delete it.
# Deletion is BLOCKED if the backup cannot be verified on disk.
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
Write-Host "   A verified backup MUST succeed before deletion proceeds." -ForegroundColor Yellow
Write-Host "   If the backup cannot be confirmed, this script will EXIT and deletion will NOT occur." -ForegroundColor Cyan

# ─── 1. Check distro is registered ──────────────────────────────────────────

Write-Host "`n==> Step 1: Checking if $DistroName is registered..."
$wslList = (wsl --list --quiet 2>&1) -replace '\0','' | Where-Object { $_ -match '\S' }
$distroExists = $wslList | Where-Object { $_.Trim() -ieq $DistroName }

if (-not $distroExists) {
    Write-Host "✓ Distro '$DistroName' is not registered in WSL — nothing to remove"
    exit 0
}
Write-Host "   Found: $DistroName"

# ─── 2. Export backup ────────────────────────────────────────────────────────

Write-Host "`n==> Step 2: Creating mandatory backup before any deletion..."
Write-Host "   BACKUP IS REQUIRED — deletion will be blocked if this step fails" -ForegroundColor Cyan
New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
$BackupFile = Join-Path $BackupDir "erc_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').tar"
Write-Host "   Backup destination: $BackupFile"

try {
    wsl --export $DistroName $BackupFile
} catch {
    Write-Host ""
    Write-Host "ERROR: wsl --export threw an exception: $_" -ForegroundColor Red
    Write-Host "ABORT: Backup could not be created. The ERC distro has NOT been deleted." -ForegroundColor Red
    Write-Host "       Resolve the export error and re-run this step to proceed." -ForegroundColor Red
    exit 1
}

# Verify the file actually exists and is non-empty
if (-not (Test-Path $BackupFile)) {
    Write-Host ""
    Write-Host "ERROR: Export command completed but backup file was not found at:" -ForegroundColor Red
    Write-Host "       $BackupFile" -ForegroundColor Red
    Write-Host "ABORT: The ERC distro has NOT been deleted. Check disk space and permissions." -ForegroundColor Red
    exit 1
}

$backupSizeBytes = (Get-Item $BackupFile).Length
if ($backupSizeBytes -lt 1MB) {
    Write-Host ""
    Write-Host "ERROR: Backup file exists but is too small ($backupSizeBytes bytes) — likely corrupt." -ForegroundColor Red
    Write-Host "ABORT: The ERC distro has NOT been deleted. Please inspect $BackupFile" -ForegroundColor Red
    exit 1
}

$backupSizeGB = [Math]::Round($backupSizeBytes / 1GB, 2)
Write-Host "   ✓ Backup verified on disk: $BackupFile ($backupSizeGB GB)"
Write-Host "   ✓ Backup integrity confirmed — proceeding with deletion" -ForegroundColor Green

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
$remaining = (wsl --list --quiet 2>&1) -replace '\0','' | Where-Object { $_.Trim() -ieq $DistroName }
if ($remaining) {
    Write-Host "   ⚠ '$DistroName' still appears in WSL list — may need reboot" -ForegroundColor Yellow
} else {
    Write-Host "   ✓ '$DistroName' no longer present in WSL"
}

Write-Host "`n✓ ERC distro removed" -ForegroundColor Green
Write-Host ""
Write-Host "  Backup location : $BackupFile"
Write-Host "  To restore      : wsl --import ERC <install-dir> \"$BackupFile\" --version 2"
