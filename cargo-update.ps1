# Quick script to update cargo dependencies
Set-Location "C:\Users\brandon.dsouza\Documents\VScode_Projects\dev-setup-app\dev-setup-app\src-tauri"
cargo update
Write-Host ""
Write-Host "Cargo dependencies updated!" -ForegroundColor Green
Write-Host ""
Write-Host "Now run the build script:"
Write-Host "  .\dev-setup-app\scripts\build\build-windows.ps1" -ForegroundColor Cyan
