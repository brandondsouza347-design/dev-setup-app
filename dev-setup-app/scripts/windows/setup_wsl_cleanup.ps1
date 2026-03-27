# setup_wsl_cleanup.ps1
# Set ERC as the default WSL distro and unregister any stale Ubuntu instances
$ErrorActionPreference = "Stop"

Write-Host "==> setup_wsl_cleanup: inspecting WSL distros..."

# Get list of registered distros
$wslList = wsl --list --quiet 2>&1 | Where-Object { $_ -match '\S' }
Write-Host "  Registered distros:"
$wslList | ForEach-Object { Write-Host "    - $_" }

# Identify the ERC distro (imported as ERC or erc)
$ercDistro = $wslList | Where-Object { $_ -match "^ERC$" } | Select-Object -First 1

if (-not $ercDistro) {
    Write-Host "  ERC distro not found in WSL list — may not be imported yet"
    Write-Host "  Skipping default assignment"
} else {
    # Check if ERC is already the default
    $wslStatus = wsl --status 2>&1 | Out-String
    if ($wslStatus -match "Default Distribution:\s*ERC") {
        Write-Host "✓ ERC is already the default WSL distro — skipping"
    } else {
        Write-Host "  Setting ERC as default WSL distro..."
        wsl --set-default ERC
        Write-Host "✓ ERC set as default WSL distro"
    }
}

# Unregister stale Ubuntu instances (Ubuntu, Ubuntu-xx.xx that are NOT ERC)
$staleDistros = $wslList | Where-Object { $_ -match "^Ubuntu" }
if ($staleDistros) {
    Write-Host "  Found Ubuntu distro(s) to unregister: $($staleDistros -join ', ')"
    foreach ($distro in $staleDistros) {
        $trimmed = $distro.Trim()
        Write-Host "  Unregistering '$trimmed'..."
        wsl --unregister $trimmed
        Write-Host "  ✓ Unregistered '$trimmed'"
    }
} else {
    Write-Host "✓ No stale Ubuntu distros found — nothing to unregister"
}

# Final status
Write-Host ""
Write-Host "✓ WSL cleanup complete"
Write-Host "  Current WSL distros:"
wsl --list --verbose 2>&1 | ForEach-Object { Write-Host "    $_" }
