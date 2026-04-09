# install_pgadmin.ps1 — Install pgAdmin 4 GUI for PostgreSQL database management
#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

Write-Output "==> Installing pgAdmin 4..."

# Check if pgAdmin is already installed
$pgAdminPaths = @(
    "$env:ProgramFiles\pgAdmin 4\v*\runtime\pgAdmin4.exe",
    "$env:ProgramFiles (x86)\pgAdmin 4\v*\runtime\pgAdmin4.exe"
)

$existing = $pgAdminPaths | ForEach-Object { Get-Item $_ -ErrorAction SilentlyContinue } | Select-Object -First 1

if ($existing) {
    Write-Output "✓ pgAdmin 4 is already installed"
    Write-Output "  Location: $($existing.DirectoryName)"
    exit 0
}

# Download pgAdmin installer
$version = "8.13"  # Update as needed
$downloadUrl = "https://ftp.postgresql.org/pub/pgadmin/pgadmin4/v$version/windows/pgadmin4-$version-x64.exe"
$installerPath = "$env:TEMP\pgadmin4-installer.exe"

Write-Output "→ Downloading pgAdmin 4 v$version..."
try {
    Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing
    Write-Output "  ✓ Downloaded to: $installerPath"
} catch {
    Write-Output "✗ Download failed: $_"
    Write-Output "  Please download manually from: https://www.pgadmin.org/download/pgadmin-4-windows/"
    exit 1
}

# Run installer silently
Write-Output "→ Installing pgAdmin 4..."
try {
    $process = Start-Process -FilePath $installerPath -ArgumentList '/VERYSILENT', '/NORESTART' -Wait -PassThru
    if ($process.ExitCode -eq 0) {
        Write-Output "✓ pgAdmin 4 installed successfully"
        Write-Output "  Launch from Start Menu or: pgAdmin 4"
        Write-Output ""
        Write-Output "  First-time setup:"
        Write-Output "    1. Launch pgAdmin 4"
        Write-Output "    2. Set master password"
        Write-Output "    3. Right-click Servers → Register → Server"
        Write-Output "    4. Name: localhost"
        Write-Output "    5. Connection tab:"
        Write-Output "       - Host: localhost"
        Write-Output "       - Port: 5432"
        Write-Output "       - Username: postgres"
        Write-Output "       - Database: postgres"
    } else {
        Write-Output "✗ Installation failed with exit code: $($process.ExitCode)"
        exit 1
    }
} catch {
    Write-Output "✗ Installation error: $_"
    exit 1
} finally {
    # Cleanup installer
    if (Test-Path $installerPath) {
        Remove-Item $installerPath -Force
    }
}
