# setup_windows_hosts.ps1
# Update Windows hosts file with localhost entries including tenant name
# Must run as Administrator
#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

$hostsPath = "C:\Windows\System32\drivers\etc\hosts"

# Get tenant name from environment variable (fallback to erckinetic for backwards compatibility)
$tenantName = $env:SETUP_TENANT_NAME
if ([string]::IsNullOrWhiteSpace($tenantName)) {
    $tenantName = "erckinetic"
    Write-Host "⚠ SETUP_TENANT_NAME not set, using default: $tenantName" -ForegroundColor Yellow
}

Write-Host "==> Using tenant name: $tenantName"

# Define the localhost entries with tenant name
$ipv4Entry = "127.0.0.1       localhost $tenantName"
$ipv6Entry = "::1             localhost $tenantName"

Write-Host "==> setup_windows_hosts: checking $hostsPath..."

if (-not (Test-Path $hostsPath)) {
    Write-Host "  Hosts file not found at $hostsPath — skipping"
    exit 0
}

# Read current content
$currentLines = Get-Content $hostsPath

# Track if we need to add entries
$hasIPv4Entry = $false
$hasIPv6Entry = $false

# Check if entries already exist
foreach ($line in $currentLines) {
    if ($line -match "^\s*127\.0\.0\.1\s+localhost\s+$tenantName\s*$") {
        $hasIPv4Entry = $true
    }
    if ($line -match "^\s*::1\s+localhost\s+$tenantName\s*$") {
        $hasIPv6Entry = $true
    }
}

$addedAny = $false

# Add IPv4 entry if not present
if (-not $hasIPv4Entry) {
    Write-Host "  Adding IPv4 entry: $ipv4Entry"
    Add-Content -Path $hostsPath -Value $ipv4Entry -Encoding ASCII
    Write-Host "✓ Added IPv4 localhost entry with tenant name"
    $addedAny = $true
} else {
    Write-Host "✓ IPv4 localhost entry with '$tenantName' already present"
}

# Add IPv6 entry if not present
if (-not $hasIPv6Entry) {
    Write-Host "  Adding IPv6 entry: $ipv6Entry"
    Add-Content -Path $hostsPath -Value $ipv6Entry -Encoding ASCII
    Write-Host "✓ Added IPv6 localhost entry with tenant name"
    $addedAny = $true
} else {
    Write-Host "✓ IPv6 localhost entry with '$tenantName' already present"
}

if (-not $addedAny) {
    Write-Host "✓ All required localhost entries already present — nothing to do"
} else {
    Write-Host ""
    Write-Host "✓ Windows hosts file updated successfully"
    Write-Host "  Format: 127.0.0.1 and ::1 point to 'localhost $tenantName'"
}
