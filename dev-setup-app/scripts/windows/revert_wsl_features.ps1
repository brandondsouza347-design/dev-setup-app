# revert_wsl_features.ps1
# Disable WSL and VirtualMachinePlatform Windows features.
# REQUIRES ADMINISTRATOR. A system restart is needed after disabling.
#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

$featuresDisabled = $false

Write-Host "==> Disabling WSL Windows Features" -ForegroundColor Cyan
Write-Host "   ⚠  After disabling, a system restart is required to complete removal." -ForegroundColor Yellow

# ─── 1. Check Windows version ───────────────────────────────────────────────

Write-Host "`n==> Step 1: Verifying Windows version..."
$WinVer = [System.Environment]::OSVersion.Version
Write-Host "   Windows Build: $($WinVer.Build)"

# ─── 2. Disable VirtualMachinePlatform ──────────────────────────────────────

Write-Host "`n==> Step 2: Checking VirtualMachinePlatform feature..."
$vmFeature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
Write-Host "   Current state: $($vmFeature.State)"

if ($vmFeature.State -eq "Disabled") {
    Write-Host "   ✓ VirtualMachinePlatform already disabled"
} else {
    Write-Host "   Disabling VirtualMachinePlatform..."
    Disable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart | Out-Null
    Write-Host "   ✓ VirtualMachinePlatform disabled"
    $featuresDisabled = $true
}

# ─── 3. Disable Windows Subsystem for Linux ─────────────────────────────────

Write-Host "`n==> Step 3: Checking WSL feature..."
$wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
Write-Host "   Current state: $($wslFeature.State)"

if ($wslFeature.State -eq "Disabled") {
    Write-Host "   ✓ WSL feature already disabled"
} else {
    Write-Host "   Disabling Windows Subsystem for Linux..."
    Disable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart | Out-Null
    Write-Host "   ✓ WSL feature disabled"
    $featuresDisabled = $true
}

# ─── 4. Result ───────────────────────────────────────────────────────────────

if ($featuresDisabled) {
    Write-Host "`n✓ WSL features disabled" -ForegroundColor Green
    Write-Host ""
    Write-Host "  ⚠  RESTART REQUIRED" -ForegroundColor Yellow
    Write-Host "     Restart your PC to complete WSL feature removal." -ForegroundColor Yellow
    Write-Host "     After restart, WSL commands will no longer be available." -ForegroundColor Yellow
    # Step succeeded — restart is required but this is not a failure
    exit 0
} else {
    Write-Host "`n✓ WSL features were already disabled — no restart needed" -ForegroundColor Green
}
