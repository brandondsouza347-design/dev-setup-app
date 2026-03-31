// state.rs — Application state management
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

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
    pub postgres_password: String,
    pub postgres_db_name: String,
    pub python_version: String,
    pub node_version: String,
    pub venv_name: String,
    pub skip_already_installed: bool,
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
}

impl Default for UserConfig {
    fn default() -> Self {
        UserConfig {
            wsl_tar_path: None,
            wsl_install_dir: None,
            postgres_password: "postgres".to_string(),
            postgres_db_name: "toogo_pos".to_string(),
            python_version: "3.9.21".to_string(),
            node_version: "22.10.0".to_string(),
            venv_name: "erc".to_string(),
            skip_already_installed: true,
            openvpn_config_path: None,
            git_name: None,
            git_email: None,
            gitlab_pat: None,
            gitlab_repo_url: None,
            clone_dir: None,
            wsl_default_user: "ubuntu".to_string(),
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
