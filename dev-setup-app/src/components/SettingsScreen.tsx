// components/SettingsScreen.tsx — Configure installation parameters
import React, { useState } from 'react';
import { Save, ChevronLeft, ChevronRight, FolderOpen } from 'lucide-react';
import { open as openDialog } from '@tauri-apps/api/dialog';
import type { UserConfig, WizardPage, OsInfo } from '../types';

interface Props {
  config: UserConfig;
  osInfo: OsInfo | null;
  onSave: (cfg: UserConfig) => Promise<void>;
  onNext: (page: WizardPage) => void;
  onBack: () => void;
}

export const SettingsScreen: React.FC<Props> = ({ config, osInfo, onSave, onNext, onBack }) => {
  const [local, setLocal] = useState<UserConfig>({ ...config });
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);

  const isWindows = osInfo?.os === 'windows';

  const update = <K extends keyof UserConfig>(key: K, value: UserConfig[K]) => {
    setLocal((prev) => ({ ...prev, [key]: value }));
    setSaved(false);
  };

  const handleSave = async () => {
    setSaving(true);
    try {
      await onSave(local);
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
              value={local.python_version}
              onChange={(e) => update('python_version', e.target.value)}
              className="input"
              placeholder="3.9.21"
            />
          </Field>
          <Field label="Virtualenv Name" hint="Name of the pyenv virtual environment">
            <input
              type="text"
              value={local.venv_name}
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
              value={local.node_version}
              onChange={(e) => update('node_version', e.target.value)}
              className="input"
              placeholder="16.20.2"
            />
          </Field>
        </Section>

        {/* PostgreSQL */}
        <Section title="PostgreSQL">
          <Field label="Database Name" hint="Project database to create">
            <input
              type="text"
              value={local.postgres_db_name}
              onChange={(e) => update('postgres_db_name', e.target.value)}
              className="input"
              placeholder="dev_db"
            />
          </Field>
          <Field label="postgres Role Password" hint="Password for the 'postgres' superuser role">
            <input
              type="password"
              value={local.postgres_password}
              onChange={(e) => update('postgres_password', e.target.value)}
              className="input"
              placeholder="postgres"
            />
          </Field>
        </Section>

        {/* WSL (Windows only) */}
        {isWindows && (
          <Section title="WSL Configuration">
            <Field label="Ubuntu 22.04 TAR File" hint="Path to ubuntu_22.04_modified.tar">
              <div className="flex gap-2">
                <input
                  type="text"
                  value={local.wsl_tar_path ?? ''}
                  onChange={(e) => update('wsl_tar_path', e.target.value || null)}
                  className="input flex-1"
                  placeholder="C:\Users\you\ubuntu_22.04_modified.tar"
                />
                <button onClick={browseTar} className="btn-secondary flex items-center gap-1 px-3">
                  <FolderOpen className="w-4 h-4" />
                </button>
              </div>
            </Field>
            <Field label="WSL Install Directory" hint="Where to extract the WSL distro">
              <div className="flex gap-2">
                <input
                  type="text"
                  value={local.wsl_install_dir ?? ''}
                  onChange={(e) => update('wsl_install_dir', e.target.value || null)}
                  className="input flex-1"
                  placeholder="C:\Users\you\WSL\Ubuntu-22.04"
                />
                <button onClick={browseDir} className="btn-secondary flex items-center gap-1 px-3">
                  <FolderOpen className="w-4 h-4" />
                </button>
              </div>
            </Field>
          </Section>
        )}

        {/* Behaviour */}
        <Section title="Behaviour">
          <div className="flex items-center gap-3">
            <input
              type="checkbox"
              id="skip-installed"
              checked={local.skip_already_installed}
              onChange={(e) => update('skip_already_installed', e.target.checked)}
              className="w-4 h-4 rounded border-gray-300"
            />
            <label htmlFor="skip-installed" className="text-sm text-gray-700 dark:text-gray-300">
              Skip steps for software that is already installed
            </label>
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
