# enable_wsl.ps1 — Enable Windows Subsystem for Linux (WSL2) feature
# Must be run as Administrator
#Requires -RunAsAdministrator

param(
    [switch]$NoReboot
)

$ErrorActionPreference = "Stop"

Write-Host "==> WSL2 Enablement Setup" -ForegroundColor Cyan

# ─── 1. Check Windows version ───────────────────────────────────────────────

Write-Host "`n==> Step 1: Checking Windows version..."
$WinVer = [System.Environment]::OSVersion.Version
Write-Host "    Windows version: $($WinVer.Major).$($WinVer.Minor) Build $($WinVer.Build)"

if ($WinVer.Build -lt 19041) {
    Write-Error "WSL2 requires Windows 10 version 2004 (Build 19041) or higher, or Windows 11."
    exit 1
}
Write-Host "✓ Windows version is compatible with WSL2"

# ─── 2. Enable WSL feature ──────────────────────────────────────────────────

Write-Host "`n==> Step 2: Enabling Windows Subsystem for Linux feature..."
$wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
if ($wslFeature.State -eq "Enabled") {
    Write-Host "✓ WSL feature already enabled"
} else {
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart
    Write-Host "✓ WSL feature enabled"
}

# ─── 3. Enable Virtual Machine Platform ────────────────────────────────────

Write-Host "`n==> Step 3: Enabling Virtual Machine Platform..."
$vmFeature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
if ($vmFeature.State -eq "Enabled") {
    Write-Host "✓ Virtual Machine Platform already enabled"
} else {
    Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart
    Write-Host "✓ Virtual Machine Platform enabled"
}

# ─── 4. Set WSL2 as default ─────────────────────────────────────────────────

Write-Host "`n==> Step 4: Setting WSL2 as default version..."
try {
    wsl --set-default-version 2
    Write-Host "✓ WSL2 set as default"
} catch {
    Write-Host "⚠ Could not set WSL2 as default. This may succeed after reboot."
}

# ─── 5. Install WSL kernel update if needed ─────────────────────────────────

Write-Host "`n==> Step 5: Checking WSL kernel update..."
try {
    wsl --update
    Write-Host "✓ WSL kernel is up to date"
} catch {
    Write-Host "⚠ WSL kernel update failed — may succeed after reboot."
}

# ─── 6. Status ──────────────────────────────────────────────────────────────

Write-Host "`n==> WSL Status:"
wsl --status 2>$null

Write-Host "`n✓ WSL2 features enabled!" -ForegroundColor Green
Write-Host ""
Write-Host "NOTE: A system restart is required to complete the WSL2 installation." -ForegroundColor Yellow
Write-Host "      After reboot, re-run this installer to continue with the remaining steps." -ForegroundColor Yellow

if (-not $NoReboot) {
    $rebootChoice = Read-Host "`nRestart now? (y/n)"
    if ($rebootChoice -eq 'y' -or $rebootChoice -eq 'Y') {
        Write-Host "Restarting in 10 seconds..."
        Start-Sleep -Seconds 10
        Restart-Computer -Force
    }
}
