// orchestrator.rs — Step definitions and script execution engine
use crate::state::UserConfig;
use serde::{Deserialize, Serialize};
use std::process::Stdio;
use std::time::Instant;
use tauri::{Emitter, WebviewWindow};
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
        },
        SetupStep {
            id: "revert_wsl_distro".to_string(),
            title: "Remove ERC Distro".to_string(),
            description: "Export a backup of the ERC distro to ~/WSL_Backup/, then unregister and delete it from WSL. All data inside will be permanently deleted.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Revert,
            required: true,
            estimated_minutes: 15,
        },
        SetupStep {
            id: "revert_wslconfig".to_string(),
            title: "Reset .wslconfig".to_string(),
            description: "Remove networkingMode=mirrored from ~/.wslconfig. The file is deleted if no other settings remain.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Revert,
            required: true,
            estimated_minutes: 1,
        },
        SetupStep {
            id: "revert_windows_hosts".to_string(),
            title: "Clean Windows Hosts File".to_string(),
            description: "Remove dev hostnames (t3582.local, erckinetic) added by the setup tool. All other entries are preserved.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Revert,
            required: true,
            estimated_minutes: 1,
        },
        SetupStep {
            id: "revert_wsl_features".to_string(),
            title: "Disable WSL Windows Features".to_string(),
            description: "Disable WSL and Virtual Machine Platform Windows features. A system restart is required to complete removal.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Revert,
            required: false,
            estimated_minutes: 2,
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
        },
        SetupStep {
            id: "homebrew".to_string(),
            title: "Install Homebrew".to_string(),
            description: "Install the macOS package manager used to install all other tools.".to_string(),
            platform: Platform::MacOs,
            category: StepCategory::PackageManager,
            required: true,
            estimated_minutes: 3,
        },
        SetupStep {
            id: "pyenv".to_string(),
            title: "Install pyenv + Python 3.9.21".to_string(),
            description: "Install pyenv for Python version management, then install Python 3.9.21 and create a virtualenv.".to_string(),
            platform: Platform::MacOs,
            category: StepCategory::Python,
            required: true,
            estimated_minutes: 10,
        },
        SetupStep {
            id: "nvm".to_string(),
            title: "Install NVM + Node 22.10.0".to_string(),
            description: "Install NVM (Node Version Manager) and Node.js 16.20.2 with Gulp.".to_string(),
            platform: Platform::MacOs,
            category: StepCategory::Node,
            required: true,
            estimated_minutes: 5,
        },
        SetupStep {
            id: "postgres_mac".to_string(),
            title: "Install PostgreSQL 16".to_string(),
            description: "Install PostgreSQL 16 via Homebrew, initialise the database cluster and start the service.".to_string(),
            platform: Platform::MacOs,
            category: StepCategory::Database,
            required: true,
            estimated_minutes: 5,
        },
        SetupStep {
            id: "redis_mac".to_string(),
            title: "Install Redis".to_string(),
            description: "Install Redis in-memory store via Homebrew and start the service.".to_string(),
            platform: Platform::MacOs,
            category: StepCategory::Cache,
            required: false,
            estimated_minutes: 2,
        },
        SetupStep {
            id: "vscode_mac".to_string(),
            title: "Configure VS Code".to_string(),
            description: "Install VS Code extensions (ESLint, Pylint, Black, Python, Git Graph, etc.) and configure shell integration.".to_string(),
            platform: Platform::MacOs,
            category: StepCategory::Editor,
            required: true,
            estimated_minutes: 3,
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
        },
        SetupStep {
            id: "import_wsl_tar".to_string(),
            title: "Import Ubuntu 22.04 from TAR".to_string(),
            description: "Import the pre-configured ERC Ubuntu TAR image into WSL2.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Wsl,
            required: true,
            estimated_minutes: 10,
        },
        SetupStep {
            id: "wsl_network".to_string(),
            title: "Configure WSL Networking".to_string(),
            description: "Set up WSL network adapter, DNS resolv.conf, and host file entries.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Network,
            required: true,
            estimated_minutes: 3,
        },
        SetupStep {
            id: "vscode_windows".to_string(),
            title: "Configure VS Code for Windows".to_string(),
            description: "Install VS Code Remote-WSL extension and configure VS Code settings for the WSL environment.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Editor,
            required: true,
            estimated_minutes: 5,
        },
        SetupStep {
            id: "git_ssh_windows".to_string(),
            title: "Git & SSH Setup".to_string(),
            description: "Configure Git identity, generate SSH keys, and set up GitHub access inside WSL.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Vcs,
            required: true,
            estimated_minutes: 5,
        },
        SetupStep {
            id: "pyenv_wsl".to_string(),
            title: "Install pyenv + Python 3.9.21 (WSL)".to_string(),
            description: "Install pyenv via the official curl installer inside WSL Ubuntu, install Python 3.9.21, and create the 'erc' virtual environment. Skipped automatically if already set up.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Python,
            required: false,
            estimated_minutes: 10,
        },
        SetupStep {
            id: "nvm_wsl".to_string(),
            title: "Install NVM v0.40.1 + Node 22.10.0 (WSL)".to_string(),
            description: "Install NVM v0.40.1 and Node.js v22.10.0 inside WSL Ubuntu and set it as the default version. Skipped automatically if already set up.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Node,
            required: false,
            estimated_minutes: 5,
        },
        SetupStep {
            id: "ubuntu_user_wsl".to_string(),
            title: "Configure Ubuntu User (WSL)".to_string(),
            description: "Check if an 'ubuntu' user exists inside WSL Ubuntu. Creates and configures it if not present; skips automatically if already set up.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Wsl,
            required: false,
            estimated_minutes: 2,
        },
        SetupStep {
            id: "postgres_wsl".to_string(),
            title: "Install PostgreSQL (WSL)".to_string(),
            description: "Check if PostgreSQL is installed inside WSL Ubuntu. Installs and initialises it if missing; skips automatically if already present.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Database,
            required: false,
            estimated_minutes: 5,
        },
        SetupStep {
            id: "redis_wsl".to_string(),
            title: "Install Redis (WSL)".to_string(),
            description: "Check if Redis is installed inside WSL Ubuntu. Installs and starts it if missing; skips automatically if already present.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Cache,
            required: false,
            estimated_minutes: 3,
        },
        SetupStep {
            id: "wslconfig_networking".to_string(),
            title: "Configure .wslconfig (Mirrored Networking)".to_string(),
            description: "Create or update C:\\Users\\<you>\\.wslconfig with networkingMode=mirrored so WSL shares the Windows network interface. Skips if already configured.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Network,
            required: false,
            estimated_minutes: 1,
        },
        SetupStep {
            id: "wsl_cleanup".to_string(),
            title: "WSL Cleanup & Set Default Distro".to_string(),
            description: "List WSL distros, set the imported ERC distro as the default, and unregister any stale Ubuntu instances. Skips if already clean.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Wsl,
            required: false,
            estimated_minutes: 2,
        },
        SetupStep {
            id: "windows_hosts".to_string(),
            title: "Update Windows Hosts File".to_string(),
            description: "Add 127.0.0.1 t3582.local (and optional tenant entries) to C:\\Windows\\System32\\drivers\\etc\\hosts. Skips if entries already present.".to_string(),
            platform: Platform::Windows,
            category: StepCategory::Network,
            required: false,
            estimated_minutes: 1,
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
    log::info!("script_path: resolved '{}' —> {}", script_name, path.display());
    let exists = path.exists();
    if !exists {
        log::error!("script_path: file does NOT exist at resolved path: {}", path.display());
    }
    Ok(path)
}

/// Execute a shell script and stream output line-by-line to the frontend via events.
pub async fn execute_script(
    window: WebviewWindow,
    app_handle: tauri::AppHandle,
    step: &SetupStep,
    config: &UserConfig,
) -> Result<Vec<String>, String> {
    let start = Instant::now();

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
        cmd.envs(build_env(config))
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
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

    // Drain the merged channel until both tasks have finished and dropped their senders
    while let Some((line, is_stderr)) = rx.recv().await {
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
        let msg = format!("Script exited with code {}", code);
        log::error!("execute_script: step '{}' FAILED — exit code={} duration={}s", step.id, code, duration);
        emit_log(&window, &step.id, &msg, LogLevel::Error);
        Err(msg)
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
        "pyenv"         => ("macos", "setup_pyenv.sh",        "bash", vec![]),
        "nvm"           => ("macos", "setup_nvm.sh",          "bash", vec![]),
        "postgres_mac"  => ("macos", "setup_postgres.sh",     "bash", vec![]),
        "redis_mac"     => ("macos", "setup_redis.sh",        "bash", vec![]),
        "vscode_mac"    => ("macos", "setup_vscode.sh",       "bash", vec![]),
        // Windows
        "enable_wsl"    => ("windows", "enable_wsl.ps1",          "powershell", vec!["-ExecutionPolicy".to_string(), "Bypass".to_string(), "-File".to_string()]),
        "import_wsl_tar"=> ("windows", "import_wsl_tar.ps1",      "powershell", vec!["-ExecutionPolicy".to_string(), "Bypass".to_string(), "-File".to_string()]),
        "wsl_network"   => ("windows", "setup_wsl_network.ps1",   "powershell", vec!["-ExecutionPolicy".to_string(), "Bypass".to_string(), "-File".to_string()]),
        "vscode_windows"=> ("windows", "setup_vscode_windows.ps1","powershell", vec!["-ExecutionPolicy".to_string(), "Bypass".to_string(), "-File".to_string()]),
        "git_ssh_windows"=>("windows","setup_git_ssh.ps1",        "powershell", vec!["-ExecutionPolicy".to_string(), "Bypass".to_string(), "-File".to_string()]),        // Windows — WSL-side bash scripts (invoked via wsl -d ERC bash)
        "pyenv_wsl"       => ("windows", "setup_pyenv_wsl.sh",         "wsl",        vec!["-d".to_string(), "ERC".to_string(), "bash".to_string()]),
        "nvm_wsl"          => ("windows", "setup_nvm_wsl.sh",           "wsl",        vec!["-d".to_string(), "ERC".to_string(), "bash".to_string()]),
        "ubuntu_user_wsl"  => ("windows", "setup_ubuntu_user_wsl.sh",   "wsl",        vec!["-d".to_string(), "ERC".to_string(), "bash".to_string()]),
        "postgres_wsl"     => ("windows", "setup_postgres_wsl.sh",      "wsl",        vec!["-d".to_string(), "ERC".to_string(), "bash".to_string()]),
        "redis_wsl"        => ("windows", "setup_redis_wsl.sh",         "wsl",        vec!["-d".to_string(), "ERC".to_string(), "bash".to_string()]),
        // Windows-side PowerShell scripts
        "wslconfig_networking" => ("windows", "setup_wslconfig_networking.ps1", "powershell", vec!["-ExecutionPolicy".to_string(), "Bypass".to_string(), "-File".to_string()]),
        "wsl_cleanup"          => ("windows", "setup_wsl_cleanup.ps1",          "powershell", vec!["-ExecutionPolicy".to_string(), "Bypass".to_string(), "-File".to_string()]),
        "windows_hosts"        => ("windows", "setup_windows_hosts.ps1",        "powershell", vec!["-ExecutionPolicy".to_string(), "Bypass".to_string(), "-File".to_string()]),
        // Revert scripts
        "revert_shutdown_wsl"  => ("windows", "revert_wsl_shutdown.ps1",   "powershell", vec!["-ExecutionPolicy".to_string(), "Bypass".to_string(), "-File".to_string()]),
        "revert_wsl_distro"    => ("windows", "revert_wsl_distro.ps1",     "powershell", vec!["-ExecutionPolicy".to_string(), "Bypass".to_string(), "-File".to_string()]),
        "revert_wslconfig"     => ("windows", "revert_wslconfig.ps1",      "powershell", vec!["-ExecutionPolicy".to_string(), "Bypass".to_string(), "-File".to_string()]),
        "revert_windows_hosts" => ("windows", "revert_windows_hosts.ps1",  "powershell", vec!["-ExecutionPolicy".to_string(), "Bypass".to_string(), "-File".to_string()]),
        "revert_wsl_features"  => ("windows", "revert_wsl_features.ps1",   "powershell", vec!["-ExecutionPolicy".to_string(), "Bypass".to_string(), "-File".to_string()]),
        _ => return Err(format!("Unknown step id: {}", step.id)),
    };

    let path = script_path(app_handle, &format!("{}/{}", script_subdir, script_name))
        .map_err(|e| e)?;

    // Strip the \\?\ extended-length prefix emitted by Rust's PathBuf on Windows.
    let path_str = {
        let s = path.to_string_lossy().to_string();
        if s.starts_with(r"\\?\") { s[4..].to_string() } else { s }
    };

    // PowerShell's -File parameter breaks on paths containing spaces (e.g. a user
    // home dir or an install path like "Dev_Setup"). Use -Command with the call
    // operator & instead — single-quoting the path handles spaces and all other
    // special characters. The extra_args from the match above are discarded for
    // PowerShell; all flags are rebuilt here.
    let (final_args, final_path) = if program == "powershell" {
        let escaped = path_str.replace('\'', "''");
        (
            vec![
                "-NonInteractive".to_string(),
                "-NoProfile".to_string(),
                "-ExecutionPolicy".to_string(),
                "Bypass".to_string(),
                "-Command".to_string(),
                format!("& '{}'", escaped),
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
    ];
    if let Some(ref tar_path) = config.wsl_tar_path {
        env.push(("SETUP_WSL_TAR_PATH".to_string(), tar_path.clone()));
    }
    if let Some(ref install_dir) = config.wsl_install_dir {
        env.push(("SETUP_WSL_INSTALL_DIR".to_string(), install_dir.clone()));
    }
    if let Some(ref openvpn_path) = config.openvpn_config_path {
        env.push(("SETUP_OPENVPN_CONFIG_PATH".to_string(), openvpn_path.clone()));
    }
    env
}

fn emit_log(window: &WebviewWindow, step_id: &str, line: &str, level: LogLevel) {
    let _ = window.emit(
        "step_log",
        LogEvent {
            step_id: step_id.to_string(),
            line: line.to_string(),
            level,
        },
    );
}

fn classify_log_line(line: &str) -> LogLevel {
    let lower = line.to_lowercase();
    if lower.contains("error") || lower.contains("failed") || lower.contains("fatal") {
        LogLevel::Error
    } else if lower.contains("warn") || lower.contains("warning") {
        LogLevel::Warn
    } else if lower.contains("✓") || lower.contains("success") || lower.contains("complete") || lower.contains("done") {
        LogLevel::Success
    } else {
        LogLevel::Info
    }
}
