# revert_wsl_shutdown.ps1
# Gracefully stop all running WSL instances before reverting.
# This prevents file-handle leaks and data corruption during distro removal.
$ErrorActionPreference = "Stop"

Write-Host "==> Shutting down all WSL instances..." -ForegroundColor Cyan

# ─── 1. List running processes ───────────────────────────────────────────────

$wslProcs = Get-Process -Name "wsl" -ErrorAction SilentlyContinue
if ($wslProcs) {
    Write-Host "   Found $($wslProcs.Count) wsl.exe process(es) running"
} else {
    Write-Host "   No wsl.exe processes detected"
}

# ─── 2. Graceful shutdown via wsl --shutdown ─────────────────────────────────

Write-Host "`n==> Step 1: Sending wsl --shutdown..."
wsl --shutdown 2>&1 | ForEach-Object { Write-Host "   $_" }

# Give the kernel some time to release handles
Start-Sleep -Seconds 3

# ─── 3. Verify all instances are stopped ────────────────────────────────────

Write-Host "`n==> Step 2: Verifying no running distributions..."
$runningCheck = wsl --list --running 2>&1 | Out-String
if ($runningCheck -match "no running distributions" -or
    $runningCheck -match "there are no" -or
    $runningCheck -match "keine laufenden" -or
    $runningCheck.Trim() -eq "") {
    Write-Host "   ✓ No WSL distributions running"
} else {
    Write-Host "   Remaining running distributions:"
    Write-Host $runningCheck

    Write-Host "   Force-stopping remaining wsl processes..."
    Get-Process -Name "wsl*" -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Host "   ✓ Force-stop complete"
}

# ─── 4. Release any lingering vmsrvc / vmmem memory ─────────────────────────

Write-Host "`n==> Step 3: Waiting for memory to be released by Hyper-V Virtual Machine..."
Start-Sleep -Seconds 2
Write-Host "   ✓ Memory release wait complete"

Write-Host "`n✓ WSL shutdown complete — safe to proceed with revert" -ForegroundColor Green
