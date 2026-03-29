# revert_git_ssh.ps1
# Undo changes made by setup_git_ssh.ps1 inside the ERC WSL distro:
#   - Remove global git identity config (user.name, user.email, core.*, init.*, pull.*)
#   - Remove SSH agent auto-start block from ~/.bashrc
#   - Leave ~/.ssh/id_ed25519 intact (key is kept — user may have added it to GitHub)
# Does NOT remove the SSH key itself to avoid locking the user out of GitHub.
$ErrorActionPreference = "Stop"
$DistroName = "ERC"

# Helper: write bash snippet to a temp LF-only file and execute via WSL.
# Avoids stdin-pipe CRLF re-introduction by PowerShell 5.1 on Windows.
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

Write-Host "==> Reverting Git & SSH Configuration" -ForegroundColor Cyan

# ─── 1. Check distro is available ───────────────────────────────────────────

Write-Host "`n==> Step 1: Checking WSL distro..."
$existingDistros = (wsl --list --quiet 2>$null) -replace '\0','' | Where-Object { $_ -match $DistroName }
if (-not $existingDistros) {
    Write-Host "   ✓ Distro '$DistroName' not present — git/ssh config already clean"
    exit 0
}
Write-Host "   ✓ $DistroName is available"

# ─── 2. Remove Git global identity settings ─────────────────────────────────

Write-Host "`n==> Step 2: Removing Git global identity from WSL..."
Invoke-WslBash @"
git config --global --unset user.name 2>/dev/null || true
git config --global --unset user.email 2>/dev/null || true
git config --global --unset core.autocrlf 2>/dev/null || true
git config --global --unset core.eol 2>/dev/null || true
git config --global --unset init.defaultBranch 2>/dev/null || true
git config --global --unset pull.rebase 2>/dev/null || true
echo 'Step 2 complete - Git global identity settings removed'
"@

# ─── 3. Remove SSH agent auto-start from ~/.bashrc ──────────────────────────

Write-Host "`n==> Step 3: Removing SSH agent auto-start from WSL ~/.bashrc..."
Invoke-WslBash @"
if grep -qF '# SSH agent auto-start' ~/.bashrc 2>/dev/null; then
    sed -i '/# SSH agent auto-start/,/^fi/d' ~/.bashrc
    echo 'Step 3 complete - SSH agent auto-start block removed from ~/.bashrc'
else
    echo 'Step 3 complete - SSH agent auto-start not found in ~/.bashrc, already clean'
fi
"@

# ─── 4. Summary ─────────────────────────────────────────────────────────────

Write-Host "`n✓ Git & SSH configuration reverted" -ForegroundColor Green
Write-Host ""
Write-Host "  NOTE: SSH key files (~/.ssh/id_ed25519*) were NOT removed." -ForegroundColor Yellow
Write-Host "        If you want to remove them, run inside WSL:" -ForegroundColor Yellow
Write-Host "          rm ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.pub" -ForegroundColor Cyan
