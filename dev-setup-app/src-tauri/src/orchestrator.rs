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
            title: "Install NVM + Node 16.20.2".to_string(),
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
            description: "Import the pre-configured Ubuntu 22.04 TAR image into WSL2.".to_string(),
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
    ]
}

/// Resolves the path to a bundled script relative to the app resources directory.
fn script_path(app_handle: &tauri::AppHandle, script_name: &str) -> Result<std::path::PathBuf, String> {
    use tauri::Manager;
    let resource_dir = app_handle
        .path()
        .resource_dir()
        .map_err(|e| e.to_string())?;
    Ok(resource_dir.join("scripts").join(script_name))
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

    emit_log(&window, &step.id, &format!("▶ Starting: {}", step.title), LogLevel::Info);

    let mut child = tokio::process::Command::new(&program)
        .args(&args)
        .arg(&script_file)
        .envs(build_env(config))
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("Failed to spawn process: {}", e))?;

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
                all_logs.push(format!("[stderr] {}", line));
                emit_log(&window, &step.id, &line, LogLevel::Warn);
            }
        } else {
            all_logs.push(line.clone());
            emit_log(&window, &step.id, &line, classify_log_line(&line));
        }
    }

    let status = child.wait().await.map_err(|e| format!("Process wait error: {}", e))?;

    let duration = start.elapsed().as_secs();

    if status.success() {
        emit_log(
            &window,
            &step.id,
            &format!("✓ Completed in {}s", duration),
            LogLevel::Success,
        );
        Ok(all_logs)
    } else {
        let msg = format!(
            "Script exited with code {}",
            status.code().unwrap_or(-1)
        );
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
        "git_ssh_windows"=>("windows","setup_git_ssh.ps1",        "powershell", vec!["-ExecutionPolicy".to_string(), "Bypass".to_string(), "-File".to_string()]),
        _ => return Err(format!("Unknown step id: {}", step.id)),
    };

    let path = script_path(app_handle, &format!("{}/{}", script_subdir, script_name))
        .map_err(|e| e)?;

    Ok((
        program.to_string(),
        path.to_string_lossy().to_string(),
        extra_args,
    ))
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
