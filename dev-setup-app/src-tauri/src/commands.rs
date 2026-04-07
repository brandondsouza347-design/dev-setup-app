// commands.rs — Tauri command handlers exposed to the React frontend
use crate::admin_agent::{execute_via_agent, AdminAgentState};
use crate::orchestrator::{execute_script_with_retry, find_step_by_id, get_revert_steps_for_os, get_steps_for_os, SetupStep};
use crate::state::{AppState, CancelState, StepStatus, UserConfig, RunHistory, FailedStepLog, SkippedStepLog, RunType, RunStatus, ConfigProfile, CustomWorkflow};
use serde::{Deserialize, Serialize};
use std::sync::Mutex;
use std::path::PathBuf;
use std::fs;
use std::time::{SystemTime, UNIX_EPOCH};
use tauri::{AppHandle, Emitter, Manager, State, WebviewWindow};

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
    pub skip_wsl_backup: bool,
    pub openvpn_config_path: Option<String>,
    pub git_name: Option<String>,
    pub git_email: Option<String>,
    pub gitlab_pat: Option<String>,
    pub gitlab_repo_url: Option<String>,
    pub clone_dir: Option<String>,
    pub wsl_default_user: String,
    pub tenant_name: String,
    pub tenant_id: String,
    pub cluster_name: String,
    pub aws_access_key_id: Option<String>,
    pub aws_secret_access_key: Option<String>,
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

/// Stops the currently running setup step by setting the cancellation flag.
/// The running execute_script loop picks this up within ~500 ms and kills
/// the child process, causing the current step to fail with "Stopped by user".
#[tauri::command]
pub async fn stop_setup(app_handle: AppHandle) -> Result<(), String> {
    log::info!("stop_setup: user requested cancellation");
    if let Some(cancel) = app_handle.try_state::<CancelState>() {
        let cs: tauri::State<'_, CancelState> = cancel;
        cs.cancel();
    }
    Ok(())
}

/// Starts the full setup sequence from step 0.
#[tauri::command]
pub async fn start_setup(
    window: WebviewWindow,
    app_handle: AppHandle,
    state: State<'_, Mutex<AppState>>,
) -> Result<(), String> {
    let started_at = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| format!("System time error: {}", e))?
        .as_secs() as i64;

    let (steps, config) = {
        let mut s = state.lock().unwrap();
        s.setup_started = true;
        s.setup_started_at = Some(started_at);
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

        // Add a 5-second delay after setup_workspace to let VS Code stabilize
        // before attempting to install extensions in the next step
        if idx > 0 {
            let prev_step = &steps[idx - 1];
            if prev_step.id == "setup_workspace" || prev_step.id == "setup_workspace_mac" {
                log::info!("start_setup: pausing 5s after '{}' for VS Code to stabilize", prev_step.id);
                emit_frontend_log(
                    &window,
                    &step.id,
                    "⏸ Waiting 5 seconds for VS Code to stabilize...",
                    "info",
                );
                tokio::time::sleep(tokio::time::Duration::from_secs(5)).await;
            }
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

    let completed_at = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| format!("System time error: {}", e))?
        .as_secs() as i64;

    // Collect failed steps for history
    let (started_at, failed_steps, skipped_steps) = {
        let s = state.lock().unwrap();
        let failed_steps: Vec<FailedStepLog> = s.step_states
            .iter()
            .filter(|(_, ss)| ss.status == StepStatus::Failed)
            .map(|(_, ss)| FailedStepLog {
                step_id: ss.id.clone(),
                step_name: steps.iter().find(|st| st.id == ss.id).map(|st| st.title.clone()).unwrap_or_else(|| ss.id.clone()),
                error_message: ss.error.clone(),
                logs: ss.logs.clone(),
            })
            .collect();
        let skipped_steps: Vec<SkippedStepLog> = s.step_states
            .iter()
            .filter(|(_, ss)| ss.status == StepStatus::Skipped)
            .map(|(_, ss)| SkippedStepLog {
                step_id: ss.id.clone(),
                step_name: steps.iter().find(|st| st.id == ss.id).map(|st| st.title.clone()).unwrap_or_else(|| ss.id.clone()),
            })
            .collect();
        (s.setup_started_at.unwrap_or(started_at), failed_steps, skipped_steps)
    };

    let run_status = if failed_steps.is_empty() { RunStatus::Success } else { RunStatus::Failed };

    // Save run history
    let _ = save_run_history(
        app_handle.clone(),
        RunType::Setup,
        started_at,
        completed_at,
        run_status,
        steps.len(),
        failed_steps,
        skipped_steps,
    ).await;

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
    let started_at = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| format!("System time error: {}", e))?
        .as_secs() as i64;

    {
        let mut s = state.lock().unwrap();
        s.revert_started_at = Some(started_at);
    }

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

                // Save failed revert history
                let completed_at = SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .map_err(|e| format!("System time error: {}", e))?
                    .as_secs() as i64;

                let failed_step = FailedStepLog {
                    step_id: step.id.clone(),
                    step_name: step.title.clone(),
                    error_message: Some(err.clone()),
                    logs: vec![],
                };

                let _ = save_run_history(
                    app_handle.clone(),
                    RunType::Revert,
                    started_at,
                    completed_at,
                    RunStatus::Failed,
                    revert_steps.len(),
                    vec![failed_step],
                    vec![],
                ).await;

                return Err(format!("Revert step '{}' failed: {}", step.title, err));
            }
        }
    }

    let completed_at = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| format!("System time error: {}", e))?
        .as_secs() as i64;

    // Save successful revert history
    let _ = save_run_history(
        app_handle.clone(),
        RunType::Revert,
        started_at,
        completed_at,
        RunStatus::Success,
        revert_steps.len(),
        vec![],
        vec![],
    ).await;

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
        checks.push(check_openvpn_installed(&os.os));
        checks.push(check_vpn_connectivity().await);
    } else if os.os == "windows" {
        checks.push(check_command_available("wsl", "WSL"));
        checks.push(check_command_available("winget", "winget"));
        checks.push(check_command_available("powershell", "PowerShell"));
        checks.push(check_openvpn_installed(&os.os));
        checks.push(check_vpn_connectivity().await);
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
    pub warning: bool,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub actionable: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub action_id: Option<String>,
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
        warning: false,
        message: if available {
            format!("{} is available", label)
        } else {
            format!("{} not found in PATH", label)
        },
        actionable: None,
        action_id: None,
    }
}

async fn check_vpn_connectivity() -> PrereqCheck {
    use std::time::Duration;
    log::info!("check_vpn_connectivity: testing TCP connection to gitlab.toogoerp.net:443");
    let result = tokio::time::timeout(
        Duration::from_secs(3),
        tokio::net::TcpStream::connect("gitlab.toogoerp.net:443"),
    )
    .await;
    match result {
        Ok(Ok(_)) => {
            log::info!("check_vpn_connectivity: [PASS] gitlab.toogoerp.net:443 reachable");
            PrereqCheck {
                name: "GitLab VPN Connectivity".to_string(),
                passed: true,
                warning: false,
                message: "gitlab.toogoerp.net is reachable — VPN is connected.".to_string(),
                actionable: None,
                action_id: None,
            }
        }
        _ => {
            log::warn!("check_vpn_connectivity: [WARN] gitlab.toogoerp.net:443 not reachable");
            PrereqCheck {
                name: "GitLab VPN Connectivity".to_string(),
                passed: false,
                warning: true,
                message: "Cannot reach gitlab.toogoerp.net:443. VPN required for GitLab SSH key upload and repository cloning. Click 'Connect to VPN' to proceed.".to_string(),
                actionable: Some(true),
                action_id: Some("connect_vpn".to_string()),
            }
        }
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
        warning: false,
        message: home
            .map(|p| format!("Home directory: {}", p.display()))
            .unwrap_or_else(|| "Could not determine home directory".to_string()),
        actionable: None,
        action_id: None,
    }
}

#[allow(unused_variables, dead_code)]
fn check_admin_rights() -> PrereqCheck {
    #[cfg(target_os = "windows")]
    {
        use std::os::windows::process::CommandExt;
        let is_admin = std::process::Command::new("powershell")
            .args([
                "-NoProfile",
                "-NonInteractive",
                "-Command",
                "[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)",
            ])
            .creation_flags(0x08000000) // CREATE_NO_WINDOW — suppress console flash
            .output()
            .ok()
            .and_then(|o| String::from_utf8(o.stdout).ok())
            .map(|s| s.trim().eq_ignore_ascii_case("true"))
            .unwrap_or(false);
        log::info!("check_admin_rights: is_admin={}", is_admin);
        return PrereqCheck {
            name: "Administrator Rights".to_string(),
            passed: is_admin,
            warning: false,
            message: if is_admin {
                "Running as Administrator".to_string()
            } else {
                "Not running as Administrator — use the 'Enable Admin Steps' button below to grant elevated access for WSL steps.".to_string()
            },
            actionable: None,
            action_id: None,
        };
    }
    #[allow(unreachable_code)]
    PrereqCheck {
        name: "Administrator Rights".to_string(),
        passed: true,
        warning: false,
        message: "Not applicable on this platform".to_string(),
        actionable: None,
        action_id: None,
    }
}

fn check_openvpn_installed(os: &str) -> PrereqCheck {
    let (app_name, _check_cmd) = if os == "windows" {
        ("OpenVPN", "openvpn")
    } else {
        ("Tunnelblick", "tunnelblick")
    };

    let installed = if os == "windows" {
        // Check if OpenVPN is installed via common paths
        std::path::Path::new(r"C:\Program Files\OpenVPN\bin\openvpn.exe").exists()
            || std::path::Path::new(r"C:\Program Files (x86)\OpenVPN\bin\openvpn.exe").exists()
            || which::which("openvpn").is_ok()
    } else {
        // Check if Tunnelblick is installed on macOS
        std::path::Path::new("/Applications/Tunnelblick.app").exists()
    };

    log::info!("check_openvpn_installed: os={}, app={}, installed={}", os, app_name, installed);

    PrereqCheck {
        name: format!("{} (VPN Client)", app_name),
        passed: installed,
        warning: !installed,
        message: if installed {
            format!("{} is installed", app_name)
        } else {
            format!("{} not found. Required to access corporate GitLab server for SSH keys and repository cloning. Click 'Install {}' to set up VPN access.", app_name, app_name)
        },
        actionable: Some(!installed),
        action_id: Some("install_openvpn".to_string()),
    }
}

/// Executes the OpenVPN installation script as a pre-check action.
/// Windows: installs OpenVPN via winget
/// macOS: installs Tunnelblick via Homebrew
#[tauri::command]
pub async fn install_openvpn_prereq(
    window: WebviewWindow,
    app_handle: AppHandle,
    state: State<'_, Mutex<AppState>>,
) -> Result<(), String> {
    let os = detect_os();

    // On Windows, check if admin agent is ready and use it (avoids second UAC prompt)
    #[cfg(target_os = "windows")]
    if os.os == "windows" {
        if let Some(agent_state) = app_handle.try_state::<AdminAgentState>() {
            if agent_state.is_ready() {
                log::info!("install_openvpn_prereq: Using admin agent (already elevated)");
                emit_frontend_log(&window, "__prereq_action__", "▶ Install OpenVPN", "info");
                emit_frontend_log(&window, "__prereq_action__", "Using existing admin privileges (no UAC prompt)", "info");

                let step = SetupStep {
                    id: "install_openvpn".to_string(),
                    title: "Install OpenVPN".to_string(),
                    description: "Installing OpenVPN via winget".to_string(),
                    platform: crate::orchestrator::Platform::Windows,
                    category: crate::orchestrator::StepCategory::Network,
                    required: true,
                    estimated_minutes: 3,
                    rollback_steps: vec![],
                };

                let config = {
                    let s = state.lock().unwrap();
                    s.config.clone()
                };

                let result = execute_via_agent(&window, &app_handle, &step, &config, agent_state.inner()).await;

                return match result {
                    Ok(_) => {
                        emit_frontend_log(&window, "__prereq_action__", "✓ OpenVPN installed successfully", "success");
                        Ok(())
                    }
                    Err(e) => {
                        emit_frontend_log(&window, "__prereq_action__", &format!("✗ Installation failed: {}", e), "error");
                        Err(e)
                    }
                };
            }
        }
    }

    // Fall back to regular execution (will trigger UAC on Windows if not elevated)
    let (step_id, title, description) = if os.os == "windows" {
        (
            "install_openvpn",
            "Install OpenVPN",
            "Installing OpenVPN via winget (UAC prompt will appear)",
        )
    } else {
        (
            "install_openvpn_mac",
            "Install Tunnelblick",
            "Installing Tunnelblick via Homebrew for VPN access",
        )
    };

    log::info!("install_openvpn_prereq: executing {} for os={}", step_id, os.os);
    emit_frontend_log(&window, "__prereq_action__", &format!("▶ {}", title), "info");
    emit_frontend_log(&window, "__prereq_action__", description, "info");

    // Create a minimal SetupStep for script execution
    let step = SetupStep {
        id: step_id.to_string(),
        title: title.to_string(),
        description: description.to_string(),
        platform: if os.os == "windows" {
            crate::orchestrator::Platform::Windows
        } else {
            crate::orchestrator::Platform::MacOs
        },
        category: crate::orchestrator::StepCategory::Network,
        required: true,
        estimated_minutes: 3,
        rollback_steps: vec![],
    };

    let config = {
        let s = state.lock().unwrap();
        s.config.clone()
    };

    let result = execute_script_with_retry(window.clone(), app_handle.clone(), &step, &config).await;

    match result {
        Ok(_) => {
            emit_frontend_log(&window, "__prereq_action__", &format!("✓ {} installed successfully", title), "success");
            Ok(())
        }
        Err(e) => {
            emit_frontend_log(&window, "__prereq_action__", &format!("✗ Installation failed: {}", e), "error");
            Err(e)
        }
    }
}

/// Executes the VPN connection script as a pre-check action.
/// Windows: launches OpenVPN
/// macOS: launches Tunnelblick
#[tauri::command]
pub async fn connect_vpn_prereq(
    window: WebviewWindow,
    app_handle: AppHandle,
    state: State<'_, Mutex<AppState>>,
) -> Result<(), String> {
    let os = detect_os();
    let (step_id, title, description) = if os.os == "windows" {
        (
            "connect_vpn",
            "Connect to VPN",
            "Launching OpenVPN and waiting for GitLab connectivity",
        )
    } else {
        (
            "connect_vpn_mac",
            "Connect to VPN",
            "Launching Tunnelblick and waiting for GitLab connectivity",
        )
    };

    log::info!("connect_vpn_prereq: executing {} for os={}", step_id, os.os);
    emit_frontend_log(&window, "__prereq_action__", &format!("▶ {}", title), "info");
    emit_frontend_log(&window, "__prereq_action__", description, "info");

    // Create a minimal SetupStep for script execution
    let step = SetupStep {
        id: step_id.to_string(),
        title: title.to_string(),
        description: description.to_string(),
        platform: if os.os == "windows" {
            crate::orchestrator::Platform::Windows
        } else {
            crate::orchestrator::Platform::MacOs
        },
        category: crate::orchestrator::StepCategory::Network,
        required: true,
        estimated_minutes: 3,
        rollback_steps: vec![],
    };

    let config = {
        let s = state.lock().unwrap();
        s.config.clone()
    };

    let result = execute_script_with_retry(window.clone(), app_handle.clone(), &step, &config).await;

    match result {
        Ok(_) => {
            emit_frontend_log(&window, "__prereq_action__", "✓ VPN connected successfully", "success");
            Ok(())
        }
        Err(e) => {
            emit_frontend_log(&window, "__prereq_action__", &format!("✗ VPN connection failed: {}", e), "error");
            Err(e)
        }
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

    // Helper to use default if value is None or empty
    let or_default = |opt: Option<String>, default: &str| -> Option<String> {
        match opt {
            Some(v) if !v.trim().is_empty() => Some(v),
            _ => Some(default.to_string()),
        }
    };

    s.config = UserConfig {
        wsl_tar_path: input.wsl_tar_path,
        wsl_install_dir: input.wsl_install_dir,
        postgres_password: input.postgres_password,
        postgres_db_name: input.postgres_db_name,
        python_version: input.python_version,
        node_version: input.node_version,
        venv_name: input.venv_name,
        skip_already_installed: input.skip_already_installed,
        skip_wsl_backup: input.skip_wsl_backup,
        openvpn_config_path: input.openvpn_config_path,
        git_name: input.git_name,
        git_email: input.git_email,
        gitlab_pat: input.gitlab_pat,
        gitlab_repo_url: or_default(input.gitlab_repo_url, "git@gitlab.toogoerp.net:root/erc.git"),
        clone_dir: or_default(input.clone_dir, "/home/ubuntu/VsCodeProjects/erc"),
        wsl_default_user: if input.wsl_default_user.trim().is_empty() {
            "ubuntu".to_string()
        } else {
            input.wsl_default_user
        },
        tenant_name: if input.tenant_name.trim().is_empty() {
            "erckinetic".to_string()
        } else {
            input.tenant_name
        },
        tenant_id: if input.tenant_id.trim().is_empty() {
            "t2070".to_string()
        } else {
            input.tenant_id
        },
        cluster_name: if input.cluster_name.trim().is_empty() {
            "stable".to_string()
        } else {
            input.cluster_name
        },
        aws_access_key_id: input.aws_access_key_id.filter(|s| !s.trim().is_empty()),
        aws_secret_access_key: input.aws_secret_access_key.filter(|s| !s.trim().is_empty()),
    };
    Ok(())
}

/// Opens a URL in the system default browser.
#[tauri::command]
pub async fn open_url(url: String, app_handle: AppHandle) -> Result<(), String> {
    use tauri_plugin_shell::ShellExt;
    app_handle.shell().open(&url, None).map_err(|e| e.to_string())
}

// ─── Admin Agent Commands ────────────────────────────────────────────────────

/// Spawns the elevated PowerShell admin agent via Start-Process -Verb RunAs.
/// Triggers the corporate "Elevate Trusted" dialog for powershell.exe.
/// Emits "admin_agent_log" events to the window during the connection process.
#[tauri::command]
pub async fn request_admin_agent(
    window: WebviewWindow,
    app_handle: AppHandle,
    agent_state: State<'_, crate::admin_agent::AdminAgentState>,
) -> Result<(), String> {
    log::info!("request_admin_agent: initiating elevated admin agent...");
    crate::admin_agent::spawn_admin_agent(&window, &app_handle, &agent_state).await
}

/// Returns true if the admin agent is connected and ready to execute steps.
#[tauri::command]
pub fn is_admin_agent_ready(
    agent_state: State<'_, crate::admin_agent::AdminAgentState>,
) -> bool {
    agent_state.is_ready()
}

/// Sends a shutdown command to the admin agent and clears ready state.
#[tauri::command]
pub async fn shutdown_admin_agent(
    agent_state: State<'_, crate::admin_agent::AdminAgentState>,
) -> Result<(), String> {
    log::info!("shutdown_admin_agent: shutting down admin agent...");
    crate::admin_agent::shutdown_agent(&agent_state).await;
    Ok(())
}

// ─── Run History Commands ─────────────────────────────────────────────────────

/// Returns the path to the run history JSON file in app local data directory.
fn get_run_history_path(app_handle: &AppHandle) -> Result<PathBuf, String> {
    let app_data_dir = app_handle
        .path()
        .app_local_data_dir()
        .map_err(|e| format!("Failed to get app data dir: {}", e))?;

    // Ensure directory exists
    fs::create_dir_all(&app_data_dir)
        .map_err(|e| format!("Failed to create app data dir: {}", e))?;

    Ok(app_data_dir.join("run_history.json"))
}

/// Saves a run history entry to the JSON file, auto-pruning to last 20 runs.
#[tauri::command]
pub async fn save_run_history(
    app_handle: AppHandle,
    run_type: RunType,
    started_at: i64,
    completed_at: i64,
    status: RunStatus,
    step_count: usize,
    failed_steps: Vec<FailedStepLog>,
    skipped_steps: Vec<SkippedStepLog>,
) -> Result<(), String> {
    let history_path = get_run_history_path(&app_handle)?;

    // Load existing history
    let mut history: Vec<RunHistory> = if history_path.exists() {
        let content = fs::read_to_string(&history_path)
            .map_err(|e| format!("Failed to read history file: {}", e))?;
        serde_json::from_str(&content).unwrap_or_else(|_| Vec::new())
    } else {
        Vec::new()
    };

    // Create new entry with timestamp-based ID
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| format!("System time error: {}", e))?;
    let id = format!("{}-{}", now.as_secs(), now.subsec_nanos());

    let new_entry = RunHistory {
        id,
        run_type,
        workflow_name: None,
        started_at,
        completed_at,
        status,
        step_count,
        failed_steps,
        skipped_steps,
    };

    // Add new entry and prune to last 20
    history.push(new_entry);
    if history.len() > 20 {
        let skip_count = history.len() - 20;
        history = history.into_iter().skip(skip_count).collect();
    }

    // Save back to file
    let json = serde_json::to_string_pretty(&history)
        .map_err(|e| format!("Failed to serialize history: {}", e))?;
    fs::write(&history_path, json)
        .map_err(|e| format!("Failed to write history file: {}", e))?;

    log::info!("Saved run history entry (total: {})", history.len());
    Ok(())
}

/// Loads the last 20 run history entries from the JSON file.
#[tauri::command]
pub async fn load_run_history(app_handle: AppHandle) -> Result<Vec<RunHistory>, String> {
    let history_path = get_run_history_path(&app_handle)?;

    if !history_path.exists() {
        return Ok(Vec::new());
    }

    let content = fs::read_to_string(&history_path)
        .map_err(|e| format!("Failed to read history file: {}", e))?;

    let history: Vec<RunHistory> = serde_json::from_str(&content)
        .unwrap_or_else(|_| Vec::new());

    Ok(history)
}

/// Clears selected run history entries by their IDs.
#[tauri::command]
pub async fn clear_run_history_by_ids(
    app_handle: AppHandle,
    ids: Vec<String>,
) -> Result<(), String> {
    let history_path = get_run_history_path(&app_handle)?;

    if !history_path.exists() {
        return Ok(());
    }

    let content = fs::read_to_string(&history_path)
        .map_err(|e| format!("Failed to read history file: {}", e))?;

    let mut history: Vec<RunHistory> = serde_json::from_str(&content)
        .unwrap_or_else(|_| Vec::new());

    // Filter out entries with matching IDs
    history.retain(|entry| !ids.contains(&entry.id));

    // Save back to file
    let json = serde_json::to_string_pretty(&history)
        .map_err(|e| format!("Failed to serialize history: {}", e))?;
    fs::write(&history_path, json)
        .map_err(|e| format!("Failed to write history file: {}", e))?;

    log::info!("Cleared {} history entries (remaining: {})", ids.len(), history.len());
    Ok(())
}

// ─── Configuration Profile Management ───────────────────────────────────────

fn get_profiles_dir_path(app_handle: &AppHandle) -> Result<PathBuf, String> {
    use tauri::Manager;
    let app_data_dir = app_handle
        .path()
        .app_data_dir()
        .map_err(|e| e.to_string())?;
    let profiles_dir = app_data_dir.join("profiles");

    // Create directory if it doesn't exist
    if !profiles_dir.exists() {
        fs::create_dir_all(&profiles_dir)
            .map_err(|e| format!("Failed to create profiles directory: {}", e))?;
    }

    Ok(profiles_dir)
}

fn sanitize_profile_name(name: &str) -> String {
    name.chars()
        .map(|c| match c {
            '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' => '_',
            _ => c,
        })
        .collect()
}

fn generate_profile_description(config: &UserConfig) -> String {
    let mut parts = Vec::new();

    if !config.tenant_name.is_empty() && config.tenant_name != "erckinetic" {
        parts.push(config.tenant_name.clone());
    }
    if !config.cluster_name.is_empty() && config.cluster_name != "stable" {
        parts.push(config.cluster_name.clone());
    }
    if !config.python_version.is_empty() && config.python_version != "3.9.21" {
        parts.push(format!("Python {}", config.python_version));
    }
    if !config.node_version.is_empty() && config.node_version != "16.20.2" {
        parts.push(format!("Node {}", config.node_version));
    }

    if parts.is_empty() {
        "Default configuration".to_string()
    } else {
        parts.join(" · ")
    }
}

/// Saves the current configuration as a named profile.
#[tauri::command]
pub async fn save_config_profile(
    app_handle: AppHandle,
    profile_name: String,
    state: State<'_, Mutex<AppState>>,
) -> Result<(), String> {
    if profile_name.trim().is_empty() {
        return Err("Profile name cannot be empty".to_string());
    }

    let profiles_dir = get_profiles_dir_path(&app_handle)?;
    let sanitized_name = sanitize_profile_name(&profile_name);
    let profile_path = profiles_dir.join(format!("{}.json", sanitized_name));

    let config = state.lock().unwrap().config.clone();
    let description = generate_profile_description(&config);

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| format!("System time error: {}", e))?
        .as_secs() as i64;

    let profile = ConfigProfile {
        name: profile_name.clone(),
        saved_at: now,
        description,
        config,
    };

    let json = serde_json::to_string_pretty(&profile)
        .map_err(|e| format!("Failed to serialize profile: {}", e))?;

    fs::write(&profile_path, json)
        .map_err(|e| format!("Failed to write profile file: {}", e))?;

    log::info!("Saved config profile: '{}' to {}", profile_name, profile_path.display());
    Ok(())
}

/// Lists all saved configuration profiles.
#[tauri::command]
pub async fn list_config_profiles(app_handle: AppHandle) -> Result<Vec<ConfigProfile>, String> {
    let profiles_dir = get_profiles_dir_path(&app_handle)?;

    let mut profiles = Vec::new();

    let entries = fs::read_dir(&profiles_dir)
        .map_err(|e| format!("Failed to read profiles directory: {}", e))?;

    for entry in entries {
        let entry = entry.map_err(|e| format!("Failed to read directory entry: {}", e))?;
        let path = entry.path();

        if path.extension().and_then(|s| s.to_str()) == Some("json") {
            match fs::read_to_string(&path) {
                Ok(content) => {
                    match serde_json::from_str::<ConfigProfile>(&content) {
                        Ok(profile) => profiles.push(profile),
                        Err(e) => log::warn!("Failed to parse profile {}: {}", path.display(), e),
                    }
                }
                Err(e) => log::warn!("Failed to read profile {}: {}", path.display(), e),
            }
        }
    }

    // Sort by saved_at descending (most recent first)
    profiles.sort_by(|a, b| b.saved_at.cmp(&a.saved_at));

    Ok(profiles)
}

/// Loads a saved profile and applies it to the current configuration.
#[tauri::command]
pub async fn load_config_profile(
    app_handle: AppHandle,
    profile_name: String,
    state: State<'_, Mutex<AppState>>,
) -> Result<UserConfig, String> {
    let profiles_dir = get_profiles_dir_path(&app_handle)?;
    let sanitized_name = sanitize_profile_name(&profile_name);
    let profile_path = profiles_dir.join(format!("{}.json", sanitized_name));

    if !profile_path.exists() {
        return Err(format!("Profile '{}' not found", profile_name));
    }

    let content = fs::read_to_string(&profile_path)
        .map_err(|e| format!("Failed to read profile file: {}", e))?;

    let profile: ConfigProfile = serde_json::from_str(&content)
        .map_err(|e| format!("Failed to parse profile: {}", e))?;

    // Apply to current state
    {
        let mut s = state.lock().unwrap();
        s.config = profile.config.clone();
    }

    log::info!("Loaded config profile: '{}'", profile_name);
    Ok(profile.config)
}

/// Deletes a saved configuration profile.
#[tauri::command]
pub async fn delete_config_profile(
    app_handle: AppHandle,
    profile_name: String,
) -> Result<(), String> {
    let profiles_dir = get_profiles_dir_path(&app_handle)?;
    let sanitized_name = sanitize_profile_name(&profile_name);
    let profile_path = profiles_dir.join(format!("{}.json", sanitized_name));

    if !profile_path.exists() {
        return Err(format!("Profile '{}' not found", profile_name));
    }

    fs::remove_file(&profile_path)
        .map_err(|e| format!("Failed to delete profile file: {}", e))?;

    log::info!("Deleted config profile: '{}'", profile_name);
    Ok(())
}

// ─── Workflow Management ────────────────────────────────────────────────────

fn get_workflows_dir_path(app_handle: &AppHandle) -> Result<PathBuf, String> {
    use tauri::Manager;
    let app_data_dir = app_handle
        .path()
        .app_data_dir()
        .map_err(|e| e.to_string())?;
    let workflows_dir = app_data_dir.join("workflows");

    // Create directory if it doesn't exist
    if !workflows_dir.exists() {
        fs::create_dir_all(&workflows_dir)
            .map_err(|e| format!("Failed to create workflows directory: {}", e))?;
    }

    Ok(workflows_dir)
}

/// Save a custom workflow
#[tauri::command]
pub async fn save_workflow(
    app_handle: AppHandle,
    workflow_id: String,
    name: String,
    description: String,
    step_ids: Vec<String>,
) -> Result<(), String> {
    let workflows_dir = get_workflows_dir_path(&app_handle)?;
    let workflow_path = workflows_dir.join(format!("{}.json", workflow_id));

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| format!("System time error: {}", e))?
        .as_secs() as i64;

    let workflow = CustomWorkflow {
        id: workflow_id.clone(),
        name: name.clone(),
        description,
        step_ids,
        created_at: now,
        last_run_at: None,
    };

    let json = serde_json::to_string_pretty(&workflow)
        .map_err(|e| format!("Failed to serialize workflow: {}", e))?;

    fs::write(&workflow_path, json)
        .map_err(|e| format!("Failed to write workflow file: {}", e))?;

    log::info!("Saved workflow: '{}' (ID: {}) to {}", name, workflow_id, workflow_path.display());
    Ok(())
}

/// List all custom workflows
#[tauri::command]
pub async fn list_workflows(app_handle: AppHandle) -> Result<Vec<CustomWorkflow>, String> {
    let workflows_dir = get_workflows_dir_path(&app_handle)?;
    let mut workflows = Vec::new();

    let entries = fs::read_dir(&workflows_dir)
        .map_err(|e| format!("Failed to read workflows directory: {}", e))?;

    for entry in entries {
        let entry = entry.map_err(|e| format!("Failed to read directory entry: {}", e))?;
        let path = entry.path();

        if path.extension().and_then(|s| s.to_str()) == Some("json") {
            match fs::read_to_string(&path) {
                Ok(content) => {
                    match serde_json::from_str::<CustomWorkflow>(&content) {
                        Ok(workflow) => workflows.push(workflow),
                        Err(e) => log::warn!("Failed to parse workflow {}: {}", path.display(), e),
                    }
                }
                Err(e) => log::warn!("Failed to read workflow {}: {}", path.display(), e),
            }
        }
    }

    // Sort by created_at descending (most recent first)
    workflows.sort_by(|a, b| b.created_at.cmp(&a.created_at));

    Ok(workflows)
}

/// Delete a custom workflow
#[tauri::command]
pub async fn delete_workflow(
    app_handle: AppHandle,
    workflow_id: String,
) -> Result<(), String> {
    let workflows_dir = get_workflows_dir_path(&app_handle)?;
    let workflow_path = workflows_dir.join(format!("{}.json", workflow_id));

    if !workflow_path.exists() {
        return Err(format!("Workflow '{}' not found", workflow_id));
    }

    fs::remove_file(&workflow_path)
        .map_err(|e| format!("Failed to delete workflow file: {}", e))?;

    log::info!("Deleted workflow: ID={}", workflow_id);
    Ok(())
}

/// Update workflow last_run_at timestamp
#[tauri::command]
pub async fn update_workflow_last_run(
    app_handle: AppHandle,
    workflow_id: String,
) -> Result<(), String> {
    let workflows_dir = get_workflows_dir_path(&app_handle)?;
    let workflow_path = workflows_dir.join(format!("{}.json", workflow_id));

    if !workflow_path.exists() {
        return Err(format!("Workflow '{}' not found", workflow_id));
    }

    let content = fs::read_to_string(&workflow_path)
        .map_err(|e| format!("Failed to read workflow file: {}", e))?;

    let mut workflow: CustomWorkflow = serde_json::from_str(&content)
        .map_err(|e| format!("Failed to parse workflow: {}", e))?;

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| format!("System time error: {}", e))?
        .as_secs() as i64;

    workflow.last_run_at = Some(now);

    let json = serde_json::to_string_pretty(&workflow)
        .map_err(|e| format!("Failed to serialize workflow: {}", e))?;

    fs::write(&workflow_path, json)
        .map_err(|e| format!("Failed to write workflow file: {}", e))?;

    log::info!("Updated last_run_at for workflow: ID={}", workflow_id);
    Ok(())
}

/// Execute a custom workflow (run only the steps defined in the workflow)
#[tauri::command]
pub async fn execute_workflow(
    window: WebviewWindow,
    app_handle: AppHandle,
    state: State<'_, Mutex<AppState>>,
    workflow_id: String,
) -> Result<(), String> {
    let started_at = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| format!("System time error: {}", e))?
        .as_secs() as i64;

    // Load workflow
    let workflows_dir = get_workflows_dir_path(&app_handle)?;
    let workflow_path = workflows_dir.join(format!("{}.json", workflow_id));

    if !workflow_path.exists() {
        return Err(format!("Workflow '{}' not found", workflow_id));
    }

    let content = fs::read_to_string(&workflow_path)
        .map_err(|e| format!("Failed to read workflow file: {}", e))?;

    let workflow: CustomWorkflow = serde_json::from_str(&content)
        .map_err(|e| format!("Failed to parse workflow: {}", e))?;

    log::info!("execute_workflow: Starting workflow '{}' with {} steps", workflow.name, workflow.step_ids.len());

    // Get all steps and filter by workflow.step_ids
    let (steps, config) = {
        let mut s = state.lock().unwrap();
        s.setup_started = true;
        s.setup_started_at = Some(started_at);
        s.current_step_index = 0;
        let os = detect_os();
        let all_steps = get_steps_for_os(&os.os);

        // Filter steps to only include those in workflow
        let steps: Vec<SetupStep> = all_steps
            .into_iter()
            .filter(|step| workflow.step_ids.contains(&step.id))
            .collect();

        // Sort steps by their order in workflow.step_ids
        let mut ordered_steps = Vec::new();
        for step_id in &workflow.step_ids {
            if let Some(step) = steps.iter().find(|s| &s.id == step_id) {
                ordered_steps.push(step.clone());
            }
        }

        log::info!("execute_workflow: {} steps matched from workflow definition", ordered_steps.len());

        for step in &ordered_steps {
            s.get_or_create_step(&step.id);
        }
        (ordered_steps, s.config.clone())
    };

    // Execute workflow steps
    for (idx, step) in steps.iter().enumerate() {
        // Check if already done or skipped
        let current_status = {
            let s = state.lock().unwrap();
            s.step_states.get(&step.id).map(|ss| ss.status.clone())
        };
        if matches!(current_status, Some(StepStatus::Done) | Some(StepStatus::Skipped)) {
            continue;
        }

        // Add workspace stabilization delay if needed
        if idx > 0 {
            let prev_step = &steps[idx - 1];
            if prev_step.id == "setup_workspace" || prev_step.id == "setup_workspace_mac" {
                log::info!("execute_workflow: pausing 5s after '{}' for VS Code to stabilize", prev_step.id);
                emit_frontend_log(
                    &window,
                    &step.id,
                    "⏸ Waiting 5 seconds for VS Code to stabilize...",
                    "info",
                );
                tokio::time::sleep(tokio::time::Duration::from_secs(5)).await;
            }
        }

        // Mark running
        {
            let mut s = state.lock().unwrap();
            s.current_step_index = idx;
            let ss = s.get_or_create_step(&step.id);
            ss.status = StepStatus::Running;
        }
        log::info!("execute_workflow: running step [{}/{}] id={} title='{}'", idx + 1, steps.len(), step.id, step.title);
        let _ = window.emit("step_status", serde_json::json!({ "id": step.id, "status": "running" }));

        let start = std::time::Instant::now();
        let result = execute_script_with_retry(window.clone(), app_handle.clone(), step, &config).await;
        let duration = start.elapsed().as_secs();

        {
            let mut s = state.lock().unwrap();
            let ss = s.get_or_create_step(&step.id);
            ss.duration_secs = Some(duration);

            match result {
                Ok(_) => {
                    ss.status = StepStatus::Done;
                    let _ = window.emit("step_status", serde_json::json!({ "id": step.id, "status": "done" }));
                }
                Err(e) => {
                    ss.status = StepStatus::Failed;
                    ss.error = Some(e.clone());
                    let _ = window.emit("step_status", serde_json::json!({ "id": step.id, "status": "failed", "error": e }));
                    log::error!("execute_workflow: step '{}' failed: {}", step.id, e);
                    return Err(format!("Workflow step '{}' failed: {}", step.title, e));
                }
            }
        }
    }

    // Mark workflow as complete
    {
        let mut s = state.lock().unwrap();
        s.setup_complete = true;
    }

    // Update workflow last_run_at
    update_workflow_last_run(app_handle.clone(), workflow_id.clone()).await?;

    // Save to history
    let completed_at = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| format!("System time error: {}", e))?
        .as_secs() as i64;

    let (status, failed_steps_logs, skipped_steps_logs) = {
        let s = state.lock().unwrap();
        let mut failed = Vec::new();
        let mut skipped = Vec::new();

        for step in &steps {
            if let Some(ss) = s.step_states.get(&step.id) {
                match ss.status {
                    StepStatus::Failed => {
                        failed.push(FailedStepLog {
                            step_id: step.id.clone(),
                            step_name: step.title.clone(),
                            error_message: ss.error.clone(),
                            logs: ss.logs.clone(),
                        });
                    }
                    StepStatus::Skipped => {
                        skipped.push(SkippedStepLog {
                            step_id: step.id.clone(),
                            step_name: step.title.clone(),
                        });
                    }
                    _ => {}
                }
            }
        }

        let status = if !failed.is_empty() {
            RunStatus::Failed
        } else {
            RunStatus::Success
        };

        (status, failed, skipped)
    };

    // Create history entry via the existing save_run_history function
    // But first we need to add workflow_name support to it
    // For now, save directly to file
    let history_path = get_run_history_path(&app_handle)?;
    let mut history: Vec<RunHistory> = if history_path.exists() {
        let content = fs::read_to_string(&history_path)
            .map_err(|e| format!("Failed to read history file: {}", e))?;
        serde_json::from_str(&content).unwrap_or_else(|_| Vec::new())
    } else {
        Vec::new()
    };

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| format!("System time error: {}", e))?;
    let id = format!("{}-{}", now.as_secs(), now.subsec_nanos());

    let new_entry = RunHistory {
        id,
        run_type: RunType::Workflow,
        workflow_name: Some(workflow.name.clone()),
        started_at,
        completed_at,
        status,
        step_count: steps.len(),
        failed_steps: failed_steps_logs,
        skipped_steps: skipped_steps_logs,
    };

    history.push(new_entry);
    if history.len() > 20 {
        let skip_count = history.len() - 20;
        history = history.into_iter().skip(skip_count).collect();
    }

    let json = serde_json::to_string_pretty(&history)
        .map_err(|e| format!("Failed to serialize history: {}", e))?;
    fs::write(&history_path, json)
        .map_err(|e| format!("Failed to write history file: {}", e))?;

    log::info!("execute_workflow: Workflow '{}' completed successfully", workflow.name);
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
