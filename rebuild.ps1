# Quick rebuild script
Set-Location "C:\Users\brandon.dsouza\Documents\VScode_Projects\dev-setup-app"

Write-Host ""
Write-Host "=== Version 1.11.0 Changes ===" -ForegroundColor Green
Write-Host "✓ Changed default tenant name: 'erckinetic' (was 't2070')" -ForegroundColor Cyan
Write-Host "✓ Gunicorn now auto-opens browser to http://{tenant}:8000/#" -ForegroundColor Cyan
Write-Host "✓ Tenant name used from Settings configuration" -ForegroundColor Cyan
Write-Host ""

# Delete old config to use new defaults
$configPath = "$env:LOCALAPPDATA\dev-setup-app\config.json"
if (Test-Path $configPath) {
    Write-Host "Deleting old config to use new defaults..." -ForegroundColor Yellow
    Remove-Item $configPath -Force
    Write-Host "✓ Old config deleted" -ForegroundColor Green
    Write-Host ""
}

Write-Host "Building app..." -ForegroundColor Cyan
.\dev-setup-app\scripts\build\build-windows.ps1
