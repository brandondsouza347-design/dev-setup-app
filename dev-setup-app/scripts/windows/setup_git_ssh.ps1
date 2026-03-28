# setup_git_ssh.ps1 — Configure Git identity and SSH keys inside WSL2
# Run as normal user

$ErrorActionPreference = "Stop"
$DistroName = "ERC"

Write-Host "==> Git & SSH Configuration" -ForegroundColor Cyan

# ─── 1. Check WSL is available ──────────────────────────────────────────────

Write-Host "`n==> Step 1: Checking WSL distro..."
$existingDistros = (wsl --list --quiet 2>$null) -replace '\0','' | Where-Object { $_ -match $DistroName }
if (-not $existingDistros) {
    Write-Host "ERROR: $DistroName is not installed. Run 'Import WSL TAR' step first." -ForegroundColor Red
    exit 1
}
Write-Host "✓ $DistroName is available"

# ─── 2. Install Git inside WSL ──────────────────────────────────────────────

Write-Host "`n==> Step 2: Ensuring Git is installed in WSL..."

wsl -d $DistroName -- bash -c @"
if ! command -v git &>/dev/null; then
    sudo apt-get update -q && sudo apt-get install -y git
    echo '✓ Git installed'
else
    echo "✓ Git already installed: \$(git --version)"
fi
"@

# ─── 3. Configure Git identity ──────────────────────────────────────────────

Write-Host "`n==> Step 3: Configuring Git identity inside WSL..."

# Try to get identity from Windows Git if available (safe — Windows Git may not be installed yet)
$winGitName = $null
$winGitEmail = $null
try {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $winGitName  = git config --global user.name  2>$null
        $winGitEmail = git config --global user.email 2>$null
    }
} catch {
    # Windows Git not in PATH — fall back to env vars or skip identity config
}

# Check if already configured in WSL
$wslGitName = wsl -d $DistroName -- bash -c "git config --global user.name 2>/dev/null" 2>$null

if ($wslGitName) {
    Write-Host "✓ Git identity already configured in WSL:"
    Write-Host "   Name : $wslGitName"
    $wslGitEmail = wsl -d $DistroName -- bash -c "git config --global user.email 2>/dev/null" 2>$null
    Write-Host "   Email: $wslGitEmail"
} else {
    # Use Windows Git config if available, then env vars injected by the installer,
    # then skip with a warning — Read-Host cannot be used (no interactive terminal).
    if (-not $winGitName) { $winGitName = $env:SETUP_GIT_NAME }
    if (-not $winGitEmail) { $winGitEmail = $env:SETUP_GIT_EMAIL }

    if (-not $winGitName -or -not $winGitEmail) {
        Write-Host ""
        Write-Host "⚠ Git identity not configured — skipping git config in WSL." -ForegroundColor Yellow
        Write-Host "  Set it manually once setup is complete:" -ForegroundColor Yellow
        Write-Host "    wsl -d $DistroName -- git config --global user.name 'Your Name'" -ForegroundColor Cyan
        Write-Host "    wsl -d $DistroName -- git config --global user.email 'your@email.com'" -ForegroundColor Cyan
    } else {
        wsl -d $DistroName -- bash -c @"
git config --global user.name '$winGitName'
git config --global user.email '$winGitEmail'
git config --global core.autocrlf input
git config --global core.eol lf
git config --global init.defaultBranch main
git config --global pull.rebase false
echo '✓ Git identity configured'
"@
    }
}

# ─── 4. Generate SSH key ──────────────────────────────────────────────────────

Write-Host "`n==> Step 4: Setting up SSH keys in WSL..."

$wslEmail = wsl -d $DistroName -- bash -c "git config --global user.email 2>/dev/null" 2>$null

wsl -d $DistroName -- bash -c @"
set -euo pipefail

SSH_DIR="\$HOME/.ssh"
KEY_FILE="\$SSH_DIR/id_ed25519"

mkdir -p "\$SSH_DIR"
chmod 700 "\$SSH_DIR"

if [ -f "\$KEY_FILE" ]; then
    echo '✓ SSH key already exists: '\$KEY_FILE
else
    echo '==> Generating new ED25519 SSH key...'
    ssh-keygen -t ed25519 -C '$wslEmail' -f "\$KEY_FILE" -N ''
    echo '✓ SSH key generated: '\$KEY_FILE
fi

# Start ssh-agent and add key
if ! pgrep -u "\$USER" ssh-agent > /dev/null; then
    eval \$(ssh-agent -s)
fi
ssh-add "\$KEY_FILE" 2>/dev/null || true

echo ''
echo '==> Your public SSH key (add this to GitHub/Bitbucket):'
echo '------------------------------------------------------------'
cat "\$KEY_FILE.pub"
echo '------------------------------------------------------------'
"@

# ─── 5. Configure SSH agent auto-start in WSL ────────────────────────────────

Write-Host "`n==> Step 5: Configuring SSH agent auto-start in WSL ~/.bashrc..."

wsl -d $DistroName -- bash -c @"
MARKER='# SSH agent auto-start'
if ! grep -q "\$MARKER" ~/.bashrc 2>/dev/null; then
    cat >> ~/.bashrc << 'BASHRC'

# SSH agent auto-start
if [ -z "\$SSH_AUTH_SOCK" ]; then
    eval \$(ssh-agent -s) > /dev/null 2>&1
    ssh-add ~/.ssh/id_ed25519 2>/dev/null || true
fi
BASHRC
    echo '✓ SSH agent auto-start added to ~/.bashrc'
else
    echo '✓ SSH agent auto-start already in ~/.bashrc'
fi
"@

# ─── 6. Test GitHub connectivity ─────────────────────────────────────────────

Write-Host "`n==> Step 6: Testing SSH connectivity to GitHub..."
Write-Host "   NOTE: This will only succeed after you've added your public key to GitHub."

$sshTest = wsl -d $DistroName -- bash -c "ssh -T git@github.com -o StrictHostKeyChecking=no 2>&1 || true" 2>&1
if ($sshTest -match "successfully authenticated") {
    Write-Host "✓ GitHub SSH authentication successful!"
} else {
    Write-Host "⚠ GitHub SSH not yet configured (expected until you add the key)." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  To complete GitHub SSH setup:" -ForegroundColor Cyan
    Write-Host "  1. Copy the public key shown above"
    Write-Host "  2. Go to: https://github.com/settings/ssh/new"
    Write-Host "  3. Paste the key and save"
    Write-Host "  4. Test with: wsl -d $DistroName -- ssh -T git@github.com"
}

Write-Host "`n✓ Git & SSH setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "  Git config  : $(wsl -d $DistroName -- bash -c 'git config --global --list' 2>$null)"
Write-Host ""
Write-Host "  Access WSL  : wsl -d $DistroName"
Write-Host "  SSH key     : ~/.ssh/id_ed25519.pub (inside WSL)"
