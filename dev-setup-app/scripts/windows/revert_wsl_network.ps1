# revert_wsl_network.ps1
# Undo changes made by setup_wsl_network.ps1:
#   - Unpin /etc/resolv.conf so WSL can auto-generate it again
#   - Remove generateResolvConf=false from /etc/wsl.conf
#   - Remove ERC WSL /etc/hosts dev entries
#   - Remove Windows hosts file dev entries
#   - Remove .wslconfig memory/swap block written by setup_wsl_network.ps1
#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
$DistroName = "ERC"

# Helper: write bash snippet to a temp LF-only file and execute via WSL.
function Invoke-WslBash {
    param([Parameter(Mandatory)][string]$Script)
    $tmp = [System.IO.Path]::GetTempFileName()
    $lf  = $Script.TrimStart("`r`n") -replace "`r`n", "`n" -replace "`r", "`n"
    [System.IO.File]::WriteAllText($tmp, $lf, [System.Text.UTF8Encoding]::new($false))
    $drive   = ($tmp[0]).ToString().ToLower()
    $wslPath = "/mnt/$drive" + ($tmp.Substring(2) -replace '\\', '/')
    wsl -d $DistroName -- bash $wslPath
    Remove-Item $tmp -ErrorAction SilentlyContinue
    if ($LASTEXITCODE -ne 0) { throw "WSL bash exited with code $LASTEXITCODE" }
}

Write-Host "==> Reverting WSL Network Configuration" -ForegroundColor Cyan

# ─── 1. Check distro is available ───────────────────────────────────────────

Write-Host "`n==> Step 1: Checking WSL distro..."
$existingDistros = (wsl --list --quiet 2>$null) -replace '\0','' | Where-Object { $_ -match $DistroName }
if (-not $existingDistros) {
    Write-Host "   ✓ Distro '$DistroName' not present — network config already clean" -ForegroundColor Green
    # Still clean Windows-side below
} else {
    Write-Host "   ✓ Step 1 complete — distro '$DistroName' found, proceeding with WSL-side revert" -ForegroundColor Green
}

# ─── 2. Restore resolv.conf (remove immutable flag, delete custom file) ─────

if ($existingDistros) {
    Write-Host "`n==> Step 2: Restoring resolv.conf to WSL auto-generated..."
    wsl -d $DistroName -- bash -c "sudo chattr -i /etc/resolv.conf 2>/dev/null || true; sudo rm -f /etc/resolv.conf 2>/dev/null || true"
    Write-Host "   ✓ Step 2 complete — resolv.conf unpinned and removed; WSL will auto-generate on next start" -ForegroundColor Green

    # ─── 3. Remove generateResolvConf=false from /etc/wsl.conf ──────────────

    Write-Host "`n==> Step 3: Restoring /etc/wsl.conf..."
    Invoke-WslBash @"
if [ -f /etc/wsl.conf ]; then
    sudo sed -i '/^generateResolvConf/d' /etc/wsl.conf 2>/dev/null || true
    echo 'Step 3 complete - generateResolvConf removed from /etc/wsl.conf'
else
    echo 'Step 3 complete - /etc/wsl.conf not found, nothing to revert'
fi
"@

    # ─── 4. Remove dev entries from WSL /etc/hosts ──────────────────────────

    Write-Host "`n==> Step 4: Removing dev hostnames from WSL /etc/hosts..."
    Invoke-WslBash @"
if [ -f /etc/hosts ]; then
    sudo sed -i '/erckinetic/d' /etc/hosts 2>/dev/null || true
    sudo sed -i '/Dev hostnames/d' /etc/hosts 2>/dev/null || true
    echo 'Step 4 complete - dev hostnames removed from WSL /etc/hosts'
else
    echo 'Step 4 complete - WSL /etc/hosts not found, nothing to revert'
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
        Write-Host "   ✓ Step 5 complete — removed $removedCount dev entry/entries from Windows hosts file" -ForegroundColor Green
    } else {
        Write-Host "   ✓ Step 5 complete — no dev entries found in Windows hosts file, already clean" -ForegroundColor Green
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
        Write-Host "   ✓ Step 6 complete — .wslconfig is now empty, file removed" -ForegroundColor Green
    } else {
        Set-Content -Path $wslConfigPath -Value $newContent -Encoding UTF8
        Write-Host "   ✓ Step 6 complete — .wslconfig memory/swap settings removed" -ForegroundColor Green
    }
} else {
    Write-Host "   ✓ Step 6 complete — no .wslconfig found, nothing to revert" -ForegroundColor Green
}

Write-Host "`n✓ WSL network configuration reverted successfully" -ForegroundColor Green
Write-Host "   Run 'wsl --shutdown' and relaunch WSL to apply resolv.conf changes."
