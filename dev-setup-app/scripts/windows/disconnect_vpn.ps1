# disconnect_vpn.ps1 — Disconnect OpenVPN GUI on Windows
$ErrorActionPreference = 'Stop'

Write-Output "→ Disconnecting OpenVPN..."

# Check if OpenVPN GUI is running
$openvpnProcess = Get-Process -Name "openvpn-gui" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $openvpnProcess) {
    Write-Output "⚠ OpenVPN GUI is not running"
    exit 0
}

Write-Output "  OpenVPN GUI process found (PID: $($openvpnProcess.Id))"
Write-Output "→ Stopping OpenVPN connection processes..."

# Stop all OpenVPN connection processes (not the GUI itself)
$openvpnExe = Get-Process -Name "openvpn" -ErrorAction SilentlyContinue
if ($openvpnExe) {
    Stop-Process -Name "openvpn" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

# Verify disconnection
Write-Output "→ Verifying disconnection..."
$connectedAdapter = Get-NetAdapter | Where-Object {
    ($_.InterfaceDescription -match "TAP-Windows" -or
     $_.Name -match "OpenVPN" -or
     $_.InterfaceDescription -match "OpenVPN") -and
    $_.Status -eq "Up"
}

if (-not $connectedAdapter) {
    Write-Output "✓ OpenVPN disconnected successfully"
    exit 0
} else {
    Write-Output "⚠ Connection may still be active"
    Write-Output "  Please manually disconnect from the OpenVPN GUI system tray icon"
    exit 1
}
