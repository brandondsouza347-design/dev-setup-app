# setup_wsl_network.ps1 — Configure WSL2 networking: DNS, resolv.conf, and /etc/hosts entries
#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"
$DistroName = "Ubuntu-22.04"

Write-Host "==> WSL Network Configuration" -ForegroundColor Cyan

# ─── 1. Check WSL distro is available ───────────────────────────────────────

Write-Host "`n==> Step 1: Checking WSL distro..."
$existingDistros = wsl --list --quiet 2>$null | Where-Object { $_ -match $DistroName }
if (-not $existingDistros) {
    Write-Error "$DistroName is not installed. Run 'Import WSL TAR' step first."
}
Write-Host "✓ $DistroName is available"

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
Write-Host "✓ /etc/wsl.conf written"

# ─── 3. Set DNS servers in resolv.conf ───────────────────────────────────────

Write-Host "`n==> Step 3: Setting DNS servers in resolv.conf..."

$resolvConf = @"
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
"@

wsl -d $DistroName -- bash -c "sudo rm -f /etc/resolv.conf; echo '$resolvConf' | sudo tee /etc/resolv.conf > /dev/null; sudo chattr +i /etc/resolv.conf 2>/dev/null || true"
Write-Host "✓ resolv.conf updated with Google + Cloudflare DNS"

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
    if ($hostsContent -match [regex]::Escape($hostname)) {
        Write-Host "   Already present: $hostname"
    } else {
        Add-Content -Path $hostsFile -Value "`n$entry"
        Write-Host "✓ Added: $entry"
    }
}

# ─── 5. Mirror hosts into WSL ────────────────────────────────────────────────

Write-Host "`n==> Step 5: Syncing host entries into WSL /etc/hosts..."

$hostEntries = @"

# Dev hostnames (added by setup tool)
127.0.0.1   erckinetic
127.0.0.1   erckinetic.local
"@

wsl -d $DistroName -- bash -c "grep -q 'erckinetic' /etc/hosts || echo '$hostEntries' | sudo tee -a /etc/hosts > /dev/null"
Write-Host "✓ WSL /etc/hosts updated"

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
    Write-Host "✓ .wslconfig written to $wslConfigPath"
} else {
    Write-Host "✓ .wslconfig already exists at $wslConfigPath (not overwritten)"
}

# ─── 7. Verify connectivity inside WSL ──────────────────────────────────────

Write-Host "`n==> Step 7: Testing network connectivity inside WSL..."

$pingResult = wsl -d $DistroName -- bash -c "curl -s --max-time 5 https://api.github.com/zen 2>&1 || echo 'timeout'" 2>&1
if ($pingResult -and $pingResult -notmatch "timeout|error|failed") {
    Write-Host "✓ WSL has internet access"
} else {
    Write-Host "⚠ Internet check inconclusive (may need restart)" -ForegroundColor Yellow
}

Write-Host "`n✓ WSL network configuration complete!" -ForegroundColor Green
Write-Host ""
Write-Host "  DNS  : 8.8.8.8, 8.8.4.4, 1.1.1.1"
Write-Host "  Hosts: erckinetic → 127.0.0.1"
Write-Host ""
Write-Host "NOTE: Restart WSL to apply /etc/wsl.conf changes:"
Write-Host "      wsl --shutdown && wsl -d $DistroName"
