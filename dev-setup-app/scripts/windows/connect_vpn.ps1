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

# Fast path: already connected
Write-Output "→ Step 1/2: Checking VPN connectivity..."
if (Test-GitLabReachable) {
    Write-Output "✓ Already connected — gitlab.toogoerp.net is reachable. Skipping VPN launch."
    exit 0
}

# Locate OpenVPN executable
Write-Output "→ Step 2/2: Launching OpenVPN..."
$exeCandidates = @(
    "C:\Program Files\OpenVPN\bin\openvpn-gui.exe",
    "C:\Program Files\OpenVPN Connect\OpenVPNConnect.exe",
    "C:\Program Files (x86)\OpenVPN\bin\openvpn-gui.exe"
)
$exePath = $exeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $exePath) {
    throw "OpenVPN executable not found. Ensure OpenVPN is installed (run 'Install OpenVPN' step first)."
}

# Find .ovpn file: prefer the one set in settings, then search the config dir
$ovpnFile = $null
$cfgDir = "$env:USERPROFILE\OpenVPN\config"
if ($env:SETUP_OPENVPN_CONFIG_PATH -and (Test-Path $env:SETUP_OPENVPN_CONFIG_PATH)) {
    $ovpnFile = $env:SETUP_OPENVPN_CONFIG_PATH
} else {
    $ovpnFile = Get-ChildItem -Path $cfgDir -Filter "*.ovpn" -ErrorAction SilentlyContinue |
                Select-Object -First 1 -ExpandProperty FullName
}
if (-not $ovpnFile) {
    throw "No .ovpn config file found in $cfgDir. Run 'Install OpenVPN' first or set OpenVPN Config File in Settings."
}

Write-Output "  Using config: $ovpnFile"
Start-Process -FilePath $exePath -ArgumentList "--connect `"$ovpnFile`"" -ErrorAction SilentlyContinue

# Poll for up to 3 minutes (36 × 5s)
$maxAttempts = 36
Write-Output "  Waiting for VPN connection (up to 3 minutes)..."
for ($i = 1; $i -le $maxAttempts; $i++) {
    Start-Sleep -Seconds 5
    if (Test-GitLabReachable) {
        Write-Output "✓ VPN connected — gitlab.toogoerp.net is reachable ($($i * 5)s)."
        exit 0
    }
    Write-Output "  ⏳ Waiting... ($($i * 5)s / $($maxAttempts * 5)s)"
}

throw "VPN did not connect within 3 minutes. Please connect manually and retry this step."
