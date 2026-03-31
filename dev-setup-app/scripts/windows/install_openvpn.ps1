# install_openvpn.ps1 — Install OpenVPN via winget and stage the .ovpn config
$ErrorActionPreference = 'Stop'

# Step 1: Install OpenVPN (idempotent)
Write-Output "→ Step 1/2: Checking OpenVPN installation..."
$installed = winget list --id OpenVPNTechnologies.OpenVPN --accept-source-agreements 2>&1
if ($installed -match "OpenVPN") {
    Write-Output "✓ OpenVPN is already installed — skipping."
} else {
    Write-Output "→ Installing OpenVPN via winget..."
    winget install --id OpenVPNTechnologies.OpenVPN --accept-source-agreements --accept-package-agreements --silent
    # winget exit code -1978335189 (0x80073D54) = already installed — treat as success
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {
        throw "winget install OpenVPN failed (exit code: $LASTEXITCODE)"
    }
    Write-Output "✓ OpenVPN installed."
}

# Step 2: Copy .ovpn to OpenVPN config directory
Write-Output "→ Step 2/2: Staging VPN config file..."
$configDir = "$env:USERPROFILE\OpenVPN\config"
if (-not (Test-Path $configDir)) {
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    Write-Output "  Created config directory: $configDir"
}

$ovpnSrc = $env:SETUP_OPENVPN_CONFIG_PATH
if ($ovpnSrc -and (Test-Path $ovpnSrc)) {
    $leaf = Split-Path -Leaf $ovpnSrc
    $dest = Join-Path $configDir $leaf
    if (Test-Path $dest) {
        Write-Output "✓ VPN config already in place: $dest"
    } else {
        Copy-Item -Path $ovpnSrc -Destination $dest -Force
        Write-Output "✓ VPN config copied: $ovpnSrc → $dest"
    }
} else {
    Write-Output "⚠ SETUP_OPENVPN_CONFIG_PATH is not set or file not found."
    Write-Output "  Copy your .ovpn file manually to: $configDir"
}

Write-Output "✓ install_openvpn complete."
