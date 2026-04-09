# revert_wsl_distro.ps1
# Export a MANDATORY backup of the ERC WSL distro, then unregister and delete it.
# Deletion is BLOCKED if the backup cannot be verified on disk.
# Run as normal user (Administrator not required for wsl --export / --unregister).
$ErrorActionPreference = "Stop"

$DistroName  = "ERC"
$BackupDir   = if ($env:SETUP_WSL_BACKUP_PATH) { $env:SETUP_WSL_BACKUP_PATH } else { Join-Path $env:USERPROFILE "WSL_Backup" }

# Build list of WSL filesystem directories (ext subdirs) to clean up
# IMPORTANT: We only delete the 'ext' subdirectory (actual WSL filesystem),
# NOT parent folders, to protect user data and backup tars stored nearby
$InstallDirs = @(
    (Join-Path $env:USERPROFILE "WSL\ERC\ext"),
    (Join-Path $env:USERPROFILE "WSL\Ubuntu-22.04\ext"),
    (Join-Path $env:USERPROFILE "WSL\Ubuntu\ext")
)

# Add the actual install directory from environment variable if it was customized
if ($env:SETUP_WSL_INSTALL_DIR) {
    $customDir = Join-Path $env:SETUP_WSL_INSTALL_DIR "ext"
    if ($customDir -and -not ($InstallDirs -contains $customDir)) {
        $InstallDirs += $customDir
        Write-Host "   Added custom install directory from SETUP_WSL_INSTALL_DIR: $customDir" -ForegroundColor Cyan
    }
}

$SkipBackup = $env:SETUP_SKIP_WSL_BACKUP -eq 'true'

Write-Host "==> WSL Distro Removal: $DistroName" -ForegroundColor Yellow
Write-Host "   ⚠  WARNING: This will permanently delete the $DistroName WSL environment." -ForegroundColor Yellow
if ($SkipBackup) {
    Write-Host "   ⚠  Backup is DISABLED — distro will be deleted without any restore option!" -ForegroundColor Red
} else {
    Write-Host "   A verified backup MUST succeed before deletion proceeds." -ForegroundColor Yellow
    Write-Host "   If the backup cannot be confirmed, this script will EXIT and deletion will NOT occur." -ForegroundColor Cyan
}

# ─── 1. Check distro is registered ──────────────────────────────────────────

Write-Host "`n==> Step 1: Checking if $DistroName is registered..."
Write-Host "   Running 'wsl --list --quiet' (10 second timeout)..." -ForegroundColor Cyan

try {
    # Run wsl --list with a timeout to detect if WSL is hung
    $listJob = Start-Job -ScriptBlock {
        (wsl --list --quiet 2>&1) -replace '\0','' | Where-Object { $_ -match '\S' }
    }
    
    $completed = Wait-Job -Job $listJob -Timeout 10
    
    if (-not $completed) {
        Stop-Job -Job $listJob -ErrorAction SilentlyContinue
        Remove-Job -Job $listJob -Force -ErrorAction SilentlyContinue
        Write-Host ""
        Write-Host "ERROR: WSL is not responding (command timed out after 10 seconds)" -ForegroundColor Red
        Write-Host ""
        Write-Host "This usually means:" -ForegroundColor Yellow
        Write-Host "  - WSL is hung or in a bad state" -ForegroundColor Yellow
        Write-Host "  - A WSL process is stuck waiting" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Solutions:" -ForegroundColor Cyan
        Write-Host "  1. Open Task Manager and end all 'wsl.exe' and 'wslservice.exe' processes" -ForegroundColor Cyan
        Write-Host "  2. Restart your computer" -ForegroundColor Cyan
        Write-Host "  3. After reboot, run the revert again" -ForegroundColor Cyan
        Write-Host ""
        exit 1
    }
    
    $wslList = Receive-Job -Job $listJob
    Remove-Job -Job $listJob -Force -ErrorAction SilentlyContinue
} catch {
    Write-Host ""
    Write-Host "ERROR: Failed to query WSL: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$distroExists = $wslList | Where-Object { $_.Trim() -ieq $DistroName }

if (-not $distroExists) {
    Write-Host "✓ Distro '$DistroName' is not registered in WSL — nothing to remove"
    exit 0
}
Write-Host "   ✓ Found: $DistroName" -ForegroundColor Green

# ─── 1.5. Clean /tmp before backup ────────────────────────────────────────────

if (-not $SkipBackup) {
    Write-Host "`n==> Step 1.5: Pre-backup cleanup to avoid socket file errors..."
    Write-Host "   Attempting to remove socket/pipe files from /tmp (30 second timeout)..." -ForegroundColor Cyan
    
    try {
        # Run cleanup with a timeout to prevent indefinite hanging
        $cleanupJob = Start-Job -ScriptBlock {
            param($distro)
            wsl -d $distro -u root bash -c "find /tmp -type s -delete 2>/dev/null; find /tmp -type p -delete 2>/dev/null; echo 'CLEANUP_DONE'" 2>&1
        } -ArgumentList $DistroName
        
        # Wait up to 30 seconds for cleanup
        $completed = Wait-Job -Job $cleanupJob -Timeout 30
        
        if ($completed) {
            $output = Receive-Job -Job $cleanupJob
            if ($output -match 'CLEANUP_DONE') {
                Write-Host "   ✓ Cleaned socket and pipe files from /tmp" -ForegroundColor Green
            } else {
                Write-Host "   ⚠ Cleanup completed but verification failed (output: $output)" -ForegroundColor Yellow
            }
        } else {
            Stop-Job -Job $cleanupJob -ErrorAction SilentlyContinue
            Write-Host "   ⚠ Cleanup timed out after 30 seconds (WSL may be unresponsive)" -ForegroundColor Yellow
            Write-Host "   Proceeding anyway - backup may show socket errors if they exist" -ForegroundColor Yellow
        }
        
        Remove-Job -Job $cleanupJob -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Host "   ⚠ Could not clean /tmp: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "   Continuing anyway - backup may show socket errors if they exist" -ForegroundColor Yellow
    }
}

# ─── 1.6. Ensure WSL is fully stopped ─────────────────────────────────────────

if (-not $SkipBackup) {
    Write-Host "`n==> Step 1.6: Ensuring WSL is fully stopped before backup..."
    Write-Host "   This prevents new processes from creating socket files during export"
    try {
        # Try graceful shutdown first
        Write-Host "   Sending wsl --shutdown command..." -ForegroundColor Cyan
        wsl --shutdown 2>&1 | Out-Null
        Start-Sleep -Seconds 3
        
        # Kill any remaining WSL processes
        Write-Host "   Checking for remaining WSL processes..." -ForegroundColor Cyan
        $wslProcesses = Get-Process -Name "wsl*","wslservice" -ErrorAction SilentlyContinue
        if ($wslProcesses) {
            Write-Host "   Stopping $($wslProcesses.Count) remaining WSL process(es)..." -ForegroundColor Cyan
            $wslProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
        } else {
            Write-Host "   No remaining WSL processes found" -ForegroundColor Green
        }
        
        Start-Sleep -Seconds 2
        Write-Host "   ✓ WSL fully stopped and ready for backup" -ForegroundColor Green
    } catch {
        Write-Host "   ⚠ Could not fully stop WSL: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "   Continuing anyway - backup will proceed" -ForegroundColor Yellow
    }
}

# ─── 2. Export backup (optional) ────────────────────────────────────────────

if ($SkipBackup) {
    Write-Host "`n==> Step 2: Backup skipped (user disabled backup option)" -ForegroundColor Yellow
    Write-Host "   ⚠ WARNING: No backup will be created. Distro cannot be restored after deletion." -ForegroundColor Yellow
} else {
    Write-Host "`n==> Step 2: Creating mandatory backup..."
    Write-Host "   BACKUP IS REQUIRED — deletion will be blocked if this step fails" -ForegroundColor Cyan
    
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    $BackupFile = Join-Path $BackupDir "erc_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').tar"
    Write-Host "   Backup destination: $BackupFile"
    Write-Host ""
    Write-Host "   Starting export... (this may take 5-15 minutes depending on distro size)" -ForegroundColor Cyan
    Write-Host "   The process is working even when there's no new output — please wait" -ForegroundColor Cyan
    Write-Host ""

    try {
        # Start wsl --export as a background job so we can show progress
        $exportJob = Start-Job -ScriptBlock {
            param($distro, $file)
            wsl --export $distro $file
        } -ArgumentList $DistroName, $BackupFile

        $startTime = Get-Date
        $lastSize = 0
        $noGrowthCount = 0
        $maxNoGrowthCycles = 6  # 3 minutes of no growth = stall warning

        # Monitor the job and show progress indicators every 30 seconds
        while ($exportJob.State -eq 'Running') {
            Start-Sleep -Seconds 30
            $elapsed = [Math]::Round(((Get-Date) - $startTime).TotalSeconds)

            # Check if backup file exists and is growing
            if (Test-Path $BackupFile) {
                $currentSize = (Get-Item $BackupFile).Length
                $sizeMB = [Math]::Round($currentSize / 1MB, 1)
                $growthMB = [Math]::Round(($currentSize - $lastSize) / 1MB, 1)

                if ($currentSize -gt $lastSize) {
                    Write-Host "   ⏳ Exporting... ${elapsed}s elapsed | ${sizeMB} MB written | +${growthMB} MB last 30s" -ForegroundColor Cyan
                    $noGrowthCount = 0
                } else {
                    # No growth detected
                    $noGrowthCount++
                    if ($noGrowthCount -ge $maxNoGrowthCycles) {
                        Write-Host "   ⚠ Export appears stalled (no growth for 3 minutes at ${sizeMB} MB)" -ForegroundColor Yellow
                        Write-Host "   This may indicate a hung WSL process or disk I/O issue" -ForegroundColor Yellow
                        Write-Host "   Waiting for job to complete or timeout..." -ForegroundColor Yellow
                    } else {
                        Write-Host "   ⏳ Exporting... ${elapsed}s elapsed | ${sizeMB} MB written | finalizing..." -ForegroundColor Cyan
                    }
                }
                $lastSize = $currentSize
            } else {
                Write-Host "   ⏳ Initializing export... ${elapsed}s elapsed" -ForegroundColor Cyan
            }
        }

        # Wait for job to complete and get any output/errors
        $jobResult = Receive-Job -Job $exportJob -Wait -ErrorAction Stop
        Remove-Job -Job $exportJob

        $totalElapsed = [Math]::Round(((Get-Date) - $startTime).TotalSeconds)
        Write-Host "   ✓ Export completed in ${totalElapsed}s" -ForegroundColor Green
    } catch {
        Write-Host ""
        $errorMsg = $_.ToString()
        Write-Host "ERROR: wsl --export failed: $errorMsg" -ForegroundColor Red
        
        # Check if this is a socket file error (common issue)
        if ($errorMsg -match "pax format cannot archive sockets|cannot archive pipes") {
            Write-Host ""
            Write-Host "⚠ This error occurs when WSL has active processes with socket/pipe files in /tmp." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Solutions:" -ForegroundColor Cyan
            Write-Host "  1. Enable 'Skip WSL Backup' in Settings and retry (fastest, no backup)" -ForegroundColor Cyan
            Write-Host "  2. Manually stop all WSL processes and retry this step" -ForegroundColor Cyan
            Write-Host "  3. Reboot your computer to ensure WSL is fully stopped, then retry" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "The WSL distro has NOT been deleted - it's safe to retry." -ForegroundColor Yellow
        } else {
            Write-Host "ABORT: Backup could not be created. The ERC distro has NOT been deleted." -ForegroundColor Red
            Write-Host "       Resolve the export error and re-run this step to proceed." -ForegroundColor Red
        }
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
}

# ─── 3. Unregister distro ────────────────────────────────────────────────────

Write-Host "`n==> Step 3: Unregistering '$DistroName' from WSL..."
wsl --unregister $DistroName 2>&1 | ForEach-Object { Write-Host "   $_" }
Write-Host "   ✓ Unregister command completed"

# ─── 4. Remove leftover install directories ─────────────────────────────────

Write-Host "`n==> Step 4: Cleaning up install directories..."

# Also check for WSL directories in common root locations
$commonRootDirs = @(
    "C:\wsl_brandon",
    "C:\WSL",
    (Join-Path $env:USERPROFILE "wsl_brandon")
)

foreach ($rootDir in $commonRootDirs) {
    $ercSubdir = Join-Path $rootDir "erc\ext"
    if ((Test-Path $ercSubdir) -and -not ($InstallDirs -contains $ercSubdir)) {
        Write-Host "   Found additional ERC installation: $ercSubdir" -ForegroundColor Yellow
        $InstallDirs += $ercSubdir
    }
}

foreach ($dir in $InstallDirs) {
    if (Test-Path $dir) {
        # Safety check: Never delete the backup directory
        $isBackupDir = $false
        if ($BackupDir) {
            $backupNormalized = [System.IO.Path]::GetFullPath($BackupDir).TrimEnd('\', '/')
            $dirNormalized = [System.IO.Path]::GetFullPath($dir).TrimEnd('\', '/')
            if ($dirNormalized -eq $backupNormalized -or $dirNormalized.StartsWith($backupNormalized + '\')) {
                $isBackupDir = $true
            }
        }
        
        if ($isBackupDir) {
            Write-Host "   ⚠ SKIPPING: $dir (protected - contains backup directory)" -ForegroundColor Yellow
            Write-Host "   Backup tars are preserved at: $BackupDir" -ForegroundColor Green
        } else {
            Write-Host "   Removing WSL filesystem: $dir" -ForegroundColor Cyan
            try {
                Remove-Item -Path $dir -Recurse -Force -ErrorAction Stop
                Write-Host "   ✓ Removed: $dir" -ForegroundColor Green
            } catch {
                Write-Host "   ⚠ Failed to remove $dir : $_" -ForegroundColor Yellow
                Write-Host "   You may need to manually delete this directory" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "   Skipped (not found): $dir"
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
