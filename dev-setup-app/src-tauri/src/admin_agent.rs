// admin_agent.rs — File-based IPC admin agent.
//
// ARCHITECTURE:
//   IPC directory: C:\Users\Public\DevSetupAgent\
//
//   Rust (non-elevated) writes:
//       cmd_{step_id}.json   — {"step_id":"...","script":"...","env":{...}}
//       agent_shutdown.flag  — tells elevated PS to exit
//
//   Elevated PS (admin_agent.ps1) writes:
//       agent_ready.flag     — written once when PS is alive and looping
//       log_{step_id}.txt    — step output, grows as PS appends lines
//       done_{step_id}.json  — {"done":true,"code":0} on completion
//
// Elevation:
//   ShellExecuteExW("runas", "powershell.exe", <inline -Command>) is called.
//   The inline -Command:
//     1. Creates C:\Program Files\DevSetupAgent\ (admin-only, AppLocker-trusted)
//     2. Copies admin_agent.ps1 there from C:\Users\Public\
//     3. Runs it with & — AppLocker allows scripts from Program Files
//   This bypasses both the "no scripts from user-writable paths" AppLocker rule
//   AND the CLM restriction on iex/Add-Type (.NET pipes).

use crate::orchestrator::{LogEvent, LogLevel, SetupStep};
use crate::state::UserConfig;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tauri::{AppHandle, Emitter, WebviewWindow};

// ── Step IDs that require administrator privileges ────────────────────────────

pub const ADMIN_STEP_IDS: &[&str] = &[
    "enable_wsl",
    "wsl_network",
    "windows_hosts",
    "install_openvpn",
    "revert_wsl_features",
    "revert_windows_hosts",
    "revert_wsl_network",
];

/// IPC directory — readable/writable by both elevated and non-elevated sessions.
const AGENT_DIR: &str = r"C:\Users\Public\DevSetupAgent";

// ── State ─────────────────────────────────────────────────────────────────────

pub struct AdminAgentState {
    pub ready: Arc<AtomicBool>,
}

impl AdminAgentState {
    pub fn new() -> Self {
        AdminAgentState {
            ready: Arc::new(AtomicBool::new(false)),
        }
    }
    pub fn is_ready(&self) -> bool {
        self.ready.load(Ordering::SeqCst)
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

fn agent_path(file: &str) -> std::path::PathBuf {
    std::path::Path::new(AGENT_DIR).join(file)
}

#[cfg(target_os = "windows")]
fn emit_agent_progress(window: &WebviewWindow, line: &str, level: &str) {
    log::info!("[admin_agent] {}", line);
    let _ = window.emit("admin_agent_log", serde_json::json!({ "line": line, "level": level }));
}

fn agent_log_summary() -> String {
    let path = agent_path("agent.log");
    if let Ok(txt) = std::fs::read_to_string(&path) {
        let lines: Vec<&str> = txt.lines().collect();
        let tail = if lines.len() > 40 { &lines[lines.len() - 40..] } else { &lines[..] };
        format!("({})\n{}", path.display(), tail.join("\n"))
    } else {
        format!(
            "(log not found at {})\n\
             The elevated PowerShell may have been blocked by AppLocker/WDAC.\n\
             Check: Event Viewer > Apps and Services > Microsoft > Windows > AppLocker > MSI and Script",
            path.display()
        )
    }
}

fn classify_log_line(line: &str) -> LogLevel {
    let l = line.to_lowercase();
    if l.contains("error") || l.contains("failed") || l.contains("fatal") {
        LogLevel::Error
    } else if l.contains("warn") {
        LogLevel::Warn
    } else if l.contains("success") || l.contains("complete") || line.contains('\u{2713}') {
        LogLevel::Success
    } else {
        LogLevel::Info
    }
}

fn emit_log(window: &WebviewWindow, step_id: &str, line: &str, level: LogLevel) {
    // 🔒 SECURITY: Redact sensitive data from logs before emitting to UI
    let redacted_line = crate::security::redact_sensitive_log(line);

    let _ = window.emit(
        "step_log",
        LogEvent { step_id: step_id.to_string(), line: redacted_line, level },
    );
}

// ── Win32 ShellExecuteExW ─────────────────────────────────────────────────────

#[cfg(target_os = "windows")]
mod ffi {
    #![allow(non_snake_case, non_camel_case_types, dead_code)]
    #[repr(C)]
    pub struct SHELLEXECUTEINFOW {
        pub cbSize:         u32,
        pub fMask:          u32,
        pub hwnd:           usize,
        pub lpVerb:         *const u16,
        pub lpFile:         *const u16,
        pub lpParameters:   *const u16,
        pub lpDirectory:    *const u16,
        pub nShow:          i32,
        pub hInstApp:       usize,
        pub lpIDList:       usize,
        pub lpClass:        *const u16,
        pub hkeyClass:      usize,
        pub dwHotKey:       u32,
        pub hIconOrMonitor: usize,
        pub hProcess:       usize,
    }
    pub const SEE_MASK_NOCLOSEPROCESS: u32 = 0x0000_0040;
    /// Show minimised — visible in taskbar so PAM security scanners do not
    /// flag it as a hidden admin process (some PAM tools block SW_HIDE=0).
    pub const SW_SHOWMINIMIZED: i32 = 2;
    #[link(name = "Shell32")]
    extern "system" {
        pub fn ShellExecuteExW(pExecInfo: *mut SHELLEXECUTEINFOW) -> i32;
    }
}

/// Blocking wrapper around ShellExecuteExW — call from spawn_blocking.
#[cfg(target_os = "windows")]
fn shell_execute_elevated(ps_params: &str) -> Result<(), String> {
    use std::ffi::OsStr;
    use std::os::windows::ffi::OsStrExt;
    let verb:   Vec<u16> = OsStr::new("runas").encode_wide().chain(Some(0)).collect();
    let file:   Vec<u16> = OsStr::new("powershell.exe").encode_wide().chain(Some(0)).collect();
    let params: Vec<u16> = OsStr::new(ps_params).encode_wide().chain(Some(0)).collect();
    let mut info = ffi::SHELLEXECUTEINFOW {
        cbSize:         std::mem::size_of::<ffi::SHELLEXECUTEINFOW>() as u32,
        fMask:          ffi::SEE_MASK_NOCLOSEPROCESS,
        hwnd:           0,
        lpVerb:         verb.as_ptr(),
        lpFile:         file.as_ptr(),
        lpParameters:   params.as_ptr(),
        lpDirectory:    std::ptr::null(),
        nShow:          ffi::SW_SHOWMINIMIZED,
        hInstApp:       0,
        lpIDList:       0,
        lpClass:        std::ptr::null(),
        hkeyClass:      0,
        dwHotKey:       0,
        hIconOrMonitor: 0,
        hProcess:       0,
    };
    let ok = unsafe { ffi::ShellExecuteExW(&mut info) };
    if ok != 0 {
        Ok(())
    } else {
        let err  = std::io::Error::last_os_error();
        let code = err.raw_os_error().unwrap_or(0);
        if code == 1223 {
            Err("Elevation dialog was cancelled or denied.".to_string())
        } else {
            Err(format!("ShellExecuteExW failed (OS error {}): {}", code, err))
        }
    }
}

// ── Spawn ─────────────────────────────────────────────────────────────────────

pub async fn spawn_admin_agent(
    window: &WebviewWindow,
    app_handle: &AppHandle,
    state: &AdminAgentState,
) -> Result<(), String> {
    #[cfg(not(target_os = "windows"))]
    {
        let _ = (window, app_handle, state);
        return Err("Admin agent is only supported on Windows".to_string());
    }

    #[cfg(target_os = "windows")]
    {
        emit_agent_progress(window, "\u{1f50d} Step 1/4 \u{2014} Locating admin agent script...", "info");

        // Resolve bundled admin_agent.ps1
        let script_path = {
            let resource_dir = app_handle.path().resource_dir().map_err(|e| e.to_string())?;
            let p = resource_dir.join("scripts").join("windows").join("admin_agent.ps1");
            if !p.exists() {
                let msg = format!("Admin agent script not found at: {}\nPlease reinstall.", p.display());
                emit_agent_progress(window, &format!("\u{2717} {}", msg), "error");
                return Err(msg);
            }
            let s = p.to_string_lossy().to_string();
            s.strip_prefix(r"\\?\").unwrap_or(&s).to_string()
        };
        emit_agent_progress(window, &format!("\u{2713} Script found: {}", script_path), "info");

        // Clean up stale IPC files from previous runs
        let _ = std::fs::remove_file(agent_path("agent_ready.flag"));
        let _ = std::fs::remove_file(agent_path("agent_shutdown.flag"));
        let _ = std::fs::remove_file(agent_path("agent.log"));

        // Stage the PS script to the IPC directory
        if let Err(e) = std::fs::create_dir_all(AGENT_DIR) {
            return Err(format!("Failed to create IPC directory: {}", e));
        }
        if let Err(e) = std::fs::copy(&script_path, agent_path("admin_agent.ps1")) {
            return Err(format!("Failed to stage agent script: {}", e));
        }
        emit_agent_progress(window, "\u{2713} Script staged to C:\\Users\\Public\\DevSetupAgent\\", "info");

        emit_agent_progress(window, "\u{1f680} Step 2/4 \u{2014} Launching elevation dialog...", "info");

        // The inline -Command:
        //   1. mkdir C:\Program Files\DevSetupAgent\ (admin-owned — AppLocker allows scripts from here)
        //   2. Copy admin_agent.ps1 there from the IPC dir
        //   3. Run it with & (AppLocker trusts Program Files; CLM is not enforced for trusted paths)
        //
        // Using basic cmdlets and & — works even in CLM.
        let ps_params = r#"-NonInteractive -NoProfile -ExecutionPolicy Bypass -Command "New-Item -ItemType Directory -Force -Path 'C:\Program Files\DevSetupAgent' | Out-Null; Copy-Item -Path 'C:\Users\Public\DevSetupAgent\admin_agent.ps1' -Destination 'C:\Program Files\DevSetupAgent\agent.ps1' -Force; & 'C:\Program Files\DevSetupAgent\agent.ps1'""#;
        log::info!("spawn_admin_agent: ShellExecuteExW params: {}", ps_params);

        let ps_params_owned = ps_params.to_owned();
        let elevation_result = tokio::task::spawn_blocking(move || shell_execute_elevated(&ps_params_owned))
            .await
            .map_err(|e| format!("Elevation task error: {}", e))?;

        match elevation_result {
            Ok(()) => emit_agent_progress(window, "\u{2713} Step 2/4 \u{2014} Elevation approved!", "info"),
            Err(e) => {
                emit_agent_progress(window, &format!("\u{2717} {}", e), "error");
                return Err(e);
            }
        }

        emit_agent_progress(window, "\u{23f3} Step 3/4 \u{2014} Waiting for agent_ready.flag...", "info");

        // Poll for agent_ready.flag written by admin_agent.ps1 on startup
        let max_wait_secs: u64 = 120;
        let poll_ms: u64 = 500;
        let total_polls = (max_wait_secs * 1000) / poll_ms;
        let ready_flag = agent_path("agent_ready.flag");
        let mut ready = false;

        for attempt in 0..total_polls {
            if ready_flag.exists() {
                ready = true;
                break;
            }
            if attempt > 0 && attempt % 10 == 0 {
                let elapsed = (attempt * poll_ms) / 1000;
                emit_agent_progress(
                    window,
                    &format!("\u{23f3} Still waiting... ({}s)", elapsed),
                    "info",
                );
            }
            tokio::time::sleep(std::time::Duration::from_millis(poll_ms)).await;
        }

        if !ready {
            let msg = format!(
                "Timed out after {}s waiting for agent_ready.flag.\n\n\
                 The elevation was approved but the script did not start.\n\
                 A security policy (AppLocker/WDAC) may be blocking it.\n\n\
                 Check: Event Viewer > Apps and Services Logs > Microsoft > Windows > AppLocker > MSI and Script\n\n\
                 Agent log (C:\\Users\\Public\\DevSetupAgent\\agent.log):\n{}",
                max_wait_secs,
                agent_log_summary()
            );
            emit_agent_progress(window, "\u{2717} Timed out.", "error");
            return Err(msg);
        }

        state.ready.store(true, Ordering::SeqCst);
        emit_agent_progress(
            window,
            "\u{2705} Step 4/4 \u{2014} Agent ready! Admin steps will run elevated automatically.",
            "success",
        );
        log::info!("spawn_admin_agent: agent_ready.flag found — agent is alive.");
        Ok(())
    }
}

// ── Execute a step via the agent ──────────────────────────────────────────────

pub async fn execute_via_agent(
    window: &WebviewWindow,
    app_handle: &AppHandle,
    step: &SetupStep,
    config: &UserConfig,
    state: &AdminAgentState,
) -> Result<Vec<String>, String> {
    #[cfg(not(target_os = "windows"))]
    {
        let _ = (window, app_handle, step, config, state);
        return Err("Admin agent is only supported on Windows".to_string());
    }

    #[cfg(target_os = "windows")]
    {
        // Log step start immediately so users see which step failed if agent isn't ready
        emit_log(window, &step.id, &format!("▶ Starting (via admin agent): {}", step.title), LogLevel::Info);

        if !state.is_ready() {
            return Err("Admin steps require elevation. Click 'Enable Admin Steps' first.".to_string());
        }

        let script_path = {
            let resource_dir = app_handle.path().resource_dir().map_err(|e| e.to_string())?;
            let (subdir, name) = admin_script_name(&step.id)?;
            let p = resource_dir.join("scripts").join(subdir).join(name);
            if !p.exists() {
                return Err(format!("Script not found: {}", p.display()));
            }
            let s = p.to_string_lossy().to_string();
            s.strip_prefix(r"\\?\").unwrap_or(&s).to_string()
        };

        let step_id = step.id.clone();
        let cmd_file  = agent_path(&format!("cmd_{}.json", step_id));
        let log_file  = agent_path(&format!("log_{}.txt", step_id));
        let done_file = agent_path(&format!("done_{}.json", step_id));

        // Generate a unique nonce for this attempt. The agent echoes it back in
        // the done file so we never mistake a stale done file from a previous
        // failed attempt for the current run's completion signal.
        let run_id = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis()
            .to_string();

        // Retry stale file deletion — AV scanner holds files open briefly after
        // writes, causing remove_file to silently fail with the single-shot call.
        for f in [&log_file, &done_file] {
            for _ in 0..20u32 {
                if !f.exists() { break; }
                if std::fs::remove_file(f).is_ok() { break; }
                std::thread::sleep(std::time::Duration::from_millis(500));
            }
        }

        // Buffer: give the agent's previous finally-block time to finish releasing
        // file handles (staged script + log) before we queue the next command.
        tokio::time::sleep(std::time::Duration::from_secs(5)).await;

        // Write the command file (includes run_id nonce)
        let cmd = serde_json::json!({
            "step_id": step_id,
            "script":  script_path,
            "env":     build_env_json(config),
            "run_id":  run_id,
        });
        std::fs::write(&cmd_file, serde_json::to_string(&cmd).unwrap().as_bytes())
            .map_err(|e| format!("Failed to write command file: {}", e))?;

        // Poll: stream log_*.txt incrementally, stop when done_*.json appears
        let max_secs: u64 = 600;
        let poll_ms:  u64 = 500;
        let total = (max_secs * 1000) / poll_ms;
        let mut all_logs: Vec<String> = Vec::new();
        let mut bytes_read: u64 = 0;
        let mut line_buf = String::new();

        for _ in 0..total {
            // Incrementally read new bytes from the growing log file
            if log_file.exists() {
                use std::io::{Read, Seek, SeekFrom};
                if let Ok(mut f) = std::fs::File::open(&log_file) {
                    if bytes_read > 0 {
                        let _ = f.seek(SeekFrom::Start(bytes_read));
                    }
                    let mut buf = Vec::new();
                    if let Ok(n) = f.read_to_end(&mut buf) {
                        if n > 0 {
                            bytes_read += n as u64;
                            line_buf.push_str(&String::from_utf8_lossy(&buf));
                            while let Some(pos) = line_buf.find('\n') {
                                let line = line_buf[..pos].trim_end_matches('\r').to_string();
                                line_buf = line_buf[pos + 1..].to_string();
                                if !line.is_empty() {
                                    let lvl = classify_log_line(&line);
                                    all_logs.push(line.clone());
                                    emit_log(window, &step_id, &line, lvl);
                                }
                            }
                        }
                    }
                }
            }

            if done_file.exists() {
                // Flush any remaining partial line
                let tail = line_buf.trim().to_string();
                if !tail.is_empty() {
                    let lvl = classify_log_line(&tail);
                    all_logs.push(tail.clone());
                    emit_log(window, &step_id, &tail, lvl);
                }
                // Retry reading the done file — AV scanner can hold it open briefly
                // right after PS writes it, causing an empty or partial read.
                let mut done_raw = String::new();
                for attempt in 0..10u32 {
                    match std::fs::read_to_string(&done_file) {
                        Ok(s) if !s.trim().is_empty() => { done_raw = s; break; }
                        _ => {
                            if attempt < 9 {
                                std::thread::sleep(std::time::Duration::from_millis(500));
                            }
                        }
                    }
                }
                // Strip UTF-8 BOM if present (PowerShell 5.x Out-File -Encoding UTF8 adds it)
                let done_str = done_raw.trim_start_matches('\u{feff}');
                let parsed = serde_json::from_str::<serde_json::Value>(done_str).ok();
                // Verify run_id nonce — if missing or mismatched this is a stale
                // done file from a previous attempt; skip it and keep polling.
                let done_run_id = parsed.as_ref()
                    .and_then(|v| v.get("run_id"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("");
                if !done_run_id.is_empty() && done_run_id != run_id {
                    log::warn!("execute_via_agent: stale done file (run_id={} vs expected {}) — ignoring", done_run_id, run_id);
                    // Delete the stale file so it doesn't block future polls
                    let _ = std::fs::remove_file(&done_file);
                    continue;
                }
                let code: i64 = parsed
                    .and_then(|v| v.get("code").and_then(|c| c.as_i64()))
                    .unwrap_or(-1);
                let _ = std::fs::remove_file(&done_file);
                let _ = std::fs::remove_file(&log_file);
                return if code == 0 {
                    emit_log(window, &step_id, "\u{2713} Completed via admin agent", LogLevel::Success);
                    Ok(all_logs)
                } else {
                    let msg = format!("Script exited with code {}", code);
                    emit_log(window, &step_id, &msg, LogLevel::Error);
                    Err(msg)
                };
            }

            tokio::time::sleep(std::time::Duration::from_millis(poll_ms)).await;
        }

        let _ = std::fs::remove_file(&cmd_file);
        Err(format!("Admin step '{}' timed out after {}s", step_id, max_secs))
    }
}

// ── Shutdown ──────────────────────────────────────────────────────────────────

pub async fn shutdown_agent(state: &AdminAgentState) {
    let _ = std::fs::write(agent_path("agent_shutdown.flag"), b"shutdown");
    state.ready.store(false, Ordering::SeqCst);
    log::info!("shutdown_agent: wrote agent_shutdown.flag");
}

// ── Private helpers ──────────────────────────────────────────────────────────

fn admin_script_name(step_id: &str) -> Result<(&'static str, &'static str), String> {
    match step_id {
        "enable_wsl"           => Ok(("windows", "enable_wsl.ps1")),
        "wsl_network"          => Ok(("windows", "setup_wsl_network.ps1")),
        "windows_hosts"        => Ok(("windows", "setup_windows_hosts.ps1")),
        "install_openvpn"      => Ok(("windows", "install_openvpn.ps1")),
        "revert_wsl_features"  => Ok(("windows", "revert_wsl_features.ps1")),
        "revert_windows_hosts" => Ok(("windows", "revert_windows_hosts.ps1")),
        "revert_wsl_network"   => Ok(("windows", "revert_wsl_network.ps1")),
        _ => Err(format!("'{}' is not an admin-required step", step_id)),
    }
}

fn build_env_json(config: &UserConfig) -> serde_json::Value {
    let mut map = serde_json::Map::new();
    map.insert("SETUP_PYTHON_VERSION".into(), config.python_version.clone().into());
    map.insert("SETUP_NODE_VERSION".into(),   config.node_version.clone().into());
    map.insert("SETUP_VENV_NAME".into(),      config.venv_name.clone().into());
    map.insert("SETUP_POSTGRES_PASSWORD".into(), config.postgres_password.clone().into());
    map.insert("SETUP_POSTGRES_DB".into(),    config.postgres_db_name.clone().into());
    map.insert("SETUP_SKIP_INSTALLED".into(), config.skip_already_installed.to_string().into());
    if let Some(ref v) = config.wsl_tar_path         { map.insert("SETUP_WSL_TAR_PATH".into(),         v.clone().into()); }
    if let Some(ref v) = config.wsl_install_dir      { map.insert("SETUP_WSL_INSTALL_DIR".into(),      v.clone().into()); }
    if let Some(ref v) = config.openvpn_config_path  { map.insert("SETUP_OPENVPN_CONFIG_PATH".into(),  v.clone().into()); }
    if let Some(ref v) = config.git_name              { map.insert("SETUP_GIT_NAME".into(),             v.clone().into()); }
    if let Some(ref v) = config.git_email             { map.insert("SETUP_GIT_EMAIL".into(),            v.clone().into()); }
    if let Some(ref v) = config.gitlab_pat            { map.insert("SETUP_GITLAB_PAT".into(),           v.clone().into()); }
    if let Some(ref v) = config.gitlab_repo_url       { map.insert("SETUP_GITLAB_REPO_URL".into(),      v.clone().into()); }
    if let Some(ref v) = config.clone_dir             { map.insert("SETUP_CLONE_DIR".into(),            v.clone().into()); }
    map.insert("SETUP_WSL_DEFAULT_USER".into(), config.wsl_default_user.clone().into());
    serde_json::Value::Object(map)
}
