# enable_wsl.ps1 — Enable Windows Subsystem for Linux (WSL2) feature
# Must be run as Administrator
#Requires -RunAsAdministrator

param(
    [switch]$NoReboot
)

$ErrorActionPreference = "Stop"
$rebootRequired = $false

Write-Host "==> WSL2 Enablement Setup" -ForegroundColor Cyan

# ─── 1. Check Windows version ───────────────────────────────────────────────

Write-Host "`n==> Step 1: Checking Windows version..."
$WinVer = [System.Environment]::OSVersion.Version
Write-Host "    Windows version: $($WinVer.Major).$($WinVer.Minor) Build $($WinVer.Build)"

if ($WinVer.Build -lt 19041) {
    Write-Host "ERROR: WSL2 requires Windows 10 version 2004 (Build 19041) or higher, or Windows 11." -ForegroundColor Red
    exit 1
}
Write-Host "✓ Windows version is compatible with WSL2"

# ─── 2. Check CPU virtualisation is enabled ─────────────────────────────────────────────────────

Write-Host "`n==> Step 2: Checking CPU virtualisation support (required for WSL2)..."
try {
    # If VirtualMachinePlatform is already enabled, virtualisation is definitely
    # working — skip the WMI firmware check entirely.  The WMI property
    # VirtualizationFirmwareEnabled is known to return False on machines where
    # Hyper-V, Credential Guard, or VBS is active even when virtualisation is
    # fully operational.  Task Manager → Performance → CPU is the reliable indicator.
    $vmPlatform = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction SilentlyContinue
    if ($vmPlatform -and $vmPlatform.State -eq "Enabled") {
        Write-Host "✓ Virtual Machine Platform is already enabled — virtualisation is available"
    } else {
        $cpu = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1
        Write-Host "   CPU: $($cpu.Name)"
        $virtEnabled = $cpu.VirtualizationFirmwareEnabled
        Write-Host "   Virtualisation firmware enabled (WMI): $virtEnabled"

        if ($virtEnabled -eq $false) {
            # WMI returns False on Hyper-V/VBS machines even when VT active.
            # Treat as a warning, not a hard failure — if WSL features enable
            # successfully below, virtualisation was working.
            Write-Host "⚠ WMI reports VirtualizationFirmwareEnabled = False." -ForegroundColor Yellow
            Write-Host "  This is a known false negative on machines with Hyper-V or VBS enabled." -ForegroundColor Yellow
            Write-Host "  Continuing — if WSL2 fails to start after reboot, verify in Task Manager:" -ForegroundColor Yellow
            Write-Host "    Task Manager → Performance → CPU → Virtualisation: Enabled" -ForegroundColor Yellow
        } else {
            Write-Host "✓ CPU virtualisation is enabled"
        }
    }
} catch {
    Write-Host "   ⚠ Could not query CPU virtualisation status — continuing" -ForegroundColor Yellow
}

# ─── 3. Enable WSL feature ─────────────────────────────────────────────────────

Write-Host "`n==> Step 3: Enabling Windows Subsystem for Linux feature..."
$wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
if ($wslFeature.State -eq "Enabled") {
    Write-Host "✓ WSL feature already enabled"
} else {
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart
    Write-Host "✓ WSL feature enabled"
    $rebootRequired = $true
}

# ─── 4. Enable Virtual Machine Platform ─────────────────────────────────────────────────────

Write-Host "`n==> Step 4: Enabling Virtual Machine Platform..."
$vmFeature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
if ($vmFeature.State -eq "Enabled") {
    Write-Host "✓ Virtual Machine Platform already enabled"
} else {
    Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart
    Write-Host "✓ Virtual Machine Platform enabled"
    $rebootRequired = $true
}

# ─── 5. Set WSL2 as default ─────────────────────────────────────────────────────

Write-Host "`n==> Step 5: Setting WSL2 as default version..."
try {
    wsl --set-default-version 2
    Write-Host "✓ WSL2 set as default"
} catch {
    Write-Host "⚠ Could not set WSL2 as default. This may succeed after reboot."
}

# ─── 6. Install WSL kernel update if needed ───────────────────────────────────────────────────

Write-Host "`n==> Step 6: Checking WSL kernel update..."
try {
    wsl --update
    Write-Host "✓ WSL kernel is up to date"
} catch {
    Write-Host "⚠ WSL kernel update failed — may succeed after reboot."
}

# ─── 7. Status ─────────────────────────────────────────────────────

Write-Host "`n==> WSL Status:"
try {
    wsl --status 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "⚠ WSL status check returned code $LASTEXITCODE — WSL may still be completing an update" -ForegroundColor Yellow
    }
} catch {
    Write-Host "⚠ Could not retrieve WSL status — WSL may be completing an update, this is normal" -ForegroundColor Yellow
}

if ($rebootRequired) {
    Write-Host "`n⚠  RESTART REQUIRED" -ForegroundColor Yellow
    Write-Host "   WSL2 features were just enabled and require a system restart to take effect." -ForegroundColor Yellow
    Write-Host "   Please save your work, restart your PC, then re-run this installer." -ForegroundColor Yellow
    Write-Host "   This step will be detected as already complete on the next run." -ForegroundColor Yellow
    exit 1
} else {
    Write-Host "`n✓ WSL2 features already enabled — no restart needed" -ForegroundColor Green
}
