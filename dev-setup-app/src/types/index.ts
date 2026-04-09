// types/index.ts — Shared TypeScript types matching Rust structs

export type OS = 'macos' | 'windows' | 'linux';

export interface OsInfo {
  os: OS;
  arch: string;
  version: string;
  is_apple_silicon: boolean;
}

export type StepStatus = 'pending' | 'running' | 'done' | 'failed' | 'skipped';

export type StepCategory =
  | 'prerequisites'
  | 'package_manager'
  | 'python'
  | 'node'
  | 'database'
  | 'cache'
  | 'vcs'
  | 'editor'
  | 'wsl'
  | 'network'
  | 'revert';

export interface SetupStep {
  id: string;
  title: string;
  description: string;
  platform: 'macos' | 'windows' | 'both';
  category: StepCategory;
  required: boolean;
  estimated_minutes: number;
  rollback_steps: string[];
}

export interface StepResult {
  id: string;
  status: StepStatus;
  logs: string[];
  error: string | null;
  retry_count: number;
  duration_secs: number | null;
  restart_required: boolean;
}

export interface UserConfig {
  wsl_tar_path: string | null;
  wsl_install_dir: string | null;
  wsl_backup_path: string | null;
  postgres_password: string;
  postgres_db_name: string;
  python_version: string;
  node_version: string;
  venv_name: string;
  skip_already_installed: boolean;
  skip_wsl_backup: boolean;
  openvpn_config_path: string | null;
  tunnelblick_installer_path: string | null;
  vpn_method: "tunnelblick" | "openvpn-cli" | null;
  git_name: string | null;
  git_email: string | null;
  gitlab_pat: string | null;
  gitlab_repo_url: string | null;
  clone_dir: string | null;
  wsl_default_user: string;
  tenant_name: string;
  tenant_id: string;
  cluster_name: string;
  aws_access_key_id?: string | null;
  aws_secret_access_key?: string | null;
}

export interface FullState {
  steps: StepResult[];
  current_step_index: number;
  setup_started: boolean;
  setup_complete: boolean;
  config: UserConfig;
}

export interface PrereqCheck {
  name: string;
  passed: boolean;
  warning?: boolean;
  message: string;
  actionable?: boolean;
  action_id?: string;
}

export type LogLevel = 'info' | 'warn' | 'error' | 'success';

export interface LogEvent {
  step_id: string;
  line: string;
  level: LogLevel;
}

export interface LogEntry {
  stepId: string;
  line: string;
  level: string;
  ts: number;
}

export type StepStatusEvent = {
  id: string;
  status: StepStatus;
  error?: string;
};

// Wizard page identifiers
export type WizardPage =
  | 'welcome'
  | 'prereqs'
  | 'settings'
  | 'wizard'
  | 'progress'
  | 'complete'
  | 'revert'
  | 'history'
  | 'workflow'
  | 'custom-progress';

export type AdminAgentStatus = 'idle' | 'requesting' | 'ready' | 'error';

// Navigation section for collapsible sidebar menus
export interface NavSection {
  id: string;
  label: string;
  icon?: React.ReactNode;
  children: NavItem[];
}

export interface NavItem {
  id: WizardPage;
  label: string;
  icon: React.ReactNode;
  badge?: number;
}

// Run History types
export type RunType = 'setup' | 'revert' | 'workflow';
export type RunStatus = 'success' | 'failed' | 'cancelled';

export interface FailedStepLog {
  step_id: string;
  step_name: string;
  error_message: string | null;
  logs: string[];
}

export interface SkippedStepLog {
  step_id: string;
  step_name: string;
}

export interface RunHistory {
  id: string;              // UUID/timestamp-based ID
  run_type: RunType;
  workflow_name?: string;  // Name of custom workflow if run_type='workflow'
  started_at: number;      // Unix timestamp (seconds)
  completed_at: number;    // Unix timestamp (seconds)
  status: RunStatus;
  step_count: number;
  failed_steps: FailedStepLog[];
  skipped_steps?: SkippedStepLog[];
}

// Workflow types
export interface CustomWorkflow {
  id: string;              // UUID
  name: string;            // User-friendly workflow name
  description: string;     // Optional description
  step_ids: string[];      // Array of step IDs to execute in order
  created_at: number;      // Unix timestamp (seconds)
  last_run_at?: number;    // Unix timestamp of last execution
  settings?: {             // Workflow-specific settings (overrides global)
    overrides: Partial<UserConfig>;  // Custom values that override global settings
    nullify: (keyof UserConfig)[];   // Settings explicitly disabled for this workflow
  };
}

// Configuration Profile types
export interface ConfigProfile {
  name: string;             // User-friendly profile name
  saved_at: number;         // Unix timestamp (seconds)
  description: string;      // Auto-generated from config values
  config: UserConfig;       // Saved configuration
}
