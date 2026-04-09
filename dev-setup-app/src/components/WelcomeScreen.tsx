// components/WelcomeScreen.tsx — Landing page showing OS detection and entry point
import { Monitor, Apple, Terminal, ChevronRight, Cpu } from 'lucide-react';
import type { OsInfo, WizardPage } from '../types';

interface Props {
  osInfo: OsInfo | null;
  onNext: (page: WizardPage) => void;
}

export const WelcomeScreen: React.FC<Props> = ({ osInfo, onNext }) => {
  const isMac = osInfo?.os === 'macos';
  const isWindows = osInfo?.os === 'windows';
  const icon = isMac ? (
    <Apple className="w-8 h-8" />
  ) : isWindows ? (
    <Monitor className="w-8 h-8" />
  ) : (
    <Terminal className="w-8 h-8" />
  );

  const osLabel = isMac
    ? `macOS ${osInfo?.version ?? ''}${osInfo?.is_apple_silicon ? ' (Apple Silicon)' : ' (Intel)'}`
    : isWindows
    ? 'Windows'
    : osInfo?.os ?? 'Detecting…';

  const whatInstalls = isMac
    ? [
        '⌘ Xcode Command Line Tools',
        '🍺 Homebrew — macOS package manager',
        '🐍 pyenv + Python 3.9.21 + erc virtualenv',
        '🟢 NVM v0.40.1 + Node.js 22.10.0 + Gulp',
        '🐘 PostgreSQL 16 (with roles & databases)',
        '📦 Redis cache server',
        '🌐 Update macOS hosts file (tenant entries)',
        '💙 VS Code extensions + shell integration',
        '🔑 Git identity + SSH key generation + GitLab upload',
        '📂 Clone ERC repository',
        '🐍 pyenv local Python version set',
        '🖥️ Workspace setup (extensions + MCP servers + open VS Code)',
        '⚙️ Python interpreter configuration',
        '📦 Install pip requirements',
        '🗄️ Migrate shared schemas',
        '👥 Copy tenant data',
        '✏️ Update tenant name in database',
        '📦 Install frontend dependencies',
        '🏗️ Build front-end assets',
        '🚀 Start Gunicorn server',
        '🛢️ Install pgAdmin 4 GUI (optional)',
      ]
    : [
        '🐧 WSL2 feature enablement',
        '📦 ERC Ubuntu import from TAR (Ubuntu 24.04 LTS)',
        '🌐 WSL network & DNS configuration',
        '🔧 .wslconfig mirrored networking (skipped if present)',
        '🧹 WSL cleanup & set ERC as default distro (skipped if clean)',
        '💙 VS Code + Remote-WSL extension + settings',
        '🔑 Git identity + SSH key generation (WSL)',
        '👤 Ubuntu user configuration (WSL — skipped if present)',
        '🐍 pyenv + Python 3.9.21 + erc virtualenv (WSL — skipped if present)',
        '🟢 NVM v0.40.1 + Node.js 22.10.0 (WSL — skipped if present)',
        '🐘 PostgreSQL 16 (WSL — skipped if present)',
        '📦 Redis cache server (WSL — skipped if present)',
        '📝 Windows hosts file (tenant entries — skipped if present)',
        '🔑 GitLab SSH key upload',
        '📂 Clone ERC repository',
        '🐍 pyenv local Python version set',
        '🖥️ Open VS Code workspace',
        '🔌 Install workspace extensions + MCP config (Kibana, GitLab, Atlassian)',
        '⚙️ Python interpreter configuration',
        '📦 Install pip requirements',
        '🗄️ Migrate shared schemas',
        '👥 Copy tenant data',
        '✏️ Update tenant name in database',
        '📦 Install frontend dependencies',
        '🏗️ Build front-end assets',
        '🚀 Start Gunicorn server',
        '🛢️ Install pgAdmin 4 GUI (optional)',
      ];

  return (
    <div className="flex flex-col items-center justify-center min-h-full py-12 px-8 text-center">
      {/* Logo / header */}
      <div className="mb-8">
        <div className="inline-flex items-center justify-center w-20 h-20 rounded-2xl bg-blue-600 text-white mb-4 shadow-lg">
          <Terminal className="w-10 h-10" />
        </div>
        <h1 className="text-3xl font-bold text-gray-900 dark:text-white">
          Dev Environment Setup
        </h1>
        <p className="mt-2 text-gray-500 dark:text-gray-400 max-w-lg">
          Automated developer environment installer. Runs each step one at a time,
          streams live logs, and lets you retry on failures.
        </p>
      </div>

      {/* OS detection card */}
      <div className="w-full max-w-md mb-8 p-4 bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 shadow-sm">
        <div className="flex items-center gap-3 mb-2">
          <span className="text-blue-500">{icon}</span>
          <div className="text-left">
            <div className="text-sm text-gray-500 dark:text-gray-400">Detected platform</div>
            <div className="font-semibold text-gray-900 dark:text-white">{osLabel || 'Detecting…'}</div>
          </div>
          {osInfo?.is_apple_silicon && (
            <div className="ml-auto flex items-center gap-1 text-xs bg-purple-100 dark:bg-purple-900 text-purple-700 dark:text-purple-300 px-2 py-0.5 rounded-full">
              <Cpu className="w-3 h-3" />
              Apple Silicon
            </div>
          )}
        </div>
      </div>

      {/* What will be installed */}
      <div className="w-full max-w-md mb-10 text-left">
        <h3 className="text-sm font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-wide mb-3">
          What will be installed
        </h3>
        <ul className="space-y-2">
          {whatInstalls.map((item, i) => (
            <li key={i} className="flex items-start gap-2 text-sm text-gray-700 dark:text-gray-300">
              <span>{item}</span>
            </li>
          ))}
        </ul>
      </div>

      {/* CTA buttons */}
      <div className="flex flex-col gap-3 w-full max-w-md">
        <button
          onClick={() => onNext('prereqs')}
          disabled={!osInfo}
          className="flex items-center justify-center gap-2 w-full py-3 px-6 bg-blue-600 hover:bg-blue-700 disabled:bg-gray-300 text-white font-semibold rounded-xl transition-colors shadow-md"
        >
          Get Started
          <ChevronRight className="w-5 h-5" />
        </button>
        <button
          onClick={() => onNext('settings')}
          className="w-full py-2 px-6 border border-gray-300 dark:border-gray-600 text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-800 rounded-xl transition-colors text-sm"
        >
          ⚙️ Configure Settings First
        </button>
      </div>
    </div>
  );
};
