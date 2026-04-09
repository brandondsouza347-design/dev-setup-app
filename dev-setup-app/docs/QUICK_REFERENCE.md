# Dev_Setup Quick Reference Card

**macOS Installation | v2.6.3**

---

## 🚀 Install in 3 Commands

```bash
cd /Volumes/Dev_Setup
./install_app.sh
# Press Enter, then 'y' to launch
```

---

## ⚠️ Security Warning Fix

If you see *"Apple could not verify..."*:

```bash
xattr -cr /Applications/Dev_Setup.app
open /Applications/Dev_Setup.app
```

---

## 🎯 Launch Options

| Method | Command |
|--------|---------|
| **Spotlight** | `⌘+Space` → "Dev_Setup" |
| **Terminal** | `open /Applications/Dev_Setup.app` |
| **Finder** | Applications → Dev_Setup |

---

## ✅ Prerequisites

The app checks for:
- macOS 10.15+
- Xcode Command Line Tools
- Homebrew
- Git, curl, bash
- VPN (Tunnelblick)

**Missing something?** → Click the Install button in the app

---

## 📦 What Gets Installed

- Python 3.11 (via pyenv)
- Node.js 20 (via nvm)
- PostgreSQL 16
- Redis
- VS Code + extensions
- Git/SSH keys
- VPN client
- Workspace repos

**Time:** 30-60 minutes

---

## 🔧 Troubleshooting

| Problem | Solution |
|---------|----------|
| Permission denied | `chmod +x ./install_app.sh` |
| App won't open | `xattr -cr /Applications/Dev_Setup.app` |
| VPN not working | Check Tunnelblick in menu bar |
| Database errors | Use Revert screen in app |

---

## 📞 Support

- **IT Helpdesk:** [Your helpdesk link]
- **Slack:** #dev-setup-help
- **Logs:** `~/Library/Logs/Dev_Setup/`

---

## 💾 System Requirements

- **macOS:** 10.15 Catalina or later
- **Disk:** 10 GB free (20 GB recommended)
- **Macs:** Intel ✓ | Apple Silicon ✓
- **Network:** Internet + VPN access

---

## 🔄 Update or Uninstall

**Update:**
```bash
# Download new DMG, then:
./install_app.sh  # Replaces old version
```

**Uninstall:**
```bash
rm -rf /Applications/Dev_Setup.app
# Use Revert screen in app to remove installed tools
```

---

*Universal Binary • Works on all Mac architectures*
*Questions? Check INSTALLATION_GUIDE.md*
