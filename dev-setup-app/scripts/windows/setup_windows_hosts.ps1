# setup_windows_hosts.ps1
# Add 127.0.0.1 t3582.local to the Windows hosts file if not already present
# Must run as Administrator
#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

$hostsPath = "C:\Windows\System32\drivers\etc\hosts"
$entries = @(
    "127.0.0.1 t3582.local"
    "127.0.0.1 localhost"
)

Write-Host "==> setup_windows_hosts: checking $hostsPath..."

if (-not (Test-Path $hostsPath)) {
    Write-Host "  Hosts file not found at $hostsPath — skipping"
    exit 0
}

$currentContent = Get-Content $hostsPath -Raw

$addedAny = $false

foreach ($entry in $entries) {
    # Extract just the hostname part to check for duplicates
    $parts = $entry -split "\s+", 2
    $hostname = $parts[1]

    if ($currentContent -match [regex]::Escape($hostname)) {
        Write-Host "✓ '$hostname' already in hosts file — skipping"
    } else {
        Write-Host "  Adding: $entry"
        Add-Content -Path $hostsPath -Value $entry -Encoding ASCII
        Write-Host "✓ Added: $entry"
        $addedAny = $true
    }
}

if (-not $addedAny) {
    Write-Host "✓ All required hosts entries already present — nothing to do"
} else {
    Write-Host ""
    Write-Host "✓ Windows hosts file updated"
    Write-Host "  NOTE: entries added for .local tenant access"
    Write-Host "  Update t3582 to match your actual tenant ID if different"
}
