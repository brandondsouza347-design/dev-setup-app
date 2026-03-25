# ============================================================
# build-windows.ps1 — Build the Dev Setup app locally on Windows
# Produces: src-tauri\target\release\bundle\msi\*.msi
#           src-tauri\target\release\bundle\nsis\*-setup.exe
# ============================================================

param(
    [switch]$SkipPrereqCheck
)

$ErrorActionPreference = "Stop"
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppDir     = Resolve-Path "$ScriptDir\..\.."

# Reload PATH so node/npm/cargo are available even in a fresh terminal
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     Dev Setup App — Local Windows Builder         ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "  App dir : $AppDir"
Write-Host ""

# ── 1. Check prerequisites ───────────────────────────────────────────────────

if (-not $SkipPrereqCheck) {
    Write-Host "==> Checking prerequisites..."

    $prereqOk = $true

    function Check-Command($cmd, $label) {
        try {
            $ver = & $cmd --version 2>&1 | Select-Object -First 1
            Write-Host "  ✓ $label — $ver"
        } catch {
            Write-Host "  ✗ $label not found" -ForegroundColor Red
            return $false
        }
        return $true
    }

    if (-not (Check-Command "rustc" "Rust")) { $prereqOk = $false }
    if (-not (Check-Command "cargo" "Cargo")) { $prereqOk = $false }
    if (-not (Check-Command "node"  "Node.js")) { $prereqOk = $false }
    if (-not (Check-Command "npm"   "npm")) { $prereqOk = $false }

    # Check Tauri CLI (v2 required)
    try {
        $tauriVer = (cargo tauri --version 2>&1) -join ""
        Write-Host "  ✓ Tauri CLI — $tauriVer"
    } catch {
        Write-Host "  ✗ Tauri CLI not found" -ForegroundColor Red
        $prereqOk = $false
    }

    # Check WebView2
    $webview2 = Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" -ErrorAction SilentlyContinue
    if ($webview2) {
        Write-Host "  ✓ WebView2 Runtime installed"
    } else {
        Write-Host "  ⚠ WebView2 Runtime not detected (usually pre-installed on Windows 11)" -ForegroundColor Yellow
    }

    if (-not $prereqOk) {
        Write-Host ""
        Write-Host "══════════════════════════════════════════════════" -ForegroundColor Yellow
        Write-Host "  Missing prerequisites. Install them first:"
        Write-Host ""
        Write-Host "  1. Rust:"
        Write-Host "     winget install --id Rustlang.Rustup -e"
        Write-Host "     # then restart your terminal"
        Write-Host ""
        Write-Host "  2. Tauri CLI:"
        Write-Host "     cargo install tauri-cli"
        Write-Host ""
        Write-Host "  3. Node.js:"
        Write-Host "     winget install --id OpenJS.NodeJS.LTS -e"
        Write-Host ""
        Write-Host "  4. Visual Studio C++ Build Tools (required by Rust):"
        Write-Host "     winget install --id Microsoft.VisualStudio.2022.BuildTools -e"
        Write-Host "══════════════════════════════════════════════════" -ForegroundColor Yellow
        exit 1
    }
}

# ── 2. Install frontend dependencies ────────────────────────────────────────

Write-Host "`n==> Installing frontend dependencies..."
Set-Location $AppDir
npm ci

# ── 3. Build ─────────────────────────────────────────────────────────────────

Write-Host "`n==> Pre-caching WiX Toolset (avoids corporate SSL issues during build)..."
$wixDir      = "$env:LOCALAPPDATA\tauri\WixTools"
$wixSentinel = "$wixDir\candle.exe"
$wixZip      = "$env:TEMP\wix314-binaries.zip"
$wixUrl      = "https://github.com/wixtoolset/wix3/releases/download/wix3141rtm/wix314-binaries.zip"
if (Test-Path $wixSentinel) {
    Write-Host "  ✓ WiX already cached"
} else {
    New-Item -ItemType Directory -Force -Path $wixDir | Out-Null
    $downloaded = $false
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
        Expand-Archive -Path $wixZip -DestinationPath $wixDir -Force
        Remove-Item $wixZip -Force
        Write-Host "  ✓ WiX cached at $wixDir"
    } else {
        Write-Host ""
        Write-Host "  ERROR: WiX Toolset is required to build the MSI installer." -ForegroundColor Red
        Write-Host "  Download manually in your browser and extract to: $wixDir" -ForegroundColor Yellow
        Write-Host "  URL: $wixUrl" -ForegroundColor Cyan
        Write-Host "  Then re-run this script." -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "`n==> Pre-caching NSIS Toolset (avoids corporate SSL issues during build)..."
$nsisDir      = "$env:LOCALAPPDATA\tauri\NSIS"
$nsisSentinel = "$nsisDir\Plugins\x86-unicode\additional\nsis_tauri_utils.dll"
$nsisZip      = "$env:TEMP\nsis-3.11.zip"
$nsisUrl      = "https://github.com/tauri-apps/binary-releases/releases/download/nsis-3.11/nsis-3.11.zip"
$nsisUtilsUrl = "https://github.com/tauri-apps/nsis-tauri-utils/releases/download/nsis_tauri_utils-v0.5.3/nsis_tauri_utils.dll"
if (Test-Path $nsisSentinel) {
    Write-Host "  ✓ NSIS already cached"
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
        Write-Host "  ⚠ NSIS download failed: $_" -ForegroundColor Yellow
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
            Write-Host "  ⚠ nsis_tauri_utils download failed (build may warn but continue): $_" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  ⚠ NSIS could not be pre-cached — the .exe installer build may fail." -ForegroundColor Yellow
        Write-Host "    Manual: download $nsisUrl" -ForegroundColor Yellow
        Write-Host "    Extract to $env:LOCALAPPDATA\tauri\ then rename folder nsis-3.11 → NSIS" -ForegroundColor Yellow
    }
}

Write-Host "`n==> Building Tauri app for Windows x64..."
Write-Host "    This takes 5-15 minutes on first build (Rust compilation)"
Write-Host ""

cargo tauri build
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "══════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host "  ❌ Build failed! See errors above." -ForegroundColor Red
    Write-Host "══════════════════════════════════════════════════" -ForegroundColor Red
    exit 1
}
# ── 4. Find and report output ────────────────────────────────────────────────

Write-Host ""
Write-Host "══════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  ✅ Build complete!" -ForegroundColor Green
Write-Host ""

$bundleDir = "$AppDir\src-tauri\target\release\bundle"

$msi  = Get-ChildItem "$bundleDir\msi\*.msi"   -ErrorAction SilentlyContinue | Select-Object -First 1
$nsis = Get-ChildItem "$bundleDir\nsis\*.exe"   -ErrorAction SilentlyContinue | Select-Object -First 1

if ($msi) {
    $sizeMB = [Math]::Round($msi.Length / 1MB, 1)
    Write-Host "  📦 MSI installer  : $($msi.FullName)"
    Write-Host "  📏 Size           : ${sizeMB} MB"
}
if ($nsis) {
    $sizeMB = [Math]::Round($nsis.Length / 1MB, 1)
    Write-Host "  📦 NSIS installer : $($nsis.FullName)"
    Write-Host "  📏 Size           : ${sizeMB} MB"
}

Write-Host ""
Write-Host "  To distribute:"
Write-Host "  1. Upload the .msi or -setup.exe to GitHub Releases or a file host"
Write-Host "  2. Users: double-click installer → follow prompts → launch from Start Menu"
Write-Host "══════════════════════════════════════════════════" -ForegroundColor Green
