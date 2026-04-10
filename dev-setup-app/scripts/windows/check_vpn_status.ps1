# check_vpn_status.ps1 — Check if OpenVPN is actually connected on Windows
$ErrorActionPreference = 'Stop'

Write-Output "→ Checking OpenVPN connection status..."

# Method 1: Check if OpenVPN GUI process is running
$openvpnProcess = Get-Process -Name "openvpn-gui" -ErrorAction SilentlyContinue
if (-not $openvpnProcess) {
    Write-Output "✗ OpenVPN GUI is not running"
    exit 1
}

Write-Output "  ✓ OpenVPN GUI is running (PID: $($openvpnProcess.Id))"

# Method 2: Check for OpenVPN TAP adapter with active connection
Write-Output "  Checking TAP adapter status..."
$tapAdapter = Get-NetAdapter | Where-Object {
    $_.InterfaceDescription -match "TAP-Windows" -or
    $_.Name -match "OpenVPN" -or
    $_.InterfaceDescription -match "OpenVPN"
}

if (-not $tapAdapter) {
    Write-Output "✗ OpenVPN TAP adapter not found"
    exit 1
}

# Check if TAP adapter is up and connected
$connectedAdapter = $tapAdapter | Where-Object { $_.Status -eq "Up" }
if (-not $connectedAdapter) {
    Write-Output "✗ OpenVPN TAP adapter is down (Status: $($tapAdapter.Status))"
    exit 1
}

Write-Output "  ✓ TAP adapter is up: $($connectedAdapter.Name) ($($connectedAdapter.InterfaceDescription))"

# Method 3: Check for assigned IP address on TAP adapter
$ipConfig = Get-NetIPAddress -InterfaceIndex $connectedAdapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
if (-not $ipConfig) {
    Write-Output "✗ TAP adapter has no IPv4 address assigned"
    exit 1
}

Write-Output "  ✓ TAP adapter has IP: $($ipConfig.IPAddress)"
Write-Output "✓ OpenVPN is connected"
exit 0
