# revert_wsl_network.ps1
# Undo changes made by setup_wsl_network.ps1:
#   - Remove /etc/wsl.conf DNS settings from ERC distro
#   - Unpin /etc/resolv.conf so WSL can auto-generate it again
#   - Remove ERC WSL /etc/hosts dev entries
#   - Remove Windows hosts file dev entries (delegates to revert_windows_hosts.ps1 logic)
#   - Remove .wslconfig memory/swap block written by setup_wsl_network.ps1
#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
$DistroName = "ERC"

Write-Host "==> Reverting WSL Network Configuration" -ForegroundColor Cyan

# ─── 1. Check distro is available ───────────────────────────────────────────

Write-Host "`n==> Step 1: Checking WSL distro..."
$existingDistros = (wsl --list --quiet 2>$null) -replace '\0','' | Where-Object { $_ -match $DistroName }
if (-not $existingDistros) {
    Write-Host "   ✓ Distro '$DistroName' not present — network config already clean"
    # Still clean Windows-side below
}

# ─── 2. Restore resolv.conf (remove immutable flag, delete custom file) ─────

if ($existingDistros) {
    Write-Host "`n==> Step 2: Restoring resolv.conf to WSL auto-generated..."
    wsl -d $DistroName -- bash -c "sudo chattr -i /etc/resolv.conf 2>/dev/null || true; sudo rm -f /etc/resolv.conf 2>/dev/null || true"
    Write-Host "   ✓ resolv.conf removed — WSL will auto-generate on next start"

    # ─── 3. Remove generateResolvConf=false from /etc/wsl.conf ──────────────

    Write-Host "`n==> Step 3: Restoring /etc/wsl.conf..."
    wsl -d $DistroName -- bash -c @"
if [ -f /etc/wsl.conf ]; then
    sudo sed -i '/^generateResolvConf\s*=/d' /etc/wsl.conf 2>/dev/null
    # Remove empty [network] section
    sudo sed -i '/^\[network\]\s*$/{N;/^\[network\]\s*\n\s*$/d}' /etc/wsl.conf 2>/dev/null || true
    echo '✓ generateResolvConf line removed from /etc/wsl.conf'
else
    echo '✓ /etc/wsl.conf does not exist — nothing to revert'
fi
"@

    # ─── 4. Remove dev entries from WSL /etc/hosts ──────────────────────────

    Write-Host "`n==> Step 4: Removing dev hostnames from WSL /etc/hosts..."
    wsl -d $DistroName -- bash -c @"
if [ -f /etc/hosts ]; then
    sudo sed -i '/erckinetic/d' /etc/hosts 2>/dev/null
    sudo sed -i '/# Dev hostnames/d' /etc/hosts 2>/dev/null
    echo '✓ Dev hostnames removed from WSL /etc/hosts'
else
    echo '✓ WSL /etc/hosts does not exist — nothing to revert'
fi
"@
}

# ─── 5. Remove dev entries from Windows hosts file ──────────────────────────

Write-Host "`n==> Step 5: Removing dev hostnames from Windows hosts file..."
$hostsFile = "C:\Windows\System32\drivers\etc\hosts"
if (Test-Path $hostsFile) {
    $removePatterns = @("erckinetic", "erckinetic\.local", "localhost\.erckinetic", "# Dev hostnames \(added by setup tool\)")
    $originalLines = Get-Content $hostsFile
    $keptLines = $originalLines | Where-Object {
        $line = $_
        -not ($removePatterns | Where-Object { $line -match $_ })
    }
    $removedCount = $originalLines.Count - @($keptLines).Count
    if ($removedCount -gt 0) {
        $maxRetries = 5; $retryDelay = 3; $attempt = 0; $written = $false
        while (-not $written -and $attempt -lt $maxRetries) {
            try {
                Set-Content -Path $hostsFile -Value $keptLines -Encoding ASCII -ErrorAction Stop
                $written = $true
            } catch {
                $attempt++
                if ($attempt -lt $maxRetries) {
                    Write-Host "   Hosts file busy, retrying in ${retryDelay}s... ($attempt/$maxRetries)" -ForegroundColor Yellow
                    Start-Sleep -Seconds $retryDelay
                } else { throw }
            }
        }
        Write-Host "   ✓ Removed $removedCount dev entry/entries from Windows hosts file"
    } else {
        Write-Host "   ✓ No dev entries found in Windows hosts file — already clean"
    }
} else {
    Write-Host "   ⚠ Windows hosts file not found — skipping" -ForegroundColor Yellow
}

# ─── 6. Remove .wslconfig memory/swap settings added by setup_wsl_network ───

Write-Host "`n==> Step 6: Removing .wslconfig memory/swap settings..."
$wslConfigPath = Join-Path $env:USERPROFILE ".wslconfig"
if (Test-Path $wslConfigPath) {
    $content = Get-Content $wslConfigPath -Raw
    $keysToRemove = @("memory", "processors", "swap", "localhostForwarding")
    $newLines = ($content -split "\r?\n") | Where-Object {
        $line = $_.Trim()
        -not ($keysToRemove | Where-Object { $line -match "^\s*$_\s*=" })
    }
    $newContent = ($newLines -join "`n").Trim()
    # Remove empty [wsl2] header
    $newContent = $newContent -replace "(?m)^\[wsl2\]\s*$(\r?\n)*(?=\[|\z)", ""
    $newContent = $newContent.Trim()
    if ([string]::IsNullOrWhiteSpace($newContent)) {
        Remove-Item $wslConfigPath -Force
        Write-Host "   ✓ .wslconfig is now empty — file removed"
    } else {
        Set-Content -Path $wslConfigPath -Value $newContent -Encoding UTF8
        Write-Host "   ✓ .wslconfig memory/swap settings removed"
    }
} else {
    Write-Host "   ✓ No .wslconfig found — nothing to revert"
}

Write-Host "`n✓ WSL network configuration reverted" -ForegroundColor Green
Write-Host "   Run 'wsl --shutdown' and relaunch WSL to apply resolv.conf changes."
