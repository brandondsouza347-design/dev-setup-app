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
  | 'network';

export interface SetupStep {
  id: string;
  title: string;
  description: string;
  platform: 'macos' | 'windows' | 'both';
  category: StepCategory;
  required: boolean;
  estimated_minutes: number;
}

export interface StepResult {
  id: string;
  status: StepStatus;
  logs: string[];
  error: string | null;
  retry_count: number;
  duration_secs: number | null;
}

export interface UserConfig {
  wsl_tar_path: string | null;
  wsl_install_dir: string | null;
  postgres_password: string;
  postgres_db_name: string;
  python_version: string;
  node_version: string;
  venv_name: string;
  skip_already_installed: boolean;
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
  message: string;
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
  | 'complete';
