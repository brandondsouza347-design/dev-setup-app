# Dev Environment Setup App

A cross-platform developer environment installer built with **Tauri** (Rust + React). Automates the complete setup of a macOS or Windows development environment with a guided wizard UI, live log streaming, and error-recovery tooling.

---

## What It Installs

### macOS
| Tool | Version | Notes |
|------|---------|-------|
| Xcode Command Line Tools | latest | Required for compiling |
| Homebrew | latest | macOS package manager |
| pyenv + Python | 3.9.21 | With virtualenv `erc` |
| NVM + Node.js | 16.20.2 | With Gulp 4 |
| PostgreSQL | 16 | Roles + databases created |
| Redis | latest | Started as a service |
| VS Code Extensions | — | ESLint, Pylint, Black, Git Graph, etc. |

### Windows
| Step | Notes |
|------|-------|
| WSL2 Feature | Enabled + kernel update |
| Ubuntu 22.04 | Imported from TAR file |
| WSL Networking | DNS, resolv.conf, /etc/hosts |
| VS Code Remote-WSL | Extension + settings |
| Git + SSH Keys | Identity + ED25519 key for GitHub |

---

## Architecture

```
dev-setup-app/
├── src/                     # React frontend
│   ├── components/          # UI components
│   │   ├── WelcomeScreen    # Landing page + OS detection
│   │   ├── PrereqScreen     # Pre-flight checks
│   │   ├── SettingsScreen   # Configuration form
│   │   ├── WizardStepList   # Step review + start
│   │   ├── ProgressDashboard# Live log view + retry UI
│   │   ├── CompleteScreen   # Summary + next steps
│   │   ├── Sidebar          # Navigation
│   │   └── StepBadge        # Status indicator
│   ├── hooks/
│   │   └── useSetup.ts      # Central state + Tauri bridge
│   └── types/index.ts       # Shared TypeScript types
│
├── src-tauri/               # Rust backend
│   └── src/
│       ├── main.rs          # App entry + Tauri builder
│       ├── commands.rs      # Tauri command handlers
│       ├── orchestrator.rs  # Step definitions + script executor
│       └── state.rs         # App state + step tracking
│
└── scripts/                 # Shell scripts (bundled as resources)
    ├── macos/
    │   ├── install_xcode_clt.sh
    │   ├── install_homebrew.sh
    │   ├── setup_pyenv.sh
    │   ├── setup_nvm.sh
    │   ├── setup_postgres.sh
    │   ├── setup_redis.sh
    │   └── setup_vscode.sh
    └── windows/
        ├── enable_wsl.ps1
        ├── import_wsl_tar.ps1
        ├── setup_wsl_network.ps1
        ├── setup_vscode_windows.ps1
        └── setup_git_ssh.ps1
```

### Data Flow
```
User clicks "Start Setup"
    ↓
React calls Tauri invoke('start_setup')
    ↓
Rust: detects OS → runs step scripts one-by-one
    ↓
Each script streams stdout → 'step_log' event → React UI
    ↓
Script exit code → 'step_status' event → React updates badge
    ↓
On failure: Retry / Skip buttons appear
    ↓
All steps done → 'setup_complete' event → Complete screen
```

---

## Prerequisites (for building)

| Tool | Version | Install |
|------|---------|---------|
| Rust + Cargo | ≥ 1.70 | https://rustup.rs |
| Node.js | ≥ 18 | https://nodejs.org |
| npm | ≥ 9 | Bundled with Node |
| Tauri CLI | 1.x | `cargo install tauri-cli` |
| **macOS only** | | Xcode CLT: `xcode-select --install` |
| **Windows only** | | WebView2 (pre-installed on Win11) |

---

## Getting Started

### 1. Install dependencies

```bash
cd dev-setup-app
npm install
```

### 2. Run in development mode

```bash
npm run tauri dev
```

The app window opens automatically. The Vite dev server runs at `http://localhost:1420` and Tauri provides the Rust backend.

### 3. Build for production

```bash
npm run tauri build
```

Produces:
- **macOS**: `src-tauri/target/release/bundle/dmg/*.dmg`
- **Windows**: `src-tauri/target/release/bundle/msi/*.msi`

---

## Configuration

Before running setup, go to **Settings** to configure:

| Setting | Default | Description |
|---------|---------|-------------|
| Python Version | `3.9.21` | Installed via pyenv |
| Virtualenv Name | `erc` | Name for pyenv virtualenv |
| Node Version | `16.20.2` | Installed via NVM |
| PostgreSQL DB | `dev_db` | Database to create |
| PostgreSQL Password | `postgres` | Password for postgres role |
| WSL TAR Path | *(empty)* | **Required on Windows**: path to `ubuntu_22.04_modified.tar` |
| WSL Install Dir | `~/WSL/Ubuntu-22.04` | Where to extract the distro |
| Skip Installed | `true` | Skip steps for already-installed tools |

---

## Script Environment Variables

Scripts receive configuration via environment variables:

| Variable | Description |
|----------|-------------|
| `SETUP_PYTHON_VERSION` | Python version to install |
| `SETUP_VENV_NAME` | Virtualenv name |
| `SETUP_NODE_VERSION` | Node.js version |
| `SETUP_POSTGRES_PASSWORD` | postgres role password |
| `SETUP_POSTGRES_DB` | Database name |
| `SETUP_WSL_TAR_PATH` | Windows: path to TAR file |
| `SETUP_WSL_INSTALL_DIR` | Windows: WSL install directory |
| `SETUP_SKIP_INSTALLED` | Skip installed components |

---

## Adding New Steps

1. **Create a script** in `scripts/macos/` or `scripts/windows/`
2. **Add the step** to `all_steps()` in `src-tauri/src/orchestrator.rs`
3. **Add the mapping** in `build_script_command()` in the same file
4. **Rebuild**: `npm run tauri build`

---

## Troubleshooting

### macOS: `brew services` LaunchAgent error
```bash
brew services stop postgresql@16
rm ~/Library/LaunchAgents/homebrew.mxcl.postgresql@16.plist
pg_ctl -D /opt/homebrew/var/postgresql@16 start
```

### macOS: pyenv not found after install
```bash
source ~/.zshrc
# or restart your terminal
```

### Windows: WSL TAR import hangs
- Ensure the TAR file is not corrupted
- Check available disk space (need ≥ 15 GB)
- Try importing manually: `wsl --import Ubuntu-22.04 C:\WSL\Ubuntu-22.04 C:\path\to\ubuntu.tar`

### Windows: WSL2 requires a restart
Enable WSL step will prompt for restart. After reboot, re-open the installer — it will resume from where it left off.

---

## VS Code Extensions Installed

| Extension | Purpose |
|-----------|---------|
| `atlassian.atlascode` | Jira & Bitbucket |
| `amazonwebservices.aws-toolkit-vscode` | AWS Toolkit |
| `ms-python.black-formatter` | Python formatter |
| `dbaeumer.vscode-eslint` | JavaScript linting |
| `mhutchie.git-graph` | Git visualisation |
| `ms-python.pylint` | Python linting |
| `ms-python.python` | Python language support |
| `ms-python.debugpy` | Python debugger |
| `humao.rest-client` | REST API testing |
| `codeium.codeium` | AI code completion |
| `redhat.vscode-yaml` | YAML support |
| `eamodio.gitlens` | Advanced Git features |
| `ms-vscode-remote.remote-wsl` | WSL development |

---

## License

MIT
