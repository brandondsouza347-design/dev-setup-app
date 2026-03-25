# ============================================================
# install-build-deps-windows.ps1
# Run this ONCE on a fresh Windows machine to install all
# build tools. After this, run build-windows.ps1.
# Run as Administrator.
# ============================================================
#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

# Reload PATH so any previously-installed tools are visible immediately
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Installing Build Dependencies (Windows)          ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Helper
function Install-WithWinget($id, $label) {
    Write-Host "==> $label..."
    try {
        $result = winget list --id $id 2>&1
        if ($result -match $id) {
            Write-Host "  ✓ Already installed"
            return
        }
    } catch {}
    winget install --id $id --accept-source-agreements --accept-package-agreements -e
    Write-Host "  ✓ $label installed"
}

# ── 1. Check winget ──────────────────────────────────────────
Write-Host "==> [1/5] Checking winget..."
try {
    winget --version | Out-Null
    Write-Host "  ✓ winget available"
} catch {
    Write-Host "  ✗ winget not found. Install App Installer from the Microsoft Store." -ForegroundColor Red
    Start-Process "ms-windows-store://pdp/?productid=9NBLGGH4NNS1"
    exit 1
}

# ── 2. Visual Studio Build Tools (Rust requires MSVC linker) ─
Write-Host ""
Write-Host "==> [2/5] Visual Studio C++ Build Tools..."
$vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$hasBuildTools = $false
if (Test-Path $vsWhere) {
    $vsInstalls = & $vsWhere -products * -requires Microsoft.VisualCpp.Tools.HostX64.TargetX64 2>$null
    $hasBuildTools = ($vsInstalls -ne $null -and $vsInstalls.Length -gt 0)
}
if ($hasBuildTools) {
    Write-Host "  ✓ C++ Build Tools already installed"
} else {
    winget install --id Microsoft.VisualStudio.2022.BuildTools `
        --override "--quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended" `
        --accept-source-agreements --accept-package-agreements -e
    Write-Host "  ✓ C++ Build Tools installed"
}

# ── 3. Rust ───────────────────────────────────────────────────
Write-Host ""
Write-Host "==> [3/5] Rust toolchain..."
try {
    $rv = rustc --version 2>&1
    Write-Host "  ✓ Already installed: $rv"
    rustup update stable
} catch {
    Install-WithWinget "Rustlang.Rustup" "Rust (rustup)"
    # Reload PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    Write-Host "  ✓ Rust installed"
}

# ── 4. Node.js ────────────────────────────────────────────────
Write-Host ""
Write-Host "==> [4/5] Node.js LTS..."
try {
    $nv = node --version 2>&1
    Write-Host "  ✓ Already installed: $nv"
} catch {
    Install-WithWinget "OpenJS.NodeJS.LTS" "Node.js LTS"
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}
# Permanently add Node.js to User PATH if missing
$nodePath = "C:\Program Files\nodejs"
$userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
if ((Test-Path $nodePath) -and ($userPath -notlike "*nodejs*")) {
    [System.Environment]::SetEnvironmentVariable("Path", $userPath + ";$nodePath", "User")
    Write-Host "  ✓ Node.js added to permanent User PATH"
}
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# ── 5. Tauri CLI ──────────────────────────────────────────────
Write-Host ""
Write-Host "==> [5/6] Tauri CLI..."
try {
    $tv = (cargo tauri --version 2>&1) -join ""
    Write-Host "  ✓ Already installed: $tv"
} catch {
    Write-Host "  Installing Tauri CLI (takes 2-3 minutes, compiles from source)..."
    cargo install tauri-cli --locked
    Write-Host "  ✓ Tauri CLI installed"
}

# ── WebView2 Runtime ──────────────────────────────────────────
Write-Host ""
Write-Host "==> WebView2 Runtime (required by Tauri)..."
$wv2 = Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" -ErrorAction SilentlyContinue
if ($wv2) {
    Write-Host "  ✓ WebView2 already installed"
} else {
    Install-WithWinget "Microsoft.EdgeWebView2Runtime" "WebView2 Runtime"
}

# ── 6. WiX Toolset (pre-cache to avoid corporate SSL issues) ──
Write-Host ""
Write-Host "==> [6/7] WiX Toolset (MSI bundler for Tauri)..."
$wixDir  = "$env:LOCALAPPDATA\tauri\WixTools"
$wixSentinel = "$wixDir\candle.exe"
$wixZip  = "$env:TEMP\wix314-binaries.zip"
$wixUrl  = "https://github.com/wixtoolset/wix3/releases/download/wix3141rtm/wix314-binaries.zip"
if (Test-Path $wixSentinel) {
    Write-Host "  ✓ WiX already cached at $wixDir"
} else {
    New-Item -ItemType Directory -Force -Path $wixDir | Out-Null
    $downloaded = $false

    # Try WebClient with system proxy + default Windows credentials (works through corporate proxies)
    try {
        Write-Host "  Downloading WiX via system proxy..."
        $wc = New-Object System.Net.WebClient
        $wc.Proxy = [System.Net.WebRequest]::GetSystemWebProxy()
        $wc.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
        $wc.DownloadFile($wixUrl, $wixZip)
        $downloaded = $true
    } catch {
        Write-Host "  ⚠ Automatic download failed: $_" -ForegroundColor Yellow
    }

    if ($downloaded) {
        Write-Host "  Extracting WiX..."
        Expand-Archive -Path $wixZip -DestinationPath $wixDir -Force
        Remove-Item $wixZip -Force
        Write-Host "  ✓ WiX cached at $wixDir"
    } else {
        Write-Host "" -ForegroundColor Yellow
        Write-Host "  ══════════════════════════════════════════════════" -ForegroundColor Yellow
        Write-Host "  ACTION REQUIRED — Manual WiX download needed:" -ForegroundColor Yellow
        Write-Host "" -ForegroundColor Yellow
        Write-Host "  1. Open this URL in your browser and save the file:" -ForegroundColor Yellow
        Write-Host "     $wixUrl" -ForegroundColor Cyan
        Write-Host "" -ForegroundColor Yellow
        Write-Host "  2. Extract the zip contents into:" -ForegroundColor Yellow
        Write-Host "     $wixDir" -ForegroundColor Cyan
        Write-Host "" -ForegroundColor Yellow
        Write-Host "  3. Re-run this script (it will skip the download next time)." -ForegroundColor Yellow
        Write-Host "  ══════════════════════════════════════════════════" -ForegroundColor Yellow
        Write-Host ""
        $global:wixMissing = $true
    }
}

# ── 7. NSIS Toolset (pre-cache to avoid corporate SSL issues) ──
Write-Host ""
Write-Host "==> [7/7] NSIS Toolset (EXE bundler for Tauri)..."
$nsisDir      = "$env:LOCALAPPDATA\tauri\NSIS"
$nsisSentinel = "$nsisDir\Plugins\x86-unicode\additional\nsis_tauri_utils.dll"
$nsisZip      = "$env:TEMP\nsis-3.11.zip"
$nsisUrl      = "https://github.com/tauri-apps/binary-releases/releases/download/nsis-3.11/nsis-3.11.zip"
$nsisUtilsUrl = "https://github.com/tauri-apps/nsis-tauri-utils/releases/download/nsis_tauri_utils-v0.5.3/nsis_tauri_utils.dll"
if (Test-Path $nsisSentinel) {
    Write-Host "  ✓ NSIS already cached at $nsisDir"
} else {
    $nsisDownloaded = $false
    try {
        Write-Host "  Downloading NSIS via system proxy..."
        $wc = New-Object System.Net.WebClient
        $wc.Proxy = [System.Net.WebRequest]::GetSystemWebProxy()
        $wc.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
        $wc.DownloadFile($nsisUrl, $nsisZip)
        $nsisDownloaded = $true
    } catch {
        Write-Host "  ⚠ Automatic download failed: $_" -ForegroundColor Yellow
    }
    if ($nsisDownloaded) {
        $tauriDir = "$env:LOCALAPPDATA\tauri"
        if (Test-Path "$tauriDir\nsis-3.11") { Remove-Item "$tauriDir\nsis-3.11" -Recurse -Force }
        if (Test-Path $nsisDir) { Remove-Item $nsisDir -Recurse -Force }
        Expand-Archive -Path $nsisZip -DestinationPath $tauriDir -Force
        Rename-Item "$tauriDir\nsis-3.11" "NSIS" -ErrorAction SilentlyContinue
        Remove-Item $nsisZip -Force
        $utilsDir = "$nsisDir\Plugins\x86-unicode\additional"
        New-Item -ItemType Directory -Force -Path $utilsDir | Out-Null
        try {
            $wc2 = New-Object System.Net.WebClient
            $wc2.Proxy = [System.Net.WebRequest]::GetSystemWebProxy()
            $wc2.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
            $wc2.DownloadFile($nsisUtilsUrl, "$utilsDir\nsis_tauri_utils.dll")
            Write-Host "  ✓ NSIS cached at $nsisDir"
        } catch {
            Write-Host "  ⚠ nsis_tauri_utils download failed: $_" -ForegroundColor Yellow
            $global:nsisMissing = $true
        }
    } else {
        Write-Host "" -ForegroundColor Yellow
        Write-Host "  ══════════════════════════════════════════════════" -ForegroundColor Yellow
        Write-Host "  ACTION REQUIRED — Manual NSIS download needed:" -ForegroundColor Yellow
        Write-Host "" -ForegroundColor Yellow
        Write-Host "  1. Open this URL in your browser and save the file:" -ForegroundColor Yellow
        Write-Host "     $nsisUrl" -ForegroundColor Cyan
        Write-Host "     Extract to $env:LOCALAPPDATA\tauri\  then rename nsis-3.11 folder → NSIS" -ForegroundColor Yellow
        Write-Host "" -ForegroundColor Yellow
        Write-Host "  2. Also download nsis_tauri_utils.dll:" -ForegroundColor Yellow
        Write-Host "     $nsisUtilsUrl" -ForegroundColor Cyan
        Write-Host "     Place at $nsisSentinel" -ForegroundColor Yellow
        Write-Host "  ══════════════════════════════════════════════════" -ForegroundColor Yellow
        $global:nsisMissing = $true
    }
}

# ── 8. PowerShell profile — auto-refresh PATH on every terminal start ──
Write-Host ""
Write-Host "==> Configuring PowerShell profile (auto PATH refresh)..."
$profileLine = '$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")'
$profilePaths = @(
    # Current user, all hosts (used by VS Code terminal and regular PowerShell)
    [System.IO.Path]::Combine([System.Environment]::GetFolderPath("MyDocuments"), "WindowsPowerShell", "Microsoft.PowerShell_profile.ps1"),
    # PowerShell 7+ profile path
    [System.IO.Path]::Combine([System.Environment]::GetFolderPath("MyDocuments"), "PowerShell", "Microsoft.PowerShell_profile.ps1")
)
foreach ($profilePath in $profilePaths) {
    $profileDir = Split-Path $profilePath -Parent
    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
    }
    if (-not (Test-Path $profilePath)) {
        New-Item -ItemType File -Force -Path $profilePath | Out-Null
    }
    $existingContent = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
    if ($existingContent -notlike "*GetEnvironmentVariable*") {
        Add-Content -Path $profilePath -Value ""
        Add-Content -Path $profilePath -Value "# Auto-refresh PATH from registry (added by install-build-deps-windows.ps1)"
        Add-Content -Path $profilePath -Value $profileLine
        Write-Host "  ✓ Profile updated: $profilePath"
    } else {
        Write-Host "  ✓ Already configured: $profilePath"
    }
}

# ── 8. Install / update frontend npm packages ────────────────────────────────
Write-Host ""
Write-Host "==> Installing frontend npm packages..."
$appDir = Resolve-Path "$PSScriptRoot\..\.."
Set-Location $appDir
npm install
Write-Host "  ✓ npm packages up to date"

Write-Host ""
Write-Host "══════════════════════════════════════════════════" -ForegroundColor Green
if ($global:wixMissing -or $global:nsisMissing) {
    Write-Host "  ⚠ Build dependencies installed (manual download step required — see above)" -ForegroundColor Yellow
} else {
    Write-Host "  ✅ All build dependencies installed!" -ForegroundColor Green
}
Write-Host ""
Write-Host "  PATH is now auto-refreshed in every new terminal."
Write-Host "  Open a new VS Code terminal and node/npm/cargo will work immediately."
Write-Host ""
Write-Host "  Next step — build the app:"
Write-Host "    cd dev-setup-app"
Write-Host "    .\scripts\build\build-windows.ps1"
Write-Host "══════════════════════════════════════════════════" -ForegroundColor Green
