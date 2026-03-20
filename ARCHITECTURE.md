# Dev Setup App — Architecture & Documentation

> **Cross-platform developer environment installer built with Tauri (Rust + React)**
> Current phase: POC / Phase 1

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Application Structure](#application-structure)
4. [Execution Flow](#execution-flow)
5. [Scripts Layer](#scripts-layer)
6. [CI/CD Pipeline](#cicd-pipeline)
7. [Pros & Cons](#pros--cons)
8. [Phase 2 — ERC Framework Bridge Course](#phase-2--erc-framework-bridge-course)
9. [Phase 2 — Manager Onboarding Tracking Dashboard](#phase-2--manager-onboarding-tracking-dashboard)

---

## Overview

The **Dev Setup App** automates the entire developer environment setup process for new engineers joining the team. Instead of following a 20-page manual document, a new developer simply downloads and runs a single installer that provisions their machine end-to-end.

| | |
|---|---|
| **Platforms** | macOS (Universal DMG) · Windows (NSIS `.exe` + MSI) |
| **Stack** | Tauri v1 · Rust · React · TypeScript · Vite |
| **Installer size** | ~10–20 MB |
| **Build** | GitHub Actions (free tier, personal account) |

---

## Architecture

```mermaid
graph TD
    subgraph Frontend["🖥️ Frontend — React + TypeScript"]
        A[Setup Wizard UI]
        B[Progress Dashboard]
        C[Log Streamer]
        D[Error & Retry UI]
        E[Settings Panel]
    end

    subgraph Rust["⚙️ Rust Core — Tauri Commands"]
        F[OS Detector]
        G[Step Orchestrator]
        H[Script Executor]
        I[State Manager]
        J[Permission Handler\nsudo / UAC]
        K[File & Config Writer]
    end

    subgraph Scripts["📜 Scripts Layer"]
        subgraph macOS["🍎 macOS — bash/zsh"]
            L[install_homebrew.sh]
            M[setup_pyenv.sh]
            N[setup_nvm.sh]
            O[setup_postgres.sh]
            P[setup_redis.sh]
            Q[setup_vscode.sh]
        end
        subgraph Windows["🪟 Windows — PowerShell"]
            R[enable_wsl.ps1]
            S[import_tar.ps1]
            T[setup_network.ps1]
            U[setup_vscode.ps1]
            V[setup_git_ssh.ps1]
        end
    end

    A -->|invoke command| G
    B -->|listen events| H
    C -->|stream stdout| H
    D -->|retry trigger| G
    E -->|config values| K

    G --> F
    F -->|macOS| macOS
    F -->|Windows| Windows
    G --> H
    H --> I
    H --> J
    H --> K
    H -->|stdout/stderr stream| C
```

---

## Application Structure

```mermaid
graph LR
    subgraph Repo["📁 Repository"]
        A[dev-setup-app/]
        A --> B[src/ — React frontend]
        A --> C[src-tauri/ — Rust backend]
        A --> D[scripts/]
        D --> E[macos/]
        D --> F[windows/]
        A --> G[.github/workflows/]
        G --> H[build.yml]
    end

    subgraph Frontend["src/"]
        B --> B1[components/]
        B --> B2[pages/]
        B --> B3[hooks/]
        B --> B4[store/]
    end

    subgraph Rust["src-tauri/"]
        C --> C1[src/main.rs]
        C --> C2[Cargo.toml]
        C --> C3[tauri.conf.json]
        C --> C4[icons/]
    end
```

---

## Execution Flow

```mermaid
sequenceDiagram
    actor Dev as 👨‍💻 New Developer
    participant UI as React UI
    participant Rust as Rust Core
    participant OS as OS Layer
    participant Script as Shell Scripts

    Dev->>UI: Opens app, clicks "Start Setup"
    UI->>Rust: invoke("start_setup")
    Rust->>OS: Detect operating system
    OS-->>Rust: macOS / Windows

    loop For each setup step
        Rust->>Script: Execute script (e.g. install_homebrew.sh)
        Script-->>Rust: stdout/stderr stream
        Rust-->>UI: emit("log", { message, step })
        UI-->>Dev: Live log output + progress bar

        alt Script succeeds
            Rust->>Rust: Mark step ✅ complete
            Rust-->>UI: emit("step_complete", { step })
        else Script fails
            Rust-->>UI: emit("step_error", { step, error })
            UI-->>Dev: Show error + Retry button
            Dev->>UI: Click Retry
            UI->>Rust: invoke("retry_step", { step })
        end
    end

    Rust-->>UI: emit("setup_complete")
    UI-->>Dev: 🎉 Setup complete!
```

---

## Scripts Layer

### macOS Scripts

| Script | Purpose |
|---|---|
| `install_homebrew.sh` | Install Homebrew package manager |
| `setup_pyenv.sh` | Install pyenv + Python version management |
| `setup_nvm.sh` | Install nvm + Node.js LTS |
| `setup_postgres.sh` | Install & initialise PostgreSQL via Homebrew |
| `setup_redis.sh` | Install & start Redis via Homebrew |
| `setup_vscode.sh` | Install VS Code + recommended extensions |

### Windows Scripts

| Script | Purpose |
|---|---|
| `enable_wsl.ps1` | Enable WSL2 feature + set default version |
| `import_tar.ps1` | Import pre-configured Ubuntu `.tar` into WSL |
| `setup_network.ps1` | Configure proxy, DNS, and network settings |
| `setup_vscode.ps1` | Install VS Code + WSL extension + dev extensions |
| `setup_git_ssh.ps1` | Generate SSH key pair + configure git globals |

---

## CI/CD Pipeline

```mermaid
flowchart TD
    A([git push to master\nor git tag v*.*.*]) --> B{GitHub Actions\nTriggered}

    B --> C[🍎 macOS Job\nmacos-latest runner]
    B --> D[🪟 Windows Job\nwindows-latest runner]

    subgraph macOS Job
        C --> C1[Checkout code]
        C1 --> C2[Setup Node 20 + Rust stable]
        C2 --> C3[Rust cache restore]
        C3 --> C4[Generate PNG + ICO icons\nvia Pillow]
        C4 --> C5[Create .icns\nvia iconutil]
        C5 --> C6[npm install]
        C6 --> C7[tauri build\n--target universal-apple-darwin]
        C7 --> C8[Upload artifact\nDev Setup_1.0.0_universal.dmg]
    end

    subgraph Windows Job
        D --> D1[Checkout code]
        D1 --> D2[Setup Node 20 + Rust stable]
        D2 --> D3[Rust cache restore]
        D3 --> D4[pip install Pillow]
        D4 --> D5[Generate PNG + ICO + ICNS icons]
        D5 --> D6[npm install]
        D6 --> D7[tauri build\nWindows x64]
        D7 --> D8[Upload artifact\n.msi + .exe installers]
    end

    C8 --> E[📋 Summary Job]
    D8 --> E
    E --> F{Was this a\ngit tag push?}
    F -->|Yes v*.*.* tag| G[🚀 Create GitHub Release\nAttach all artifacts]
    F -->|No — branch push| H[✅ Artifacts available\nin Actions tab only]
```

### Triggering a Public Release

```bash
# Tag and push to create a GitHub Release with download links
git tag v1.0.0
git push personal v1.0.0
```

This creates a public release at:
`https://github.com/brandondsouza347-design/dev-setup-app/releases`

### Workflow Inputs (Manual Trigger)

The workflow supports `workflow_dispatch` for manual runs with these options:

| Input | Options | Default |
|---|---|---|
| `platforms` | `all`, `macos-only`, `windows-only` | `all` |
| `publish` | `true`, `false` | `false` |

---

## Pros & Cons

### ✅ Pros

| Benefit | Detail |
|---|---|
| **Tiny installer** | ~10–20 MB — no bundled browser engine (unlike Electron ~150 MB) |
| **Fast startup** | Rust binary starts instantly, no V8 warm-up |
| **Secure** | Tauri's allowlist model — frontend can only call explicitly permitted Rust commands |
| **Native OS integration** | Rust has direct access to filesystem, processes, permissions (sudo/UAC) |
| **Real log streaming** | Rust streams stdout/stderr from scripts in real-time to the UI |
| **Cross-platform single codebase** | One React UI, one Rust core — OS differences handled in scripts layer only |
| **Maintainable scripts** | Shell/PowerShell scripts are easy to update without recompiling the app |
| **Free CI/CD** | GitHub Actions free tier builds both platforms automatically on every push |
| **Retry logic** | Failed steps can be retried without restarting the entire setup |

### ❌ Cons

| Limitation | Detail |
|---|---|
| **Rust learning curve** | Tauri commands and async Rust require Rust knowledge to extend |
| **No Linux support** | Dropped intentionally — team uses macOS and Windows only |
| **Longer initial build** | First Rust compile takes ~2–3 min (subsequent builds use cache) |
| **Script maintenance** | macOS/Windows scripts must be kept in sync as tooling versions evolve |
| **No code signing** | Currently unsigned — macOS Gatekeeper and Windows SmartScreen will warn users |
| **No auto-update** | Tauri updater is disabled — new versions require re-download |
| **Registry files read-only** | Cargo registry crates are read-only; patching wry for webkit2gtk compat requires chmod workaround |

---

## Phase 2 — ERC Framework Bridge Course

> **Goal:** After a developer's machine is set up, guide them through the ERC (Epicor Reference Client) codebase — both frontend and backend — so they can contribute confidently within their first week.

```mermaid
flowchart LR
    subgraph Phase1["✅ Phase 1 — Current"]
        A[Machine Setup\nHomebrew · Node · Python\nPostgres · Redis · VS Code\nWSL · SSH · Git]
    end

    subgraph Phase2["🔜 Phase 2 — Bridge Course"]
        B[ERC Frontend Track\nReact · TypeScript\nComponent Patterns\nState Management]
        C[ERC Backend Track\nAPI Structure · REST\nDatabase Models\nAuth Patterns]
        D[Interactive Exercises\nReal codebase walkthroughs\nGuided code tasks\nQuiz checkpoints]
        E[VS Code Integration\nAuto-open relevant files\nHighlight patterns in-editor]
    end

    A -->|Setup complete| B
    A -->|Setup complete| C
    B --> D
    C --> D
    D --> E
```

### What Phase 2 Covers

#### Frontend Track
- ERC component library — how components are structured and named
- State management patterns used in the codebase
- How to find and read existing components before building new ones
- TypeScript conventions specific to the ERC frontend
- How to run the frontend locally and connect to a dev API

#### Backend Track
- ERC API architecture — routing, middleware, controllers
- Database models and migration patterns
- Authentication and authorisation flow
- How to run the backend locally with a seeded database
- How to write and run backend tests

#### Delivery Format (Planned)
- Embedded in the same Tauri app — new tab after Phase 1 completes
- Step-by-step guided lessons with real code snippets from the ERC repo
- Each lesson has a completion checkpoint (quiz, code task, or acknowledgement)
- Progress saved locally and synced to a central tracking backend (see Phase 2 Tracking below)

---

## Phase 2 — Manager Onboarding Tracking Dashboard

> **Goal:** Give team leads and managers full visibility into each developer's onboarding progress — what's been completed, what's been skipped, and where someone is stuck.

```mermaid
flowchart TD
    subgraph Dev["👨‍💻 Developer's Machine"]
        A[Dev Setup App\nPhase 1 + Phase 2]
        A -->|On each step completion| B[Local State Store\nJSON / SQLite]
        B -->|Sync on network available| C[Progress API\nREST / WebSocket]
    end

    subgraph Backend["☁️ Tracking Backend"]
        C --> D[Progress Service]
        D --> E[Database\nDeveloper · Step · Timestamp · Status]
    end

    subgraph Dashboard["📊 Manager Dashboard\nWeb App"]
        E --> F[Team Overview\nAll developers at a glance]
        E --> G[Individual Timeline\nStep-by-step history]
        E --> H[Skipped Steps Report\nHighlights gaps]
        E --> I[Alerts\nStuck on a step > N hours]
    end
```

### Tracking Data Model (Planned)

```mermaid
erDiagram
    DEVELOPER {
        string id PK
        string name
        string email
        string team
        datetime enrolled_at
    }

    STEP {
        string id PK
        string name
        string phase
        string platform
        int order
        bool required
    }

    PROGRESS {
        string id PK
        string developer_id FK
        string step_id FK
        enum status "pending | in_progress | complete | skipped | failed"
        datetime started_at
        datetime completed_at
        int retry_count
        string error_message
    }

    DEVELOPER ||--o{ PROGRESS : has
    STEP ||--o{ PROGRESS : tracked_in
```

### Manager Dashboard Features (Planned)

| Feature | Description |
|---|---|
| **Team Overview** | Grid of all developers with overall % complete, colour-coded by status |
| **Individual Timeline** | Full step-by-step history for one developer with timestamps |
| **Skipped Steps** | Highlight which required steps were skipped and why |
| **Stuck Alert** | Notify manager when a developer has been on the same step for > 2 hours |
| **Completion Report** | Export CSV/PDF of team onboarding status for a sprint or cohort |
| **Retry Heatmap** | Show which setup steps fail most often across the team — feeds back into script improvements |

### End-to-End Tracking Flow

```mermaid
sequenceDiagram
    actor Dev as 👨‍💻 Developer
    participant App as Tauri App
    participant API as Progress API
    actor Mgr as 👔 Manager

    Dev->>App: Starts onboarding
    App->>API: POST /progress { developer, step: "homebrew", status: "started" }

    App->>App: Runs install_homebrew.sh
    App->>API: POST /progress { step: "homebrew", status: "complete", duration: 45s }

    Dev->>App: Skips "setup_redis" step
    App->>API: POST /progress { step: "redis", status: "skipped", reason: "user_skipped" }

    App->>API: POST /progress { step: "setup_vscode", status: "failed", error: "..." }
    App->>API: POST /progress { step: "setup_vscode", status: "complete", retries: 2 }

    API-->>Mgr: 🔔 Alert: Alex skipped Redis setup
    Mgr->>API: GET /team/overview
    API-->>Mgr: Dashboard: Alex — 8/10 steps complete, 1 skipped, 1 retried
```

---

## Summary

```mermaid
timeline
    title Dev Setup App — Roadmap
    section Phase 1 ✅
        Machine Setup : macOS DMG installer
                      : Windows NSIS + MSI installer
                      : Automated GitHub Actions CI/CD
                      : Script-based tool installation
    section Phase 2 🔜
        Bridge Course  : ERC Frontend walkthrough
                      : ERC Backend walkthrough
                      : Interactive code exercises
                      : VS Code integration
        Manager Tracking : Per-developer progress API
                         : Skipped step detection
                         : Manager dashboard web app
                         : Stuck-developer alerts
```

---

*Built with [Tauri](https://tauri.app) · [React](https://react.dev) · [Rust](https://www.rust-lang.org)*
*CI/CD via [GitHub Actions](https://github.com/features/actions)*
