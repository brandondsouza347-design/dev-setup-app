# connect_vpn.ps1 — Launch OpenVPN and poll until gitlab.toogoerp.net:443 is reachable
$ErrorActionPreference = 'Stop'

function Test-GitLabReachable {
    try {
        $tcp = [System.Net.Sockets.TcpClient]::new()
        $task = $tcp.ConnectAsync("gitlab.toogoerp.net", 443)
        $completed = $task.Wait(3000)
        $ok = $completed -and (-not $task.IsFaulted)
        try { $tcp.Close() } catch {}
        return $ok
    } catch {
        return $false
    }
}

function Test-VpnStatus {
    try {
        # Try multiple ways to locate the check script
        $scriptLocations = @()

        # Method 1: Use PSScriptRoot if available
        if ($PSScriptRoot) {
            $scriptLocations += (Join-Path $PSScriptRoot "check_vpn_status.ps1")
        }

        # Method 2: Try relative to current working directory
        $scriptLocations += "scripts\windows\check_vpn_status.ps1"
        $scriptLocations += ".\scripts\windows\check_vpn_status.ps1"

        # Method 3: Try in current directory
        $scriptLocations += "check_vpn_status.ps1"
        $scriptLocations += ".\check_vpn_status.ps1"

        foreach ($checkScript in $scriptLocations) {
            if (Test-Path $checkScript -ErrorAction SilentlyContinue) {
                $result = & powershell -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File $checkScript 2>&1
                return $LASTEXITCODE -eq 0
            }
        }
    } catch {
        # If VPN status check fails, return false (not connected)
        return $false
    }
    return $false
}

# Step 1: Check VPN connection status
Write-Output "→ Step 1/3: Checking VPN connection status..."
if (Test-VpnStatus) {
    Write-Output "  ✓ OpenVPN already connected. Verifying GitLab connectivity..."
    if (Test-GitLabReachable) {
        Write-Output "✓ VPN connected and GitLab is reachable. No action needed."
        exit 0
    } else {
        Write-Output "⚠ VPN connected but GitLab not reachable. Check network routing."
        exit 1
    }
}

Write-Output "  Checking GitLab connectivity to determine if VPN needed..."
if (Test-GitLabReachable) {
    Write-Output "✓ GitLab is already reachable. VPN may already be connected via another method."
    exit 0
}

Write-Output "  GitLab not reachable. Launching VPN..."

# Step 2: Locate OpenVPN executable
Write-Output "→ Step 2/3: Launching OpenVPN..."
$exeCandidates = @(
    "C:\Program Files\OpenVPN\bin\openvpn-gui.exe",
    "C:\Program Files\OpenVPN Connect\OpenVPNConnect.exe",
    "C:\Program Files (x86)\OpenVPN\bin\openvpn-gui.exe"
)
$exePath = $exeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $exePath) {
    Write-Output "  Searched locations:"
    $exeCandidates | ForEach-Object { Write-Output "    - $_" }
    throw "OpenVPN executable not found. Ensure OpenVPN is installed (run 'Install OpenVPN' step first)."
}
Write-Output "  Found OpenVPN at: $exePath"

# Find .ovpn file: prefer the one in OpenVPN\config, then fall back to settings path
$ovpnFile = $null
$cfgDir = "$env:USERPROFILE\OpenVPN\config"
Write-Output "  Looking for .ovpn config file..."

# First, try to find it in the standard OpenVPN config directory
$ovpnFile = Get-ChildItem -Path $cfgDir -Filter "*.ovpn" -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
if ($ovpnFile) {
    Write-Output "  Found config in OpenVPN directory: $ovpnFile"
} elseif ($env:SETUP_OPENVPN_CONFIG_PATH -and (Test-Path $env:SETUP_OPENVPN_CONFIG_PATH)) {
    # Fall back to settings path if nothing in config dir
    $ovpnFile = $env:SETUP_OPENVPN_CONFIG_PATH
    Write-Output "  Using config from settings: $ovpnFile"
}

if (-not $ovpnFile) {
    Write-Output "  Searched: $cfgDir"
    Write-Output "  Searched: SETUP_OPENVPN_CONFIG_PATH = '$env:SETUP_OPENVPN_CONFIG_PATH'"
    throw "No .ovpn config file found. Run 'Install OpenVPN' first or set 'OpenVPN Config File' in Settings."
}

Write-Output "  Launching OpenVPN with profile: $(Split-Path -Leaf $ovpnFile)"

# Kill any existing OpenVPN GUI to ensure clean connection
$existingProcess = Get-Process -Name "openvpn-gui" -ErrorAction SilentlyContinue
if ($existingProcess) {
    Write-Output "  Stopping existing OpenVPN GUI instance..."
    Stop-Process -Name "openvpn-gui" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

# Determine if config is in standard directory or custom location
$profileName = [System.IO.Path]::GetFileNameWithoutExtension($ovpnFile)
$isInConfigDir = $ovpnFile.StartsWith($cfgDir, [System.StringComparison]::OrdinalIgnoreCase)

if ($isInConfigDir) {
    # Use profile name only (OpenVPN GUI looks in config directory)
    Write-Output "  Starting OpenVPN GUI with profile name: $profileName"
    Start-Process -FilePath $exePath -ArgumentList "--connect", $profileName -WindowStyle Hidden -ErrorAction SilentlyContinue
} else {
    # Use full path for configs outside standard directory
    Write-Output "  Starting OpenVPN GUI with config path: $ovpnFile"
    Start-Process -FilePath $exePath -ArgumentList "--connect", "`"$ovpnFile`"" -WindowStyle Hidden -ErrorAction SilentlyContinue
}

Write-Output "  OpenVPN process started — waiting for tunnel to establish..."

# Step 3: Poll for VPN connection
$maxAttempts = 36
Write-Output "→ Step 3/3: Waiting for VPN connection (polling every 5s, timeout: 3 minutes)..."
for ($i = 1; $i -le $maxAttempts; $i++) {
    Start-Sleep -Seconds 5

    # Primary check: GitLab reachability (always works)
    if (Test-GitLabReachable) {
        # Optional: Verify VPN status if check is available
        $vpnStatus = Test-VpnStatus
        if ($vpnStatus) {
            Write-Output "✓ VPN connected successfully (OpenVPN GUI connected and GitLab reachable)"
        } else {
            Write-Output "✓ GitLab is now reachable after $($i * 5) seconds."
        }
        Write-Output "  Connection established in $($i * 5) seconds."
        exit 0
    }
    if ($i % 6 -eq 0) {
        Write-Output "  ⏳ Still waiting... ($($i * 5)s / $($maxAttempts * 5)s elapsed)"
    }
}

throw "VPN did not connect within 3 minutes. Please connect manually and retry this step."
