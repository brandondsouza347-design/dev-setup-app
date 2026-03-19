# ============================================================
# install-build-deps-windows.ps1
# Run this ONCE on a fresh Windows machine to install all
# build tools. After this, run build-windows.ps1.
# Run as Administrator.
# ============================================================
#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

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

# ── 5. Tauri CLI ──────────────────────────────────────────────
Write-Host ""
Write-Host "==> [5/5] Tauri CLI..."
try {
    $tv = cargo tauri --version 2>&1
    Write-Host "  ✓ Already installed: $tv"
} catch {
    Write-Host "  Installing Tauri CLI (takes 2-3 minutes)..."
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

Write-Host ""
Write-Host "══════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  ✅ All build dependencies installed!" -ForegroundColor Green
Write-Host ""
Write-Host "  IMPORTANT: Close and reopen your terminal to reload PATH."
Write-Host ""
Write-Host "  Next step — build the app:"
Write-Host "    cd dev-setup-app"
Write-Host "    .\scripts\build\build-windows.ps1"
Write-Host "══════════════════════════════════════════════════" -ForegroundColor Green
