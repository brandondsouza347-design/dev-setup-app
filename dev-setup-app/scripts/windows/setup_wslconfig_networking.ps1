# setup_wslconfig_networking.ps1
# Create or update .wslconfig with networkingMode=mirrored
# Skips if already configured
$ErrorActionPreference = "Stop"

$wslConfigPath = Join-Path $env:USERPROFILE ".wslconfig"

Write-Host "==> setup_wslconfig_networking: checking $wslConfigPath..."

# Read existing content if file exists
$existingContent = ""
if (Test-Path $wslConfigPath) {
    $existingContent = Get-Content $wslConfigPath -Raw -ErrorAction SilentlyContinue
}

# Check if already configured
if ($existingContent -match "networkingMode\s*=\s*mirrored") {
    Write-Host "✓ .wslconfig already has networkingMode=mirrored — skipping"
    exit 0
}

Write-Host "  networkingMode=mirrored not found — configuring..."

# Build the block to add
$wsl2Block = "[wsl2]`nnetworkingMode=mirrored"

if ($existingContent -match "\[wsl2\]") {
    # [wsl2] section exists — inject the setting after the section header
    $newContent = $existingContent -replace "(\[wsl2\])", "`$1`nnetworkingMode=mirrored"
    Set-Content -Path $wslConfigPath -Value $newContent -Encoding UTF8
    Write-Host "  Injected networkingMode=mirrored into existing [wsl2] section"
} elseif ($existingContent.Trim() -ne "") {
    # File exists but no [wsl2] section
    $newContent = $existingContent.TrimEnd() + "`n`n$wsl2Block"
    Set-Content -Path $wslConfigPath -Value $newContent -Encoding UTF8
    Write-Host "  Appended [wsl2] section"
} else {
    # File doesn't exist or is empty
    Set-Content -Path $wslConfigPath -Value $wsl2Block -Encoding UTF8
    Write-Host "  Created $wslConfigPath"
}

Write-Host "✓ .wslconfig configured with networkingMode=mirrored"
Write-Host ""
Write-Host "NOTE: Run 'wsl --shutdown' for changes to take effect"
