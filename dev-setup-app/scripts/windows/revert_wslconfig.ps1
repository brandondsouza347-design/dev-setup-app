# revert_wslconfig.ps1
# Remove networkingMode=mirrored (and related setup-added settings) from ~/.wslconfig.
# Preserves all other user settings. Removes the file only if it becomes empty.
$ErrorActionPreference = "Stop"

$wslConfigPath = Join-Path $env:USERPROFILE ".wslconfig"

Write-Host "==> Reverting .wslconfig networking settings..." -ForegroundColor Cyan

# ─── 1. Check file exists ────────────────────────────────────────────────────

if (-not (Test-Path $wslConfigPath)) {
    Write-Host "✓ No .wslconfig found — nothing to revert"
    exit 0
}

$content = Get-Content $wslConfigPath -Raw
Write-Host "   Current .wslconfig content:"
$content -split "`n" | ForEach-Object { Write-Host "     $_" }

# ─── 2. Check if already clean ──────────────────────────────────────────────

if ($content -notmatch "networkingMode") {
    Write-Host "`n✓ networkingMode not present — .wslconfig is already clean"
    exit 0
}

# ─── 3. Remove networkingMode line ──────────────────────────────────────────

Write-Host "`n==> Step 1: Removing networkingMode setting..."
# Remove line containing networkingMode (any value)
$newLines = ($content -split "\r?\n") | Where-Object { $_ -notmatch "^\s*networkingMode\s*=" }
$newContent = $newLines -join "`n"

# Remove empty [wsl2] sections (header with no keys below it)
$newContent = $newContent -replace "(?m)^\[wsl2\]\s*(\r?\n|\r)(?=\[|\z)", ""
$newContent = $newContent.Trim()

# ─── 4. Write or remove file ────────────────────────────────────────────────

if ([string]::IsNullOrWhiteSpace($newContent)) {
    Remove-Item $wslConfigPath -Force
    Write-Host "   ✓ .wslconfig is now empty — file removed"
} else {
    Set-Content -Path $wslConfigPath -Value $newContent -Encoding UTF8 -NoNewline:$false
    Write-Host "   ✓ networkingMode removed. Updated .wslconfig:"
    $newContent -split "`n" | ForEach-Object { Write-Host "     $_" }
}

Write-Host "`n✓ .wslconfig reverted" -ForegroundColor Green
Write-Host "  NOTE: Run 'wsl --shutdown' then relaunch WSL for changes to take effect"
