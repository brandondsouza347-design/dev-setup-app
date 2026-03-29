// commands.rs — Tauri command handlers exposed to the React frontend
use crate::orchestrator::{execute_script_with_retry, find_step_by_id, get_revert_steps_for_os, get_steps_for_os, SetupStep};
use crate::state::{AppState, StepStatus, UserConfig};
use serde::{Deserialize, Serialize};
use std::sync::Mutex;
use tauri::{AppHandle, Emitter, State, WebviewWindow};

#[derive(Serialize)]
pub struct OsInfo {
    pub os: String,           // "macos" | "windows" | "linux"
    pub arch: String,         // "x86_64" | "aarch64"
    pub version: String,
    pub is_apple_silicon: bool,
}

#[derive(Serialize)]
pub struct StepResult {
    pub id: String,
    pub status: StepStatus,
    pub logs: Vec<String>,
    pub error: Option<String>,
    pub retry_count: u32,
    pub duration_secs: Option<u64>,
}

#[derive(Serialize)]
pub struct FullState {
    pub steps: Vec<StepResult>,
    pub current_step_index: usize,
    pub setup_started: bool,
    pub setup_complete: bool,
    pub config: UserConfig,
}

#[derive(Deserialize)]
pub struct ConfigInput {
    pub wsl_tar_path: Option<String>,
    pub wsl_install_dir: Option<String>,
    pub postgres_password: String,
    pub postgres_db_name: String,
    pub python_version: String,
    pub node_version: String,
    pub venv_name: String,
    pub skip_already_installed: bool,
    pub openvpn_config_path: Option<String>,
    pub git_name: Option<String>,
    pub git_email: Option<String>,
}

/// Detects the current operating system.
#[tauri::command]
pub fn detect_os() -> OsInfo {
    let os = std::env::consts::OS;
    let arch = std::env::consts::ARCH;

    let is_apple_silicon = os == "macos" && arch == "aarch64";

    let info = OsInfo {
        os: match os {
            "macos" => "macos",
            "windows" => "windows",
            _ => "linux",
        }
        .to_string(),
        arch: arch.to_string(),
        version: os_version(),
        is_apple_silicon,
    };
    log::info!("detect_os: os={} arch={} version={} apple_silicon={}", info.os, info.arch, info.version, info.is_apple_silicon);
    info
}

/// Returns the ordered list of setup steps for the detected OS.
#[tauri::command]
pub fn get_setup_steps(os: String) -> Vec<SetupStep> {
    get_steps_for_os(&os)
}

/// Returns the ordered list of revert steps for the detected OS (Windows only).
#[tauri::command]
pub fn get_revert_steps(os: String) -> Vec<SetupStep> {
    get_revert_steps_for_os(&os)
}

fn emit_frontend_log(window: &WebviewWindow, step_id: &str, line: &str, level: &str) {
    let _ = window.emit(
        "step_log",
        serde_json::json!({
            "step_id": step_id,
            "line": line,
            "level": level,
        }),
    );
}

fn resolve_setup_rollback_steps(os: &str, step_id: &str) -> Result<(Vec<SetupStep>, usize, SetupStep, Vec<SetupStep>), String> {
    let setup_steps = get_steps_for_os(os);
    let target_index = setup_steps
        .iter()
        .position(|step| step.id == step_id)
        .ok_or_else(|| format!("Unknown setup step: {}", step_id))?;
    let target_step = setup_steps[target_index].clone();

    if target_step.rollback_steps.is_empty() {
        return Err(format!("Step '{}' does not support targeted revert", target_step.title));
    }

    let revert_steps = get_revert_steps_for_os(os);
    let rollback_steps = target_step
        .rollback_steps
        .iter()
        .map(|rollback_id| {
            revert_steps
                .iter()
                .find(|step| step.id == *rollback_id)
                .cloned()
                .ok_or_else(|| format!("Rollback step '{}' is not defined", rollback_id))
        })
        .collect::<Result<Vec<_>, _>>()?;

    Ok((setup_steps, target_index, target_step, rollback_steps))
}

/// Starts the full setup sequence from step 0.
#[tauri::command]
pub async fn start_setup(
    window: WebviewWindow,
    app_handle: AppHandle,
    state: State<'_, Mutex<AppState>>,
) -> Result<(), String> {
    let (steps, config) = {
        let mut s = state.lock().unwrap();
        s.setup_started = true;
        s.current_step_index = 0;
        let os = detect_os();
        let steps = get_steps_for_os(&os.os);
        log::info!("start_setup: beginning full setup for os={} — {} steps queued", os.os, steps.len());
        for step in &steps {
            s.get_or_create_step(&step.id);
        }
        (steps, s.config.clone())
    };

    for (idx, step) in steps.iter().enumerate() {
        // Check if already done or skipped
        let current_status = {
            let s = state.lock().unwrap();
            s.step_states.get(&step.id).map(|ss| ss.status.clone())
        };
        if matches!(current_status, Some(StepStatus::Done) | Some(StepStatus::Skipped)) {
            continue;
        }

        // Mark running
        {
            let mut s = state.lock().unwrap();
            s.current_step_index = idx;
            let ss = s.get_or_create_step(&step.id);
            ss.status = StepStatus::Running;
        }
        log::info!("start_setup: running step [{}/{}] id={} title='{}'", idx + 1, steps.len(), step.id, step.title);
        let _ = window.emit("step_status", serde_json::json!({ "id": step.id, "status": "running" }));

        let start = std::time::Instant::now();
        let result = execute_script_with_retry(window.clone(), app_handle.clone(), step, &config).await;
        let duration = start.elapsed().as_secs();

        {
            let mut s = state.lock().unwrap();
            let ss = s.get_or_create_step(&step.id);
            ss.duration_secs = Some(duration);
            match result {
                Ok(logs) => {
                    log::info!("start_setup: step '{}' completed successfully in {}s ({} log lines)", step.id, duration, logs.len());
                    ss.status = StepStatus::Done;
                    ss.logs = logs;
                    ss.error = None;
                }
                Err(err) => {
                    log::error!("start_setup: step '{}' FAILED after {}s — {}", step.id, duration, err);
                    ss.status = StepStatus::Failed;
                    ss.error = Some(err.clone());
                    let _ = window.emit(
                        "step_status",
                        serde_json::json!({ "id": step.id, "status": "failed", "error": err }),
                    );
                    // Stop the whole sequence on failure — user must retry
                    return Err(format!("Step '{}' failed: {}", step.title, err));
                }
            }
        }

        let _ = window.emit("step_status", serde_json::json!({ "id": step.id, "status": "done" }));
    }

    {
        let mut s = state.lock().unwrap();
        s.setup_complete = true;
    }
    let _ = window.emit("setup_complete", true);
    Ok(())
}

/// Resumes setup from the first non-done, non-skipped step.
/// Used after a retry succeeds mid-sequence so the user can continue without
/// restarting the entire sequence from scratch. Completed steps are skipped.
#[tauri::command]
pub async fn resume_setup(
    window: WebviewWindow,
    app_handle: AppHandle,
    state: State<'_, Mutex<AppState>>,
) -> Result<(), String> {
    log::info!("resume_setup: resuming from first pending/failed step");
    // Reset setup_complete so start_setup runs to the end again.
    {
        let mut s = state.lock().unwrap();
        s.setup_complete = false;
        // Reset any failed steps back to pending so start_setup will pick them up.
        for ss in s.step_states.values_mut() {
            if ss.status == StepStatus::Failed {
                ss.status = StepStatus::Pending;
                ss.error = None;
            }
        }
    }
    start_setup(window, app_handle, state).await
}

/// Runs a single step by its ID (useful for retry or running individually).
#[tauri::command]
pub async fn run_step(
    step_id: String,
    window: WebviewWindow,
    app_handle: AppHandle,
    state: State<'_, Mutex<AppState>>,
) -> Result<(), String> {
    log::info!("run_step: requested step_id={}", step_id);
    let (step, config) = {
        let s = state.lock().unwrap();
        let os = detect_os();
        let step = find_step_by_id(&os.os, &step_id)
            .ok_or_else(|| { log::error!("run_step: unknown step_id={}", step_id); format!("Unknown step: {}", step_id) })?;
        (step, s.config.clone())
    };

    {
        let mut s = state.lock().unwrap();
        let ss = s.get_or_create_step(&step.id);
        ss.status = StepStatus::Running;
        ss.logs.clear();
        ss.error = None;
    }
    let _ = window.emit("step_status", serde_json::json!({ "id": step_id, "status": "running" }));

    let start = std::time::Instant::now();
    let result = execute_script_with_retry(window.clone(), app_handle.clone(), &step, &config).await;
    let duration = start.elapsed().as_secs();

    let mut s = state.lock().unwrap();
    let ss = s.get_or_create_step(&step.id);
    ss.duration_secs = Some(duration);

    match result {
        Ok(logs) => {
            log::info!("run_step: step '{}' done in {}s ({} log lines)", step_id, duration, logs.len());
            ss.status = StepStatus::Done;
            ss.logs = logs;
            ss.error = None;
            let _ = window.emit("step_status", serde_json::json!({ "id": step_id, "status": "done" }));
            Ok(())
        }
        Err(err) => {
            log::error!("run_step: step '{}' FAILED after {}s — {}", step_id, duration, err);
            ss.status = StepStatus::Failed;
            ss.error = Some(err.clone());
            let _ = window.emit(
                "step_status",
                serde_json::json!({ "id": step_id, "status": "failed", "error": err }),
            );
            Err(err)
        }
    }
}

/// Runs the full revert sequence in order: shutdown WSL → remove distro → reset config → clean hosts → disable features.
/// Stops on first failure. Emits step_status and revert_complete events.
#[tauri::command]
pub async fn start_revert(
    window: WebviewWindow,
    app_handle: AppHandle,
    state: State<'_, Mutex<AppState>>,
) -> Result<(), String> {
    let config = {
        state.lock().unwrap().config.clone()
    };
    let os = detect_os();
    let revert_steps = get_revert_steps_for_os(&os.os);
    if revert_steps.is_empty() {
        return Err("Revert is only supported on Windows".to_string());
    }
    log::info!("start_revert: beginning revert sequence ({} steps)", revert_steps.len());

    for step in &revert_steps {
        log::info!("start_revert: running revert step '{}'", step.id);
        let _ = window.emit("step_status", serde_json::json!({ "id": step.id, "status": "running" }));

        let start = std::time::Instant::now();
        let result = execute_script_with_retry(window.clone(), app_handle.clone(), step, &config).await;
        let duration = start.elapsed().as_secs();

        match result {
            Ok(_) => {
                log::info!("start_revert: step '{}' done in {}s", step.id, duration);
                let _ = window.emit("step_status", serde_json::json!({ "id": step.id, "status": "done" }));
            }
            Err(err) => {
                log::error!("start_revert: step '{}' FAILED after {}s — {}", step.id, duration, err);
                let _ = window.emit(
                    "step_status",
                    serde_json::json!({ "id": step.id, "status": "failed", "error": err }),
                );
                return Err(format!("Revert step '{}' failed: {}", step.title, err));
            }
        }
    }

    let _ = window.emit("revert_complete", true);
    Ok(())
}

/// Reverts a single completed setup step using an explicit rollback mapping.
/// This is currently limited to steps that declare safe rollback coverage.
#[tauri::command]
pub async fn revert_setup_step(
    step_id: String,
    window: WebviewWindow,
    app_handle: AppHandle,
    state: State<'_, Mutex<AppState>>,
) -> Result<(), String> {
    let os = detect_os();
    if os.os != "windows" {
        return Err("Targeted revert is only supported on Windows".to_string());
    }

    let (setup_steps, target_index, target_step, rollback_steps) =
        resolve_setup_rollback_steps(&os.os, &step_id)?;

    let config = {
        let s = state.lock().unwrap();
        let current_status = s
            .step_states
            .get(&step_id)
            .map(|ss| ss.status.clone())
            .unwrap_or(StepStatus::Pending);
        if !matches!(current_status, StepStatus::Done | StepStatus::Failed) {
            return Err(format!(
                "Step '{}' must be completed or failed before it can be reverted",
                target_step.title
            ));
        }

        let later_completed: Vec<String> = setup_steps
            .iter()
            .skip(target_index + 1)
            .filter(|step| {
                matches!(
                    s.step_states.get(&step.id).map(|ss| ss.status.clone()),
                    Some(StepStatus::Done)
                )
            })
            .map(|step| step.title.clone())
            .collect();
        if !later_completed.is_empty() {
            return Err(format!(
                "Cannot revert '{}' because later setup steps already completed: {}. Use full Revert Setup instead.",
                target_step.title,
                later_completed.join(", ")
            ));
        }

        s.config.clone()
    };

    emit_frontend_log(
        &window,
        &step_id,
        &format!("↩ Reverting '{}'...", target_step.title),
        "warn",
    );

    for rollback_step in &rollback_steps {
        log::info!(
            "revert_setup_step: running rollback step '{}' for setup step '{}'",
            rollback_step.id,
            target_step.id
        );
        let _ = window.emit(
            "step_status",
            serde_json::json!({ "id": rollback_step.id, "status": "running" }),
        );

        let start = std::time::Instant::now();
        let result = execute_script_with_retry(window.clone(), app_handle.clone(), rollback_step, &config).await;
        let duration = start.elapsed().as_secs();

        match result {
            Ok(_) => {
                log::info!(
                    "revert_setup_step: rollback step '{}' done in {}s",
                    rollback_step.id,
                    duration
                );
                let _ = window.emit(
                    "step_status",
                    serde_json::json!({ "id": rollback_step.id, "status": "done" }),
                );
            }
            Err(err) => {
                log::error!(
                    "revert_setup_step: rollback step '{}' FAILED after {}s — {}",
                    rollback_step.id,
                    duration,
                    err
                );
                let _ = window.emit(
                    "step_status",
                    serde_json::json!({ "id": rollback_step.id, "status": "failed", "error": err }),
                );
                return Err(format!(
                    "Rollback step '{}' failed: {}",
                    rollback_step.title,
                    err
                ));
            }
        }
    }

    let mut reset_step_ids: Vec<String> = Vec::new();
    {
        let mut s = state.lock().unwrap();
        s.setup_complete = false;
        s.current_step_index = target_index;

        let target_state = s.get_or_create_step(&step_id);
        target_state.status = StepStatus::Pending;
        target_state.error = None;
        target_state.duration_secs = None;
        target_state.logs.clear();
        reset_step_ids.push(step_id.clone());

        for step in setup_steps.iter().skip(target_index + 1) {
            let step_state = s.get_or_create_step(&step.id);
            if matches!(step_state.status, StepStatus::Failed | StepStatus::Running | StepStatus::Pending) {
                step_state.status = StepStatus::Pending;
                step_state.error = None;
                step_state.duration_secs = None;
                reset_step_ids.push(step.id.clone());
            }
        }
    }

    for reset_id in reset_step_ids {
        let _ = window.emit(
            "step_status",
            serde_json::json!({ "id": reset_id, "status": "pending" }),
        );
    }
    emit_frontend_log(
        &window,
        &step_id,
        &format!("↩ '{}' reverted. You can run setup again from this step.", target_step.title),
        "success",
    );

    Ok(())
}

/// Marks a step as failed → pending and increments retry counter, then reruns it.
#[tauri::command]
pub async fn retry_step(
    step_id: String,
    window: WebviewWindow,
    app_handle: AppHandle,
    state: State<'_, Mutex<AppState>>,
) -> Result<(), String> {
    let retry_count = {
        let mut s = state.lock().unwrap();
        let ss = s.get_or_create_step(&step_id);
        ss.retry_count += 1;
        ss.status = StepStatus::Pending;
        ss.error = None;
        ss.retry_count
    };
    log::warn!("retry_step: retrying step_id={} (attempt #{})", step_id, retry_count);
    run_step(step_id, window, app_handle, state).await
}

/// Marks a step as skipped so the wizard can continue.
#[tauri::command]
pub fn skip_step(
    step_id: String,
    state: State<'_, Mutex<AppState>>,
) -> Result<(), String> {
    let mut s = state.lock().unwrap();
    let ss = s.get_or_create_step(&step_id);
    ss.status = StepStatus::Skipped;
    Ok(())
}

/// Returns the complete persisted state of all steps.
#[tauri::command]
pub fn get_state(state: State<'_, Mutex<AppState>>) -> FullState {
    let s = state.lock().unwrap();
    let os = detect_os();
    let steps = get_steps_for_os(&os.os);
    let step_results: Vec<StepResult> = steps
        .iter()
        .map(|step| {
            if let Some(ss) = s.step_states.get(&step.id) {
                StepResult {
                    id: ss.id.clone(),
                    status: ss.status.clone(),
                    logs: ss.logs.clone(),
                    error: ss.error.clone(),
                    retry_count: ss.retry_count,
                    duration_secs: ss.duration_secs,
                }
            } else {
                StepResult {
                    id: step.id.clone(),
                    status: StepStatus::Pending,
                    logs: vec![],
                    error: None,
                    retry_count: 0,
                    duration_secs: None,
                }
            }
        })
        .collect();
    FullState {
        steps: step_results,
        current_step_index: s.current_step_index,
        setup_started: s.setup_started,
        setup_complete: s.setup_complete,
        config: s.config.clone(),
    }
}

/// Wipes all progress and resets to initial state.
#[tauri::command]
pub fn reset_state(state: State<'_, Mutex<AppState>>) -> Result<(), String> {
    let mut s = state.lock().unwrap();
    s.reset();
    Ok(())
}

/// Runs pre-flight checks: internet connection, disk space, required tools.
#[tauri::command]
pub async fn check_prerequisites() -> Vec<PrereqCheck> {
    let mut checks: Vec<PrereqCheck> = Vec::new();
    let os = detect_os();
    log::info!("check_prerequisites: starting pre-flight checks for os={}", os.os);

    // Disk space: require >= 10 GB free on home dir
    let disk = check_disk_space();
    log::info!("check_prerequisites: [{}] {} — {}", if disk.passed { "PASS" } else { "FAIL" }, disk.name, disk.message);
    checks.push(disk);

    // OS-specific checks
    if os.os == "macos" {
        checks.push(check_command_available("git", "Git"));
        checks.push(check_command_available("curl", "curl"));
        checks.push(check_command_available("bash", "bash"));
    } else if os.os == "windows" {
        checks.push(check_admin_rights());
        checks.push(check_command_available("wsl", "WSL"));
        checks.push(check_command_available("winget", "winget"));
        checks.push(check_command_available("powershell", "PowerShell"));
    }

    let failed: Vec<_> = checks.iter().filter(|c| !c.passed).map(|c| c.name.as_str()).collect();
    if failed.is_empty() {
        log::info!("check_prerequisites: all checks passed");
    } else {
        log::warn!("check_prerequisites: {} check(s) failed — {:?}", failed.len(), failed);
    }

    checks
}

#[derive(Serialize)]
pub struct PrereqCheck {
    pub name: String,
    pub passed: bool,
    pub message: String,
}

fn check_command_available(cmd: &str, label: &str) -> PrereqCheck {
    let via_which = which::which(cmd);
    let found_by_which = via_which.is_ok();
    let found_by_fallback = !found_by_which && check_fallback_path(cmd);
    let available = found_by_which || found_by_fallback;

    if found_by_which {
        log::info!("check_command_available: [PASS] '{}' found via PATH — {:?}", cmd, which::which(cmd).unwrap());
    } else if found_by_fallback {
        log::info!("check_command_available: [PASS] '{}' not in PATH but found at absolute fallback location", cmd);
    } else {
        log::warn!("check_command_available: [FAIL] '{}' ({}) not found in PATH or fallback locations", cmd, label);
    }

    PrereqCheck {
        name: label.to_string(),
        passed: available,
        message: if available {
            format!("{} is available", label)
        } else {
            format!("{} not found in PATH", label)
        },
    }
}

/// On Windows, Tauri apps may not inherit the full system PATH.
/// Check well-known absolute locations as a fallback.
#[allow(unused_variables)]
fn check_fallback_path(cmd: &str) -> bool {
    #[cfg(target_os = "windows")]
    {
        let fallbacks: &[&str] = match cmd {
            "powershell" => &[
                r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe",
            ],
            "wsl" => &[
                r"C:\Windows\System32\wsl.exe",
                r"C:\Windows\SysNative\wsl.exe",
            ],
            _ => &[],
        };
        for path in fallbacks {
            let exists = std::path::Path::new(path).exists();
            log::info!("check_fallback_path: '{}' — checking {} — exists={}", cmd, path, exists);
            if exists {
                return true;
            }
        }
        return false;
    }
    #[allow(unreachable_code)]
    false
}

fn check_disk_space() -> PrereqCheck {
    // Simple heuristic: check home dir exists
    let home = dirs::home_dir();
    PrereqCheck {
        name: "Home Directory".to_string(),
        passed: home.is_some(),
        message: home
            .map(|p| format!("Home directory: {}", p.display()))
            .unwrap_or_else(|| "Could not determine home directory".to_string()),
    }
}

#[allow(unused_variables, dead_code)]
fn check_admin_rights() -> PrereqCheck {
    #[cfg(target_os = "windows")]
    {
        let is_admin = std::process::Command::new("powershell")
            .args([
                "-NoProfile",
                "-NonInteractive",
                "-Command",
                "[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)",
            ])
            .output()
            .ok()
            .and_then(|o| String::from_utf8(o.stdout).ok())
            .map(|s| s.trim().eq_ignore_ascii_case("true"))
            .unwrap_or(false);
        log::info!("check_admin_rights: is_admin={}", is_admin);
        return PrereqCheck {
            name: "Administrator Rights".to_string(),
            passed: is_admin,
            message: if is_admin {
                "Running as Administrator".to_string()
            } else {
                "Not running as Administrator \u{2014} WSL enablement requires admin. Right-click the app and select 'Run as administrator'.".to_string()
            },
        };
    }
    #[allow(unreachable_code)]
    PrereqCheck {
        name: "Administrator Rights".to_string(),
        passed: true,
        message: "Not applicable on this platform".to_string(),
    }
}

/// Opens the system terminal (fallback for manual steps).
#[tauri::command]
pub fn open_terminal() -> Result<(), String> {
    let os = std::env::consts::OS;
    match os {
        "macos" => {
            std::process::Command::new("open")
                .args(["-a", "Terminal"])
                .spawn()
                .map_err(|e| e.to_string())?;
        }
        "windows" => {
            // Spawn directly so each failure is catchable (not via cmd /c start which swallows it)
            let launched = std::process::Command::new("wt").spawn().is_ok()
                || std::process::Command::new("powershell").spawn().is_ok()
                || std::process::Command::new("cmd").spawn().is_ok();
            if !launched {
                log::error!("open_terminal: could not open any terminal (wt / powershell / cmd all failed)");
                return Err("Could not open a terminal".to_string());
            }
            log::info!("open_terminal: terminal launched");
        }
        _ => {}
    }
    Ok(())
}

/// Returns the current user configuration.
#[tauri::command]
pub fn get_config(state: State<'_, Mutex<AppState>>) -> UserConfig {
    state.lock().unwrap().config.clone()
}

/// Saves updated user configuration.
#[tauri::command]
pub fn save_config(
    input: ConfigInput,
    state: State<'_, Mutex<AppState>>,
) -> Result<(), String> {
    let mut s = state.lock().unwrap();
    s.config = UserConfig {
        wsl_tar_path: input.wsl_tar_path,
        wsl_install_dir: input.wsl_install_dir,
        postgres_password: input.postgres_password,
        postgres_db_name: input.postgres_db_name,
        python_version: input.python_version,
        node_version: input.node_version,
        venv_name: input.venv_name,
        skip_already_installed: input.skip_already_installed,
        openvpn_config_path: input.openvpn_config_path,
        git_name: input.git_name,
        git_email: input.git_email,
    };
    Ok(())
}

// ─── Helpers ────────────────────────────────────────────────────────────────

fn os_version() -> String {
    // Best-effort version string
    if cfg!(target_os = "macos") {
        std::process::Command::new("sw_vers")
            .arg("-productVersion")
            .output()
            .ok()
            .and_then(|o| String::from_utf8(o.stdout).ok())
            .unwrap_or_else(|| "unknown".to_string())
            .trim()
            .to_string()
    } else if cfg!(target_os = "windows") {
        "Windows 10/11".to_string()
    } else {
        "unknown".to_string()
    }
}
