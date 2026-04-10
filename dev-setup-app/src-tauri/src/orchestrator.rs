// orchestrator.rs — Step definitions and script execution engine
use crate::admin_agent::{execute_via_agent, AdminAgentState, ADMIN_STEP_IDS};
use crate::state::{CancelState, UserConfig};
use serde::{Deserialize, Serialize};
use std::process::Stdio;
use std::time::Instant;
use tauri::{Emitter, Manager, WebviewWindow};
use tokio::sync::mpsc;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SetupStep {
    pub id: String,
    pub title: String,
    pub description: String,
    pub platform: Platform,
    pub category: StepCategory,
    pub required: bool,
    pub estimated_minutes: u8,
    #[serde(default)]
    pub rollback_steps: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum Platform {
    MacOs,
    Windows,
    Both,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum StepCategory {
    Prerequisites,
    PackageManager,
    Python,
    Node,
    Database,
    Cache,
    Vcs,
    Editor,
    Wsl,
    Network,
    Revert,
}

#[derive(Clone, Serialize)]
pub struct LogEvent {
    pub step_id: String,
    pub line: String,
    pub level: LogLevel,
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum LogLevel {
    Info,
    Warn,
    Error,
    Success,
}

/// Returns revert steps (Windows only — undoes WSL setup).
pub fn get_revert_steps_for_os(os: &str) -> Vec<SetupStep> {
    if os != "windows" {
        return vec![];
    }
    vec![
        SetupStep {
            id: "revert_shutdown_wsl".to_string(),
            title: "Shutdown WSL".to_string(),
            description: "Gracefully stop all running WSL instances to prevent data corruption and memory leaks before reverting.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Revert,
            required: true,
            estimated_minutes: 1,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "revert_git_ssh".to_string(),
            title: "Revert Git & SSH Config".to_string(),
            description: "Remove git global identity and SSH agent auto-start from the ERC WSL distro. SSH keys are preserved. Skipped automatically if the distro is not present.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Revert,
            required: true,
            estimated_minutes: 1,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "revert_vscode_windows".to_string(),
            title: "Revert VS Code Configuration".to_string(),
            description: "Uninstall all extensions installed by setup and remove the written settings.json and mcp.json files.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Revert,
            required: true,
            estimated_minutes: 3,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "revert_wsl_network".to_string(),
            title: "Revert WSL Network Config".to_string(),
            description: "Restore resolv.conf, remove dev entries from WSL /etc/hosts and Windows hosts file, and remove memory/swap settings from .wslconfig.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Revert,
            required: true,
            estimated_minutes: 2,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "revert_wsl_distro".to_string(),
            title: "Remove ERC Distro".to_string(),
            description: "Export a backup of the ERC distro to ~/WSL_Backup/, then unregister and delete it from WSL. All data inside will be permanently deleted.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Revert,
            required: true,
            estimated_minutes: 15,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "revert_wslconfig".to_string(),
            title: "Reset .wslconfig".to_string(),
            description: "Remove networkingMode=mirrored from ~/.wslconfig. The file is deleted if no other settings remain.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Revert,
            required: true,
            estimated_minutes: 1,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "revert_windows_hosts".to_string(),
            title: "Clean Windows Hosts File".to_string(),
            description: "Remove localhost entries with tenant name added by the setup tool. All other entries are preserved.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Revert,
            required: true,
            estimated_minutes: 1,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "revert_wsl_features".to_string(),
            title: "Disable WSL Windows Features".to_string(),
            description: "Disable WSL and Virtual Machine Platform Windows features. A system restart is required after this step to complete removal.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Revert,
            required: false,
            estimated_minutes: 2,
            rollback_steps: vec![],
        },
    ]
}

/// Look up a step by ID across both setup and revert lists.
pub fn find_step_by_id(os: &str, id: &str) -> Option<SetupStep> {
    get_steps_for_os(os)
        .into_iter()
        .find(|s| s.id == id)
        .or_else(|| get_revert_steps_for_os(os).into_iter().find(|s| s.id == id))
}

/// Returns the full ordered list of setup steps for the given OS.
pub fn get_steps_for_os(os: &str) -> Vec<SetupStep> {
    let all_steps = all_steps();
    all_steps
        .into_iter()
        .filter(|s| match os {
            "macos" => s.platform == Platform::MacOs || s.platform == Platform::Both,
            "windows" => s.platform == Platform::Windows || s.platform == Platform::Both,
            _ => false,
        })
        .collect()
}

fn all_steps() -> Vec<SetupStep> {
    vec![
        // ── macOS steps ──────────────────────────────────────────────────────
        SetupStep {
            id: "xcode_clt".to_string(),
            title: "Xcode Command Line Tools".to_string(),
            description: "Install Xcode CLT required for compiling software on macOS.".to_string(),
            platform: Platform::MacOs,
            category: StepCategory::Prerequisites,
            required: true,
            estimated_minutes: 5,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "homebrew".to_string(),
            title: "Install Homebrew".to_string(),
            description: "Install the macOS package manager used to install all other tools.".to_string(),
            platform: Platform::MacOs,
            category: StepCategory::PackageManager,
            required: true,
            estimated_minutes: 3,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "pyenv".to_string(),
            title: "Install pyenv + Python 3.9.21".to_string(),
            description: "Install pyenv for Python version management, then install Python 3.9.21 and create a virtualenv.".to_string(),
            platform: Platform::MacOs,
            category: StepCategory::Python,
            required: true,
            estimated_minutes: 10,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "nvm".to_string(),
            title: "Install NVM v0.40.1 + Node 22.10.0".to_string(),
            description: "Install NVM (Node Version Manager) v0.40.1 and Node.js 22.10.0 with Gulp for frontend development.".to_string(),
            platform: Platform::MacOs,
            category: StepCategory::Node,
            required: true,
            estimated_minutes: 5,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "postgres_mac".to_string(),
            title: "Install PostgreSQL 16".to_string(),
            description: "Install PostgreSQL 16 via Homebrew, initialise the database cluster and start the service.".to_string(),
            platform: Platform::MacOs,
            category: StepCategory::Database,
            required: true,
            estimated_minutes: 5,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "redis_mac".to_string(),
            title: "Install Redis".to_string(),
            description: "Install Redis in-memory store via Homebrew and start the service.".to_string(),
            platform: Platform::MacOs,
            category: StepCategory::Cache,
            required: false,
            estimated_minutes: 2,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "mac_hosts".to_string(),
            title: "Update macOS Hosts File".to_string(),
            description: "Add 127.0.0.1 tenant entries (t3582.local, tenant name, localhost) to /etc/hosts for local development.".to_string(),
            platform: Platform::MacOs,
            category: StepCategory::Network,
            required: true,
            estimated_minutes: 1,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "vscode_mac".to_string(),
            title: "Configure VS Code".to_string(),
            description: "Install VS Code extensions (ESLint, Pylint, Black, Python, Git Graph, etc.) and configure shell integration.".to_string(),
            platform: Platform::MacOs,
            category: StepCategory::Editor,
            required: true,
            estimated_minutes: 3,
            rollback_steps: vec![],
        },
        // ── Windows steps ────────────────────────────────────────────────────
        SetupStep {
            id: "enable_wsl".to_string(),
            title: "Enable WSL2".to_string(),
            description: "Enable the Windows Subsystem for Linux feature and set WSL2 as default.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Wsl,
            required: true,
            estimated_minutes: 5,
            rollback_steps: vec![
                "revert_shutdown_wsl".to_string(),
                "revert_wsl_features".to_string(),
            ],
        },
        SetupStep {
            id: "import_wsl_tar".to_string(),
            title: "Import Ubuntu 22.04 from TAR".to_string(),
            description: "Import the pre-configured ERC Ubuntu TAR image into WSL2.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Wsl,
            required: true,
            estimated_minutes: 10,
            rollback_steps: vec![
                "revert_shutdown_wsl".to_string(),
                "revert_wsl_distro".to_string(),
            ],
        },
        SetupStep {
            id: "wsl_network".to_string(),
            title: "Configure WSL Networking".to_string(),
            description: "Set up WSL network adapter, DNS resolv.conf, and host file entries.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Network,
            required: true,
            estimated_minutes: 3,
            rollback_steps: vec![
                "revert_wsl_network".to_string(),
            ],
        },
        SetupStep {
            id: "vscode_windows".to_string(),
            title: "Configure VS Code for Windows".to_string(),
            description: "Install VS Code Remote-WSL extension and configure VS Code settings for the WSL environment.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Editor,
            required: true,
            estimated_minutes: 5,
            rollback_steps: vec![
                "revert_vscode_windows".to_string(),
            ],
        },
        SetupStep {
            id: "git_ssh_windows".to_string(),
            title: "Git & SSH Setup".to_string(),
            description: "Configure Git identity, generate SSH keys, and set up GitHub access inside WSL.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Vcs,
            required: true,
            estimated_minutes: 5,
            rollback_steps: vec![
                "revert_git_ssh".to_string(),
            ],
        },
        SetupStep {
            id: "pyenv_wsl".to_string(),
            title: "Install pyenv + Python 3.9.21 (WSL)".to_string(),
            description: "Install pyenv via the official curl installer inside WSL Ubuntu, install Python 3.9.21, and create the 'erc' virtual environment. Skipped automatically if already set up.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Python,
            required: false,
            estimated_minutes: 10,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "nvm_wsl".to_string(),
            title: "Install NVM v0.40.1 + Node 22.10.0 (WSL)".to_string(),
            description: "Install NVM v0.40.1 and Node.js v22.10.0 inside WSL Ubuntu and set it as the default version. Skipped automatically if already set up.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Node,
            required: false,
            estimated_minutes: 5,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "ubuntu_user_wsl".to_string(),
            title: "Configure Ubuntu User (WSL)".to_string(),
            description: "Check if an 'ubuntu' user exists inside WSL Ubuntu. Creates and configures it if not present; skips automatically if already set up.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Wsl,
            required: false,
            estimated_minutes: 2,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "postgres_wsl".to_string(),
            title: "Install PostgreSQL (WSL)".to_string(),
            description: "Check if PostgreSQL is installed inside WSL Ubuntu. Installs and initialises it if missing; skips automatically if already present.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Database,
            required: false,
            estimated_minutes: 5,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "redis_wsl".to_string(),
            title: "Install Redis (WSL)".to_string(),
            description: "Check if Redis is installed inside WSL Ubuntu. Installs and starts it if missing; skips automatically if already present.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Cache,
            required: false,
            estimated_minutes: 3,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "wslconfig_networking".to_string(),
            title: "Configure .wslconfig (Mirrored Networking)".to_string(),
            description: "Create or update C:\\Users\\<you>\\.wslconfig with networkingMode=mirrored so WSL shares the Windows network interface. Skips if already configured.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Network,
            required: false,
            estimated_minutes: 1,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "wsl_cleanup".to_string(),
            title: "WSL Cleanup & Set Default Distro".to_string(),
            description: "List WSL distros, set the imported ERC distro as the default, and unregister any stale Ubuntu instances. Skips if already clean.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Wsl,
            required: false,
            estimated_minutes: 2,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "windows_hosts".to_string(),
            title: "Update Windows Hosts File".to_string(),
            description: "Add localhost entries with tenant name (127.0.0.1 and ::1 localhost <tenant_name>) to C:\\Windows\\System32\\drivers\\etc\\hosts for local dev access.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Network,
            required: false,
            estimated_minutes: 1,
            rollback_steps: vec![],
        },
        // ── GitLab onboarding track (Windows) ──────────────────────────────────────────────────
        SetupStep {
            id: "gitlab_ssh".to_string(),
            title: "Add SSH Key to GitLab".to_string(),
            description: "Generate an SSH key in WSL (if needed) and upload it to GitLab via API. Falls back to manual instructions if no PAT is set.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Vcs,
            required: true,
            estimated_minutes: 2,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "clone_repo".to_string(),
            title: "Clone Project Repository".to_string(),
            description: "Clone the ERC repository into the configured WSL clone directory. Runs git pull if the repo already exists.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Vcs,
            required: true,
            estimated_minutes: 3,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "pyenv_local".to_string(),
            title: "Set Python Version (pyenv local)".to_string(),
            description: "Run pyenv local erc inside the cloned repo to pin the virtualenv for the project directory.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Python,
            required: true,
            estimated_minutes: 1,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "setup_workspace".to_string(),
            title: "Open VS Code Workspace".to_string(),
            description: "Configure workspace trust and open the Propello workspace in VS Code (WSL remote mode).".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Editor,
            required: false,
            estimated_minutes: 1,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "install_workspace_extensions".to_string(),
            title: "Install Extensions + Configure MCP".to_string(),
            description: "Install workspace extensions to WSL remote (dev tools: Python, ESLint, Black) and Windows (UI: icon theme, Remote-WSL). Then configure MCP servers (Kibana, GitLab, Atlassian) for both environments.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Editor,
            required: false,
            estimated_minutes: 6,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "python_interpreter".to_string(),
            title: "Configure Python Interpreter".to_string(),
            description: "Display step-by-step instructions for selecting the pyenv virtualenv as VS Code's Python interpreter.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Editor,
            required: false,
            estimated_minutes: 1,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "install_pip_requirements".to_string(),
            title: "Install pip Requirements".to_string(),
            description: "Install all Python dependencies from requirements.txt in the project root using the activated virtual environment.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Python,
            required: false,
            estimated_minutes: 5,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "migrate_shared".to_string(),
            title: "Migrate Shared Schemas".to_string(),
            description: "Run Django migrate_schemas --shared to create the shared database schema structure.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Database,
            required: false,
            estimated_minutes: 2,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "copy_tenant".to_string(),
            title: "Copy Tenant Data".to_string(),
            description: "Run Django copy_tenant command to set up tenant data from the configured cluster and tenant.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Database,
            required: false,
            estimated_minutes: 10,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "update_tenant_name".to_string(),
            title: "Update Tenant Name in Database".to_string(),
            description: "Update domain_client and domain_domain tables with the configured tenant name from settings.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Database,
            required: false,
            estimated_minutes: 1,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "install_frontend_deps".to_string(),
            title: "Install Frontend Dependencies".to_string(),
            description: "Run npm install in the client directory to install all Node.js packages required for frontend development.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Node,
            required: false,
            estimated_minutes: 5,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "start_frontend_watch".to_string(),
            title: "Build Front-End Assets".to_string(),
            description: "Run npm build to compile front-end assets for production use.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Node,
            required: false,
            estimated_minutes: 5,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "start_gunicorn".to_string(),
            title: "Start Gunicorn Server".to_string(),
            description: "Start the Gunicorn ASGI server with uvicorn worker in the background for local development.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Python,
            required: false,
            estimated_minutes: 1,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "install_pgadmin_windows".to_string(),
            title: "Install pgAdmin 4 GUI".to_string(),
            description: "Install pgAdmin 4 database management GUI for PostgreSQL. Optional tool for visual database management and SQL queries.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Database,
            required: false,
            estimated_minutes: 3,
            rollback_steps: vec![],
        },
        // ── GitLab onboarding track (macOS) ─────────────────────────────────────────────────
        SetupStep {
            id: "gitlab_ssh_mac".to_string(),
            title: "Add SSH Key to GitLab".to_string(),
            description: "Generate an SSH key (if needed) and upload it to GitLab via API. Falls back to manual instructions if no PAT is set.".to_string(),
            platform: Platform::MacOs,
            category: StepCategory::Vcs,
            required: true,
            estimated_minutes: 2,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "clone_repo_mac".to_string(),
            title: "Clone Project Repository".to_string(),
            description: "Clone the ERC repository into the configured clone directory. Runs git pull if the repo already exists.".to_string(),
            platform: Platform::MacOs,
            category: StepCategory::Vcs,
            required: true,
            estimated_minutes: 3,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "pyenv_local_mac".to_string(),
            title: "Set Python Version (pyenv local)".to_string(),
            description: "Run pyenv local erc inside the cloned repo to pin the virtualenv for the project directory.".to_string(),
            platform: Platform::MacOs,
            category: StepCategory::Python,
            required: true,
            estimated_minutes: 1,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "setup_workspace_mac".to_string(),
            title: "Setup Workspace + MCP".to_string(),
            description: "Install all Propello.code-workspace extensions, configure MCP servers (Kibana, GitLab, Atlassian), enable MCP gallery, and open the workspace in VS Code.".to_string(),
            platform: Platform::MacOs,
            category: StepCategory::Editor,
            required: false,
            estimated_minutes: 4,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "python_interpreter_mac".to_string(),
            title: "Configure Python Interpreter".to_string(),
            description: "Display step-by-step instructions for selecting the pyenv virtualenv as VS Code's Python interpreter.".to_string(),
            platform: Platform::MacOs,
            category: StepCategory::Editor,
            required: false,
            estimated_minutes: 1,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "install_pip_requirements_mac".to_string(),
            title: "Install pip Requirements".to_string(),
            description: "Install all Python dependencies from requirements.txt in the project root using the activated virtual environment.".to_string(),
            platform: Platform::MacOs,
            category: StepCategory::Python,
            required: false,
            estimated_minutes: 5,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "migrate_shared_mac".to_string(),
            title: "Migrate Shared Schemas".to_string(),
            description: "Run Django migrate_schemas --shared to create the shared database schema structure.".to_string(),
            platform: Platform::MacOs,
            category: StepCategory::Database,
            required: false,
            estimated_minutes: 2,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "copy_tenant_mac".to_string(),
            title: "Copy Tenant Data".to_string(),
            description: "Run Django copy_tenant command to set up tenant data from the configured cluster and tenant.".to_string(),
            platform: Platform::MacOs,
            category: StepCategory::Database,
            required: false,
            estimated_minutes: 10,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "update_tenant_name_mac".to_string(),
            title: "Update Tenant Name in Database".to_string(),
            description: "Update domain_client and domain_domain tables with the configured tenant name from settings.".to_string(),
            platform: Platform::MacOs,
            category: StepCategory::Database,
            required: false,
            estimated_minutes: 1,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "install_frontend_deps_mac".to_string(),
            title: "Install Frontend Dependencies".to_string(),
            description: "Run npm install in the client directory to install all Node.js packages required for frontend development.".to_string(),
            platform: Platform::MacOs,
            category: StepCategory::Node,
            required: false,
            estimated_minutes: 5,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "start_frontend_watch_mac".to_string(),
            title: "Build Front-End Assets".to_string(),
            description: "Run npm build to compile front-end assets for production use.".to_string(),
            platform: Platform::MacOs,
            category: StepCategory::Node,
            required: false,
            estimated_minutes: 5,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "start_gunicorn_mac".to_string(),
            title: "Start Gunicorn Server".to_string(),
            description: "Start the Gunicorn ASGI server with uvicorn worker in the background for local development.".to_string(),
            platform: Platform::MacOs,
            category: StepCategory::Python,
            required: false,
            estimated_minutes: 1,
            rollback_steps: vec![],
        },
        SetupStep {
            id: "install_pgadmin_mac".to_string(),
            title: "Install pgAdmin 4 GUI".to_string(),
            description: "Install pgAdmin 4 database management GUI for PostgreSQL. Optional tool for visual database management and SQL queries.".to_string(),
            platform: Platform::MacOs,
            category: StepCategory::Database,
            required: false,
            estimated_minutes: 3,
            rollback_steps: vec![],
        },
    ]
}

/// Resolves the path to a bundled script relative to the app resources directory.
fn script_path(app_handle: &tauri::AppHandle, script_name: &str) -> Result<std::path::PathBuf, String> {
    use tauri::Manager;
    let resource_dir = app_handle
        .path()
        .resource_dir()
        .map_err(|e| e.to_string())?;
    let path = resource_dir.join("scripts").join(script_name);
    log::info!("script_path: resource_dir='{}' resolved='{}'", resource_dir.display(), path.display());
    if !path.exists() {
        let msg = format!(
            "Script not found: {}\n\nLooked in resource dir: {}\nExpected at: {}\n\nThis usually means the app was not rebuilt after the last change, or the installer did not bundle the scripts correctly. Please rebuild and reinstall.",
            script_name,
            resource_dir.display(),
            path.display()
        );
        log::error!("{}", msg);
        return Err(msg);
    }
    Ok(path)
}

/// Execute a shell script and stream output line-by-line to the frontend via events.
/// Admin-required steps are routed through the elevated admin agent when available.
pub async fn execute_script(
    window: WebviewWindow,
    app_handle: tauri::AppHandle,
    step: &SetupStep,
    config: &UserConfig,
) -> Result<Vec<String>, String> {
    let start = Instant::now();

    // Route admin-required steps through the elevated named-pipe agent
    if ADMIN_STEP_IDS.contains(&step.id.as_str()) {
        let agent_state = app_handle
            .try_state::<AdminAgentState>()
            .ok_or_else(|| "AdminAgentState not managed".to_string())?;
        return execute_via_agent(&window, &app_handle, step, config, &agent_state).await;
    }

    let (program, script_file, args) = build_script_command(step, config, &app_handle)?;

    log::info!(
        "execute_script: step='{}' program='{}' script='{}' args={:?}",
        step.id, program, script_file, args
    );

    emit_log(&window, &step.id, &format!("▶ Starting: {}", step.title), LogLevel::Info);

    let mut child = {
        let mut cmd = tokio::process::Command::new(&program);
        cmd.args(&args);
        // script_file is empty when the path is already embedded in args
        // (e.g. PowerShell -Command invocations) — skip to avoid a blank arg.
        if !script_file.is_empty() {
            cmd.arg(&script_file);
        }

        let env_vars = build_env(config);

        // For WSL commands, we need to set WSLENV to forward environment variables
        // from Windows into the WSL environment. Without this, the SETUP_* vars
        // are only visible in the Windows process, not inside WSL.
        if program == "wsl" {
            let wslenv_vars: Vec<String> = env_vars.iter()
                .map(|(key, _)| key.clone())
                .collect();
            let wslenv_value = wslenv_vars.join(":");
            cmd.env("WSLENV", wslenv_value);
        }

        cmd.envs(env_vars)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        // Prevent a visible console window from flashing when spawning
        // powershell.exe / wsl.exe from the GUI process on Windows.
        #[cfg(target_os = "windows")]
        cmd.creation_flags(0x08000000); // CREATE_NO_WINDOW
        cmd.spawn()
            .map_err(|e| {
                log::error!("execute_script: failed to spawn '{}' for step '{}' — {}", program, step.id, e);
                format!("Failed to spawn process: {}", e)
            })?
    };

    let stdout = child.stdout.take().unwrap();
    let stderr = child.stderr.take().unwrap();

    // Merge stdout and stderr into a single ordered channel.
    // Each sender is moved into its own spawned task; when both tasks finish
    // the channel closes naturally and rx.recv() returns None.
    let (tx, mut rx) = mpsc::unbounded_channel::<(String, bool)>(); // (line, is_stderr)
    let tx_stderr = tx.clone();

    tokio::spawn(async move {
        use tokio::io::AsyncBufReadExt;
        let mut lines = tokio::io::BufReader::new(stdout).lines();
        while let Ok(Some(line)) = lines.next_line().await {
            let _ = tx.send((line, false));
        }
    });

    tokio::spawn(async move {
        use tokio::io::AsyncBufReadExt;
        let mut lines = tokio::io::BufReader::new(stderr).lines();
        while let Ok(Some(line)) = lines.next_line().await {
            let _ = tx_stderr.send((line, true));
        }
    });

    let mut all_logs: Vec<String> = Vec::new();

    // Hard timeout to prevent indefinite hangs — 15 minutes for most steps,
    // 30 minutes for long-running steps like pyenv, import_wsl_tar
    let timeout_secs = match step.id.as_str() {
        "pyenv" | "pyenv_wsl" => 1800,      // 30 min
        "import_wsl_tar" => 1800,           // 30 min
        "revert_wsl_distro" => 1800,        // 30 min
        "clone_repo" | "clone_repo_mac" => 3600, // 60 min — large repo on first clone
        "install_pip_requirements" => 1800, // 30 min — many Python packages to install
        "install_pip_requirements_mac" => 1800, // 30 min — many Python packages to install
        "install_frontend_deps" => 1800,    // 30 min — many Node.js packages to install
        "install_frontend_deps_mac" => 1800, // 30 min — many Node.js packages to install
        "start_frontend_watch" => 1800,     // 30 min — npm build can take time
        "start_frontend_watch_mac" => 1800, // 30 min — npm build can take time
        "migrate_shared" => 1800,           // 30 min — database migrations can be slow
        "migrate_shared_mac" => 1800,       // 30 min — database migrations can be slow
        "copy_tenant" => 10800,             // 180 min — copying tenant data from remote can take 3+ hours
        "copy_tenant_mac" => 10800,         // 180 min — copying tenant data from remote can take 3+ hours
        "update_tenant_name" => 300,        // 5 min — update database tables
        "update_tenant_name_mac" => 300,    // 5 min — update database tables
        _ => 900,                           // 15 min default
    };
    let timeout = std::time::Duration::from_secs(timeout_secs);
    let timeout_handle = tokio::time::sleep(timeout);
    tokio::pin!(timeout_handle);

    // Poll the cancel flag every 500 ms so the user can stop the process.
    let mut cancel_ticker = tokio::time::interval(std::time::Duration::from_millis(500));
    cancel_ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    let cancel_state: Option<tauri::State<'_, CancelState>> = app_handle.try_state::<CancelState>();
    // Reset any stale cancellation from a previous stop before entering the loop.
    if let Some(ref cs) = cancel_state {
        cs.reset();
    }

    // Drain the merged channel until both tasks have finished and dropped their senders
    // or timeout / user cancellation is triggered.
    loop {
        tokio::select! {
            maybe_line = rx.recv() => {
                match maybe_line {
                    Some((line, is_stderr)) => {
                        if is_stderr {
                            if !line.trim().is_empty() {
                                log::warn!("[{}][stderr] {}", step.id, line);
                                all_logs.push(format!("[stderr] {}", line));
                                emit_log(&window, &step.id, &line, LogLevel::Warn);
                            }
                        } else {
                            log::info!("[{}] {}", step.id, line);
                            all_logs.push(line.clone());
                            emit_log(&window, &step.id, &line, classify_log_line(&line));
                        }
                    }
                    None => break, // Both stdout/stderr tasks finished
                }
            }
            _ = &mut timeout_handle => {
                log::error!("execute_script: step '{}' TIMEOUT after {}s — killing process", step.id, timeout_secs);
                let _ = child.kill().await;
                emit_log(
                    &window,
                    &step.id,
                    &format!("⚠ Script timeout after {}s — process killed", timeout_secs),
                    LogLevel::Error,
                );
                return Err(format!("Script timeout after {}s", timeout_secs));
            }
            _ = cancel_ticker.tick() => {
                if cancel_state.as_ref().map(|cs| cs.is_cancelled()).unwrap_or(false) {
                    log::warn!("execute_script: step '{}' cancelled by user — killing process", step.id);
                    let _ = child.kill().await;
                    if let Some(ref cs) = cancel_state {
                        cs.reset();
                    }
                    emit_log(&window, &step.id, "⚠ Setup stopped by user", LogLevel::Warn);
                    return Err("Stopped by user".to_string());
                }
            }
        }
    }

    let status = child.wait().await.map_err(|e| format!("Process wait error: {}", e))?;

    if status.success() {
        let duration = start.elapsed().as_secs();
        log::info!("execute_script: step '{}' exited successfully (exit=0) in {}s", step.id, duration);
        emit_log(
            &window,
            &step.id,
            &format!("✓ Completed in {}s", duration),
            LogLevel::Success,
        );
        Ok(all_logs)
    } else {
        let code = status.code().unwrap_or(-1);
        let duration = start.elapsed().as_secs();

        // Special handling for enable_wsl: exit code 1 means restart required (not failure)
        if step.id == "enable_wsl" && code == 1 {
            // Check if logs contain the restart message
            let has_restart_msg = all_logs.iter().any(|line|
                line.contains("RESTART WINDOWS REQUIRED") ||
                line.contains("RESTART REQUIRED")
            );

            if has_restart_msg {
                log::warn!("execute_script: step 'enable_wsl' requires system restart (exit=1)");
                emit_log(
                    &window,
                    &step.id,
                    "⚠ System restart required — WSL features enabled",
                    LogLevel::Warn,
                );
                // Mark logs with special restart marker for run_step to detect
                all_logs.push("__RESTART_REQUIRED__".to_string());
                return Ok(all_logs);
            }
        }

        let msg = format!("Script exited with code {}", code);
        log::error!("execute_script: step '{}' FAILED — exit code={} duration={}s", step.id, code, duration);
        emit_log(&window, &step.id, &msg, LogLevel::Error);
        Err(msg)
    }
}

/// Like execute_script but retries once after 2 seconds on failure.
/// Handles transient exit-1 failures caused by Windows Defender scanning newly
/// extracted scripts on first run from AppData — the retry always succeeds once
/// the scan cache is warm.
pub async fn execute_script_with_retry(
    window: WebviewWindow,
    app_handle: tauri::AppHandle,
    step: &SetupStep,
    config: &UserConfig,
) -> Result<Vec<String>, String> {
    match execute_script(window.clone(), app_handle.clone(), step, config).await {
        Ok(logs) => Ok(logs),
        Err(err) => {
            log::warn!(
                "execute_script_with_retry: step '{}' failed on attempt 1 ({}) — retrying in 2s",
                step.id, err
            );
            // Admin steps go through the elevated agent which stages scripts to disk.
            // Corporate AV scanners hold staged files open after writes, so we need
            // a longer buffer to let handles release before the retry.
            let retry_secs: u64 = if ADMIN_STEP_IDS.contains(&step.id.as_str()) { 20 } else { 8 };
            emit_log(
                &window,
                &step.id,
                &format!("⚠ Transient failure — retrying once after {}s (common on first run)...", retry_secs),
                LogLevel::Warn,
            );
            tokio::time::sleep(std::time::Duration::from_secs(retry_secs)).await;
            execute_script(window, app_handle, step, config).await
        }
    }
}

fn build_script_command(
    step: &SetupStep,
    _config: &UserConfig,
    app_handle: &tauri::AppHandle,
) -> Result<(String, String, Vec<String>), String> {
    let (script_subdir, script_name, program, extra_args) = match step.id.as_str() {
        // macOS
        "xcode_clt"     => ("macos", "install_xcode_clt.sh", "bash", vec![]),
        "homebrew"      => ("macos", "install_homebrew.sh",  "bash", vec![]),
        "install_git_mac" => ("macos", "install_git.sh",     "bash", vec![]),
        "pyenv"         => ("macos", "setup_pyenv.sh",        "bash", vec![]),
        "nvm"           => ("macos", "setup_nvm.sh",          "bash", vec![]),
        "postgres_mac"  => ("macos", "setup_postgres.sh",     "bash", vec![]),
        "redis_mac"     => ("macos", "setup_redis.sh",        "bash", vec![]),
        "mac_hosts"     => ("macos", "setup_mac_hosts.sh",    "bash", vec![]),
        "vscode_mac"    => ("macos", "setup_vscode.sh",       "bash", vec![]),
        // Windows
        "enable_wsl"    => ("windows", "enable_wsl.ps1",          "powershell", vec![]),
        "import_wsl_tar"=> ("windows", "import_wsl_tar.ps1",      "powershell", vec![]),
        "wsl_network"   => ("windows", "setup_wsl_network.ps1",   "powershell", vec![]),
        "vscode_windows"=> ("windows", "setup_vscode_windows.ps1","powershell", vec![]),
        "git_ssh_windows"=>("windows","setup_git_ssh.sh",         "wsl",        vec!["-d".to_string(), "ERC".to_string(), "bash".to_string()]),
        "pyenv_wsl"       => ("windows", "setup_pyenv_wsl.sh",         "wsl",        vec!["-d".to_string(), "ERC".to_string(), "bash".to_string()]),
        "nvm_wsl"          => ("windows", "setup_nvm_wsl.sh",           "wsl",        vec!["-d".to_string(), "ERC".to_string(), "bash".to_string()]),
        "ubuntu_user_wsl"  => ("windows", "setup_ubuntu_user_wsl.sh",   "wsl",        vec!["-d".to_string(), "ERC".to_string(), "-u".to_string(), "root".to_string(), "bash".to_string()]),
        "postgres_wsl"     => ("windows", "setup_postgres_wsl.sh",      "wsl",        vec!["-d".to_string(), "ERC".to_string(), "bash".to_string()]),
        "redis_wsl"        => ("windows", "setup_redis_wsl.sh",         "wsl",        vec!["-d".to_string(), "ERC".to_string(), "bash".to_string()]),
        // Windows-side PowerShell scripts
        "wslconfig_networking" => ("windows", "setup_wslconfig_networking.ps1", "powershell", vec![]),
        "wsl_cleanup"          => ("windows", "setup_wsl_cleanup.ps1",          "powershell", vec![]),
        "windows_hosts"        => ("windows", "setup_windows_hosts.ps1",        "powershell", vec![]),
        // Windows GitLab onboarding track
        "install_openvpn"      => ("windows", "install_openvpn.ps1",           "powershell", vec![]),
        "connect_vpn"          => ("windows", "connect_vpn.ps1",               "powershell", vec![]),
        "gitlab_ssh"           => ("windows", "setup_gitlab_ssh.sh",           "wsl",        vec!["-d".to_string(), "ERC".to_string(), "bash".to_string()]),
        "clone_repo"           => ("windows", "clone_repo.sh",                 "wsl",        vec!["-d".to_string(), "ERC".to_string(), "bash".to_string()]),
        "pyenv_local"          => ("windows", "pyenv_local.sh",                "wsl",        vec!["-d".to_string(), "ERC".to_string(), "bash".to_string()]),
        "setup_workspace"      => ("windows", "setup_workspace.ps1",          "powershell", vec![]),
        "install_workspace_extensions" => ("windows", "install_workspace_extensions.ps1", "powershell", vec![]),
        "python_interpreter"   => ("windows", "python_interpreter.sh",        "wsl",        vec!["-d".to_string(), "ERC".to_string(), "bash".to_string()]),
        "install_pip_requirements" => ("windows", "install_pip_requirements.sh", "wsl",     vec!["-d".to_string(), "ERC".to_string(), "bash".to_string()]),
        "migrate_shared"       => ("windows", "migrate_shared.sh",            "wsl",        vec!["-d".to_string(), "ERC".to_string(), "bash".to_string()]),
        "copy_tenant"          => ("windows", "copy_tenant.sh",               "wsl",        vec!["-d".to_string(), "ERC".to_string(), "bash".to_string()]),
        "update_tenant_name"   => ("windows", "update_tenant_name.sh",       "wsl",        vec!["-d".to_string(), "ERC".to_string(), "bash".to_string()]),
        "install_frontend_deps" => ("windows", "install_frontend_deps.sh",    "wsl",        vec!["-d".to_string(), "ERC".to_string(), "bash".to_string()]),
        "start_frontend_watch" => ("windows", "start_frontend_watch.sh",      "wsl",        vec!["-d".to_string(), "ERC".to_string(), "bash".to_string()]),
        "start_gunicorn"       => ("windows", "start_gunicorn.sh",            "wsl",        vec!["-d".to_string(), "ERC".to_string(), "bash".to_string()]),
        "install_pgadmin_windows" => ("windows", "install_pgadmin.ps1",       "powershell", vec!["admin".to_string()]),
        // macOS GitLab onboarding track
        "install_openvpn_mac"     => ("macos", "install_openvpn.sh",     "bash", vec![]),
        "install_tunnelblick_sources" => ("macos", "install_tunnelblick_sources.sh", "bash", vec![]),
        "install_tunnelblick_manual"  => ("macos", "install_tunnelblick_manual.sh",  "bash", vec![]),
        "install_openvpn_cli"         => ("macos", "install_openvpn_cli.sh",         "bash", vec![]),
        "connect_vpn_mac"         => ("macos", "connect_vpn.sh",         "bash", vec![]),
        "connect_vpn_cli"         => ("macos", "connect_vpn_cli.sh",     "bash", vec![]),
        "disconnect_vpn_cli"      => ("macos", "disconnect_vpn_cli.sh",  "bash", vec![]),
        "gitlab_ssh_mac"          => ("macos", "setup_gitlab_ssh.sh",    "bash", vec![]),
        "clone_repo_mac"          => ("macos", "clone_repo.sh",          "bash", vec![]),
        "pyenv_local_mac"         => ("macos", "pyenv_local.sh",         "bash", vec![]),
        "setup_workspace_mac"     => ("macos", "setup_workspace.sh",     "bash", vec![]),
        "python_interpreter_mac"  => ("macos", "python_interpreter.sh",  "bash", vec![]),
        "install_pip_requirements_mac" => ("macos", "install_pip_requirements.sh", "bash", vec![]),
        "migrate_shared_mac"       => ("macos", "migrate_shared.sh",            "bash", vec![]),
        "copy_tenant_mac"          => ("macos", "copy_tenant.sh",               "bash", vec![]),
        "update_tenant_name_mac"   => ("macos", "update_tenant_name.sh",       "bash", vec![]),
        "install_frontend_deps_mac" => ("macos", "install_frontend_deps.sh",    "bash", vec![]),
        "start_frontend_watch_mac" => ("macos", "start_frontend_watch.sh",      "bash", vec![]),
        "start_gunicorn_mac"       => ("macos", "start_gunicorn.sh",            "bash", vec![]),
        "install_pgadmin_mac"      => ("macos", "install_pgadmin_mac.sh",       "bash", vec![]),
        // Revert scripts
        "revert_shutdown_wsl"  => ("windows", "revert_wsl_shutdown.ps1",   "powershell", vec![]),
        "revert_wsl_distro"    => ("windows", "revert_wsl_distro.ps1",     "powershell", vec![]),
        "revert_wslconfig"     => ("windows", "revert_wslconfig.ps1",      "powershell", vec![]),
        "revert_windows_hosts" => ("windows", "revert_windows_hosts.ps1",  "powershell", vec![]),
        "revert_wsl_features"  => ("windows", "revert_wsl_features.ps1",   "powershell", vec![]),
        "revert_wsl_network"   => ("windows", "revert_wsl_network.ps1",    "powershell", vec![]),
        "revert_git_ssh"       => ("windows", "revert_git_ssh.ps1",        "powershell", vec![]),
        "revert_vscode_windows"=> ("windows", "revert_vscode_windows.ps1", "powershell", vec![]),
        _ => return Err(format!("Unknown step id: {}", step.id)),
    };

    let path = script_path(app_handle, &format!("{}/{}", script_subdir, script_name))
        .map_err(|e| e)?;

    // Strip the \\?\ extended-length prefix emitted by Rust's PathBuf on Windows.
    let path_str = {
        let s = path.to_string_lossy().to_string();
        if s.starts_with(r"\\?\") { s[4..].to_string() } else { s }
    };

    // For WSL bash scripts convert the Windows path to a WSL /mnt/ path so that
    // bash receives a valid Linux path even when the Windows path contains spaces
    // (e.g. a username with a space). C:\foo\bar → /mnt/c/foo/bar.
    if program == "wsl" {
        let wsl_path = {
            let s = path_str.replace('\\', "/");
            if s.len() >= 2 && s.as_bytes()[1] == b':' {
                let drive = (s.as_bytes()[0] as char).to_ascii_lowercase();
                format!("/mnt/{}{}", drive, &s[2..])
            } else {
                s
            }
        };
        return Ok((program.to_string(), wsl_path, extra_args));
    }

    // ENCODING FIX: Windows PowerShell 5.1 reads .ps1 files using the system
    // code page (CP1252) when no BOM is present. The scripts contain UTF-8
    // characters such as \u2713 (✓, bytes E2 9C 93) whose byte 0x93 maps to the
    // curly-quote \u201C in CP1252 — this terminates string literals mid-line
    // and cascades parse failures through the rest of the block.
    // Reading via Get-Content -Encoding UTF8 and executing as a scriptblock
    // forces correct UTF-8 parsing on every PS5.1 system with no BOM required.
    // Single-quoting the path (with '' escaping) also handles spaces in the path.
    let (final_args, final_path) = if program == "powershell" {
        let escaped = path_str.replace('\'', "''");
        (
            vec![
                "-NonInteractive".to_string(),
                "-NoProfile".to_string(),
                "-ExecutionPolicy".to_string(),
                "Bypass".to_string(),
                "-Command".to_string(),
                format!("& ([scriptblock]::Create((Get-Content -LiteralPath '{}' -Encoding UTF8 -Raw)))", escaped),
            ],
            String::new(),
        )
    } else {
        (extra_args, path_str)
    };

    Ok((program.to_string(), final_path, final_args))
}

fn build_env(config: &UserConfig) -> Vec<(String, String)> {
    let mut env = vec![
        ("SETUP_PYTHON_VERSION".to_string(), config.python_version.clone()),
        ("SETUP_NODE_VERSION".to_string(), config.node_version.clone()),
        ("SETUP_VENV_NAME".to_string(), config.venv_name.clone()),
        ("SETUP_POSTGRES_PASSWORD".to_string(), config.postgres_password.clone()),
        ("SETUP_POSTGRES_DB".to_string(), config.postgres_db_name.clone()),
        ("SETUP_SKIP_INSTALLED".to_string(), config.skip_already_installed.to_string()),
        ("SETUP_SKIP_WSL_BACKUP".to_string(), config.skip_wsl_backup.to_string()),
    ];
    if let Some(ref tar_path) = config.wsl_tar_path {
        env.push(("SETUP_WSL_TAR_PATH".to_string(), tar_path.clone()));
    }
    if let Some(ref install_dir) = config.wsl_install_dir {
        env.push(("SETUP_WSL_INSTALL_DIR".to_string(), install_dir.clone()));
    }
    if let Some(ref backup_path) = config.wsl_backup_path {
        env.push(("SETUP_WSL_BACKUP_PATH".to_string(), backup_path.clone()));
    }
    if let Some(ref openvpn_path) = config.openvpn_config_path {
        env.push(("SETUP_OPENVPN_CONFIG_PATH".to_string(), openvpn_path.clone()));
    }
    if let Some(ref tunnelblick_path) = config.tunnelblick_installer_path {
        env.push(("SETUP_TUNNELBLICK_INSTALLER_PATH".to_string(), tunnelblick_path.clone()));
    }
    if let Some(ref tunnelblick_url) = config.tunnelblick_remote_url {
        env.push(("SETUP_TUNNELBLICK_REMOTE_URL".to_string(), tunnelblick_url.clone()));
    }
    if let Some(ref git_name) = config.git_name {
        env.push(("SETUP_GIT_NAME".to_string(), git_name.clone()));
    }
    if let Some(ref git_email) = config.git_email {
        env.push(("SETUP_GIT_EMAIL".to_string(), git_email.clone()));
    }
    if let Some(ref v) = config.gitlab_pat {
        env.push(("SETUP_GITLAB_PAT".to_string(), v.clone()));
    }
    if let Some(ref v) = config.gitlab_repo_url {
        env.push(("SETUP_GITLAB_REPO_URL".to_string(), v.clone()));
    }
    if let Some(ref v) = config.clone_dir {
        env.push(("SETUP_CLONE_DIR".to_string(), v.clone()));
    }
    env.push(("SETUP_TENANT_NAME".to_string(), config.tenant_name.clone()));
    env.push(("SETUP_TENANT_ID".to_string(), config.tenant_id.clone()));
    env.push(("SETUP_CLUSTER_NAME".to_string(), config.cluster_name.clone()));
    if let Some(ref key_id) = config.aws_access_key_id {
        env.push(("SETUP_AWS_ACCESS_KEY_ID".to_string(), key_id.clone()));
    }
    if let Some(ref secret_key) = config.aws_secret_access_key {
        env.push(("SETUP_AWS_SECRET_ACCESS_KEY".to_string(), secret_key.clone()));
    }
    env
}

fn emit_log(window: &WebviewWindow, step_id: &str, line: &str, level: LogLevel) {
    // 🔒 SECURITY: Redact sensitive data from logs before emitting to UI
    let redacted_line = crate::security::redact_sensitive_log(line);

    let _ = window.emit(
        "step_log",
        LogEvent {
            step_id: step_id.to_string(),
            line: redacted_line,
            level,
        },
    );
}

fn classify_log_line(line: &str) -> LogLevel {
    let trimmed = line.trim();
    // Check for emoji/symbol prefixes first (more specific)
    if trimmed.starts_with("✓") || trimmed.starts_with("✅") {
        return LogLevel::Success;
    }
    if trimmed.starts_with("✗") || trimmed.starts_with("❌") {
        return LogLevel::Error;
    }
    if trimmed.starts_with("⚠") || trimmed.starts_with("⏳") || trimmed.starts_with("?") {
        return LogLevel::Warn;
    }
    if trimmed.starts_with("▶") || trimmed.starts_with("→") {
        return LogLevel::Info;
    }

    // Then check for keywords in content
    let lower = line.to_lowercase();
    if lower.contains("error") || lower.contains("failed") || lower.contains("fatal") {
        LogLevel::Error
    } else if lower.contains("warn") || lower.contains("warning") {
        LogLevel::Warn
    } else if lower.contains("success") || lower.contains("complete") || lower.contains("done") {
        LogLevel::Success
    } else {
        LogLevel::Info
    }
}
