# Dev Environment Setup App

A cross-platform developer environment installer built with **Tauri v2** (Rust + React).  
Automates the complete setup of a macOS or Windows development environment through a guided wizard UI with live log streaming, step retries, and error recovery.

[![Build & Release](https://github.com/brandondsouza347-design/dev-setup-app/actions/workflows/build.yml/badge.svg)](https://github.com/brandondsouza347-design/dev-setup-app/actions/workflows/build.yml)

---

## Repository Layout

```
dev-setup-app/                  ← app source
├── src/                        ← React + TypeScript frontend
│   ├── components/             ← UI screens and widgets
│   ├── hooks/useSetup.ts       ← central state + Tauri bridge
│   └── types/index.ts          ← shared TypeScript types
├── src-tauri/                  ← Rust backend (Tauri v2)
│   ├── src/
│   │   ├── main.rs             ← app entry + plugin registration
│   │   ├── commands.rs         ← Tauri command handlers
│   │   ├── orchestrator.rs     ← step definitions + script executor
│   │   └── state.rs            ← app state + step tracking
│   ├── capabilities/           ← Tauri v2 permission grants
│   └── tauri.conf.json         ← Tauri app configuration
├── scripts/
│   ├── macos/                  ← setup shell scripts (bundled as resources)
│   └── windows/                ← setup PowerShell scripts
└── scripts/build/
    ├── build-windows.ps1       ← local Windows build script
    ├── install-build-deps-windows.ps1  ← one-time dependency installer
    └── build-mac.sh            ← local macOS build script
.github/workflows/build.yml     ← CI/CD: build + upload artifacts
```

---

## What the App Installs

### macOS
| Tool | Version | Notes |
|------|---------|-------|
| Xcode Command Line Tools | latest | Required for compiling |
| Homebrew | latest | macOS package manager |
| pyenv + Python | 3.9.21 | With virtualenv `erc` |
| NVM + Node.js | 16.20.2 | With Gulp 4 |
| PostgreSQL | 16 | Role + database created |
| Redis | latest | Started as a service |
| VS Code Extensions | — | ESLint, Pylint, Black, GitLens, etc. |

### Windows
| Step | Notes |
|------|-------|
| WSL2 Feature | Enabled + kernel update |
| Ubuntu 22.04 | Imported from TAR file |
| WSL Networking | DNS, resolv.conf, /etc/hosts |
| VS Code Remote-WSL | Extension + settings |
| Git + SSH Keys | Identity + ED25519 key for GitHub |

---

## Building Locally

### Windows

**Step 1 — Install build dependencies** *(once per machine, run as Administrator)*

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
cd dev-setup-app
.\scripts\build\install-build-deps-windows.ps1
```

Installs: Rust, Node.js, Tauri CLI v2, WebView2, WiX Toolset, NSIS, npm packages.  
Configures PowerShell profile to auto-refresh PATH in every new terminal.

**Step 2 — Build**

```powershell
.\scripts\build\build-windows.ps1
```

Output:
```
src-tauri\target\release\bundle\msi\Dev Setup_1.0.0_x64_en-US.msi   (~4 MB)
src-tauri\target\release\bundle\nsis\Dev Setup_1.0.0_x64-setup.exe  (~3 MB)
```

> **Note:** First build takes 5–15 minutes (Rust compiles from scratch). Subsequent builds ~2 minutes.

---

### macOS

**Step 1 — Install build dependencies** *(once per machine)*

```bash
./scripts/build/install-build-deps-mac.sh
```

**Step 2 — Build**

```bash
./scripts/build/build-mac.sh
```

Output:
```
src-tauri/target/release/bundle/dmg/Dev Setup_1.0.0_universal.dmg
```

---

## Development Mode

```bash
cd dev-setup-app
npm install
cargo tauri dev   # or: npm run tauri dev
```

The Vite dev server starts at `http://localhost:1420` and the Tauri app window opens automatically with hot-reload.

---

## CI/CD

Every push to `master` or `v*.*.*` tag triggers `.github/workflows/build.yml`:

| Job | Runner | Output |
|-----|--------|--------|
| 🍎 macOS (Universal DMG) | `macos-latest` | `macos-dmg.zip` artifact |
| 🪟 Windows (MSI + NSIS) | `windows-latest` | `windows-installers.zip` artifact |

Artifacts are downloadable from **Actions → the run → Artifacts** for 14 days.  
Tagged releases (`v1.0.0`) are published automatically to GitHub Releases.

You can also trigger a manual build from **Actions → Build & Release → Run workflow**.

---

## Configuration

Before running setup, open **Settings** in the app to configure:

| Setting | Default | Description |
|---------|---------|-------------|
| Python Version | `3.9.21` | Installed via pyenv |
| Virtualenv Name | `erc` | pyenv virtualenv name |
| Node Version | `16.20.2` | Installed via NVM |
| PostgreSQL DB | `dev_db` | Database to create |
| PostgreSQL Password | `postgres` | postgres role password |
| WSL TAR Path | *(empty)* | **Windows required**: path to `ubuntu_22.04_modified.tar` |
| WSL Install Dir | `~/WSL/Ubuntu-22.04` | Where to extract the distro |
| Skip Installed | `true` | Skip steps for already-installed tools |

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Frontend | React 18, TypeScript, Vite, Tailwind CSS |
| Backend | Rust, Tauri v2 |
| Plugins | tauri-plugin-shell, fs, os, dialog, notification |
| Bundler (Windows) | WiX 3 (MSI), NSIS (EXE) |
| Bundler (macOS) | Apple DMG |
| CI/CD | GitHub Actions |

---

## Troubleshooting

### Windows: PowerShell says "execution of scripts is disabled"
```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
```

### Windows: `node` / `cargo` not found after install
Open a new terminal — PATH is auto-refreshed at startup via the PowerShell profile installed by the setup script.

### macOS: `brew services` LaunchAgent error
```bash
brew services stop postgresql@16
pg_ctl -D /opt/homebrew/var/postgresql@16 start
```

### macOS: pyenv not found after install
```bash
source ~/.zshrc  # or restart your terminal
```

### Windows: WSL TAR import hangs
- Ensure TAR file is not corrupted
- Check available disk space (≥ 15 GB required)
- Manual import: `wsl --import Ubuntu-22.04 C:\WSL\Ubuntu-22.04 C:\path\to\ubuntu.tar`

---

## Adding New Setup Steps

1. Create a script in `scripts/macos/` or `scripts/windows/`
2. Add the step to `all_steps()` in `src-tauri/src/orchestrator.rs`
3. Add the command mapping in `build_script_command()` in the same file
4. Rebuild: `cargo tauri build`

---

## License

MIT
