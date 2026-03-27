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
$removePatterns = @(
    "t3582\.local",
    "erckinetic",
    "erckinetic\.local",
    "localhost\.erckinetic",
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
Set-Content -Path $hostsFile -Value $keptLines -Encoding ASCII
Write-Host "   ✓ Hosts file updated ($($keptLines.Count) lines remaining)"

Write-Host "`n✓ Windows hosts file reverted" -ForegroundColor Green
