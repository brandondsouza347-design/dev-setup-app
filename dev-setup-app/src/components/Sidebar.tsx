// components/Sidebar.tsx — Navigation sidebar showing step progress
import { Monitor, Apple, Settings, List, Activity, CheckSquare, Home, RotateCcw } from 'lucide-react';
import type { OsInfo, WizardPage, SetupStep, StepResult } from '../types';
import { StepBadge } from './StepBadge';

interface Props {
  osInfo: OsInfo | null;
  page: WizardPage;
  steps: SetupStep[];
  stepResults: Record<string, StepResult>;
  currentStepIndex: number;
  setupStarted: boolean;
  onNavigate: (page: WizardPage) => void;
}

export const Sidebar: React.FC<Props> = ({
  osInfo,
  page,
  steps,
  stepResults,
  currentStepIndex,
  setupStarted,
  onNavigate,
}) => {
  const isMac = osInfo?.os === 'macos';
  const OsIcon = isMac ? Apple : Monitor;
  const osLabel = isMac
    ? `macOS${osInfo?.is_apple_silicon ? ' (M-series)' : ''}`
    : osInfo?.os === 'windows'
    ? 'Windows'
    : 'Linux';

  const navItems: { id: WizardPage; label: string; icon: React.ReactNode }[] = [
    { id: 'welcome',  label: 'Welcome',   icon: <Home className="w-4 h-4" /> },
    { id: 'prereqs',  label: 'Pre-checks', icon: <CheckSquare className="w-4 h-4" /> },
    { id: 'settings', label: 'Settings',   icon: <Settings className="w-4 h-4" /> },
    { id: 'wizard',   label: 'Plan',       icon: <List className="w-4 h-4" /> },
    { id: 'progress', label: 'Progress',   icon: <Activity className="w-4 h-4" /> },
    { id: 'revert',   label: 'Revert',     icon: <RotateCcw className="w-4 h-4" /> },
  ];

  return (
    <div className="w-64 h-full flex flex-col bg-gray-900 text-gray-100 border-r border-gray-700">
      {/* App branding */}
      <div className="px-5 py-5 border-b border-gray-700">
        <div className="flex items-center gap-2 mb-1">
          <div className="w-7 h-7 rounded-lg bg-blue-600 flex items-center justify-center">
            <Activity className="w-4 h-4 text-white" />
          </div>
          <span className="font-bold text-white text-sm">Dev Setup</span>
        </div>
        <div className="flex items-center gap-1.5 text-xs text-gray-400 mt-1">
          <OsIcon className="w-3.5 h-3.5" />
          {osLabel || 'Detecting…'}
        </div>
      </div>

      {/* Navigation */}
      <nav className="px-3 py-3 border-b border-gray-700">
        {navItems.map(({ id, label, icon }) => (
          <button
            key={id}
            onClick={() => onNavigate(id)}
            className={`w-full flex items-center gap-2.5 px-3 py-2 rounded-lg text-sm mb-0.5 transition-colors text-left ${
              page === id
                ? 'bg-blue-600 text-white'
                : 'text-gray-400 hover:bg-gray-800 hover:text-white'
            }`}
          >
            {icon}
            {label}
          </button>
        ))}
      </nav>

      {/* Step progress list (only visible once started) */}
      {setupStarted && (
        <div className="flex-1 overflow-y-auto px-3 py-3">
          <div className="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-2 px-1">
            Steps
          </div>
          {steps.map((step, idx) => {
            const result = stepResults[step.id];
            const status = result?.status ?? 'pending';
            const isCurrent = idx === currentStepIndex && status === 'running';

            return (
              <div
                key={step.id}
                className={`flex items-center gap-2 px-2 py-1.5 rounded-md mb-0.5 text-xs transition-colors ${
                  isCurrent ? 'bg-blue-900/50 text-blue-300' : 'text-gray-400'
                }`}
              >
                <StatusDot status={status} />
                <span className="truncate">{step.title}</span>
                {result && <StepBadge status={status} />}
              </div>
            );
          })}
        </div>
      )}

      {/* Footer */}
      <div className="px-5 py-3 border-t border-gray-700 text-xs text-gray-500">
        v{__APP_VERSION__}
      </div>
    </div>
  );
};

const StatusDot: React.FC<{ status: string }> = ({ status }) => {
  const colors: Record<string, string> = {
    pending:  'bg-gray-600',
    running:  'bg-blue-400 animate-pulse',
    done:     'bg-green-500',
    failed:   'bg-red-500',
    skipped:  'bg-yellow-400',
  };
  return (
    <span className={`shrink-0 w-2 h-2 rounded-full ${colors[status] ?? 'bg-gray-600'}`} />
  );
};
