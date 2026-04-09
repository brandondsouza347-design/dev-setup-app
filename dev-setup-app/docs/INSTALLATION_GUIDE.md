# Dev_Setup Installation Guide (macOS)
## Quick 3-Step Installation

---

## 📦 Step 1: Download & Open DMG

1. **Download** the DMG file: `Dev_Setup_2.6.3_universal.dmg`
2. **Double-click** the DMG to mount it
3. A window opens showing the app and installer

---

## 🚀 Step 2: Run the Installer

### Option A: Automated (Easiest)

1. **Open Terminal** (Press `⌘+Space`, type "Terminal")

2. **Run these commands:**
   ```bash
   cd /Volumes/Dev_Setup
   ./install_app.sh
   ```

3. **Press Enter** when prompted

4. **Press `y`** to launch the app

✅ Done! The app installs automatically.

---

### Option B: Manual Installation

1. **Drag** `Dev_Setup.app` → `Applications` folder

2. **Open Terminal** and run:
   ```bash
   xattr -cr /Applications/Dev_Setup.app
   ```

3. **Launch** from Applications folder

---

## ✨ Step 3: Launch Dev_Setup

Choose your preferred method:

| Method | Action |
|--------|--------|
| **Spotlight** | `⌘+Space` → type "Dev_Setup" → Enter |
| **Finder** | Applications → Dev_Setup (double-click) |
| **Terminal** | `open /Applications/Dev_Setup.app` |

---

## ⚠️ Troubleshooting

### "Dev_Setup Not Opened" Warning?

**You see:** *"Apple could not verify Dev_Setup..."*

**Solution:**
```bash
xattr -cr /Applications/Dev_Setup.app
open /Applications/Dev_Setup.app
```

**Why?** The app is not signed with Apple's certificate (it's an internal tool). This command tells macOS to trust it.

---

### Script Permission Denied?

**You see:** `permission denied: ./install_app.sh`

**Solution:**
```bash
chmod +x /Volumes/Dev_Setup/install_app.sh
./install_app.sh
```

---

## 📋 What Dev_Setup Does

After installation, the app will:

### 1️⃣ Check Prerequisites
- macOS version (must be 10.15+)
- Xcode Command Line Tools
- Homebrew
- Git, curl, bash
- VPN client (Tunnelblick)
- Network connectivity

**Missing something?** Click the **Install** button next to any failed check.

---

### 2️⃣ Setup Your Environment
The app automatically installs:

| Component | What It Does |
|-----------|--------------|
| **pyenv** | Python version manager |
| **Python 3.11** | Programming language |
| **nvm** | Node.js version manager |
| **Node.js 20** | JavaScript runtime |
| **PostgreSQL 16** | Database server |
| **Redis** | Cache/message broker |
| **VS Code** | Code editor with extensions |
| **Git/SSH** | Repository access |
| **VPN** | Corporate network access |
| **Workspace** | Clone your project repos |

---

### 3️⃣ Monitor Progress
- Real-time installation logs
- Step-by-step progress tracking
- Error handling with retry options
- Estimated time remaining

---

### 4️⃣ Start Coding
Once complete:
- All tools configured
- Workspace ready to use
- VS Code extensions installed
- Database initialized
- Ready for development!

---

## 💻 System Requirements

### Compatible Macs
✅ **Intel Macs** (2019 MacBook Pro and earlier)
✅ **Apple Silicon** (M1, M2, M3 chips)

### Required macOS Version
✅ **macOS 10.15 Catalina** or later
✅ Works with macOS 11 Big Sur, 12 Monterey, 13 Ventura, 14 Sonoma, etc.

### Disk Space
- **Minimum:** 10 GB free
- **Recommended:** 20 GB free (for all tools + workspace)

### Network
- Internet connection required
- VPN access to corporate network (set up during installation)

---

## 🔒 Security & Trust

### Is This Safe?

**Yes!** Dev_Setup is an internal corporate tool built by your DevOps team.

**Why the security warning?**
- The app is **not signed** with an Apple Developer certificate ($99/year)
- For internal tools, this is normal and safe
- Your company verifies the app before distribution

**What the installer does:**
- Removes macOS quarantine flag (the `xattr -cr` command)
- Allows launching without repeated warnings
- Standard practice for internal enterprise apps

**Who should use this?**
- Employees on corporate network
- Developers setting up new machines
- Anyone authorized by IT to access corporate resources

---

## 📞 Need Help?

### Installation Problems
1. Check the **Troubleshooting** section above
2. Contact your **IT Support** team
3. Check logs: `~/Library/Logs/Dev_Setup/`

### Setup Errors
- The app shows detailed error messages
- Use the **Revert** screen to undo failed steps
- Check the built-in **Logs** viewer (Settings → Logs)

### Questions About Tools
- **Python/Node.js:** See internal wiki
- **Database:** Contact database team
- **VPN:** Check IT security docs
- **Git/SSH:** See GitLab setup guide

---

## 🎯 Quick Tips

### First-Time Users
1. ✅ Run prerequisite checks first
2. ✅ Install missing components before setup
3. ✅ Connect to VPN before cloning repos
4. ✅ Allow 30-60 minutes for full setup

### Updating Dev_Setup
1. Download new DMG
2. Run installer (it replaces old version)
3. Launch the updated app

### Uninstalling
```bash
rm -rf /Applications/Dev_Setup.app
```

To remove installed tools, see the **Revert** screen in the app.

---

## 📖 Additional Resources

- **Internal Wiki:** [Company Confluence/Wiki Link]
- **GitLab:** [Your GitLab URL]
- **IT Support:** [Support Portal Link]
- **Slack Channel:** #dev-setup-help

---

*Dev_Setup v2.6.3 • Universal Binary (Intel + Apple Silicon)*
*Internal Corporate Developer Environment Installer*
*Built with ❤️ by DevOps Team*
