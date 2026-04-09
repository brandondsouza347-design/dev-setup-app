# revert_windows_hosts.ps1
# Remove dev hostname entries added by the setup tool from the Windows hosts file.
# Only removes entries it recognises; all other content is preserved.
#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

$hostsFile = "C:\Windows\System32\drivers\etc\hosts"

Write-Host "==> Reverting Windows hosts file entries..." -ForegroundColor Cyan

# ─── 1. Read current hosts file ─────────────────────────────────────────────

if (-not (Test-Path $hostsFile)) {
    Write-Host "   ⚠ Hosts file not found at $hostsFile" -ForegroundColor Yellow
    exit 1
}

$originalLines = Get-Content $hostsFile
Write-Host "   Hosts file has $($originalLines.Count) lines"

# ─── 2. Identify lines to remove ────────────────────────────────────────────

# Patterns matching entries added by setup tool
# This includes both old format and new format with tenant name appended to localhost
$removePatterns = @(
    "^\s*127\.0\.0\.1\s+localhost\s+\w+\s*$",  # IPv4 localhost with tenant name
    "^\s*::1\s+localhost\s+\w+\s*$",          # IPv6 localhost with tenant name
    "t3582\.local",                            # Old format
    "^\s*127\.0\.0\.1\s+erckinetic\s*$",      # Old format - standalone tenant
    "erckinetic\.local",                       # Old format
    "localhost\.erckinetic",                   # Old format
    "# Dev hostnames \(added by setup tool\)"
)

$keptLines   = @()
$removedLines = @()

foreach ($line in $originalLines) {
    $matched = $false
    foreach ($pattern in $removePatterns) {
        if ($line -match $pattern) {
            $matched = $true
            break
        }
    }
    if ($matched) {
        $removedLines += $line
    } else {
        $keptLines += $line
    }
}

if ($removedLines.Count -eq 0) {
    Write-Host "✓ No setup-tool entries found in hosts file — nothing to revert"
    exit 0
}

Write-Host "`n   Removing $($removedLines.Count) line(s):"
$removedLines | ForEach-Object { Write-Host "     - $_" }

# ─── 3. Trim trailing blank lines ────────────────────────────────────────────

while ($keptLines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($keptLines[-1])) {
    $keptLines = $keptLines[0..($keptLines.Count - 2)]
}

# ─── 4. Write cleaned file ──────────────────────────────────────────────────

Write-Host "`n==> Step 1: Writing cleaned hosts file..."

# Handle file locking by stopping/restarting DNS Client service
$maxRetries = 3
$retryCount = 0
$success = $false

while (-not $success -and $retryCount -lt $maxRetries) {
    try {
        if ($retryCount -gt 0) {
            Write-Host "   Retry attempt $retryCount/$maxRetries..." -ForegroundColor Yellow
        }

        # Stop DNS Client service to unlock hosts file
        Write-Host "   Stopping DNS Client service to unlock hosts file..." -ForegroundColor Cyan
        $dnsClientRunning = (Get-Service -Name Dnscache -ErrorAction SilentlyContinue).Status -eq 'Running'
        if ($dnsClientRunning) {
            Stop-Service -Name Dnscache -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500
        }

        # Write the file
        Set-Content -Path $hostsFile -Value $keptLines -Encoding ASCII -Force

        # Restart DNS Client service
        if ($dnsClientRunning) {
            Write-Host "   Restarting DNS Client service..." -ForegroundColor Cyan
            Start-Service -Name Dnscache -ErrorAction SilentlyContinue
        }

        $success = $true
        Write-Host "   ✓ Hosts file updated ($($keptLines.Count) lines remaining)" -ForegroundColor Green
    }
    catch {
        $retryCount++
        if ($retryCount -lt $maxRetries) {
            Write-Host "   ⚠ Write failed: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "   Waiting 2 seconds before retry..." -ForegroundColor Yellow
            Start-Sleep -Seconds 2
        }
        else {
            Write-Host ""
            Write-Host "ERROR: Failed to write hosts file after $maxRetries attempts" -ForegroundColor Red
            Write-Host "       $($_.Exception.Message)" -ForegroundColor Red
            Write-Host ""
            Write-Host "This usually means the file is locked by:" -ForegroundColor Yellow
            Write-Host "  - DNS Client service (Dnscache)" -ForegroundColor Yellow
            Write-Host "  - Antivirus software scanning the file" -ForegroundColor Yellow
            Write-Host "  - Another application" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Solutions:" -ForegroundColor Cyan
            Write-Host "  1. Close all browsers and network tools" -ForegroundColor Cyan
            Write-Host "  2. Temporarily disable antivirus" -ForegroundColor Cyan
            Write-Host "  3. Restart your computer and retry" -ForegroundColor Cyan
            Write-Host ""

            # Try to restart DNS Client before exiting
            if ($dnsClientRunning) {
                Start-Service -Name Dnscache -ErrorAction SilentlyContinue
            }

            throw
        }
    }
}

Write-Host "`n✓ Windows hosts file reverted" -ForegroundColor Green
