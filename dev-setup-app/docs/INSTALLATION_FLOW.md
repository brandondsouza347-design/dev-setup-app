# Dev_Setup Installation Process Flow

## Visual Installation Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                   📥 DOWNLOAD DMG FILE                           │
│             Dev_Setup_2.6.3_universal.dmg                       │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                  💿 DOUBLE-CLICK TO MOUNT                        │
│                                                                  │
│   ┌─────────────────────────────────────────────────┐          │
│   │  /Volumes/Dev_Setup/                             │          │
│   │  ├── Dev_Setup.app          (application)       │          │
│   │  ├── install_app.sh         (installer)         │          │
│   │  └── INSTALLATION_GUIDE.md  (documentation)     │          │
│   └─────────────────────────────────────────────────┘          │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
               ┌─────────┴──────────┐
               │                    │
         AUTOMATED              MANUAL
               │                    │
               ▼                    ▼
   ┌────────────────────┐   ┌─────────────────────┐
   │  Open Terminal     │   │  Drag Dev_Setup.app │
   │  cd /Volumes/...   │   │  to Applications    │
   │  ./install_app.sh  │   │                     │
   └──────┬─────────────┘   └──────┬──────────────┘
          │                         │
          │                         ▼
          │                  ┌─────────────────────┐
          │                  │  Open Terminal      │
          │                  │  xattr -cr          │
          │                  │  /Applications/...  │
          │                  └──────┬──────────────┘
          │                         │
          └─────────┬───────────────┘
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│              ✅ APPLICATION INSTALLED                            │
│          /Applications/Dev_Setup.app                            │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                    🚀 LAUNCH DEV_SETUP                           │
│                                                                  │
│   Method 1: Spotlight (⌘+Space → "Dev_Setup")                  │
│   Method 2: Finder (Applications → Dev_Setup)                   │
│   Method 3: Terminal (open /Applications/Dev_Setup.app)        │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                 📋 PREREQUISITE CHECKS                           │
│                                                                  │
│   ✓  macOS Version (10.15+)                                    │
│   ✓  Xcode Command Line Tools                                  │
│   ✓  Homebrew                                                   │
│   ✓  Git, curl, bash                                           │
│   ✓  VPN Client (Tunnelblick)                                  │
│   ✓  Network Connectivity                                      │
│                                                                  │
│   ⚠️  Missing items? → Click "Install" button                  │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│               🔧 AUTOMATED ENVIRONMENT SETUP                     │
│                                                                  │
│   Step 1:  Install Homebrew                         [▓▓░░░] 40%│
│   Step 2:  Install Xcode Command Line Tools         [▓▓▓░░] 60%│
│   Step 3:  Install Python (pyenv)                   [▓▓▓▓░] 80%│
│   Step 4:  Install Node.js (nvm)                    [▓▓▓▓▓] 100%│
│   Step 5:  Install PostgreSQL                                   │
│   Step 6:  Install Redis                                        │
│   Step 7:  Configure VS Code                                    │
│   Step 8:  Install VS Code Extensions                           │
│   Step 9:  Setup Git/SSH                                        │
│   Step 10: Clone Workspace Repositories                         │
│                                                                  │
│   ⏱️  Progress: 30-60 minutes                                   │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                  ✨ SETUP COMPLETE                               │
│                                                                  │
│   ✅  All tools installed                                       │
│   ✅  Development environment configured                        │
│   ✅  Workspace ready to use                                    │
│   ✅  VS Code with extensions                                   │
│   ✅  Database initialized                                      │
│                                                                  │
│   🎉  READY TO START CODING!                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Troubleshooting Path

```
┌─────────────────────────────────────────┐
│   ⚠️  SECURITY WARNING APPEARS          │
│   "Apple could not verify Dev_Setup"    │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│   Open Terminal and run:                │
│   xattr -cr /Applications/Dev_Setup.app│
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│   ✅ Security warning bypassed          │
│   App now launches without warnings     │
└─────────────────────────────────────────┘
```

---

## Component Dependencies

```
                    Dev_Setup.app
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
        ▼                 ▼                 ▼
   ┌─────────┐      ┌─────────┐      ┌─────────┐
   │ Homebrew│      │  Xcode  │      │  macOS  │
   │ Package │      │   CLT   │      │ 10.15+  │
   │ Manager │      │         │      │         │
   └────┬────┘      └────┬────┘      └─────────┘
        │                │
        │                └──────────┐
        │                           │
        ▼                           ▼
   ┌─────────────────────────────────────┐
   │  Python (pyenv)                     │
   │  Node.js (nvm)                      │
   │  PostgreSQL                         │
   │  Redis                              │
   │  Git, SSH                           │
   │  VS Code Extensions                 │
   └─────────────────────────────────────┘
                    │
                    ▼
          ┌──────────────────┐
          │  Workspace Repos │
          │  (Your Projects) │
          └──────────────────┘
```

---

## Installation Decision Tree

```
START: Downloaded DMG?
        │
        ├─ NO → Download from internal server
        │
        └─ YES → Mount DMG (double-click)
                    │
                    ▼
        Terminal access available?
                    │
        ├─ YES → Run ./install_app.sh (RECOMMENDED)
        │           │
        │           └─ Done! ✅
        │
        └─ NO  → Manual installation
                    │
                    ├─ Drag to Applications
                    ├─ Run xattr command (may need help)
                    └─ Launch app
                        │
                        └─ Done! ✅
```

---

## Time Estimation

```
┌────────────────────────────────────────────────┐
│  Installation Phase         │  Time Required   │
├─────────────────────────────┼──────────────────┤
│  Download DMG               │  2-5 minutes     │
│  Mount & Run Installer      │  1 minute        │
│  App Installation           │  30 seconds      │
│  First Launch               │  10 seconds      │
│  Prerequisite Checks        │  30 seconds      │
│  Install Missing Tools      │  5-10 minutes    │
│  Python + Node.js Setup     │  10-15 minutes   │
│  Database Installation      │  5-8 minutes     │
│  VS Code + Extensions       │  8-12 minutes    │
│  Clone Repositories         │  3-8 minutes     │
├─────────────────────────────┼──────────────────┤
│  TOTAL (with fast internet) │  30-45 minutes   │
│  TOTAL (with slow internet) │  45-90 minutes   │
└────────────────────────────────────────────────┘
```

---

## Support Flow

```
        Having Issues?
              │
              ▼
        Check QUICK_REFERENCE.md
              │
              ├─ Found solution? → Done! ✅
              │
              └─ Still stuck?
                    ▼
            Check INSTALLATION_GUIDE.md
                    │
                    ├─ Found solution? → Done! ✅
                    │
                    └─ Still stuck?
                          ▼
                    Check app Logs (Settings → Logs)
                          │
                          ├─ Found error message? → Search wiki
                          │
                          └─ Still stuck?
                                ▼
                          Contact IT Support
                          - Email: helpdesk@company.com
                          - Slack: #dev-setup-help
                          - Include: screenshots, error logs
```

---

*Visual guide for Dev_Setup v2.6.3*
*Print or share this flowchart with new users*
