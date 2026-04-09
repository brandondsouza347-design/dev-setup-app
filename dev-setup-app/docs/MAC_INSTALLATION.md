# Dev_Setup - macOS Installation Guide

## Quick Start

### Step 1: Download the DMG
Download `Dev_Setup_2.6.3_universal.dmg` from your internal distribution server.

### Step 2: Mount the DMG
Double-click the downloaded `.dmg` file. A new window will open showing:
- Dev_Setup.app (the application)
- install_app.sh (the installer script)

### Step 3: Run the Installer

**Option A: Simple Installation (Recommended)**

1. Open Terminal (Applications → Utilities → Terminal)
2. Navigate to the mounted DMG:
   ```bash
   cd /Volumes/Dev_Setup
   ```
3. Run the installer:
   ```bash
   ./install_app.sh
   ```
4. Follow the on-screen prompts
5. Press `y` when asked to launch the app

**Option B: Manual Installation**

1. Drag `Dev_Setup.app` to the Applications folder
2. Open Terminal and run:
   ```bash
   xattr -cr /Applications/Dev_Setup.app
   ```
3. Launch from Applications folder or Spotlight

### Step 4: Launch Dev_Setup

Choose any method:
- **Spotlight**: Press `⌘+Space`, type "Dev_Setup", press Enter
- **Finder**: Go to Applications → Dev_Setup
- **Terminal**: `open /Applications/Dev_Setup.app`

---

## Troubleshooting

### Issue: "Dev_Setup Not Opened" Warning
**Error Message**: *"Apple could not verify Dev_Setup is free of malware..."*

**Solution**:
```bash
xattr -cr /Applications/Dev_Setup.app
```

Then launch the app again.

### Issue: Installer Script Permission Denied
**Error**: `permission denied: ./install_app.sh`

**Solution**:
```bash
chmod +x /Volumes/Dev_Setup/install_app.sh
./install_app.sh
```

### Issue: App Not Found in Applications
**Solution**: Re-run the installer or manually copy:
```bash
cp -R /Volumes/Dev_Setup/Dev_Setup.app /Applications/
xattr -cr /Applications/Dev_Setup.app
```

---

## System Requirements

### Prerequisite Checks
The app will automatically verify:
- ✓ macOS version (10.15 Catalina or later)
- ✓ Xcode Command Line Tools
- ✓ Homebrew package manager
- ✓ Git, curl, bash
- ✓ OpenVPN/Tunnelblick (for VPN access)
- ✓ VPN connectivity to corporate network

### Missing Prerequisites
If checks fail, the app provides **Install** buttons to set up missing components automatically.

---

## Architecture Support

### Intel Macs (x86_64)
✓ Fully supported (MacBook Pro 2019 and earlier)

### Apple Silicon (M1/M2/M3)
✓ Fully supported (native ARM64)

### Universal Binary
The `.dmg` includes both architectures for maximum compatibility.

---

## Uninstallation

To remove Dev_Setup:
```bash
rm -rf /Applications/Dev_Setup.app
```

---

## Security Notes

### Why the Installer Removes Quarantine
macOS adds a "quarantine" flag to downloaded apps for security. Since Dev_Setup is an internal corporate tool (not signed with an Apple Developer certificate), the installer removes this flag to enable launching without warnings.

**This is safe for internal tools where:**
- You trust the source (your company's internal distribution)
- The app is unsigned but verified by your IT team
- You're on a corporate network with security controls

### Alternative: Code Signing (Future)
For broader distribution, the app can be code-signed with an Apple Developer certificate to eliminate warnings entirely.

---

## Support

**For installation issues:**
- Check the Troubleshooting section above
- Contact your IT team or DevOps
- Review logs: `~/Library/Logs/Dev_Setup/`

**For setup errors during environment configuration:**
- The app provides detailed error messages
- Check the built-in logs viewer (Settings → Logs)
- Revert specific steps using the Revert screen

---

## What's Next?

After installation:
1. **Prerequisites Screen**: Review and install missing components
2. **Setup Screen**: Configure development environment
3. **Progress Dashboard**: Monitor installation progress
4. **Complete Screen**: Verify setup and launch your workspace

Dev_Setup will install:
- Python (via pyenv)
- Node.js (via nvm)
- PostgreSQL 16
- Redis
- VS Code extensions
- Git/SSH configuration
- VPN setup (Tunnelblick)
- Corporate GitLab access
- Workspace repositories

Total setup time: ~30-60 minutes (depending on internet speed)

---

*Dev_Setup v2.6.3*
*Internal Corporate Tool*
