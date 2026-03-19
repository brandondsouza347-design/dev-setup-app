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

    # Check Tauri CLI
    try {
        $tauriVer = cargo tauri --version 2>&1
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

Write-Host "`n==> Building Tauri app for Windows x64..."
Write-Host "    This takes 5-15 minutes on first build (Rust compilation)"
Write-Host ""

cargo tauri build

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
