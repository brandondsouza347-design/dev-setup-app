// utils/stepSettings.ts — Step-to-settings mapping and detection logic

import type { UserConfig } from '../types';

/**
 * Map of step IDs to the settings they require.
 * This drives the dynamic settings detection for custom workflows.
 */
export const STEP_SETTINGS_MAP: Record<string, (keyof UserConfig)[]> = {
  // ── WSL Setup Steps ────────────────────────────────────────────────────────
  enable_wsl: [],
  import_wsl_tar: ['wsl_tar_path', 'wsl_install_dir'],
  wsl_network: [],
  wslconfig_networking: [],
  wsl_cleanup: [],
  ubuntu_user_wsl: ['wsl_default_user'],

  // ── Hosts File Steps ───────────────────────────────────────────────────────
  windows_hosts: ['tenant_name'],
  mac_hosts: ['tenant_name'],

  // ── Git & SSH Steps ────────────────────────────────────────────────────────
  git_ssh_windows: ['git_name', 'git_email'],
  gitlab_ssh: ['git_name', 'git_email', 'gitlab_pat', 'gitlab_repo_url'],
  gitlab_ssh_mac: ['git_name', 'git_email', 'gitlab_pat', 'gitlab_repo_url'],

  // ── Repository Steps ───────────────────────────────────────────────────────
  clone_repo: ['gitlab_repo_url', 'clone_dir'],
  clone_repo_mac: ['gitlab_repo_url', 'clone_dir'],

  // ── Python Environment Steps ───────────────────────────────────────────────
  pyenv: ['python_version'],
  pyenv_wsl: ['python_version'],
  pyenv_local: ['python_version', 'venv_name'],
  pyenv_local_mac: ['python_version', 'venv_name'],
  python_interpreter: ['clone_dir', 'venv_name'],
  python_interpreter_mac: ['clone_dir', 'venv_name'],
  install_pip_requirements: ['clone_dir', 'venv_name'],
  install_pip_requirements_mac: ['clone_dir', 'venv_name'],

  // ── Node.js Environment Steps ──────────────────────────────────────────────
  nvm: ['node_version'],
  nvm_wsl: ['node_version'],
  install_frontend_deps: ['clone_dir', 'node_version'],
  install_frontend_deps_mac: ['clone_dir', 'node_version'],

  // ── Database Steps ─────────────────────────────────────────────────────────
  postgres_wsl: ['postgres_password', 'postgres_db_name'],
  postgres_mac: ['postgres_password', 'postgres_db_name'],
  redis_wsl: [],
  redis_mac: [],
  install_pgadmin_windows: [],
  install_pgadmin_mac: [],

  // ── Django/Backend Steps ───────────────────────────────────────────────────
  migrate_shared: ['clone_dir', 'venv_name', 'postgres_db_name'],
  migrate_shared_mac: ['clone_dir', 'venv_name', 'postgres_db_name'],
  copy_tenant: ['clone_dir', 'venv_name', 'tenant_name', 'tenant_id', 'cluster_name', 'aws_access_key_id', 'aws_secret_access_key'],
  copy_tenant_mac: ['clone_dir', 'venv_name', 'tenant_name', 'tenant_id', 'cluster_name', 'aws_access_key_id', 'aws_secret_access_key'],
  update_tenant_name: ['clone_dir', 'tenant_name'],
  update_tenant_name_mac: ['clone_dir', 'tenant_name'],

  // ── Server/Service Steps ───────────────────────────────────────────────────
  start_frontend_watch: ['clone_dir'],
  start_frontend_watch_mac: ['clone_dir'],
  start_gunicorn: ['clone_dir', 'venv_name'],
  start_gunicorn_mac: ['clone_dir', 'venv_name'],

  // ── VPN Steps ──────────────────────────────────────────────────────────────
  install_openvpn: ['openvpn_config_path'],
  connect_vpn: ['openvpn_config_path'],

  // ── IDE/Editor Steps ───────────────────────────────────────────────────────
  vscode_windows: [],
  vscode_mac: [],
  setup_workspace: ['clone_dir'],
  setup_workspace_mac: ['clone_dir'],
  install_workspace_extensions: [],

  // ── Development Tools Steps ────────────────────────────────────────────────
  xcode_clt: [],
  homebrew: [],

  // ── Revert Steps ───────────────────────────────────────────────────────────
  revert_shutdown_wsl: [],
  revert_git_ssh: [],
  revert_vscode_windows: [],
  revert_wsl_network: [],
  revert_wsl_distro: ['wsl_backup_path', 'skip_wsl_backup'],
  revert_wslconfig: [],
  revert_windows_hosts: [],
  revert_wsl_features: [],
};

/**
 * Setting categories for UI organization
 */
export enum SettingCategory {
  WSL = 'WSL Configuration',
  Git = 'Git & GitLab',
  Python = 'Python Environment',
  Node = 'Node.js Environment',
  Database = 'Database',
  Tenant = 'Tenant & AWS',
  Network = 'Network & VPN',
  Workspace = 'Workspace & IDE',
}

/**
 * Map settings to their categories
 */
export const SETTING_CATEGORIES: Record<keyof UserConfig, SettingCategory> = {
  // WSL
  wsl_tar_path: SettingCategory.WSL,
  wsl_install_dir: SettingCategory.WSL,
  wsl_default_user: SettingCategory.WSL,
  wsl_backup_path: SettingCategory.WSL,
  skip_wsl_backup: SettingCategory.WSL,
  skip_already_installed: SettingCategory.WSL,

  // Git & GitLab
  git_name: SettingCategory.Git,
  git_email: SettingCategory.Git,
  gitlab_pat: SettingCategory.Git,
  gitlab_repo_url: SettingCategory.Git,
  clone_dir: SettingCategory.Git,

  // Python
  python_version: SettingCategory.Python,
  venv_name: SettingCategory.Python,

  // Node.js
  node_version: SettingCategory.Node,

  // Database
  postgres_password: SettingCategory.Database,
  postgres_db_name: SettingCategory.Database,

  // Tenant & AWS
  tenant_name: SettingCategory.Tenant,
  tenant_id: SettingCategory.Tenant,
  cluster_name: SettingCategory.Tenant,
  aws_access_key_id: SettingCategory.Tenant,
  aws_secret_access_key: SettingCategory.Tenant,

  // Network & VPN
  openvpn_config_path: SettingCategory.Network,
  tunnelblick_installer_path: SettingCategory.Network,
  vpn_method: SettingCategory.Network,
};

/**
 * Get all settings required by a list of step IDs.
 * Returns a Set to automatically deduplicate.
 */
export function getRequiredSettings(stepIds: string[]): Set<keyof UserConfig> {
  const required = new Set<keyof UserConfig>();

  stepIds.forEach(stepId => {
    const settings = STEP_SETTINGS_MAP[stepId];
    if (settings) {
      settings.forEach(setting => required.add(setting));
    }
  });

  return required;
}

/**
 * Group required settings by category for UI organization.
 */
export function groupSettingsByCategory(
  settings: Set<keyof UserConfig>
): Map<SettingCategory, Set<keyof UserConfig>> {
  const grouped = new Map<SettingCategory, Set<keyof UserConfig>>();

  settings.forEach(setting => {
    const category = SETTING_CATEGORIES[setting];
    if (!category) return; // Skip if no category defined

    if (!grouped.has(category)) {
      grouped.set(category, new Set());
    }
    grouped.get(category)!.add(setting);
  });

  return grouped;
}

/**
 * Check if any steps in the list require a specific setting.
 */
export function stepRequiresSetting(
  stepIds: string[],
  setting: keyof UserConfig
): boolean {
  return stepIds.some(stepId => {
    const settings = STEP_SETTINGS_MAP[stepId];
    return settings && settings.includes(setting);
  });
}

/**
 * Get human-readable labels for settings (used in UI).
 */
export const SETTING_LABELS: Record<keyof UserConfig, string> = {
  wsl_tar_path: 'WSL Tar Archive Path',
  wsl_install_dir: 'WSL Installation Directory',
  wsl_default_user: 'WSL Default User',
  wsl_backup_path: 'WSL Backup Directory',
  skip_wsl_backup: 'Skip WSL Backup',
  skip_already_installed: 'Skip Already Installed',
  git_name: 'Git User Name',
  git_email: 'Git User Email',
  gitlab_pat: 'GitLab Personal Access Token',
  gitlab_repo_url: 'GitLab Repository URL',
  clone_dir: 'Clone Directory',
  python_version: 'Python Version',
  venv_name: 'Virtual Environment Name',
  node_version: 'Node.js Version',
  postgres_password: 'PostgreSQL Password',
  postgres_db_name: 'PostgreSQL Database Name',
  tenant_name: 'Tenant Name',
  tenant_id: 'Tenant ID',
  cluster_name: 'Cluster Name',
  aws_access_key_id: 'AWS Access Key ID',
  aws_secret_access_key: 'AWS Secret Access Key',
  openvpn_config_path: 'OpenVPN Config File Path',
  tunnelblick_installer_path: 'Tunnelblick Installer Path',
  vpn_method: 'VPN Method',
};

/**
 * Get helpful descriptions for settings (used in tooltips/placeholders).
 */
export const SETTING_DESCRIPTIONS: Partial<Record<keyof UserConfig, string>> = {
  wsl_tar_path: 'Path to the Ubuntu WSL tar file to import',
  wsl_install_dir: 'Directory where WSL will be installed',
  git_name: 'Your full name for Git commits (e.g., "John Doe")',
  git_email: 'Your email for Git commits (e.g., "john@example.com")',
  gitlab_pat: 'Personal Access Token for GitLab authentication',
  gitlab_repo_url: 'SSH URL of the GitLab repository to clone',
  clone_dir: 'Directory path where the repository will be cloned',
  python_version: 'Python version to install (e.g., "3.9.21")',
  venv_name: 'Name for the Python virtual environment',
  node_version: 'Node.js version to install (e.g., "22.10.0")',
  tenant_name: 'Tenant identifier for the application',
  tenant_id: 'Numeric tenant ID',
  cluster_name: 'Cluster environment name (e.g., "stable")',
  openvpn_config_path: 'Path to .ovpn configuration file',
};
