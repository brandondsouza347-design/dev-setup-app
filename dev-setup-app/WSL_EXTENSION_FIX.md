# WSL Extension Installation Fix - Complete Guide

## Problem Summary

**Issue**: VS Code extensions report as "already installed" but aren't actually in WSL
- Extensions exist on Windows host
- VS Code's `--install-extension` with `--remote wsl+ERC` returns success (exit code 0)
- BUT extensions don't appear in WSL VS Code Server
- User sees "Install in WSL: ERC" buttons despite script reporting success

**Root Cause**: VS Code CLI returns success when extension exists on Windows, even when installation to WSL remote fails

**Current State**:
- ✅ SSL bypass configured (both Windows and WSL)
- ✅ No SSL certificate errors
- ❌ Extensions not actually installed in WSL despite success messages

**Verified WSL Extensions** (only 5 installed):
```
~/.vscode-server/extensions/
├── epicor.angularjs-ref-0.1.4
├── epicor.djangoref-0.1.20
├── epicor.git-patch-manager-2.2.6
├── github.copilot-chat-0.43.0
└── pip-checker.pip-requirements-checker-1.0.0
```

**Missing** (16 workspace-recommended extensions):
- alefragnani.bookmarks
- ckolkman.vscode-postgres
- cweijan.dbclient-jdbc
- cweijan.vscode-database-client2
- eamodio.gitlens
- humao.rest-client
- mhutchie.git-graph
- ms-python.black-formatter
- ms-python.debugpy
- ms-python.pylint
- ms-python.python
- ms-python.vscode-pylance
- redhat.vscode-yaml
- dbaeumer.vscode-eslint
- github.copilot
- github.copilot-chat (installed but may need update)

---

## Fix #1: Add Installation Verification (IMPLEMENTED)

### What Changed

Updated `install_workspace_extensions.ps1` lines 337-365 to verify each extension after installation:

**Before** (trusted exit code):
```powershell
if ($LASTEXITCODE -eq 0) {
    $wslSuccess++
    Write-Output "    [OK] Installed to WSL"
}
```

**After** (actual verification):
```powershell
# Verify the extension is actually installed in WSL
Start-Sleep -Milliseconds 500  # Give VS Code Server time to update
$installedExtensions = & $codePath --remote "wsl+ERC" --list-extensions 2>&1 | Where-Object { $_ -match '^\w' }
$isInstalled = $installedExtensions -contains $ext

if ($isInstalled) {
    $wslSuccess++
    Write-Output "    [OK] Verified installed in WSL"
} else {
    $wslFail++
    Write-Output "    [ERROR] Not found in WSL after installation attempt"
}
```

### How to Apply

**Option A: Automatic (Rebuild)**
```powershell
cd C:\Users\brandon.dsouza\Documents\VScode_Projects\dev-setup-app\dev-setup-app
.\scripts\build\build-windows.ps1
```

**Option B: Manual UTF-8 BOM Re-save (if needed)**
```powershell
cd C:\Users\brandon.dsouza\Documents\VScode_Projects\dev-setup-app\dev-setup-app
$path = "scripts\windows\install_workspace_extensions.ps1"
$content = Get-Content $path -Raw
[System.IO.File]::WriteAllText((Join-Path (Get-Location) $path), $content, [System.Text.UTF8Encoding]::new($true))
```

### Expected Outcome

After rebuilding and running setup:
- ✅ Script attempts installation with `--force`
- ✅ Queries `--list-extensions` to verify each extension
- ✅ Reports accurate success/failure counts
- ✅ Shows which extensions failed to install
- ⚠️ **May still fail if underlying issue persists** → See Fix #2

---

## Fix #2: Alternative WSL-Based Installation (RECOMMENDED IF FIX #1 FAILS)

### Investigation Results

**VS Code Server in WSL**:
```bash
~/.vscode-server/
├── bin/               # VS Code Server binaries
├── data/
│   └── Machine/
│       └── settings.json  # ✅ SSL bypass configured
└── extensions/        # ❌ Missing most workspace extensions
```

**Key Finding**: Extensions installed from Windows using `code --remote wsl+ERC --install-extension` may not propagate correctly to WSL Server

### Alternative Approach: Install from Inside WSL

Instead of installing from Windows PowerShell, install directly inside the WSL environment.

#### Step-by-Step Implementation

**1. Create WSL-based installation script**

Create `scripts/windows/install_wsl_extensions_direct.sh`:

```bash
#!/bin/bash
# Install VS Code extensions directly inside WSL

set -e

# VS Code Server CLI path
VSCODE_CLI="$HOME/.vscode-server/bin/*/bin/code-server"

# Expand glob to get actual path
VSCODE_CLI=$(echo $VSCODE_CLI)

if [ ! -f "$VSCODE_CLI" ]; then
    echo "[ERROR] VS Code Server CLI not found at $VSCODE_CLI"
    echo "  Please open VS Code connected to WSL at least once to initialize the server"
    exit 1
fi

echo "Using VS Code Server CLI: $VSCODE_CLI"

# Extensions to install (workspace recommendations)
EXTENSIONS=(
    "alefragnani.bookmarks"
    "ckolkman.vscode-postgres"
    "cweijan.dbclient-jdbc"
    "cweijan.vscode-database-client2"
    "eamodio.gitlens"
    "github.copilot"
    "github.copilot-chat"
    "humao.rest-client"
    "mhutchie.git-graph"
    "ms-python.black-formatter"
    "ms-python.debugpy"
    "ms-python.pylint"
    "ms-python.python"
    "ms-python.vscode-pylance"
    "redhat.vscode-yaml"
    "dbaeumer.vscode-eslint"
)

SUCCESS=0
FAILED=0

echo "Installing ${#EXTENSIONS[@]} extensions to WSL VS Code Server..."
echo ""

for ext in "${EXTENSIONS[@]}"; do
    echo "  [WSL] $ext"
    if $VSCODE_CLI --install-extension "$ext" --force; then
        # Verify installation
        if $VSCODE_CLI --list-extensions | grep -q "^$ext$"; then
            echo "    [OK] Verified installed"
            ((SUCCESS++))
        else
            echo "    [ERROR] Not found after installation"
            ((FAILED++))
        fi
    else
        echo "    [ERROR] Installation failed"
        ((FAILED++))
    fi
    echo ""
done

echo "═══════════════════════════════════════════════"
echo "  Results: $SUCCESS installed, $FAILED failed"
echo "═══════════════════════════════════════════════"

if [ $FAILED -gt 0 ]; then
    exit 1
fi
```

**2. Make script executable**

```bash
chmod +x scripts/windows/install_wsl_extensions_direct.sh
```

**3. Update PowerShell orchestrator**

Modify `install_workspace_extensions.ps1` to call the bash script:

```powershell
# After WSL SSL bypass configuration (around line 320)

Write-Output ""
Write-Output "→ Installing extensions using WSL-based approach..."
try {
    $scriptPath = "/mnt/c/Users/brandon.dsouza/Documents/VScode_Projects/dev-setup-app/dev-setup-app/scripts/windows/install_wsl_extensions_direct.sh"
    wsl -d ERC -- bash "$scriptPath"

    if ($LASTEXITCODE -eq 0) {
        Write-Output "[OK] WSL extensions installed successfully"
    } else {
        Write-Output "[ERROR] WSL extension installation encountered errors"
    }
} catch {
    Write-Output "[ERROR] Failed to run WSL extension installer: $($_.Exception.Message)"
}
```

**4. Test manually first**

```bash
# From inside WSL
cd /mnt/c/Users/brandon.dsouza/Documents/VScode_Projects/dev-setup-app/dev-setup-app
bash scripts/windows/install_wsl_extensions_direct.sh
```

### Advantages of WSL-Based Approach

✅ **Direct installation** - No Windows→WSL translation issues
✅ **Uses VS Code Server CLI** - Installs to correct location
✅ **Proper verification** - Can query installed extensions directly
✅ **Better error messages** - See actual installation failures
✅ **Works with SSL bypass** - Uses WSL settings.json we created

### Disadvantages

⚠️ **Requires VS Code Server initialized** - User must connect to WSL at least once
⚠️ **More complex** - Two-script approach (PowerShell + Bash)
⚠️ **Path dependencies** - Need to find VS Code Server CLI path dynamically

---

## Fix #3: Hybrid Approach (RECOMMENDED)

Combine both approaches for maximum reliability:

1. **Try Windows-based installation first** (Fix #1 - with verification)
2. **If verification fails**, fall back to WSL-based installation (Fix #2)

### Implementation

```powershell
# In install_workspace_extensions.ps1 (around line 330)

Write-Output "→ Installing extensions to WSL remote environment (ERC)..."
Write-Output "  (Extensions will be installed inside the WSL VS Code Server)"

$wslSuccess = 0
$wslFail = 0
$failedExtensions = @()

foreach ($ext in $wslExtensions) {
    Write-Output "  [WSL] $ext"
    try {
        # Attempt 1: Windows-based installation
        $result = & $codePath --remote "wsl+ERC" --install-extension $ext --force 2>&1

        # Verify installation
        Start-Sleep -Milliseconds 500
        $installedExtensions = & $codePath --remote "wsl+ERC" --list-extensions 2>&1 | Where-Object { $_ -match '^\w' }
        $isInstalled = $installedExtensions -contains $ext

        if ($isInstalled) {
            $wslSuccess++
            Write-Output "    [OK] Verified installed in WSL"
        } else {
            Write-Output "    [WARN] Not verified via Windows method, will retry with WSL-based approach"
            $failedExtensions += $ext
            $wslFail++
        }
    } catch {
        Write-Output "    [ERROR] Exception: $($_.Exception.Message)"
        $failedExtensions += $ext
        $wslFail++
    }
}

# Attempt 2: WSL-based installation for failed extensions
if ($failedExtensions.Count -gt 0) {
    Write-Output ""
    Write-Output "→ Retrying $($failedExtensions.Count) failed extensions using WSL-based approach..."

    # Create temporary extension list file
    $tempExtList = "/tmp/vscode_ext_install.txt"
    $failedExtensions -join "`n" | wsl -d ERC -- bash -c "cat > $tempExtList"

    # Install using VS Code Server CLI
    wsl -d ERC -- bash -c @"
#!/bin/bash
VSCODE_CLI=\$(echo \$HOME/.vscode-server/bin/*/bin/code-server)
while IFS= read -r ext; do
    echo "  [WSL-Direct] \$ext"
    if \$VSCODE_CLI --install-extension "\$ext" --force; then
        echo "    [OK] Installed via WSL method"
    else
        echo "    [ERROR] Failed even with WSL method"
    fi
done < $tempExtList
"@
}
```

---

## Troubleshooting Guide

### Issue: "VS Code Server CLI not found"

**Cause**: VS Code Server hasn't been initialized in WSL
**Solution**:
```bash
# Open VS Code connected to WSL to initialize the server
code --remote wsl+ERC /home/ubuntu
```

### Issue: Extensions still show "Install in WSL: ERC"

**Cause**: Extensions installed to Windows instead of WSL
**Solution**: Verify extensions in WSL:
```bash
wsl -d ERC -- bash -c "ls ~/.vscode-server/extensions/"
```

### Issue: SSL certificate errors persist

**Verification**:
```bash
# Check WSL settings.json
wsl -d ERC -- cat ~/.vscode-server/data/Machine/settings.json

# Should show:
# {
#   "http.proxyStrictSSL": false,
#   "http.proxy": ""
# }
```

**If missing**, run SSL bypass configuration manually:
```bash
wsl -d ERC -- bash -c "mkdir -p ~/.vscode-server/data/Machine && echo '{\"http.proxyStrictSSL\": false, \"http.proxy\": \"\"}' > ~/.vscode-server/data/Machine/settings.json"
```

### Issue: "Extension already installed" but not in WSL

**Diagnosis**:
```powershell
# List Windows extensions
code --list-extensions

# List WSL extensions
code --remote wsl+ERC --list-extensions
```

If extension appears in Windows but not WSL → Use Fix #2 (WSL-based installation)

---

## Testing Procedure

After applying the fix:

**1. Rebuild application**
```powershell
.\scripts\build\build-windows.ps1
```

**2. Run setup**
Launch the rebuilt app and run the "Install Extensions + Configure MCP" step

**3. Verify installations**

```powershell
# Check WSL extensions via CLI
code --remote wsl+ERC --list-extensions

# Or from inside WSL
wsl -d ERC -- bash -c "ls ~/.vscode-server/extensions/ | sort"
```

**Expected Result** (16 extensions in WSL):
```
alefragnani.bookmarks-*
ckolkman.vscode-postgres-*
cweijan.dbclient-jdbc-*
cweijan.vscode-database-client2-*
dbaeumer.vscode-eslint-*
eamodio.gitlens-*
github.copilot-*
github.copilot-chat-*
humao.rest-client-*
mhutchie.git-graph-*
ms-python.black-formatter-*
ms-python.debugpy-*
ms-python.pylint-*
ms-python.python-*
ms-python.vscode-pylance-*
redhat.vscode-yaml-*
```

**4. Visual verification**

Open VS Code → Extensions view → Filter by "WSL: ERC - INSTALLED"
All 16 extensions should appear without "Install in WSL: ERC" buttons

---

## Recommended Action Plan

**Phase 1: Test Current Fix** (Already implemented)
1. ✅ Verification logic added to `install_workspace_extensions.ps1`
2. Rebuild application
3. Run setup and observe results

**Phase 2: If Still Failing** (Implement Fix #2)
1. Create `install_wsl_extensions_direct.sh` bash script
2. Update PowerShell orchestrator to call bash script
3. Test manually from WSL first
4. Rebuild and test via setup app

**Phase 3: Final Fallback** (Implement Fix #3)
1. Combine both approaches
2. Try Windows method first, WSL method for failures
3. Provides maximum compatibility

---

## Next Steps

1. **Rebuild now**: `.\scripts\build\build-windows.ps1`
2. **Run setup**: Test extension installation step
3. **Check logs**: Look for "[OK] Verified installed in WSL" vs "[ERROR] Not found in WSL"
4. **If failures persist**: Implement Fix #2 (WSL-based installation)
5. **Verify final state**: All extensions appear in WSL Extensions view

---

## Files Modified

- ✅ `scripts/windows/install_workspace_extensions.ps1` (lines 337-365)
  - Added post-installation verification
  - Changed from trusting exit code to actual extension query

## Files to Create (If needed)

- ⏸ `scripts/windows/install_wsl_extensions_direct.sh` (Fix #2)
  - WSL-based installation script
  - Uses VS Code Server CLI directly

---

**Status**: Fix #1 implemented, ready for testing
**Next**: Rebuild and test → Implement Fix #2 if needed
