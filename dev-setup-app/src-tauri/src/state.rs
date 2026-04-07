// state.rs — Application state management
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum StepStatus {
    Pending,
    Running,
    Done,
    Failed,
    Skipped,
}

impl Default for StepStatus {
    fn default() -> Self {
        StepStatus::Pending
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StepState {
    pub id: String,
    pub status: StepStatus,
    pub logs: Vec<String>,
    pub error: Option<String>,
    pub retry_count: u32,
    pub duration_secs: Option<u64>,
}

impl StepState {
    pub fn new(id: &str) -> Self {
        StepState {
            id: id.to_string(),
            status: StepStatus::Pending,
            logs: Vec::new(),
            error: None,
            retry_count: 0,
            duration_secs: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserConfig {
    pub wsl_tar_path: Option<String>,
    pub wsl_install_dir: Option<String>,
    #[serde(default)]
    pub wsl_backup_path: Option<String>,
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
    #[serde(default)]
    pub gitlab_pat: Option<String>,
    #[serde(default)]
    pub gitlab_repo_url: Option<String>,
    #[serde(default)]
    pub clone_dir: Option<String>,
    #[serde(default)]
    pub wsl_default_user: String,
    #[serde(default)]
    pub tenant_name: String,
    #[serde(default)]
    pub tenant_id: String,
    #[serde(default)]
    pub cluster_name: String,
    /// AWS credentials - NOT persisted to disk for security
    #[serde(skip)]
    pub aws_access_key_id: Option<String>,
    #[serde(skip)]
    pub aws_secret_access_key: Option<String>,
}

impl Default for UserConfig {
    fn default() -> Self {
        UserConfig {
            wsl_tar_path: None,
            wsl_install_dir: None,
            wsl_backup_path: None,
            postgres_password: "postgres".to_string(),
            postgres_db_name: "toogo_pos".to_string(),
            python_version: "3.9.21".to_string(),
            node_version: "22.10.0".to_string(),
            venv_name: "erc".to_string(),
            skip_already_installed: false,
            skip_wsl_backup: false,
            openvpn_config_path: None,
            git_name: None,
            git_email: None,
            gitlab_pat: None,
            gitlab_repo_url: Some("git@gitlab.toogoerp.net:root/erc.git".to_string()),
            clone_dir: Some("/home/ubuntu/VsCodeProjects/erc".to_string()),
            wsl_default_user: "ubuntu".to_string(),
            tenant_name: "erckinetic".to_string(),
            tenant_id: "t2070".to_string(),
            cluster_name: "stable".to_string(),
            aws_access_key_id: None,
            aws_secret_access_key: None,
        }
    }
}

#[derive(Debug, Default)]
pub struct AppState {
    pub step_states: HashMap<String, StepState>,
    pub current_step_index: usize,
    pub setup_started: bool,
    pub setup_complete: bool,
    pub config: UserConfig,
    pub setup_started_at: Option<i64>,
    pub revert_started_at: Option<i64>,
}

impl AppState {
    pub fn get_or_create_step(&mut self, id: &str) -> &mut StepState {
        self.step_states
            .entry(id.to_string())
            .or_insert_with(|| StepState::new(id))
    }

    pub fn reset(&mut self) {
        self.step_states.clear();
        self.current_step_index = 0;
        self.setup_started = false;
        self.setup_complete = false;
    }
}

/// Shared cancellation flag. Managed independently of AppState so it can be
/// read inside async execute_script without holding the AppState mutex.
pub struct CancelState {
    cancel_requested: AtomicBool,
}

impl CancelState {
    pub fn new() -> Self {
        CancelState {
            cancel_requested: AtomicBool::new(false),
        }
    }
    pub fn cancel(&self) {
        self.cancel_requested.store(true, Ordering::SeqCst);
    }
    pub fn reset(&self) {
        self.cancel_requested.store(false, Ordering::SeqCst);
    }
    pub fn is_cancelled(&self) -> bool {
        self.cancel_requested.load(Ordering::SeqCst)
    }
}

// ── Run History ──────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum RunType {
    Setup,
    Revert,
    Workflow,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum RunStatus {
    Success,
    Failed,
    Cancelled,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FailedStepLog {
    pub step_id: String,
    pub step_name: String,
    pub error_message: Option<String>,
    pub logs: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkippedStepLog {
    pub step_id: String,
    pub step_name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RunHistory {
    pub id: String,              // UUID
    pub run_type: RunType,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub workflow_name: Option<String>,  // Name of custom workflow if run_type=Workflow
    pub started_at: i64,          // Unix timestamp (seconds)
    pub completed_at: i64,        // Unix timestamp (seconds)
    pub status: RunStatus,
    pub step_count: usize,
    pub failed_steps: Vec<FailedStepLog>,
    #[serde(default)]
    pub skipped_steps: Vec<SkippedStepLog>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CustomWorkflow {
    pub id: String,              // UUID
    pub name: String,            // User-friendly workflow name
    pub description: String,     // Optional description
    pub step_ids: Vec<String>,   // Array of step IDs to execute in order
    pub created_at: i64,         // Unix timestamp (seconds)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_run_at: Option<i64>, // Unix timestamp of last execution
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConfigProfile {
    pub name: String,
    pub saved_at: i64,           // Unix timestamp (seconds)
    pub description: String,     // Auto-generated summary
    pub config: UserConfig,
}
