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
Write-Output "  Testing TCP connection to gitlab.toogoerp.net:443..."
if (Test-GitLabReachable) {
    Write-Output "✓ Already connected — gitlab.toogoerp.net:443 is reachable. No VPN action needed."
    exit 0
}
Write-Output "  gitlab.toogoerp.net:443 is not reachable — VPN connection required."

# Locate OpenVPN executable
Write-Output "→ Step 2/2: Launching OpenVPN..."
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

# Find .ovpn file: prefer the one set in settings, then search the config dir
$ovpnFile = $null
$cfgDir = "$env:USERPROFILE\OpenVPN\config"
Write-Output "  Looking for .ovpn config file..."
if ($env:SETUP_OPENVPN_CONFIG_PATH -and (Test-Path $env:SETUP_OPENVPN_CONFIG_PATH)) {
    $ovpnFile = $env:SETUP_OPENVPN_CONFIG_PATH
    Write-Output "  Using config from settings: $ovpnFile"
} else {
    $ovpnFile = Get-ChildItem -Path $cfgDir -Filter "*.ovpn" -ErrorAction SilentlyContinue |
                Select-Object -First 1 -ExpandProperty FullName
    if ($ovpnFile) {
        Write-Output "  Found config in default directory: $ovpnFile"
    }
}
if (-not $ovpnFile) {
    Write-Output "  Searched: $cfgDir"
    Write-Output "  Searched: SETUP_OPENVPN_CONFIG_PATH = '$env:SETUP_OPENVPN_CONFIG_PATH'"
    throw "No .ovpn config file found. Run 'Install OpenVPN' first or set 'OpenVPN Config File' in Settings."
}

Write-Output "  Launching OpenVPN with profile: $(Split-Path -Leaf $ovpnFile)"

# Check if OpenVPN GUI is already running
$profileName = [System.IO.Path]::GetFileNameWithoutExtension($ovpnFile)
$existingProcess = Get-Process -Name "openvpn-gui" -ErrorAction SilentlyContinue

if ($existingProcess) {
    Write-Output "  OpenVPN GUI already running — using IPC command"
    Start-Process -FilePath $exePath -ArgumentList "--command", "connect", $profileName -WindowStyle Hidden -ErrorAction SilentlyContinue
} else {
    Write-Output "  Starting new OpenVPN GUI instance"
    Start-Process -FilePath $exePath -ArgumentList "--connect", "`"$ovpnFile`"" -WindowStyle Hidden -ErrorAction SilentlyContinue
}

Write-Output "  OpenVPN process started — waiting for tunnel to establish..."

# Poll for up to 3 minutes (36 × 5s), log every 30s
$maxAttempts = 36
Write-Output "  Polling gitlab.toogoerp.net:443 every 5s (timeout: 3 minutes)..."
for ($i = 1; $i -le $maxAttempts; $i++) {
    Start-Sleep -Seconds 5
    if (Test-GitLabReachable) {
        Write-Output "✓ VPN tunnel established — gitlab.toogoerp.net:443 reachable after $($i * 5)s."
        exit 0
    }
    if ($i % 6 -eq 0) {
        Write-Output "  ⏳ Still waiting... ($($i * 5)s / $($maxAttempts * 5)s elapsed)"
    }
}

throw "VPN did not connect within 3 minutes. Please connect manually and retry this step."
