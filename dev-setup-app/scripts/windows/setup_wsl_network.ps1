# setup_wsl_network.ps1 — Configure WSL2 networking: DNS, resolv.conf, and /etc/hosts entries
#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"
$DistroName = "ERC"

Write-Host "==> WSL Network Configuration" -ForegroundColor Cyan

# ─── 1. Check WSL distro is available ───────────────────────────────────────

Write-Host "`n==> Step 1: Checking WSL distro..."
# Spin until the distro appears — wsl --import in the previous step may
# still be committing to the registry. Exit the loop the moment it is found.
$timeoutSecs = 60
$elapsed = 0
$existingDistros = $null
while ($elapsed -lt $timeoutSecs) {
    $existingDistros = (wsl --list --quiet 2>$null) -replace '\0','' | Where-Object { $_ -match $DistroName }
    if ($existingDistros) { break }
    if ($elapsed -eq 0) { Write-Host "   $DistroName not yet visible, waiting..." -ForegroundColor Yellow }
    Start-Sleep -Seconds 1
    $elapsed++
    if ($elapsed % 5 -eq 0) { Write-Host "   Still waiting... (${elapsed}s)" }
}
if (-not $existingDistros) {
    Write-Host "ERROR: $DistroName is not installed. Run 'Import WSL TAR' step first." -ForegroundColor Red
    exit 1
}
Write-Host "✓ Step 1 complete — WSL distro '$DistroName' is registered and ready (detected after ${elapsed}s)" -ForegroundColor Green

# ─── 2. Disable WSL auto-generating resolv.conf ──────────────────────────────

Write-Host "`n==> Step 2: Configuring WSL to use fixed DNS (not auto-generated)..."

$wslConf = @"
[network]
generateResolvConf = false

[automount]
enabled = true
options = "metadata"

[interop]
enabled = true
appendWindowsPath = true
"@

wsl -d $DistroName -- bash -c "echo '$wslConf' | sudo tee /etc/wsl.conf > /dev/null"
Write-Host "✓ Step 2 complete — /etc/wsl.conf written with generateResolvConf=false, automount and interop enabled" -ForegroundColor Green

# ─── 3. Set DNS servers in resolv.conf ───────────────────────────────────────

Write-Host "`n==> Step 3: Setting DNS servers in resolv.conf..."

$resolvConf = @"
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
"@

# chattr -i first in case a previous run made the file immutable — suppress
# errors so the command never writes to stderr (which PS5.1 treats as a
# NativeCommandError when ErrorActionPreference=Stop).
wsl -d $DistroName -- bash -c "sudo chattr -i /etc/resolv.conf 2>/dev/null || true; sudo rm -f /etc/resolv.conf 2>/dev/null || true; printf '%s\n' '$resolvConf' | sudo tee /etc/resolv.conf > /dev/null; sudo chattr +i /etc/resolv.conf 2>/dev/null || true"
Write-Host "✓ Step 3 complete — /etc/resolv.conf pinned with nameservers: 8.8.8.8, 8.8.4.4, 1.1.1.1" -ForegroundColor Green

# ─── 4. Configure Windows hosts file ─────────────────────────────────────────

Write-Host "`n==> Step 4: Adding development hostnames to Windows hosts file..."

$hostsFile = "C:\Windows\System32\drivers\etc\hosts"
$hostsContent = Get-Content $hostsFile

$entriesToAdd = @(
    "127.0.0.1   erckinetic",
    "127.0.0.1   erckinetic.local",
    "127.0.0.1   localhost.erckinetic"
)

foreach ($entry in $entriesToAdd) {
    $hostname = ($entry -split "\s+")[1]
    # Re-read each iteration so we pick up entries written in the same loop.
    $hostsContent = Get-Content -Path $hostsFile -Raw
    if ($hostsContent -match [regex]::Escape($hostname)) {
        Write-Host "   Already present: $hostname"
    } else {
        # Hosts file can be briefly locked by Defender/antivirus — retry up to 5x.
        $maxRetries = 5; $retryDelay = 3; $attempt = 0; $written = $false
        while (-not $written -and $attempt -lt $maxRetries) {
            try {
                Add-Content -Path $hostsFile -Value "`n$entry" -ErrorAction Stop
                $written = $true
            } catch {
                $attempt++
                if ($attempt -lt $maxRetries) {
                    Write-Host "   Hosts file busy, retrying in ${retryDelay}s... ($attempt/$maxRetries)" -ForegroundColor Yellow
                    Start-Sleep -Seconds $retryDelay
                } else {
                    throw
                }
            }
        }
        Write-Host "   ✓ Added hostname entry: $entry" -ForegroundColor Green
    }
}
Write-Host "✓ Step 4 complete — development hostnames written to Windows hosts file ($hostsFile)" -ForegroundColor Green

# ─── 5. Mirror hosts into WSL ────────────────────────────────────────────────

Write-Host "`n==> Step 5: Syncing host entries into WSL /etc/hosts..."

$hostEntries = @"

# Dev hostnames (added by setup tool)
127.0.0.1   erckinetic
127.0.0.1   erckinetic.local
"@

wsl -d $DistroName -- bash -c "grep -q 'erckinetic' /etc/hosts || echo '$hostEntries' | sudo tee -a /etc/hosts > /dev/null"
Write-Host "✓ Step 5 complete — dev hostnames (erckinetic, erckinetic.local) mirrored into WSL /etc/hosts" -ForegroundColor Green

# ─── 6. Configure .wslconfig for Windows host ────────────────────────────────

Write-Host "`n==> Step 6: Writing .wslconfig for memory and swap settings..."

$wslConfigPath = Join-Path $env:USERPROFILE ".wslconfig"
$wslConfigContent = @"
[wsl2]
memory=4GB
processors=2
swap=2GB
localhostForwarding=true
"@

if (-not (Test-Path $wslConfigPath)) {
    Set-Content -Path $wslConfigPath -Value $wslConfigContent
    Write-Host "✓ Step 6 complete — .wslconfig created at $wslConfigPath (memory=4GB, processors=2, swap=2GB, localhostForwarding=true)" -ForegroundColor Green
} else {
    Write-Host "✓ Step 6 complete — .wslconfig already exists at $wslConfigPath and was not overwritten" -ForegroundColor Green
}

# ─── 7. Verify connectivity inside WSL ──────────────────────────────────────

Write-Host "`n==> Step 7: Testing network connectivity inside WSL..."

$pingResult = wsl -d $DistroName -- bash -c "curl -s --max-time 5 https://api.github.com/zen 2>&1 || echo 'timeout'" 2>&1
if ($pingResult -and $pingResult -notmatch "timeout|error|failed") {
    Write-Host "✓ Step 7 complete — WSL has outbound internet access (GitHub API responded: $pingResult)" -ForegroundColor Green
} else {
    Write-Host "⚠ Step 7: Internet check inconclusive — WSL may need a restart to pick up the new DNS config" -ForegroundColor Yellow
}

Write-Host "`n✓ WSL network configuration complete!" -ForegroundColor Green
Write-Host ""
Write-Host "  DNS  : 8.8.8.8, 8.8.4.4, 1.1.1.1"
Write-Host "  Hosts: erckinetic → 127.0.0.1"
Write-Host ""
Write-Host "NOTE: Restart WSL to apply /etc/wsl.conf changes:"
Write-Host "      wsl --shutdown && wsl -d $DistroName"
