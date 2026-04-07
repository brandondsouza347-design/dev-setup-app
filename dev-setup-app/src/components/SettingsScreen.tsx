// components/SettingsScreen.tsx — Configure installation parameters
import React, { useState, useEffect } from 'react';
import { Save, ChevronLeft, ChevronRight, FolderOpen, AlertTriangle, ExternalLink, Bookmark, Trash2, Upload } from 'lucide-react';
import { open as openDialog } from '@tauri-apps/plugin-dialog';
import { invoke } from '@tauri-apps/api/core';
import type { UserConfig, WizardPage, OsInfo, ConfigProfile } from '../types';

interface Props {
  config: UserConfig;
  osInfo: OsInfo | null;
  onUpdate: (key: keyof UserConfig, value: string) => void;
  onSave: (cfg: UserConfig) => Promise<void>;
  onNext: (page: WizardPage) => void;
  onBack: () => void;
}

export const SettingsScreen: React.FC<Props> = ({ config, osInfo, onUpdate, onSave, onNext, onBack }) => {
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [profiles, setProfiles] = useState<ConfigProfile[]>([]);
  const [loadingProfiles, setLoadingProfiles] = useState(true);

  const isWindows = osInfo?.os === 'windows';

  // Load profiles on mount
  useEffect(() => {
    loadProfiles();
  }, []);

  const loadProfiles = async () => {
    try {
      const list = await invoke<ConfigProfile[]>('list_config_profiles');
      setProfiles(list);
    } catch (err) {
      console.error('Failed to load profiles:', err);
    } finally {
      setLoadingProfiles(false);
    }
  };

  const update = <K extends keyof UserConfig>(key: K, value: UserConfig[K]) => {
    onUpdate(key, value as string);
    setSaved(false);
  };

  const handleSave = async () => {
    setSaving(true);
    try {
      await onSave(config);
      setSaved(true);
    } finally {
      setSaving(false);
    }
  };

  const browseTar = async () => {
    const selected = await openDialog({
      title: 'Select Ubuntu 22.04 TAR file',
      filters: [{ name: 'TAR Archive', extensions: ['tar'] }],
    });
    if (typeof selected === 'string') {
      update('wsl_tar_path', selected);
    }
  };

  const browseDir = async () => {
    const selected = await openDialog({
      title: 'Select WSL installation directory',
      directory: true,
    });
    if (typeof selected === 'string') {
      update('wsl_install_dir', selected);
    }
  };

  const openGitLabPAT = () =>
    invoke('open_url', {
      url: 'https://gitlab.toogoerp.net/-/profile/personal_access_tokens?name=DevSetup&scopes=api,write_repository',
    });

  const handleSaveAsProfile = async () => {
    const name = prompt('Enter profile name:');
    if (!name || name.trim().length === 0) return;

    try {
      await invoke('save_config_profile', { profileName: name.trim(), state: {} });
      await loadProfiles();
    } catch (err) {
      alert(`Failed to save profile: ${err}`);
    }
  };

  const handleLoadProfile = async (profileName: string) => {
    try {
      const loadedConfig = await invoke<UserConfig>('load_config_profile', { profileName });
      // Apply the loaded config directly
      await onSave(loadedConfig);
      setSaved(true);
    } catch (err) {
      alert(`Failed to load profile: ${err}`);
    }
  };

  const handleDeleteProfile = async (profileName: string) => {
    if (!confirm(`Delete profile "${profileName}"?`)) return;

    try {
      await invoke('delete_config_profile', { profileName });
      await loadProfiles();
    } catch (err) {
      alert(`Failed to delete profile: ${err}`);
    }
  };

  return (
    <div className="flex flex-col h-full p-8 overflow-y-auto">
      <div className="mb-6">
        <button onClick={onBack} className="flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700 dark:hover:text-gray-300 mb-4">
          <ChevronLeft className="w-4 h-4" /> Back
        </button>
        <h2 className="text-2xl font-bold text-gray-900 dark:text-white">Settings</h2>
        <p className="text-gray-500 dark:text-gray-400 mt-1">
          Customise the setup before it runs. Defaults work for most developers.
        </p>
      </div>

      <div className="space-y-8 flex-1">

        {/* Python */}
        <Section title="Python">
          <Field label="Python Version" hint="Installed via pyenv">
            <input
              type="text"
              value={config.python_version}
              onChange={(e) => update('python_version', e.target.value)}
              className="input"
              placeholder="3.9.21"
            />
          </Field>
          <Field label="Virtualenv Name" hint="Name of the pyenv virtual environment">
            <input
              type="text"
              value={config.venv_name}
              onChange={(e) => update('venv_name', e.target.value)}
              className="input"
              placeholder="erc"
            />
          </Field>
        </Section>

        {/* Node */}
        <Section title="Node.js">
          <Field label="Node Version" hint="Installed via NVM">
            <input
              type="text"
              value={config.node_version}
              onChange={(e) => update('node_version', e.target.value)}
              className="input"
              placeholder="22.10.0"
            />
          </Field>
        </Section>

        {/* PostgreSQL */}
        <Section title="PostgreSQL">
          <Field label="Database Name" hint="Project database to create">
            <input
              type="text"
              value={config.postgres_db_name}
              onChange={(e) => update('postgres_db_name', e.target.value)}
              className="input"
              placeholder="toogo_pos"
            />
          </Field>
          <Field label="postgres Role Password" hint="Password for the 'postgres' superuser role">
            <input
              type="password"
              value={config.postgres_password}
              onChange={(e) => update('postgres_password', e.target.value)}
              className="input"
              placeholder="postgres"
            />
          </Field>
        </Section>

        {/* WSL (Windows only) */}
        {isWindows && (
          <Section title="WSL Configuration">
            <Field label="ERC Ubuntu TAR File" hint="Path to erc_ubuntu.tar (or ubuntu_22.04_modified.tar)">
              <div className="flex gap-2">
                <input
                  type="text"
                  value={config.wsl_tar_path ?? ''}
                  onChange={(e) => update('wsl_tar_path', e.target.value || null)}
                  className="input flex-1"
                  placeholder="C:\Users\you\erc_ubuntu.tar"
                />
                <button onClick={browseTar} className="btn-secondary flex items-center gap-1 px-3">
                  <FolderOpen className="w-4 h-4" />
                </button>
              </div>
            </Field>
            <Field label="WSL Install Directory" hint="Where to extract the ERC distro">
              <div className="flex gap-2">
                <input
                  type="text"
                  value={config.wsl_install_dir ?? ''}
                  onChange={(e) => update('wsl_install_dir', e.target.value || null)}
                  className="input flex-1"
                  placeholder="C:\Users\you\WSL\ERC"
                />
                <button onClick={browseDir} className="btn-secondary flex items-center gap-1 px-3">
                  <FolderOpen className="w-4 h-4" />
                </button>
              </div>
            </Field>
            <Field label="WSL Default User" hint="Linux username to log in as when WSL starts (default: ubuntu)">
              <input
                type="text"
                value={config.wsl_default_user}
                onChange={(e) => update('wsl_default_user', e.target.value || 'ubuntu')}
                className="input"
                placeholder="ubuntu"
              />
            </Field>
          </Section>
        )}

        {/* Git Identity */}
        <Section title="Git Identity">
          <Field label="Full Name" hint={isWindows ? "Used for git config user.name inside WSL" : "Used for git config user.name"}>
            <input
              type="text"
              value={config.git_name ?? ''}
              onChange={(e) => update('git_name', e.target.value || null)}
              className="input"
              placeholder="Jane Smith"
            />
          </Field>
          <Field label="Email Address" hint="Used for git config user.email and SSH key comment">
            <input
              type="email"
              value={config.git_email ?? ''}
              onChange={(e) => update('git_email', e.target.value || null)}
              className="input"
              placeholder="jane@example.com"
            />
          </Field>
        </Section>

        {/* Behaviour */}
        <Section title="Behaviour">
          <div className="flex items-center gap-3">
            <input
              type="checkbox"
              id="skip-installed"
              checked={config.skip_already_installed}
              onChange={(e) => update('skip_already_installed', e.target.checked)}
              className="w-4 h-4 rounded border-gray-300"
            />
            <label htmlFor="skip-installed" className="text-sm text-gray-700 dark:text-gray-300">
              Skip steps for software that is already installed
            </label>
          </div>
        </Section>

        {/* GitLab Configuration */}
        <Section title="GitLab Configuration">
          <div className="flex items-start gap-2 p-3 rounded-lg bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-700 text-blue-800 dark:text-blue-300 text-sm">
            <AlertTriangle className="w-4 h-4 mt-0.5 shrink-0" />
            <span>A GitLab Personal Access Token is required for automated SSH key upload. Leave blank to add your SSH key manually.</span>
          </div>
          <Field label="Personal Access Token (PAT)" hint="Needed for automated SSH key upload">
            <div className="flex gap-2">
              <input
                type="password"
                value={config.gitlab_pat ?? ''}
                onChange={(e) => update('gitlab_pat', e.target.value || null)}
                className="input flex-1"
                placeholder="glpat-xxxxxxxxxxxxxxxxxxxx"
              />
              <button
                onClick={openGitLabPAT}
                className="btn-secondary flex items-center gap-1 px-3 text-sm whitespace-nowrap"
                title="Open GitLab to create a PAT"
              >
                <ExternalLink className="w-4 h-4" />
                Create PAT
              </button>
            </div>
          </Field>
          <Field label="Repository URL" hint="SSH URL of the repo to clone">
            <input
              type="text"
              value={config.gitlab_repo_url ?? 'git@gitlab.toogoerp.net:root/erc.git'}
              onChange={(e) => update('gitlab_repo_url', e.target.value || null)}
              className="input"
              placeholder="git@gitlab.toogoerp.net:root/erc.git"
            />
          </Field>
          <Field label="Clone Directory" hint={isWindows ? 'WSL path e.g. /home/ubuntu/VsCodeProjects/erc' : 'e.g. ~/VsCodeProjects/erc'}>
            <input
              type="text"
              value={config.clone_dir ?? '/home/ubuntu/VsCodeProjects/erc'}
              onChange={(e) => update('clone_dir', e.target.value || null)}
              className="input"
              placeholder={isWindows ? '/home/ubuntu/VsCodeProjects/erc' : '~/VsCodeProjects/erc'}
            />
          </Field>
        </Section>

        <Section title="Django Configuration">
          <Field label="Tenant Name" hint="Display name for tenant (can have spaces, e.g., ERC Kinetic Conversion)">
            <input
              type="text"
              value={config.tenant_name}
              onChange={(e) => update('tenant_name', e.target.value)}
              className="input"
              placeholder="erckinetic"
            />
          </Field>
          <Field label="Tenant ID" hint="Technical identifier used by copy_tenant command (no spaces, e.g., t2070)">
            <input
              type="text"
              value={config.tenant_id}
              onChange={(e) => update('tenant_id', e.target.value)}
              className="input"
              placeholder="t2070"
            />
          </Field>
          <Field label="Cluster Name" hint="Cluster name for copy_tenant command (e.g., stable)">
            <input
              type="text"
              value={config.cluster_name}
              onChange={(e) => update('cluster_name', e.target.value)}
              className="input"
              placeholder="stable"
            />
          </Field>
        </Section>

        <Section title="AWS Credentials (Session Only - Not Saved)">
          <div className="flex items-start gap-2 p-3 rounded-lg bg-yellow-50 dark:bg-yellow-900/20 border border-yellow-200 dark:border-yellow-700 text-yellow-800 dark:text-yellow-300 text-sm mb-4">
            <AlertTriangle className="w-4 h-4 mt-0.5 shrink-0" />
            <span>AWS credentials are used for Django S3/SNS operations. They are NOT saved to disk - you'll need to re-enter them each session for security.</span>
          </div>
          <Field label="AWS Access Key ID" hint="Required for S3 and SNS operations in Django commands">
            <input
              type="password"
              value={config.aws_access_key_id ?? ''}
              onChange={(e) => update('aws_access_key_id', e.target.value || null)}
              className="input"
              placeholder="AKIA..."
            />
          </Field>
          <Field label="AWS Secret Access Key" hint="Required for S3 and SNS operations in Django commands">
            <input
              type="password"
              value={config.aws_secret_access_key ?? ''}
              onChange={(e) => update('aws_secret_access_key', e.target.value || null)}
              className="input"
              placeholder="Secret key..."
            />
          </Field>
        </Section>

        {/* Configuration Profiles */}
        <Section title="Configuration Profiles">
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <p className="text-sm text-gray-600 dark:text-gray-400">
                Save named configurations for quick switching between different environments
              </p>
              <button
                onClick={handleSaveAsProfile}
                className="flex items-center gap-2 px-3 py-1.5 text-sm border border-gray-300 dark:border-gray-600 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-700 transition-colors"
              >
                <Bookmark className="w-4 h-4" />
                Save As Profile
              </button>
            </div>

            {loadingProfiles ? (
              <div className="text-sm text-gray-500 dark:text-gray-400 py-4 text-center">
                Loading profiles...
              </div>
            ) : profiles.length === 0 ? (
              <div className="text-sm text-gray-500 dark:text-gray-400 py-4 text-center border border-dashed border-gray-300 dark:border-gray-600 rounded-lg">
                No saved profiles yet. Click "Save As Profile" to create one.
              </div>
            ) : (
              <div className="space-y-2">
                {profiles.map((profile) => (
                  <div
                    key={profile.name}
                    className="flex items-center justify-between p-3 rounded-lg border border-gray-200 dark:border-gray-700 hover:bg-gray-50 dark:hover:bg-gray-700/50 transition-colors"
                  >
                    <div className="flex-1">
                      <div className="font-medium text-sm text-gray-900 dark:text-white">
                        {profile.name}
                      </div>
                      <div className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                        {profile.description}
                      </div>
                      <div className="text-xs text-gray-400 dark:text-gray-500 mt-1">
                        Saved {new Date(profile.saved_at * 1000).toLocaleString()}
                      </div>
                    </div>
                    <div className="flex items-center gap-2 ml-4">
                      <button
                        onClick={() => handleLoadProfile(profile.name)}
                        className="flex items-center gap-1.5 px-3 py-1.5 text-sm bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors"
                      >
                        <Upload className="w-3.5 h-3.5" />
                        Apply
                      </button>
                      <button
                        onClick={() => handleDeleteProfile(profile.name)}
                        className="p-1.5 text-red-600 hover:bg-red-50 dark:hover:bg-red-900/20 rounded transition-colors"
                        title="Delete profile"
                      >
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </Section>
      </div>

      {/* Footer */}
      <div className="flex items-center justify-between mt-6 pt-4 border-t border-gray-200 dark:border-gray-700">
        <button
          onClick={handleSave}
          disabled={saving}
          className="flex items-center gap-2 px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-800 text-sm disabled:opacity-50 transition-colors"
        >
          <Save className="w-4 h-4" />
          {saving ? 'Saving…' : saved ? '✓ Saved' : 'Save'}
        </button>
        <button
          onClick={async () => { await handleSave(); onNext('wizard'); }}
          className="flex items-center gap-2 px-6 py-2 bg-blue-600 hover:bg-blue-700 text-white font-semibold rounded-lg transition-colors"
        >
          Continue
          <ChevronRight className="w-4 h-4" />
        </button>
      </div>
    </div>
  );
};

// ─── Sub-components ─────────────────────────────────────────────────────────

const Section: React.FC<{ title: string; children: React.ReactNode }> = ({ title, children }) => (
  <div>
    <h3 className="text-sm font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-wide mb-3">
      {title}
    </h3>
    <div className="space-y-4 bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 p-4">
      {children}
    </div>
  </div>
);

const Field: React.FC<{ label: string; hint?: string; children: React.ReactNode }> = ({
  label,
  hint,
  children,
}) => (
  <div>
    <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
      {label}
      {hint && <span className="ml-2 text-xs text-gray-400 font-normal">{hint}</span>}
    </label>
    {children}
  </div>
);
